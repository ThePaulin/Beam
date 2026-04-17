const std = @import("std");

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

pub const Host = struct {
    ctx: *anyopaque,
    caps: Capabilities = .{},
    set_status: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
    set_extension_status: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
    set_plugin_activity: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void = defaultSetPluginActivity,
    register_command: *const fn (ctx: *anyopaque, name: []const u8, description: []const u8, handler: CommandHandler) anyerror!void = defaultRegisterCommand,
    register_event: *const fn (ctx: *anyopaque, event: []const u8, handler: EventHandler) anyerror!void = defaultRegisterEvent,

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

test "plugin abi symbols are exposed" {
    try std.testing.expectEqualStrings("beam_plugin_init", InitSymbol);
    try std.testing.expectEqualStrings("beam_plugin_deinit", DeinitSymbol);
}
