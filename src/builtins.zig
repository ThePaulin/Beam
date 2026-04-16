const std = @import("std");

pub const Host = struct {
    ctx: *anyopaque,
    set_status: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
    set_extension_status: *const fn (ctx: *anyopaque, text: []const u8) anyerror!void,
};

pub const CommandHandler = *const fn (host: *Host, args: []const []const u8) anyerror!void;
pub const EventHandler = *const fn (host: *Host, payload: []const u8) anyerror!void;

pub const Command = struct {
    name: []u8,
    description: []u8,
    handler: CommandHandler,
};

pub const EventListener = struct {
    event: []u8,
    handler: EventHandler,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    commands: std.array_list.Managed(Command),
    events: std.array_list.Managed(EventListener),
    status: std.array_list.Managed(u8),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .commands = std.array_list.Managed(Command).init(allocator),
            .events = std.array_list.Managed(EventListener).init(allocator),
            .status = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.clearRegistrations();
        self.commands.deinit();
        self.events.deinit();
        self.status.deinit();
    }

    pub fn rebuild(self: *Registry, host: *Host, enabled: []const []const u8) !void {
        self.clearRegistrations();
        self.status.clearRetainingCapacity();
        try self.registerCoreModules(host, enabled);
    }

    pub fn invokeCommand(self: *Registry, host: *Host, name: []const u8, args: []const []const u8) !bool {
        for (self.commands.items) |command| {
            if (std.mem.eql(u8, command.name, name)) {
                try command.handler(host, args);
                return true;
            }
        }
        return false;
    }

    pub fn emit(self: *Registry, host: *Host, event: []const u8, payload: []const u8) void {
        for (self.events.items) |listener| {
            if (!std.mem.eql(u8, listener.event, event)) continue;
            listener.handler(host, payload) catch |err| {
                std.debug.print("[beam] builtin {s} event {s} failed: {s}\n", .{ listener.event, event, @errorName(err) });
            };
        }
    }

    pub fn statusText(self: *const Registry) []const u8 {
        return self.status.items;
    }

    pub fn setStatus(self: *Registry, text: []const u8) !void {
        self.status.clearRetainingCapacity();
        try self.status.appendSlice(text);
    }

    fn registerCoreModules(self: *Registry, host: *Host, enabled: []const []const u8) !void {
        if (enabled.len == 0) return;
        for (enabled) |name| {
            if (std.mem.eql(u8, name, "hello")) {
                try self.registerHello(host);
                continue;
            }
            std.debug.print("[beam] unknown builtin module {s}\n", .{name});
        }
    }

    fn registerHello(self: *Registry, host: *Host) !void {
        try self.registerCommand("hello", "show a native built-in status message", helloCommand);
        try self.registerEvent("buffer_open", helloBufferOpen);
        try self.registerEvent("buffer_save", helloBufferSave);
        try host.set_extension_status(host.ctx, "hello built-in ready");
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
};

fn helloCommand(host: *Host, args: []const []const u8) !void {
    _ = args;
    try host.set_extension_status(host.ctx, "hello from native built-ins");
}

fn helloBufferOpen(host: *Host, payload: []const u8) !void {
    _ = payload;
    try host.set_extension_status(host.ctx, "hello built-in saw buffer open");
}

fn helloBufferSave(host: *Host, payload: []const u8) !void {
    _ = payload;
    try host.set_extension_status(host.ctx, "hello built-in saw buffer save");
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
        .set_status = TestState.setStatus,
        .set_extension_status = TestState.setExtStatus,
    };
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.rebuild(&host, &.{"hello"});
    try std.testing.expect(try registry.invokeCommand(&host, "hello", &.{}));
    try std.testing.expectEqualStrings("hello from native built-ins", state.ext_status);
    registry.emit(&host, "buffer_open", "{}");
    try std.testing.expectEqualStrings("hello built-in saw buffer open", state.ext_status);
}
