const std = @import("std");

pub const PaneKind = enum { editor, terminal, diagnostics, picker, custom, plugin_details };

pub const PaneAction = enum { open, update, invoke };

pub const PaneActionHandler = *const fn (ctx: *anyopaque, pane_id: u64, action: PaneAction, payload: []const u8) anyerror!void;

pub const PaneType = struct {
    id: u64,
    owner: []u8,
    name: []u8,
    handler: ?PaneActionHandler = null,
    ctx: ?*anyopaque = null,
};

pub const Pane = struct {
    id: u64,
    kind: PaneKind,
    type_id: ?u64 = null,
    title: []u8,
    focus: bool = false,
    width_hint: usize = 0,
    height_hint: usize = 0,
    streaming: std.array_list.Managed(u8),
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    panes: std.array_list.Managed(Pane),
    types: std.array_list.Managed(PaneType),
    focused_index: ?usize = null,
    next_id: u64 = 1,
    next_type_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{
            .allocator = allocator,
            .panes = std.array_list.Managed(Pane).init(allocator),
            .types = std.array_list.Managed(PaneType).init(allocator),
        };
    }

    pub fn deinit(self: *Manager) void {
        for (self.panes.items) |pane| {
            self.allocator.free(pane.title);
            pane.streaming.deinit();
        }
        for (self.types.items) |pane_type| {
            self.allocator.free(pane_type.owner);
            self.allocator.free(pane_type.name);
        }
        self.panes.deinit();
        self.types.deinit();
    }

    pub fn registerPaneType(self: *Manager, owner: []const u8, name: []const u8, ctx: *anyopaque, handler: ?PaneActionHandler) !u64 {
        if (self.findPaneTypeByName(owner, name)) |pane_type| {
            return pane_type.id;
        }
        const owner_copy = try self.allocator.dupe(u8, owner);
        errdefer self.allocator.free(owner_copy);
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        try self.types.append(.{
            .id = type_id,
            .owner = owner_copy,
            .name = name_copy,
            .handler = handler,
            .ctx = ctx,
        });
        return type_id;
    }

    pub fn open(self: *Manager, kind: PaneKind, title: []const u8) !u64 {
        const pane = Pane{
            .id = self.next_id,
            .kind = kind,
            .title = try self.allocator.dupe(u8, title),
            .streaming = std.array_list.Managed(u8).init(self.allocator),
        };
        self.next_id += 1;
        try self.panes.append(pane);
        if (self.focused_index == null) self.focused_index = 0;
        return pane.id;
    }

    pub fn createPaneOfType(self: *Manager, type_id: u64, title: []const u8) !u64 {
        if (self.findPaneTypeById(type_id) == null) return error.NotFound;
        const pane = Pane{
            .id = self.next_id,
            .kind = .custom,
            .type_id = type_id,
            .title = try self.allocator.dupe(u8, title),
            .streaming = std.array_list.Managed(u8).init(self.allocator),
        };
        self.next_id += 1;
        try self.panes.append(pane);
        if (self.focused_index == null) self.focused_index = 0;
        _ = self.triggerPaneAction(pane.id, .open, title);
        return pane.id;
    }

    pub fn focus(self: *Manager, pane_id: u64) bool {
        for (self.panes.items, 0..) |pane, idx| {
            if (pane.id == pane_id) {
                if (self.focused_index) |current| self.panes.items[current].focus = false;
                self.focused_index = idx;
                self.panes.items[idx].focus = true;
                return true;
            }
        }
        return false;
    }

    pub fn updatePaneState(self: *Manager, pane_id: u64, title: ?[]const u8, body: ?[]const u8) !bool {
        for (self.panes.items) |*pane| {
            if (pane.id != pane_id) continue;
            if (title) |next_title| {
                self.allocator.free(pane.title);
                pane.title = try self.allocator.dupe(u8, next_title);
            }
            if (body) |next_body| {
                pane.streaming.clearRetainingCapacity();
                try pane.streaming.appendSlice(next_body);
            }
            _ = self.triggerPaneAction(pane_id, .update, body orelse "");
            return true;
        }
        return false;
    }

    pub fn triggerPaneAction(self: *Manager, pane_id: u64, action: PaneAction, payload: []const u8) bool {
        const pane = self.findPaneById(pane_id) orelse return false;
        const type_id = pane.type_id orelse return false;
        const pane_type = self.findPaneTypeById(type_id) orelse return false;
        const handler = pane_type.handler orelse return true;
        const ctx = pane_type.ctx orelse return false;
        handler(ctx, pane_id, action, payload) catch return false;
        return true;
    }

    pub fn findByKind(self: *const Manager, kind: PaneKind) ?u64 {
        for (self.panes.items) |pane| {
            if (pane.kind == kind) return pane.id;
        }
        return null;
    }

    pub fn focusedPaneId(self: *const Manager) ?u64 {
        const idx = self.focused_index orelse return null;
        return self.panes.items[idx].id;
    }

    pub fn focusedPaneKind(self: *const Manager) ?PaneKind {
        const idx = self.focused_index orelse return null;
        return self.panes.items[idx].kind;
    }

    pub fn updateTitle(self: *Manager, pane_id: u64, title: []const u8) !bool {
        return try self.updatePaneState(pane_id, title, null);
    }

    pub fn setBody(self: *Manager, pane_id: u64, body: []const u8) !bool {
        return try self.updatePaneState(pane_id, null, body);
    }

    pub fn appendStreaming(self: *Manager, pane_id: u64, text: []const u8) !bool {
        for (self.panes.items) |*pane| {
            if (pane.id == pane_id) {
                try pane.streaming.appendSlice(text);
                return true;
            }
        }
        return false;
    }

    pub fn paneBody(self: *const Manager, pane_id: u64) ?[]const u8 {
        const pane = self.findPaneById(pane_id) orelse return null;
        return pane.streaming.items;
    }

    pub fn clearStreaming(self: *Manager, pane_id: u64) bool {
        for (self.panes.items) |*pane| {
            if (pane.id == pane_id) {
                pane.streaming.clearRetainingCapacity();
                return true;
            }
        }
        return false;
    }

    pub fn statusText(self: *const Manager, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "panes={d}", .{self.panes.items.len});
    }

    fn findPaneById(self: *const Manager, pane_id: u64) ?*Pane {
        for (self.panes.items) |*pane| {
            if (pane.id == pane_id) return pane;
        }
        return null;
    }

    fn findPaneTypeById(self: *const Manager, type_id: u64) ?*PaneType {
        for (self.types.items) |*pane_type| {
            if (pane_type.id == type_id) return pane_type;
        }
        return null;
    }

    fn findPaneTypeByName(self: *const Manager, owner: []const u8, name: []const u8) ?PaneType {
        for (self.types.items) |pane_type| {
            if (std.mem.eql(u8, pane_type.owner, owner) and std.mem.eql(u8, pane_type.name, name)) return pane_type;
        }
        return null;
    }
};

test "pane manager focus and update" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const id = try manager.open(.editor, "main");
    try std.testing.expect(manager.focus(id));
    try std.testing.expectEqualStrings("main", manager.panes.items[0].title);
    try std.testing.expect(try manager.updateTitle(id, "edited"));
    try std.testing.expectEqualStrings("edited", manager.panes.items[0].title);
}

test "pane manager registers types and updates pane state" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestState = struct {
        seen: usize = 0,

        fn handle(ctx: *anyopaque, pane_id: u64, action: PaneAction, payload: []const u8) anyerror!void {
            _ = pane_id;
            _ = action;
            _ = payload;
            const state: *@This() = @ptrCast(@alignCast(ctx));
            state.seen += 1;
        }
    };

    var state = TestState{};
    const type_id = try manager.registerPaneType("plugin-hello", "detail", &state, TestState.handle);
    const pane_id = try manager.createPaneOfType(type_id, "detail pane");
    try std.testing.expect(try manager.updatePaneState(pane_id, "updated detail pane", "body text"));
    try std.testing.expectEqualStrings("updated detail pane", manager.panes.items[0].title);
    try std.testing.expectEqualStrings("body text", manager.panes.items[0].streaming.items);
    try std.testing.expect(manager.triggerPaneAction(pane_id, .invoke, "ping"));
    try std.testing.expect(state.seen >= 3);
}
