const std = @import("std");
const diagnostics_mod = @import("diagnostics.zig");
const pane_mod = @import("pane.zig");
const scheduler_mod = @import("scheduler.zig");

pub const api_version: u32 = 1;

pub const Capability = enum {
    command,
    event,
    status,
    buffer_read,
    buffer_edit,
    jobs,
    workspace,
    diagnostics,
    picker,
    pane,
    fs_read,
    tree_query,
    decoration,
    lsp,
};

pub const Capabilities = struct {
    command: bool = false,
    event: bool = false,
    status: bool = false,
    buffer_read: bool = false,
    buffer_edit: bool = false,
    jobs: bool = false,
    workspace: bool = false,
    diagnostics: bool = false,
    picker: bool = false,
    pane: bool = false,
    fs_read: bool = false,
    tree_query: bool = false,
    decoration: bool = false,
    lsp: bool = false,

    pub fn allows(self: Capabilities, capability: Capability) bool {
        return switch (capability) {
            .command => self.command,
            .event => self.event,
            .status => self.status,
            .buffer_read => self.buffer_read,
            .buffer_edit => self.buffer_edit,
            .jobs => self.jobs,
            .workspace => self.workspace,
            .diagnostics => self.diagnostics,
            .picker => self.picker,
            .pane => self.pane,
            .fs_read => self.fs_read,
            .tree_query => self.tree_query,
            .decoration => self.decoration,
            .lsp => self.lsp,
        };
    }
};

pub const Manifest = struct {
    name: []const u8,
    version: []const u8,
    api_version: u32 = api_version,
    capabilities: Capabilities = .{},
};

pub const CommandHandler = *const fn (ctx: *anyopaque, args: []const []const u8) anyerror!void;
pub const EventHandler = *const fn (ctx: *anyopaque, payload: []const u8) anyerror!void;
pub const JobHandler = *const fn (ctx: *anyopaque, kind: scheduler_mod.JobKind, request_generation: u64, workspace_generation: u64) anyerror!u64;
pub const DecorationHandler = *const fn (ctx: *anyopaque, decoration: diagnostics_mod.Decoration) anyerror!void;
pub const PaneTextHandler = *const fn (ctx: *anyopaque, pane_id: u64, title: []const u8, text: []const u8) anyerror!void;

pub const PluginInitFn = *const fn (host: *const Host) callconv(.c) c_int;
pub const PluginDeinitFn = *const fn (host: *const Host) callconv(.c) void;

pub const InitSymbol: [:0]const u8 = "beam_plugin_init";
pub const DeinitSymbol: [:0]const u8 = "beam_plugin_deinit";

fn defaultRegisterCommand(_: *anyopaque, _: []const u8, _: []const u8, _: CommandHandler) anyerror!void {
    return error.PermissionDenied;
}

fn defaultRegisterEvent(_: *anyopaque, _: []const u8, _: EventHandler) anyerror!void {
    return error.PermissionDenied;
}

fn defaultSetPluginActivity(_: *anyopaque, _: []const u8) anyerror!void {
    return error.PermissionDenied;
}

fn defaultSpawnJob(_: *anyopaque, _: scheduler_mod.JobKind, _: u64, _: u64) anyerror!u64 {
    return error.PermissionDenied;
}

fn defaultAddDecoration(_: *anyopaque, _: diagnostics_mod.Decoration) anyerror!void {
    return error.PermissionDenied;
}

fn defaultSetPaneText(_: *anyopaque, _: u64, _: []const u8, _: []const u8) anyerror!void {
    return error.PermissionDenied;
}

pub const Host = struct {
    ctx: *anyopaque,
    caps: Capabilities = .{},
    set_status: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
    set_extension_status: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
    set_plugin_activity: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void = defaultSetPluginActivity,
    register_command: *const fn (ctx: *anyopaque, name: []const u8, description: []const u8, handler: CommandHandler) anyerror!void = defaultRegisterCommand,
    register_event: *const fn (ctx: *anyopaque, event: []const u8, handler: EventHandler) anyerror!void = defaultRegisterEvent,
    spawn_job: *const fn (ctx: *anyopaque, kind: scheduler_mod.JobKind, request_generation: u64, workspace_generation: u64) anyerror!u64 = defaultSpawnJob,
    add_decoration: *const fn (ctx: *anyopaque, decoration: diagnostics_mod.Decoration) anyerror!void = defaultAddDecoration,
    set_pane_text: *const fn (ctx: *anyopaque, pane_id: u64, title: []const u8, text: []const u8) anyerror!void = defaultSetPaneText,

    pub fn require(self: *const Host, capability: Capability) !void {
        if (!self.caps.allows(capability)) return error.PermissionDenied;
    }

    pub fn setStatus(self: *const Host, text: []const u8) !void {
        try self.require(.status);
        try self.set_status(self.ctx, text);
    }

    pub fn setExtensionStatus(self: *const Host, text: []const u8) !void {
        try self.require(.status);
        try self.set_extension_status(self.ctx, text);
    }

    pub fn setPluginActivity(self: *const Host, text: []const u8) !void {
        try self.require(.status);
        try self.set_plugin_activity(self.ctx, text);
    }

    pub fn registerCommand(self: *const Host, name: []const u8, description: []const u8, handler: CommandHandler) !void {
        try self.require(.command);
        try self.register_command(self.ctx, name, description, handler);
    }

    pub fn registerEvent(self: *const Host, event: []const u8, handler: EventHandler) !void {
        try self.require(.event);
        try self.register_event(self.ctx, event, handler);
    }

    pub fn spawnJob(self: *const Host, kind: scheduler_mod.JobKind, request_generation: u64, workspace_generation: u64) !u64 {
        try self.require(.jobs);
        return try self.spawn_job(self.ctx, kind, request_generation, workspace_generation);
    }

    pub fn addDecoration(self: *const Host, decoration: diagnostics_mod.Decoration) !void {
        try self.require(.decoration);
        try self.add_decoration(self.ctx, decoration);
    }

    pub fn setPaneText(self: *const Host, pane_id: u64, title: []const u8, text: []const u8) !void {
        try self.require(.pane);
        try self.set_pane_text(self.ctx, pane_id, title, text);
    }
};

pub fn validateManifest(manifest: Manifest) !void {
    if (manifest.name.len == 0) return error.InvalidManifest;
    if (manifest.version.len == 0) return error.InvalidManifest;
    if (manifest.api_version != api_version) return error.IncompatiblePluginApiVersion;
}

test "manifest validation rejects incompatible api versions" {
    try std.testing.expectError(
        error.IncompatiblePluginApiVersion,
        validateManifest(.{
            .name = "sample",
            .version = "0.1.0",
            .api_version = api_version + 1,
        }),
    );
}

test "manifest validation rejects missing names" {
    try std.testing.expectError(
        error.InvalidManifest,
        validateManifest(.{
            .name = "",
            .version = "0.1.0",
        }),
    );
}

test "host capability gating works" {
    const Dummy = struct {
        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtensionStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }
    };

    var host = Host{
        .ctx = undefined,
        .caps = .{},
        .set_status = Dummy.setStatus,
        .set_extension_status = Dummy.setExtensionStatus,
    };
    try std.testing.expectError(error.PermissionDenied, host.setStatus("nope"));
}

test "new capability flags are recognized" {
    const caps = Capabilities{
        .tree_query = true,
        .decoration = true,
        .lsp = true,
    };
    try std.testing.expect(caps.allows(.tree_query));
    try std.testing.expect(caps.allows(.decoration));
    try std.testing.expect(caps.allows(.lsp));
}

test "plugin abi symbols are exposed" {
    try std.testing.expectEqualStrings("beam_plugin_init", InitSymbol);
    try std.testing.expectEqualStrings("beam_plugin_deinit", DeinitSymbol);
}
