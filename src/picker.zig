const std = @import("std");
const listpane = @import("listpane.zig");

pub const SourceState = listpane.SourceState;
pub const Item = listpane.Item;
pub const Picker = listpane.ListPane;

test "picker selection and query" {
    var picker = Picker.init(std.testing.allocator);
    defer picker.deinit();
    try picker.setQuery("abc");
    try picker.setItems(&.{
        .{ .id = 1, .label = "one" },
        .{ .id = 2, .label = "two" },
    });
    picker.moveSelection(1);
    try std.testing.expectEqual(@as(usize, 1), picker.selected);
}
