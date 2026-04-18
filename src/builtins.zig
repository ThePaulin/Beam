const std = @import("std");
const plugin_mod = @import("plugin.zig");

pub const api_version: u32 = plugin_mod.api_version;
pub const Capability = plugin_mod.Capability;
pub const Capabilities = plugin_mod.Capabilities;
pub const Host = plugin_mod.Host;
pub const Manifest = plugin_mod.Manifest;

pub const CommandHandler = plugin_mod.CommandHandler;
pub const EventHandler = plugin_mod.EventHandler;
pub const AsyncResultKind = plugin_mod.CompletionKind;
pub const AsyncResultHandler = plugin_mod.CompletionHandler;
pub const RequestHandle = plugin_mod.RequestHandle;

pub const Command = struct {
    name: []u8,
    description: []u8,
    handler: CommandHandler,
};

pub const EventListener = struct {
    event: []u8,
    handler: EventHandler,
};

pub const AsyncResultListener = struct {
    kind: AsyncResultKind,
    handle: RequestHandle,
    handler: AsyncResultHandler,
};

pub const Registry = struct {
    pub const api_version: u32 = 1;

    allocator: std.mem.Allocator,
    commands: std.array_list.Managed(Command),
    extension_commands: std.array_list.Managed(Command),
    events: std.array_list.Managed(EventListener),
    extension_events: std.array_list.Managed(EventListener),
    async_results: std.array_list.Managed(AsyncResultListener),
    status: std.array_list.Managed(u8),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .commands = std.array_list.Managed(Command).init(allocator),
            .extension_commands = std.array_list.Managed(Command).init(allocator),
            .events = std.array_list.Managed(EventListener).init(allocator),
            .extension_events = std.array_list.Managed(EventListener).init(allocator),
            .async_results = std.array_list.Managed(AsyncResultListener).init(allocator),
            .status = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.clearRegistrations();
        self.clearExtensionRegistrations();
        self.clearAsyncResults();
        self.commands.deinit();
        self.extension_commands.deinit();
        self.events.deinit();
        self.extension_events.deinit();
        self.async_results.deinit();
        self.status.deinit();
    }

    pub fn rebuild(self: *Registry, host: *Host, requested_api_version: u32, manifests: []const Manifest) !void {
        if (requested_api_version != Registry.api_version) return error.IncompatibleBuiltinApiVersion;
        self.clearRegistrations();
        self.clearAsyncResults();
        self.status.clearRetainingCapacity();
        try self.registerCoreModules(host, manifests);
    }

    pub fn invokeCommand(self: *Registry, host: *Host, name: []const u8, args: []const []const u8) !bool {
        for (self.commands.items) |command| {
            if (std.mem.eql(u8, command.name, name)) {
                try command.handler(host, args);
                return true;
            }
        }
        for (self.extension_commands.items) |command| {
            if (std.mem.eql(u8, command.name, name)) {
                try command.handler(host, args);
                return true;
            }
        }
        return false;
    }

    pub fn registerExtensionCommand(self: *Registry, name: []const u8, description: []const u8, handler: CommandHandler) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const description_copy = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(description_copy);
        try self.extension_commands.append(.{
            .name = name_copy,
            .description = description_copy,
            .handler = handler,
        });
    }

    pub fn registerExtensionEvent(self: *Registry, event: []const u8, handler: EventHandler) !void {
        const event_copy = try self.allocator.dupe(u8, event);
        errdefer self.allocator.free(event_copy);
        try self.extension_events.append(.{
            .event = event_copy,
            .handler = handler,
        });
    }

    pub fn registerAsyncResultHandler(self: *Registry, kind: AsyncResultKind, handle: RequestHandle, handler: AsyncResultHandler) !void {
        try self.async_results.append(.{
            .kind = kind,
            .handle = handle,
            .handler = handler,
        });
    }

    pub fn registerJobResultHandler(self: *Registry, handle: RequestHandle, handler: AsyncResultHandler) !void {
        try self.registerAsyncResultHandler(.job, handle, handler);
    }

    pub fn registerServiceResultHandler(self: *Registry, handle: RequestHandle, handler: AsyncResultHandler) !void {
        try self.registerAsyncResultHandler(.service, handle, handler);
    }

    pub fn emitAsyncResult(self: *Registry, host: *Host, kind: AsyncResultKind, handle: RequestHandle, success: bool, payload: []const u8) void {
        var index: usize = 0;
        while (index < self.async_results.items.len) {
            const listener = self.async_results.items[index];
            if (listener.kind != kind or !listener.handle.matches(handle)) {
                index += 1;
                continue;
            }
            _ = self.async_results.orderedRemove(index);
            listener.handler(host, kind, handle, success, payload) catch |err| {
                std.debug.print("[beam] async result handler failed: {s}\n", .{@errorName(err)});
            };
        }
    }

    pub fn emitJobResult(self: *Registry, host: *Host, handle: RequestHandle, success: bool, payload: []const u8) void {
        self.emitAsyncResult(host, .job, handle, success, payload);
    }

    pub fn emitServiceResult(self: *Registry, host: *Host, handle: RequestHandle, success: bool, payload: []const u8) void {
        self.emitAsyncResult(host, .service, handle, success, payload);
    }

    pub fn clearAsyncResults(self: *Registry) void {
        self.async_results.clearRetainingCapacity();
    }

    pub fn emit(self: *Registry, host: *Host, event: []const u8, payload: []const u8) void {
        for (self.events.items) |listener| {
            if (!std.mem.eql(u8, listener.event, event)) continue;
            listener.handler(host, payload) catch |err| {
                std.debug.print("[beam] builtin {s} event {s} failed: {s}\n", .{ listener.event, event, @errorName(err) });
            };
        }
        for (self.extension_events.items) |listener| {
            if (!std.mem.eql(u8, listener.event, event)) continue;
            listener.handler(host, payload) catch |err| {
                std.debug.print("[beam] extension {s} event {s} failed: {s}\n", .{ listener.event, event, @errorName(err) });
            };
        }
    }

    pub fn statusText(self: *const Registry) []const u8 {
        return self.status.items;
    }

    pub fn extensionCommands(self: *const Registry) []const Command {
        return self.extension_commands.items;
    }

    pub fn setStatus(self: *Registry, text: []const u8) !void {
        self.status.clearRetainingCapacity();
        try self.status.appendSlice(text);
    }

    fn registerCoreModules(self: *Registry, host: *Host, manifests: []const Manifest) !void {
        if (manifests.len == 0) return;
        for (manifests) |manifest| {
            if (std.mem.eql(u8, manifest.name, "hello")) {
                try self.registerHello(host, manifest);
                continue;
            }
            std.debug.print("[beam] unknown builtin module {s}\n", .{manifest.name});
        }
    }

    fn registerHello(self: *Registry, host: *Host, manifest: Manifest) !void {
        if (manifest.api_version != Registry.api_version) return;
        if (!manifest.capabilities.allows(.command) or !manifest.capabilities.allows(.event) or !manifest.capabilities.allows(.status)) {
            std.debug.print("[beam] builtin {s} missing required capabilities\n", .{manifest.name});
            return;
        }
        try self.registerCommand("hello", "show a native built-in status message", helloCommand);
        try self.registerEvent("buffer_open", helloBufferOpen);
        try self.registerEvent("buffer_save", helloBufferSave);
        try host.setExtensionStatus("hello built-in ready");
    }

    fn registerCommand(self: *Registry, name: []const u8, description: []const u8, handler: CommandHandler) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const description_copy = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(description_copy);
        try self.commands.append(.{
            .name = name_copy,
            .description = description_copy,
            .handler = handler,
        });
    }

    fn registerEvent(self: *Registry, event: []const u8, handler: EventHandler) !void {
        const event_copy = try self.allocator.dupe(u8, event);
        errdefer self.allocator.free(event_copy);
        try self.events.append(.{
            .event = event_copy,
            .handler = handler,
        });
    }

    fn clearRegistrations(self: *Registry) void {
        for (self.commands.items) |command| {
            self.allocator.free(command.name);
            self.allocator.free(command.description);
        }
        self.commands.clearRetainingCapacity();

        for (self.events.items) |listener| {
            self.allocator.free(listener.event);
        }
        self.events.clearRetainingCapacity();
    }

    pub fn clearExtensionRegistrations(self: *Registry) void {
        for (self.extension_commands.items) |command| {
            self.allocator.free(command.name);
            self.allocator.free(command.description);
        }
        self.extension_commands.clearRetainingCapacity();

        for (self.extension_events.items) |listener| {
            self.allocator.free(listener.event);
        }
        self.extension_events.clearRetainingCapacity();
        self.clearAsyncResults();
    }
};

fn helloCommand(ctx: *anyopaque, args: []const []const u8) !void {
    _ = args;
    const host: *Host = @ptrCast(@alignCast(ctx));
    try host.setExtensionStatus("hello from native built-ins");
}

fn helloBufferOpen(ctx: *anyopaque, payload: []const u8) !void {
    _ = payload;
    const host: *Host = @ptrCast(@alignCast(ctx));
    try host.setExtensionStatus("hello built-in saw buffer open");
}

fn helloBufferSave(ctx: *anyopaque, payload: []const u8) !void {
    _ = payload;
    const host: *Host = @ptrCast(@alignCast(ctx));
    try host.setExtensionStatus("hello built-in saw buffer save");
}

fn extensionPluginCommand(ctx: *anyopaque, args: []const []const u8) !void {
    _ = args;
    const host: *Host = @ptrCast(@alignCast(ctx));
    try host.setExtensionStatus("extension command invoked");
}

fn extensionPluginEvent(ctx: *anyopaque, payload: []const u8) !void {
    _ = payload;
    const host: *Host = @ptrCast(@alignCast(ctx));
    try host.setExtensionStatus("extension event invoked");
}

test "builtin registry invokes native commands and events" {
    const TestState = struct {
        status: []u8 = &[_]u8{},
        ext_status: []u8 = &[_]u8{},

        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            const state: *@This() = @ptrCast(@alignCast(ctx));
            if (state.ext_status.len > 0) std.testing.allocator.free(state.ext_status);
            state.ext_status = try std.testing.allocator.dupe(u8, text);
        }
    };

    var state = TestState{};
    defer if (state.ext_status.len > 0) std.testing.allocator.free(state.ext_status);
    var host = Host{
        .ctx = &state,
        .caps = .{ .status = true, .command = true, .event = true },
        .set_status = TestState.setStatus,
        .set_extension_status = TestState.setExtStatus,
    };
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.rebuild(&host, Registry.api_version, &.{
        .{
            .name = "hello",
            .version = "0.1.0",
            .api_version = Registry.api_version,
            .capabilities = .{ .command = true, .event = true, .status = true },
        },
    });
    try std.testing.expect(try registry.invokeCommand(&host, "hello", &.{}));
    try std.testing.expectEqualStrings("hello from native built-ins", state.ext_status);
    registry.emit(&host, "buffer_open", "{}");
    try std.testing.expectEqualStrings("hello built-in saw buffer open", state.ext_status);
}

test "builtin registry invokes extension commands and events" {
    const TestState = struct {
        ext_status: []u8 = &[_]u8{},

        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            const state: *@This() = @ptrCast(@alignCast(ctx));
            if (state.ext_status.len > 0) std.testing.allocator.free(state.ext_status);
            state.ext_status = try std.testing.allocator.dupe(u8, text);
        }
    };

    var state = TestState{};
    defer if (state.ext_status.len > 0) std.testing.allocator.free(state.ext_status);
    var host = Host{
        .ctx = &state,
        .caps = .{ .status = true, .command = true, .event = true },
        .set_status = TestState.setStatus,
        .set_extension_status = TestState.setExtStatus,
        .register_command = struct {
            fn call(ctx: *anyopaque, name: []const u8, description: []const u8, handler: CommandHandler) anyerror!void {
                _ = ctx;
                _ = name;
                _ = description;
                _ = handler;
            }
        }.call,
        .register_event = struct {
            fn call(ctx: *anyopaque, event: []const u8, handler: EventHandler) anyerror!void {
                _ = ctx;
                _ = event;
                _ = handler;
            }
        }.call,
    };
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerExtensionCommand("hello-plugin", "announce that the hello plugin is loaded", extensionPluginCommand);
    try registry.registerExtensionEvent("buffer_open", extensionPluginEvent);
    try std.testing.expect(try registry.invokeCommand(&host, "hello-plugin", &.{}));
    try std.testing.expectEqualStrings("extension command invoked", state.ext_status);
    registry.emit(&host, "buffer_open", "{}");
    try std.testing.expectEqualStrings("extension event invoked", state.ext_status);
}

test "builtin registry routes async results by handle" {
    const TestState = struct {
        handled: usize = 0,
        payload: []u8 = &[_]u8{},

        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn handle(ctx: *anyopaque, kind: AsyncResultKind, request_handle: RequestHandle, success: bool, payload: []const u8) anyerror!void {
            _ = kind;
            _ = request_handle;
            _ = success;
            const host: *Host = @ptrCast(@alignCast(ctx));
            const state: *@This() = @ptrCast(@alignCast(host.ctx));
            state.handled += 1;
            if (state.payload.len > 0) std.testing.allocator.free(state.payload);
            state.payload = try std.testing.allocator.dupe(u8, payload);
        }
    };

    var state = TestState{};
    defer if (state.payload.len > 0) std.testing.allocator.free(state.payload);
    var host = Host{
        .ctx = &state,
        .caps = .{ .status = true, .command = true, .event = true, .job_results = true },
        .set_status = TestState.setStatus,
        .set_extension_status = TestState.setExtStatus,
    };
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    const handle = RequestHandle{ .id = 7, .request_generation = 11, .workspace_generation = 13 };
    try registry.registerAsyncResultHandler(.job, handle, TestState.handle);
    registry.emitJobResult(&host, handle, true, "done");
    try std.testing.expectEqual(@as(usize, 1), state.handled);
    try std.testing.expectEqualStrings("done", state.payload);

    const stale = RequestHandle{ .id = 7, .request_generation = 12, .workspace_generation = 13 };
    registry.emitJobResult(&host, stale, true, "ignored");
    try std.testing.expectEqual(@as(usize, 1), state.handled);
}

test "capability denial fails clearly" {
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
    var host = Host{
        .ctx = undefined,
        .caps = .{},
        .set_status = Dummy.setStatus,
        .set_extension_status = Dummy.setExtStatus,
    };
    try std.testing.expectError(error.PermissionDenied, host.setStatus("nope"));
}
