const std = @import("std");
const builtin = @import("builtin");

pub const Size = struct {
    cols: usize = 80,
    rows: usize = 24,
};

pub const RawMode = struct {
    file: std.fs.File,
    original_posix: ?std.posix.termios = null,
    original_windows_mode: ?u32 = null,

    pub fn enable(file: std.fs.File) !RawMode {
        var mode = RawMode{ .file = file };
        if (builtin.os.tag == .windows) {
            var current: u32 = 0;
            if (std.os.windows.kernel32.GetConsoleMode(file.handle, &current) != 0) {
                mode.original_windows_mode = current;
                const new_mode = (current & ~(@as(u32, 0x0001) | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0040)) | 0x0200;
                _ = std.os.windows.kernel32.SetConsoleMode(file.handle, new_mode);
            }
            return mode;
        }

        var term = try std.posix.tcgetattr(file.handle);
        mode.original_posix = term;
        if (@hasField(@TypeOf(term.lflag), "ECHO")) term.lflag.ECHO = false;
        if (@hasField(@TypeOf(term.lflag), "ICANON")) term.lflag.ICANON = false;
        if (@hasField(@TypeOf(term.lflag), "IEXTEN")) term.lflag.IEXTEN = false;
        if (@hasField(@TypeOf(term.lflag), "ISIG")) term.lflag.ISIG = false;
        try std.posix.tcsetattr(file.handle, .FLUSH, term);
        return mode;
    }

    pub fn disable(self: *RawMode) void {
        if (builtin.os.tag == .windows) {
            if (self.original_windows_mode) |mode| {
                _ = std.os.windows.kernel32.SetConsoleMode(self.file.handle, mode);
            }
            return;
        }
        if (self.original_posix) |term| {
            std.posix.tcsetattr(self.file.handle, .FLUSH, term) catch {};
        }
    }
};

pub fn size(stdout_file: std.fs.File) Size {
    if (builtin.os.tag == .windows) {
        var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(stdout_file.handle, &info) != 0) {
            const rows = @as(usize, @intCast(info.srWindow.Bottom - info.srWindow.Top + 1));
            const cols = @as(usize, @intCast(info.srWindow.Right - info.srWindow.Left + 1));
            return .{ .cols = cols, .rows = rows };
        }
        return .{};
    }

    var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    if (std.posix.system.ioctl(stdout_file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0) {
        return .{ .cols = ws.col, .rows = ws.row };
    }
    return .{};
}

pub fn clear(writer: anytype) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
}

pub fn hideCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25l");
}

pub fn showCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25h");
}

pub fn setCursorShape(writer: anytype, block: bool) !void {
    // DECSCUSR: 2 = steady block, 6 = steady bar.
    if (block) {
        try writer.writeAll("\x1b[2 q");
    } else {
        try writer.writeAll("\x1b[6 q");
    }
}

pub fn enterAltScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[?1049h");
}

pub fn leaveAltScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[?1049l");
}
