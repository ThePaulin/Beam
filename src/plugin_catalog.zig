const std = @import("std");
const builtin = @import("builtin");
const listpane_mod = @import("listpane.zig");
const plugin_mod = @import("plugin.zig");

pub const EntrySource = enum {
    builtin,
    filesystem,
};

pub const EntryState = enum {
    loaded,
    unknown,
    incompatible,
};

pub const Entry = struct {
    manifest: plugin_mod.Manifest,
    state: EntryState,
    source: EntrySource,
    note: ?[]u8 = null,
};

const LoadedPlugin = struct {
    name: []u8,
    lib: std.DynLib,
    deinit_fn: ?plugin_mod.PluginDeinitFn = null,
};

pub const Catalog = struct {
    allocator: std.mem.Allocator,
    host: ?plugin_mod.Host = null,
    entries: std.array_list.Managed(Entry),
    builtin_manifests: std.array_list.Managed(plugin_mod.Manifest),
    filesystem_manifests: std.array_list.Managed(plugin_mod.Manifest),
    loaded_plugins: std.array_list.Managed(LoadedPlugin),

    pub fn init(allocator: std.mem.Allocator) Catalog {
        return .{
            .allocator = allocator,
            .entries = std.array_list.Managed(Entry).init(allocator),
            .builtin_manifests = std.array_list.Managed(plugin_mod.Manifest).init(allocator),
            .filesystem_manifests = std.array_list.Managed(plugin_mod.Manifest).init(allocator),
            .loaded_plugins = std.array_list.Managed(LoadedPlugin).init(allocator),
        };
    }

    pub fn deinit(self: *Catalog) void {
        self.clear();
        self.entries.deinit();
        self.builtin_manifests.deinit();
        self.filesystem_manifests.deinit();
        self.loaded_plugins.deinit();
    }

    pub fn clear(self: *Catalog) void {
        self.unloadAll();
        for (self.entries.items) |entry| {
            self.allocator.free(entry.manifest.name);
            self.allocator.free(entry.manifest.version);
            if (entry.note) |note| self.allocator.free(note);
        }
        self.entries.clearRetainingCapacity();
        self.clearManifests(&self.builtin_manifests);
        self.clearManifests(&self.filesystem_manifests);
    }

    pub fn rebuild(self: *Catalog, host: *const plugin_mod.Host, builtin_names: []const []const u8, plugin_root: []const u8, plugin_enabled_names: []const []const u8) !void {
        self.clear();
        self.host = host.*;
        try self.loadBuiltinManifests(builtin_names);
        try self.loadFilesystemManifests(host, plugin_root, plugin_enabled_names);
    }

    pub fn manifests(self: *const Catalog) []const plugin_mod.Manifest {
        return self.builtin_manifests.items;
    }

    pub fn pluginManifests(self: *const Catalog) []const plugin_mod.Manifest {
        return self.filesystem_manifests.items;
    }

    pub fn statusText(self: *const Catalog, allocator: std.mem.Allocator) ![]u8 {
        var loaded: usize = 0;
        var unknown: usize = 0;
        var incompatible: usize = 0;
        for (self.entries.items) |entry| {
            switch (entry.state) {
                .loaded => loaded += 1,
                .unknown => unknown += 1,
                .incompatible => incompatible += 1,
            }
        }
        return try std.fmt.allocPrint(allocator, "plugins {d} loaded / {d} unknown / {d} incompatible", .{ loaded, unknown, incompatible });
    }

    pub fn fillListPane(self: *const Catalog, allocator: std.mem.Allocator, pane: *listpane_mod.ListPane) !void {
        var items = std.array_list.Managed(listpane_mod.Item).init(allocator);
        defer {
            for (items.items) |item| {
                if (item.path) |path| allocator.free(path);
                allocator.free(item.label);
                if (item.detail) |detail| allocator.free(detail);
            }
            items.deinit();
        }
        for (self.entries.items, 0..) |entry, idx| {
            const label = try std.fmt.allocPrint(allocator, "{s} [{s}]", .{ entry.manifest.name, @tagName(entry.source) });
            const detail = if (entry.note) |note| try allocator.dupe(u8, note) else null;
            try items.append(.{
                .id = @intCast(idx + 1),
                .label = label,
                .detail = detail,
                .score = if (entry.state == .loaded) 100 else 0,
            });
        }
        try pane.setItems(items.items);
    }

    pub fn findEntry(self: *const Catalog, name: []const u8) ?*const Entry {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.manifest.name, name)) return entry;
        }
        return null;
    }

    fn loadBuiltinManifests(self: *Catalog, builtin_names: []const []const u8) !void {
        for (builtin_names) |name| {
            const spec = builtinManifestForName(name);
            if (spec) |manifest| {
                try self.appendManifest(.builtin, try duplicateManifest(self.allocator, manifest), .loaded, null);
            } else {
                try self.appendUnknownEntry(.builtin, name, "unknown builtin module");
            }
        }
    }

    fn loadFilesystemManifests(self: *Catalog, host: *const plugin_mod.Host, plugin_root: []const u8, enabled_names: []const []const u8) !void {
        if (plugin_root.len == 0) return;
        var dir = std.fs.cwd().openDir(plugin_root, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                if (enabled_names.len > 0) {
                    for (enabled_names) |name| {
                        try self.appendUnknownEntry(.filesystem, name, "plugin root missing");
                    }
                }
                return;
            },
            else => return err,
        };
        defer dir.close();

        var found_enabled = std.array_list.Managed([]u8).init(self.allocator);
        defer {
            for (found_enabled.items) |name| self.allocator.free(name);
            found_enabled.deinit();
        }

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (enabled_names.len > 0 and !nameIsEnabled(entry.name, enabled_names)) continue;
            const manifest = self.readFilesystemManifest(plugin_root, entry.name) catch |err| switch (err) {
                error.FileNotFound => {
                    try self.appendUnknownEntry(.filesystem, entry.name, "manifest not found");
                    continue;
                },
                else => return err,
            };
            if (manifest.state == .loaded) {
                if (enabled_names.len > 0) {
                    try found_enabled.append(try self.allocator.dupe(u8, entry.name));
                }
                errdefer self.freeManifest(manifest.manifest);
                const loaded = self.tryLoadFilesystemPlugin(host, plugin_root, entry.name, manifest.manifest) catch |err| switch (err) {
                    error.FileNotFound => {
                        self.freeManifest(manifest.manifest);
                        try self.appendUnknownEntry(.filesystem, entry.name, "plugin binary not found");
                        continue;
                    },
                    error.PermissionDenied => {
                        self.freeManifest(manifest.manifest);
                        try self.appendUnknownEntry(.filesystem, entry.name, "plugin load denied");
                        continue;
                    },
                    else => return err,
                };
                try self.loaded_plugins.append(loaded);
                errdefer self.removeLastLoadedPlugin();
                try self.appendManifest(.filesystem, manifest.manifest, .loaded, null);
                continue;
            }
            try self.appendManifest(.filesystem, manifest.manifest, manifest.state, manifest.note);
            if (enabled_names.len > 0) {
                try found_enabled.append(try self.allocator.dupe(u8, entry.name));
            }
        }

        if (enabled_names.len > 0) {
            for (enabled_names) |name| {
                if (!containsName(found_enabled.items, name)) {
                    try self.appendUnknownEntry(.filesystem, name, "manifest not found");
                }
            }
        }
    }

    fn readFilesystemManifest(self: *Catalog, plugin_root: []const u8, plugin_name: []const u8) !LoadedManifest {
        const manifest_path = try std.fs.path.join(self.allocator, &[_][]const u8{ plugin_root, plugin_name, "plugin.toml" });
        defer self.allocator.free(manifest_path);
        const raw = std.fs.cwd().readFileAlloc(self.allocator, manifest_path, 1 << 20) catch |err| switch (err) {
            error.FileNotFound => return err,
            else => return err,
        };
        defer self.allocator.free(raw);

        const draft = try parseManifestDraft(raw, plugin_name);
        const manifest = try materializeManifest(self.allocator, draft);
        const validation = plugin_mod.validateManifest(manifest);
        if (validation) |_| {
            return .{
                .manifest = manifest,
                .state = .loaded,
                .note = null,
            };
        } else |err| switch (err) {
            error.IncompatiblePluginApiVersion => {
                return .{
                    .manifest = manifest,
                    .state = .incompatible,
                    .note = "incompatible plugin api version",
                };
            },
            error.InvalidManifest => {
                return .{
                    .manifest = manifest,
                    .state = .unknown,
                    .note = "invalid manifest",
                };
            },
            else => return err,
        }
    }

    fn appendUnknownEntry(self: *Catalog, source: EntrySource, name: []const u8, note_text: []const u8) !void {
        const manifest = plugin_mod.Manifest{
            .name = try self.allocator.dupe(u8, name),
            .version = try self.allocator.dupe(u8, "0.0.0"),
            .api_version = plugin_mod.api_version,
            .capabilities = .{},
        };
        try self.appendEntry(source, manifest, .unknown, note_text);
    }

    fn appendManifest(self: *Catalog, source: EntrySource, manifest: plugin_mod.Manifest, state: EntryState, note_text: ?[]const u8) !void {
        const note = if (note_text) |text| try self.allocator.dupe(u8, text) else null;
        try self.entries.append(.{
            .manifest = manifest,
            .state = state,
            .source = source,
            .note = note,
        });
        if (state == .loaded) {
            switch (source) {
                .builtin => try self.builtin_manifests.append(manifest),
                .filesystem => try self.filesystem_manifests.append(manifest),
            }
        }
    }

    fn appendEntry(self: *Catalog, source: EntrySource, manifest: plugin_mod.Manifest, state: EntryState, note_text: []const u8) !void {
        try self.appendManifest(source, manifest, state, note_text);
    }

    fn tryLoadFilesystemPlugin(self: *Catalog, host: *const plugin_mod.Host, plugin_root: []const u8, plugin_name: []const u8, manifest: plugin_mod.Manifest) !LoadedPlugin {
        const plugin_path = try self.resolvePluginLibraryPath(plugin_root, plugin_name);
        defer self.allocator.free(plugin_path);

        var lib = try std.DynLib.open(plugin_path);
        errdefer lib.close();

        const init_fn = lib.lookup(plugin_mod.PluginInitFn, plugin_mod.InitSymbol) orelse return error.PermissionDenied;
        const deinit_fn = lib.lookup(plugin_mod.PluginDeinitFn, plugin_mod.DeinitSymbol);
        const rc = init_fn(host);
        if (rc != 0) return error.PermissionDenied;

        return .{
            .name = try self.allocator.dupe(u8, manifest.name),
            .lib = lib,
            .deinit_fn = deinit_fn,
        };
    }

    fn unloadAll(self: *Catalog) void {
        for (self.loaded_plugins.items) |*plugin| {
            if (plugin.deinit_fn) |deinit_fn| {
                if (self.host) |plugin_host| {
                    deinit_fn(&plugin_host);
                }
            }
            self.allocator.free(plugin.name);
            plugin.lib.close();
        }
        self.loaded_plugins.clearRetainingCapacity();
    }

    fn removeLastLoadedPlugin(self: *Catalog) void {
        if (self.loaded_plugins.items.len == 0) return;
        const idx = self.loaded_plugins.items.len - 1;
        const plugin = self.loaded_plugins.items[idx];
        self.loaded_plugins.items.len = idx;
        if (plugin.deinit_fn) |deinit_fn| {
            if (self.host) |plugin_host| {
                deinit_fn(&plugin_host);
            }
        }
        self.allocator.free(plugin.name);
        var lib = plugin.lib;
        lib.close();
    }

    fn resolvePluginLibraryPath(self: *Catalog, plugin_root: []const u8, plugin_name: []const u8) ![]u8 {
        for (libraryCandidates()) |candidate| {
            const path = try std.fs.path.join(self.allocator, &[_][]const u8{ plugin_root, plugin_name, candidate });
            if (std.fs.cwd().access(path, .{})) |_| {
                return path;
            } else |err| switch (err) {
                error.FileNotFound => self.allocator.free(path),
                else => return err,
            }
        }
        return error.FileNotFound;
    }

    fn duplicateManifest(allocator: std.mem.Allocator, manifest: plugin_mod.Manifest) !plugin_mod.Manifest {
        return .{
            .name = try allocator.dupe(u8, manifest.name),
            .version = try allocator.dupe(u8, manifest.version),
            .api_version = manifest.api_version,
            .capabilities = manifest.capabilities,
        };
    }

    fn freeManifest(self: *Catalog, manifest: plugin_mod.Manifest) void {
        self.allocator.free(manifest.name);
        self.allocator.free(manifest.version);
    }

    fn clearManifests(self: *Catalog, list: *std.array_list.Managed(plugin_mod.Manifest)) void {
        _ = self;
        list.clearRetainingCapacity();
    }
};

const LoadedManifest = struct {
    manifest: plugin_mod.Manifest,
    state: EntryState,
    note: ?[]const u8,
};

const ManifestDraft = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    api_version: ?u32 = null,
    capabilities: plugin_mod.Capabilities = .{},
};

fn builtinManifestForName(name: []const u8) ?plugin_mod.Manifest {
    if (std.mem.eql(u8, name, "hello")) {
        return .{
            .name = "hello",
            .version = "0.1.0",
            .api_version = plugin_mod.api_version,
            .capabilities = .{ .command = true, .event = true, .status = true },
        };
    }
    return null;
}

fn libraryCandidates() []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "plugin.dll", "libbeam_plugin.dll", "beam_plugin.dll" },
        .macos, .ios, .tvos, .watchos, .visionos => &[_][]const u8{ "plugin.dylib", "libbeam_plugin.dylib", "beam_plugin.dylib" },
        else => &[_][]const u8{ "plugin.so", "libbeam_plugin.so", "beam_plugin.so" },
    };
}

fn parseManifestDraft(text: []const u8, fallback_name: []const u8) !ManifestDraft {
    var draft = ManifestDraft{};
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, stripComment(std.mem.trim(u8, raw_line, " \t\r")), " \t\r");
        if (line.len == 0) continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            section = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidManifest;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, section, "plugin") or section.len == 0) {
            if (std.mem.eql(u8, key, "name")) {
                draft.name = try parseString(value);
                continue;
            }
            if (std.mem.eql(u8, key, "version")) {
                draft.version = try parseString(value);
                continue;
            }
            if (std.mem.eql(u8, key, "api_version")) {
                draft.api_version = try parseInt(value);
                continue;
            }
        }

        if (std.mem.eql(u8, section, "capabilities")) {
            const enabled = try parseBool(value);
            if (std.mem.eql(u8, key, "command")) draft.capabilities.command = enabled else
            if (std.mem.eql(u8, key, "event")) draft.capabilities.event = enabled else
            if (std.mem.eql(u8, key, "status")) draft.capabilities.status = enabled else
            if (std.mem.eql(u8, key, "buffer_read")) draft.capabilities.buffer_read = enabled else
            if (std.mem.eql(u8, key, "buffer_edit")) draft.capabilities.buffer_edit = enabled else
            if (std.mem.eql(u8, key, "jobs")) draft.capabilities.jobs = enabled else
            if (std.mem.eql(u8, key, "workspace")) draft.capabilities.workspace = enabled else
            if (std.mem.eql(u8, key, "diagnostics")) draft.capabilities.diagnostics = enabled else
            if (std.mem.eql(u8, key, "picker")) draft.capabilities.picker = enabled else
            if (std.mem.eql(u8, key, "pane")) draft.capabilities.pane = enabled else
            if (std.mem.eql(u8, key, "fs_read")) draft.capabilities.fs_read = enabled else
                return error.InvalidManifest;
            continue;
        }

        return error.InvalidManifest;
    }

    if (draft.name == null) draft.name = fallback_name;
    return draft;
}

fn materializeManifest(allocator: std.mem.Allocator, draft: ManifestDraft) !plugin_mod.Manifest {
    const name = draft.name orelse "";
    const version = draft.version orelse "";
    return .{
        .name = try allocator.dupe(u8, name),
        .version = try allocator.dupe(u8, version),
        .api_version = draft.api_version orelse plugin_mod.api_version,
        .capabilities = draft.capabilities,
    };
}

fn parseString(value: []const u8) ![]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') return error.InvalidManifest;
    return value[1 .. value.len - 1];
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidManifest;
}

fn parseInt(value: []const u8) !u32 {
    return std.fmt.parseUnsigned(u32, value, 10) catch error.InvalidManifest;
}

fn stripComment(line: []const u8) []const u8 {
    var in_string = false;
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        const c = line[idx];
        if (c == '"' and (idx == 0 or line[idx - 1] != '\\')) {
            in_string = !in_string;
        } else if (c == '#' and !in_string) {
            return line[0..idx];
        }
    }
    return line;
}

fn nameIsEnabled(name: []const u8, enabled_names: []const []const u8) bool {
    for (enabled_names) |enabled| {
        if (std.mem.eql(u8, enabled, name)) return true;
    }
    return false;
}

fn containsName(names: []const []u8, name: []const u8) bool {
    for (names) |existing| {
        if (std.mem.eql(u8, existing, name)) return true;
    }
    return false;
}

test "plugin catalog loads builtin and filesystem manifests" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    const Dummy = struct {
        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }
    };
    var host = plugin_mod.Host{
        .ctx = undefined,
        .caps = .{ .status = true },
        .set_status = Dummy.setStatus,
        .set_extension_status = Dummy.setExtStatus,
    };

    try tmp.dir.makePath("plugins/hello");
    try tmp.dir.writeFile(.{
        .sub_path = "plugins/hello/plugin.toml",
        .data =
        \\[plugin]
        \\name = "hello"
        \\version = "0.1.0"
        \\api_version = 1
        \\
        \\[capabilities]
        \\command = true
        \\event = true
        \\status = true
    });

    var catalog = Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    try catalog.rebuild(&host, &.{"hello"}, "plugins", &.{"hello"});
    try std.testing.expectEqual(@as(usize, 2), catalog.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), catalog.builtin_manifests.items.len);
    try std.testing.expectEqual(@as(usize, 0), catalog.filesystem_manifests.items.len);
    try std.testing.expectEqualStrings("hello", catalog.entries.items[0].manifest.name);
    try std.testing.expectEqualStrings("hello", catalog.entries.items[1].manifest.name);
    try std.testing.expectEqual(EntryState.unknown, catalog.entries.items[1].state);
}

test "plugin catalog tracks missing filesystem entries" {
    const Dummy = struct {
        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }
    };
    var host = plugin_mod.Host{
        .ctx = undefined,
        .caps = .{ .status = true },
        .set_status = Dummy.setStatus,
        .set_extension_status = Dummy.setExtStatus,
    };
    var catalog = Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    try catalog.rebuild(&host, &.{ "hello", "missing" }, "plugins", &.{"missing"});
    try std.testing.expectEqual(@as(usize, 3), catalog.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), catalog.builtin_manifests.items.len);
    try std.testing.expectEqual(@as(usize, 0), catalog.filesystem_manifests.items.len);
    try std.testing.expectEqualStrings("missing", catalog.entries.items[1].manifest.name);
    try std.testing.expectEqual(EntryState.unknown, catalog.entries.items[1].state);
}
