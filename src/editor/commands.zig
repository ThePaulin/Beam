const std = @import("std");

pub const CommandSpec = struct {
    name: []const u8,
    aliases: []const []const u8,
    description: []const u8,
};

pub const builtin_commands: []const CommandSpec = &.{
    .{ .name = "help", .aliases = &.{ "h" }, .description = "show help" },
    .{ .name = "saveas", .aliases = &.{ "sav" }, .description = "save buffer with new name" },
    .{ .name = "close", .aliases = &.{ "clo" }, .description = "close current buffer" },
    .{ .name = "terminal", .aliases = &.{ "ter" }, .description = "open terminal" },
    .{ .name = "registers", .aliases = &.{ "reg" }, .description = "show registers" },
    .{ .name = "plugins", .aliases = &.{}, .description = "show plugins" },
    .{ .name = "marks", .aliases = &.{ "ma" }, .description = "show marks" },
    .{ .name = "delmarks", .aliases = &.{}, .description = "delete marks" },
    .{ .name = "jumps", .aliases = &.{ "ju" }, .description = "show jump list" },
    .{ .name = "vimgrep", .aliases = &.{}, .description = "search with vimgrep" },
    .{ .name = "grep", .aliases = &.{}, .description = "search project" },
    .{ .name = "pickgrep", .aliases = &.{}, .description = "picker search" },
    .{ .name = "files", .aliases = &.{}, .description = "file picker" },
    .{ .name = "symbols", .aliases = &.{}, .description = "symbol picker" },
    .{ .name = "lsp", .aliases = &.{}, .description = "LSP commands" },
    .{ .name = "diagnostics", .aliases = &.{}, .description = "show diagnostics" },
    .{ .name = "dnext", .aliases = &.{}, .description = "next diagnostic" },
    .{ .name = "dprev", .aliases = &.{}, .description = "previous diagnostic" },
    .{ .name = "dopen", .aliases = &.{}, .description = "open diagnostic" },
    .{ .name = "pnext", .aliases = &.{}, .description = "next picker item" },
    .{ .name = "pprev", .aliases = &.{}, .description = "previous picker item" },
    .{ .name = "popen", .aliases = &.{}, .description = "open picker selection" },
    .{ .name = "sort", .aliases = &.{}, .description = "sort lines" },
    .{ .name = "cnext", .aliases = &.{ "cn" }, .description = "next quickfix item" },
    .{ .name = "cprevious", .aliases = &.{ "cp" }, .description = "previous quickfix item" },
    .{ .name = "copen", .aliases = &.{ "cope" }, .description = "open quickfix list" },
    .{ .name = "cclose", .aliases = &.{ "ccl" }, .description = "close quickfix" },
    .{ .name = "diffthis", .aliases = &.{}, .description = "enable diff mode" },
    .{ .name = "diffoff", .aliases = &.{ "diffo" }, .description = "disable diff mode" },
    .{ .name = "diffupdate", .aliases = &.{ "diffu" }, .description = "update diff" },
    .{ .name = "diffget", .aliases = &.{}, .description = "diff get" },
    .{ .name = "diffput", .aliases = &.{}, .description = "diff put" },
    .{ .name = "changes", .aliases = &.{}, .description = "show changes" },
    .{ .name = "open", .aliases = &.{}, .description = "open file" },
    .{ .name = "edit", .aliases = &.{ "e" }, .description = "edit file" },
    .{ .name = "bnext", .aliases = &.{ "bn" }, .description = "next buffer" },
    .{ .name = "bprevious", .aliases = &.{ "bp" }, .description = "previous buffer" },
    .{ .name = "bdelete", .aliases = &.{ "bd" }, .description = "delete buffer" },
    .{ .name = "buffer", .aliases = &.{ "b" }, .description = "switch to buffer" },
    .{ .name = "buffers", .aliases = &.{ "ls" }, .description = "list buffers" },
    .{ .name = "tabnew", .aliases = &.{}, .description = "new tab" },
    .{ .name = "tabclose", .aliases = &.{ "tabc" }, .description = "close tab" },
    .{ .name = "tabonly", .aliases = &.{ "tabo" }, .description = "close other tabs" },
    .{ .name = "tabmove", .aliases = &.{}, .description = "move tab" },
    .{ .name = "split", .aliases = &.{ "sp" }, .description = "horizontal split" },
    .{ .name = "vsplit", .aliases = &.{ "vs" }, .description = "vertical split" },
    .{ .name = "builtin", .aliases = &.{}, .description = "invoke builtin command" },
    .{ .name = "plugin", .aliases = &.{}, .description = "invoke plugin command" },
    .{ .name = "reload-config", .aliases = &.{}, .description = "reload configuration" },
    .{ .name = "refresh-sources", .aliases = &.{ "refresh" }, .description = "refresh sources" },
    .{ .name = "w", .aliases = &.{}, .description = "write buffer" },
    .{ .name = "wq", .aliases = &.{ "x" }, .description = "write and quit" },
    .{ .name = "wqa", .aliases = &.{}, .description = "write all and quit" },
    .{ .name = "q!", .aliases = &.{}, .description = "force quit" },
    .{ .name = "quit", .aliases = &.{ "q" }, .description = "quit" },
    .{ .name = "!", .aliases = &.{}, .description = "shell command" },
    .{ .name = "ZZ", .aliases = &.{}, .description = "write and quit" },
    .{ .name = "ZQ", .aliases = &.{}, .description = "quit without saving" },
};

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

pub fn matchCompletions(prefix: []const u8, allocator: std.mem.Allocator) ![]const CommandSpec {
    if (prefix.len == 0) {
        return builtin_commands;
    }
    var count: usize = 0;
    for (builtin_commands) |cmd| {
        if (std.ascii.startsWithIgnoreCase(cmd.name, prefix)) {
            count += 1;
        } else {
            for (cmd.aliases) |alias| {
                if (std.ascii.startsWithIgnoreCase(alias, prefix)) {
                    count += 1;
                    break;
                }
            }
        }
    }
    var result = try allocator.alloc(CommandSpec, count);
    var idx: usize = 0;
    for (builtin_commands) |cmd| {
        if (std.ascii.startsWithIgnoreCase(cmd.name, prefix)) {
            result[idx] = cmd;
            idx += 1;
        } else {
            for (cmd.aliases) |alias| {
                if (std.ascii.startsWithIgnoreCase(alias, prefix)) {
                    result[idx] = cmd;
                    idx += 1;
                    break;
                }
            }
        }
    }
    return result;
}

test "stripVisualRangePrefix removes quoted ranges" {
    try std.testing.expectEqualStrings("sort", stripVisualRangePrefix("'<,'>sort"));
    try std.testing.expectEqualStrings("sort", stripVisualRangePrefix("'<,' sort"));
}
