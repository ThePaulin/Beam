const std = @import("std");
const buffer_mod = @import("buffer.zig");
const diagnostics_mod = @import("diagnostics.zig");
const pane_mod = @import("pane.zig");
const scheduler_mod = @import("scheduler.zig");
const syntax_mod = @import("treesitter.zig");

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
pub const WorkspaceInfo = struct {
    root_path: []u8,
    session_generation: u64,
    open_buffer_count: usize,
};

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

fn defaultReadBufferSnapshot(_: *anyopaque, _: u64) anyerror!buffer_mod.ReadSnapshot {
    return error.PermissionDenied;
}

fn defaultFreeBufferSnapshot(_: *anyopaque, _: buffer_mod.ReadSnapshot) void {}

fn defaultBeginBufferEdit(_: *anyopaque, _: u64) anyerror!buffer_mod.EditTransaction {
    return error.PermissionDenied;
}

fn defaultReadBufferSelection(_: *anyopaque, _: u64) anyerror!?buffer_mod.Selection {
    return error.PermissionDenied;
}

fn defaultWorkspaceInfo(_: *anyopaque) anyerror!WorkspaceInfo {
    return error.PermissionDenied;
}

fn defaultReadFile(_: *anyopaque, _: []const u8) anyerror![]u8 {
    return error.PermissionDenied;
}

fn defaultFreeBytes(_: *anyopaque, _: []u8) void {}

fn defaultSyntaxNodeAtCursor(_: *anyopaque, _: u64) anyerror!?syntax_mod.Node {
    return error.PermissionDenied;
}

fn defaultSyntaxFoldRange(_: *anyopaque, _: u64) anyerror!?syntax_mod.FoldRange {
    return error.PermissionDenied;
}

fn defaultSyntaxEnclosingScope(_: *anyopaque, _: u64) anyerror!?syntax_mod.FoldRange {
    return error.PermissionDenied;
}

fn defaultSyntaxIndentForRow(_: *anyopaque, _: u64, _: usize) anyerror!usize {
    return error.PermissionDenied;
}

fn defaultSyntaxTextObjectRange(_: *anyopaque, _: u64, _: bool) anyerror!?syntax_mod.TextRange {
    return error.PermissionDenied;
}

fn defaultRequestLsp(_: *anyopaque, _: []const u8) anyerror!u64 {
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
    read_buffer_snapshot: *const fn (ctx: *anyopaque, buffer_id: u64) anyerror!buffer_mod.ReadSnapshot = defaultReadBufferSnapshot,
    free_buffer_snapshot: *const fn (ctx: *anyopaque, snapshot: buffer_mod.ReadSnapshot) void = defaultFreeBufferSnapshot,
    begin_buffer_edit: *const fn (ctx: *anyopaque, buffer_id: u64) anyerror!buffer_mod.EditTransaction = defaultBeginBufferEdit,
    read_buffer_selection: *const fn (ctx: *anyopaque, buffer_id: u64) anyerror!?buffer_mod.Selection = defaultReadBufferSelection,
    workspace_info: *const fn (ctx: *anyopaque) anyerror!WorkspaceInfo = defaultWorkspaceInfo,
    read_file: *const fn (ctx: *anyopaque, path: []const u8) anyerror![]u8 = defaultReadFile,
    free_bytes: *const fn (ctx: *anyopaque, bytes: []u8) void = defaultFreeBytes,
    syntax_node_at_cursor: *const fn (ctx: *anyopaque, buffer_id: u64) anyerror!?syntax_mod.Node = defaultSyntaxNodeAtCursor,
    syntax_fold_range: *const fn (ctx: *anyopaque, buffer_id: u64) anyerror!?syntax_mod.FoldRange = defaultSyntaxFoldRange,
    syntax_enclosing_scope: *const fn (ctx: *anyopaque, buffer_id: u64) anyerror!?syntax_mod.FoldRange = defaultSyntaxEnclosingScope,
    syntax_indent_for_row: *const fn (ctx: *anyopaque, buffer_id: u64, row: usize) anyerror!usize = defaultSyntaxIndentForRow,
    syntax_text_object_range: *const fn (ctx: *anyopaque, buffer_id: u64, inner: bool) anyerror!?syntax_mod.TextRange = defaultSyntaxTextObjectRange,
    request_definition: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,
    request_references: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,
    request_rename: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,
    request_completion: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,
    request_hover: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,
    request_code_action: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,
    request_semantic_tokens: *const fn (ctx: *anyopaque, payload: []const u8) anyerror!u64 = defaultRequestLsp,

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

    pub fn readBufferSnapshot(self: *const Host, buffer_id: u64) !buffer_mod.ReadSnapshot {
        try self.require(.buffer_read);
        return try self.read_buffer_snapshot(self.ctx, buffer_id);
    }

    pub fn freeBufferSnapshot(self: *const Host, snapshot: buffer_mod.ReadSnapshot) void {
        self.free_buffer_snapshot(self.ctx, snapshot);
    }

    pub fn beginBufferEdit(self: *const Host, buffer_id: u64) !buffer_mod.EditTransaction {
        try self.require(.buffer_edit);
        return try self.begin_buffer_edit(self.ctx, buffer_id);
    }

    pub fn readBufferSelection(self: *const Host, buffer_id: u64) !?buffer_mod.Selection {
        try self.require(.buffer_read);
        return try self.read_buffer_selection(self.ctx, buffer_id);
    }

    pub fn workspaceInfo(self: *const Host) !WorkspaceInfo {
        try self.require(.workspace);
        return try self.workspace_info(self.ctx);
    }

    pub fn freeWorkspaceInfo(self: *const Host, info: WorkspaceInfo) void {
        self.free_bytes(self.ctx, info.root_path);
    }

    pub fn readFile(self: *const Host, path: []const u8) ![]u8 {
        try self.require(.fs_read);
        return try self.read_file(self.ctx, path);
    }

    pub fn freeBytes(self: *const Host, bytes: []u8) void {
        self.free_bytes(self.ctx, bytes);
    }

    pub fn nodeAtCursor(self: *const Host, buffer_id: u64) !?syntax_mod.Node {
        try self.require(.tree_query);
        return try self.syntax_node_at_cursor(self.ctx, buffer_id);
    }

    pub fn foldRange(self: *const Host, buffer_id: u64) !?syntax_mod.FoldRange {
        try self.require(.tree_query);
        return try self.syntax_fold_range(self.ctx, buffer_id);
    }

    pub fn enclosingScope(self: *const Host, buffer_id: u64) !?syntax_mod.FoldRange {
        try self.require(.tree_query);
        return try self.syntax_enclosing_scope(self.ctx, buffer_id);
    }

    pub fn indentForRow(self: *const Host, buffer_id: u64, row: usize) !usize {
        try self.require(.tree_query);
        return try self.syntax_indent_for_row(self.ctx, buffer_id, row);
    }

    pub fn textObjectRange(self: *const Host, buffer_id: u64, inner: bool) !?syntax_mod.TextRange {
        try self.require(.tree_query);
        return try self.syntax_text_object_range(self.ctx, buffer_id, inner);
    }

    pub fn requestDefinition(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_definition(self.ctx, payload);
    }

    pub fn requestReferences(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_references(self.ctx, payload);
    }

    pub fn requestRename(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_rename(self.ctx, payload);
    }

    pub fn requestCompletion(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_completion(self.ctx, payload);
    }

    pub fn requestHover(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_hover(self.ctx, payload);
    }

    pub fn requestCodeAction(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_code_action(self.ctx, payload);
    }

    pub fn requestSemanticTokens(self: *const Host, payload: []const u8) !u64 {
        try self.require(.lsp);
        return try self.request_semantic_tokens(self.ctx, payload);
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
