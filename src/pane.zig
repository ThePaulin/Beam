const std = @import("std");

pub const PaneKind = enum { editor, terminal, diagnostics, picker, custom, plugin_details };

pub const Pane = struct {
    id: u64,
    kind: PaneKind,
    title: []u8,
    focus: bool = false,
    width_hint: usize = 0,
    height_hint: usize = 0,
    streaming: std.array_list.Managed(u8),
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    panes: std.array_list.Managed(Pane),
    focused_index: ?usize = null,
    next_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{
            .allocator = allocator,
            .panes = std.array_list.Managed(Pane).init(allocator),
        };
    }

    pub fn deinit(self: *Manager) void {
        for (self.panes.items) |pane| {
            self.allocator.free(pane.title);
            pane.streaming.deinit();
        }
        self.panes.deinit();
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
        for (self.panes.items) |*pane| {
            if (pane.id == pane_id) {
                self.allocator.free(pane.title);
                pane.title = try self.allocator.dupe(u8, title);
                return true;
            }
        }
        return false;
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
