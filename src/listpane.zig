const std = @import("std");

pub const SourceState = enum { idle, loading, ready, failed };

pub const Item = struct {
    id: u64,
    path: ?[]u8 = null,
    row: usize = 0,
    col: usize = 0,
    label: []u8,
    detail: ?[]u8 = null,
    score: i32 = 0,
};

pub const ListPane = struct {
    allocator: std.mem.Allocator,
    query: std.array_list.Managed(u8),
    items: std.array_list.Managed(Item),
    selected: usize = 0,
    preview: ?[]u8 = null,
    state: SourceState = .idle,
    error_message: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) ListPane {
        return .{
            .allocator = allocator,
            .query = std.array_list.Managed(u8).init(allocator),
            .items = std.array_list.Managed(Item).init(allocator),
        };
    }

    pub fn deinit(self: *ListPane) void {
        self.clearItems();
        self.query.deinit();
        self.items.deinit();
        if (self.preview) |text| self.allocator.free(text);
        if (self.error_message) |text| self.allocator.free(text);
    }

    pub fn clear(self: *ListPane) void {
        self.clearItems();
        self.query.clearRetainingCapacity();
        self.selected = 0;
        self.state = .idle;
        self.clearPreview();
        self.clearError();
    }

    pub fn setQuery(self: *ListPane, query: []const u8) !void {
        self.query.clearRetainingCapacity();
        try self.query.appendSlice(query);
        self.selected = 0;
    }

    pub fn setItems(self: *ListPane, items: []const Item) !void {
        self.clearItems();
        try self.items.ensureTotalCapacity(items.len);
        for (items) |item| {
            try self.items.append(.{
                .id = item.id,
                .path = if (item.path) |path| try self.allocator.dupe(u8, path) else null,
                .row = item.row,
                .col = item.col,
                .label = try self.allocator.dupe(u8, item.label),
                .detail = if (item.detail) |detail| try self.allocator.dupe(u8, detail) else null,
                .score = item.score,
            });
        }
        self.selected = if (self.items.items.len > 0) @min(self.selected, self.items.items.len - 1) else 0;
        self.state = .ready;
    }

    pub fn appendItem(self: *ListPane, item: Item) !void {
        try self.items.append(.{
            .id = item.id,
            .path = if (item.path) |path| try self.allocator.dupe(u8, path) else null,
            .row = item.row,
            .col = item.col,
            .label = try self.allocator.dupe(u8, item.label),
            .detail = if (item.detail) |detail| try self.allocator.dupe(u8, detail) else null,
            .score = item.score,
        });
        self.state = .ready;
    }

    pub fn appendOwnedItem(self: *ListPane, item: Item) !void {
        try self.items.append(item);
        self.state = .ready;
    }

    pub fn setState(self: *ListPane, state: SourceState) void {
        self.state = state;
    }

    pub fn setPreview(self: *ListPane, preview: ?[]const u8) !void {
        self.clearPreview();
        if (preview) |text| {
            self.preview = try self.allocator.dupe(u8, text);
        }
    }

    pub fn setError(self: *ListPane, message: []const u8) !void {
        self.clearError();
        self.error_message = try self.allocator.dupe(u8, message);
        self.state = .failed;
    }

    pub fn clearError(self: *ListPane) void {
        if (self.error_message) |text| self.allocator.free(text);
        self.error_message = null;
    }

    pub fn clearPreview(self: *ListPane) void {
        if (self.preview) |text| self.allocator.free(text);
        self.preview = null;
    }

    pub fn moveSelection(self: *ListPane, delta: isize) void {
        if (self.items.items.len == 0) return;
        const current: isize = @intCast(self.selected);
        const max_index: isize = @intCast(self.items.items.len - 1);
        const next = std.math.clamp(current + delta, 0, max_index);
        self.selected = @intCast(next);
    }

    pub fn selectedItem(self: *const ListPane) ?Item {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.selected];
    }

    pub fn statusText(self: *const ListPane, allocator: std.mem.Allocator, label: []const u8) ![]u8 {
        if (self.state == .failed) {
            if (self.error_message) |message| {
                return try std.fmt.allocPrint(allocator, "{s} error: {s}", .{ label, message });
            }
        }
        return try std.fmt.allocPrint(allocator, "{s} [{d}/{d}]", .{ if (self.query.items.len > 0) self.query.items else label, if (self.items.items.len == 0) 0 else self.selected + 1, self.items.items.len });
    }

    fn clearItems(self: *ListPane) void {
        for (self.items.items) |item| {
            if (item.path) |path| self.allocator.free(path);
            self.allocator.free(item.label);
            if (item.detail) |detail| self.allocator.free(detail);
        }
        self.items.clearRetainingCapacity();
    }
};

test "list pane selection and query" {
    var pane = ListPane.init(std.testing.allocator);
    defer pane.deinit();
    try pane.setQuery("abc");
    const one = try std.testing.allocator.dupe(u8, "one");
    defer std.testing.allocator.free(one);
    const two = try std.testing.allocator.dupe(u8, "two");
    defer std.testing.allocator.free(two);
    try pane.setItems(&.{
        .{ .id = 1, .label = one },
        .{ .id = 2, .label = two },
    });
    pane.moveSelection(1);
    try std.testing.expectEqual(@as(usize, 1), pane.selected);
}
