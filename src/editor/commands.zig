const std = @import("std");

pub fn matchesCommand(head: []const u8, aliases: []const []const u8, configured: []const u8) bool {
    const cfg = if (configured.len > 0 and configured[0] == ':') configured[1..] else configured;
    if (std.mem.eql(u8, head, cfg) or std.mem.eql(u8, head, configured)) return true;
    for (aliases) |alias| {
        if (std.mem.eql(u8, head, alias)) return true;
    }
    return false;
}

pub fn stripVisualRangePrefix(command: []const u8) []const u8 {
    if (std.mem.startsWith(u8, command, "'<,'>")) return std.mem.trimLeft(u8, command["'<,'>".len..], " \t");
    if (std.mem.startsWith(u8, command, "'<,'")) return std.mem.trimLeft(u8, command["'<,'".len..], " \t");
    return command;
}

test "matchesCommand accepts aliases and configured names" {
    try std.testing.expect(matchesCommand("help", &.{ "h", "help" }, ":help"));
    try std.testing.expect(matchesCommand("wq", &.{ "wq", "x" }, ":wq"));
    try std.testing.expect(matchesCommand("q!", &.{"q!"}, ":q!"));
}

test "stripVisualRangePrefix removes quoted ranges" {
    try std.testing.expectEqualStrings("sort", stripVisualRangePrefix("'<,'>sort"));
    try std.testing.expectEqualStrings("sort", stripVisualRangePrefix("'<,' sort"));
}
