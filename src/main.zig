const std = @import("std");
const App = @import("editor.zig").App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var app = App.init(allocator, args) catch |err| switch (err) {
        error.HelpRequested => return,
        else => return err,
    };
    defer app.deinit();
    try app.run();
}

test {
    _ = @import("buffer.zig");
    _ = @import("builtins.zig");
    _ = @import("config.zig");
    _ = @import("terminal.zig");
}
