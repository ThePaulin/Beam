const std = @import("std");
const config_mod = @import("../config.zig");

pub const Mode = enum { normal, insert, replace, command, search, visual, select };

pub const Style = struct {
    fg: ?u8 = null,
    bg: ?u8 = null,
    bold: bool = false,
    dim: bool = false,
};

pub const Theme = struct {
    name: []const u8,
    content_bg: ?u8,
    border: u8,
    text: u8,
    muted: u8,
    line_no: u8,
    line_no_active: u8,
    accent: u8,
    accent_alt: u8,
    prompt_bg: u8,
    prompt_fg: u8,
    status_bg: u8,
    status_fg: u8,
    contrast_fg: u8,
    search_bg: u8,
    search_fg: u8,
    visual_bg: u8,
    visual_fg: u8,
    blur: bool,
    opacity: usize,

    fn beam(content_bg: ?u8, blur: bool, opacity: usize) Theme {
        return .{
            .name = "beam",
            .content_bg = content_bg,
            .border = 60,
            .text = 252,
            .muted = 246,
            .line_no = 244,
            .line_no_active = 81,
            .accent = 81,
            .accent_alt = 45,
            .prompt_bg = 235,
            .prompt_fg = 252,
            .status_bg = 235,
            .status_fg = 252,
            .contrast_fg = 16,
            .search_bg = 221,
            .search_fg = 16,
            .visual_bg = 81,
            .visual_fg = 16,
            .blur = blur,
            .opacity = opacity,
        };
    }

    fn nvchad(content_bg: ?u8, blur: bool, opacity: usize) Theme {
        return .{
            .name = "nvchad",
            .content_bg = content_bg,
            .border = 81,
            .text = 252,
            .muted = 245,
            .line_no = 244,
            .line_no_active = 81,
            .accent = 81,
            .accent_alt = 45,
            .prompt_bg = 235,
            .prompt_fg = 252,
            .status_bg = 235,
            .status_fg = 252,
            .contrast_fg = 16,
            .search_bg = 221,
            .search_fg = 16,
            .visual_bg = 81,
            .visual_fg = 16,
            .blur = blur,
            .opacity = opacity,
        };
    }

    pub fn resolve(name: []const u8, background_color: []const u8, blur: bool, opacity: usize) Theme {
        const content_bg = resolveBackgroundColor(background_color, opacity);
        if (std.ascii.eqlIgnoreCase(name, "nvchad") or std.ascii.eqlIgnoreCase(name, "chad")) {
            return Theme.nvchad(content_bg, blur, opacity);
        }
        return Theme.beam(content_bg, blur, opacity);
    }

    pub fn modeStyle(self: Theme, mode: Mode) Style {
        return switch (mode) {
            .normal => .{ .fg = self.contrast_fg, .bg = self.accent, .bold = true },
            .insert => .{ .fg = self.contrast_fg, .bg = self.accent_alt, .bold = true },
            .replace => .{ .fg = self.contrast_fg, .bg = self.accent_alt, .bold = true },
            .command => .{ .fg = self.contrast_fg, .bg = self.prompt_bg, .bold = true },
            .search => .{ .fg = self.contrast_fg, .bg = self.search_bg, .bold = true },
            .visual => .{ .fg = self.contrast_fg, .bg = self.visual_bg, .bold = true },
            .select => .{ .fg = self.contrast_fg, .bg = self.visual_bg, .bold = true },
        };
    }

    pub fn textStyle(self: Theme, active: bool) Style {
        return .{
            .fg = if (active) self.text else self.muted,
            .bg = self.contentBg(),
            .dim = self.glassMode(),
        };
    }

    pub fn lineNumberStyle(self: Theme, active: bool) Style {
        return .{
            .fg = if (active) self.line_no_active else if (self.glassMode()) self.muted else self.line_no,
            .bg = self.contentBg(),
            .dim = self.glassMode(),
        };
    }

    pub fn searchStyle(self: Theme) Style {
        return .{ .fg = if (self.glassMode()) self.muted else self.search_fg, .bg = self.search_bg, .bold = !self.glassMode(), .dim = self.glassMode() };
    }

    pub fn visualStyle(self: Theme) Style {
        return .{ .fg = if (self.glassMode()) self.muted else self.visual_fg, .bg = self.visual_bg, .bold = !self.glassMode(), .dim = self.glassMode() };
    }

    pub fn separatorStyle(self: Theme) Style {
        return .{ .fg = if (self.glassMode()) self.muted else self.border, .bg = self.contentBg(), .dim = self.glassMode() };
    }

    pub fn statusStyle(self: Theme) Style {
        return .{ .fg = self.status_fg, .bg = self.status_bg };
    }

    pub fn promptStyle(self: Theme) Style {
        return .{ .fg = self.prompt_fg, .bg = self.prompt_bg };
    }

    fn contentBg(self: Theme) ?u8 {
        if (self.content_bg) |bg| return blendOpacity(bg, self.opacity);
        return null;
    }

    fn glassMode(self: Theme) bool {
        return self.blur or self.opacity < 100;
    }
};

pub fn modeIconText(config: *const config_mod.Config, mode: Mode) []const u8 {
    return switch (mode) {
        .normal => if (std.mem.eql(u8, config.status_bar_icon, "default")) "\u{e795}" else config.status_bar_icon,
        .insert => config.status_bar_insert_icon,
        .replace => config.status_bar_insert_icon,
        .command => "",
        .search => "",
        .visual => config.status_bar_visual_icon,
        .select => config.status_bar_visual_icon,
    };
}

pub fn modeLabel(mode: Mode) []const u8 {
    return switch (mode) {
        .normal => "NORMAL",
        .insert => "INSERT",
        .replace => "REPLACE",
        .command => "COMMAND",
        .search => "SEARCH",
        .visual => "VISUAL",
        .select => "SELECT",
    };
}

pub fn resolveBackgroundColor(spec: []const u8, opacity: usize) ?u8 {
    if (opacity == 0) return null;
    if (std.mem.eql(u8, spec, "") or std.mem.eql(u8, spec, "terminal") or std.mem.eql(u8, spec, "inherit") or std.mem.eql(u8, spec, "default")) {
        return null;
    }
    if (parseNamedColor(spec)) |color| return color;
    if (spec.len > 0 and spec[0] == '#') {
        return rgbToXterm(spec[1..]) orelse null;
    }
    const numeric = std.fmt.parseUnsigned(u16, spec, 10) catch return null;
    if (numeric > 255) return null;
    return @as(u8, @intCast(numeric));
}

fn parseNamedColor(spec: []const u8) ?u8 {
    return if (std.ascii.eqlIgnoreCase(spec, "black")) 0 else if (std.ascii.eqlIgnoreCase(spec, "red")) 1 else if (std.ascii.eqlIgnoreCase(spec, "green")) 2 else if (std.ascii.eqlIgnoreCase(spec, "yellow")) 3 else if (std.ascii.eqlIgnoreCase(spec, "blue")) 4 else if (std.ascii.eqlIgnoreCase(spec, "magenta")) 5 else if (std.ascii.eqlIgnoreCase(spec, "cyan")) 6 else if (std.ascii.eqlIgnoreCase(spec, "white")) 7 else if (std.ascii.eqlIgnoreCase(spec, "bright_black") or std.ascii.eqlIgnoreCase(spec, "gray") or std.ascii.eqlIgnoreCase(spec, "grey")) 8 else if (std.ascii.eqlIgnoreCase(spec, "bright_red")) 9 else if (std.ascii.eqlIgnoreCase(spec, "bright_green")) 10 else if (std.ascii.eqlIgnoreCase(spec, "bright_yellow")) 11 else if (std.ascii.eqlIgnoreCase(spec, "bright_blue")) 12 else if (std.ascii.eqlIgnoreCase(spec, "bright_magenta")) 13 else if (std.ascii.eqlIgnoreCase(spec, "bright_cyan")) 14 else if (std.ascii.eqlIgnoreCase(spec, "bright_white")) 15 else null;
}

fn rgbToXterm(spec: []const u8) ?u8 {
    if (spec.len != 6) return null;
    const r = std.fmt.parseUnsigned(u8, spec[0..2], 16) catch return null;
    const g = std.fmt.parseUnsigned(u8, spec[2..4], 16) catch return null;
    const b = std.fmt.parseUnsigned(u8, spec[4..6], 16) catch return null;
    return rgbToXtermIndex(r, g, b);
}

fn rgbToXtermIndex(r: u8, g: u8, b: u8) u8 {
    const gray = @as(u16, @intCast((@as(u16, r) + @as(u16, g) + @as(u16, b)) / 3));
    if (@max(@max(r, g), b) == @min(@min(r, g), b)) {
        const level: u8 = @as(u8, @intCast(@min(@as(u16, 23), gray / 11)));
        return @as(u8, @intCast(232 + level));
    }
    const rc: u8 = @as(u8, @intCast(@min(@as(u16, 5), (@as(u16, r) * 5 + 127) / 255)));
    const gc: u8 = @as(u8, @intCast(@min(@as(u16, 5), (@as(u16, g) * 5 + 127) / 255)));
    const bc: u8 = @as(u8, @intCast(@min(@as(u16, 5), (@as(u16, b) * 5 + 127) / 255)));
    return @as(u8, @intCast(16 + 36 * rc + 6 * gc + bc));
}

fn blendOpacity(color: u8, opacity: usize) u8 {
    if (opacity >= 100) return color;
    const percent = @as(u16, @intCast(opacity));
    const rgb = xtermToRgb(color);
    const r = @as(u8, @intCast((@as(u16, rgb.r) * percent) / 100));
    const g = @as(u8, @intCast((@as(u16, rgb.g) * percent) / 100));
    const b = @as(u8, @intCast((@as(u16, rgb.b) * percent) / 100));
    return rgbToXtermIndex(r, g, b);
}

const Rgb = struct { r: u8, g: u8, b: u8 };

fn xtermToRgb(color: u8) Rgb {
    if (color < 16) {
        return switch (color) {
            0 => .{ .r = 0, .g = 0, .b = 0 },
            1 => .{ .r = 205, .g = 0, .b = 0 },
            2 => .{ .r = 0, .g = 205, .b = 0 },
            3 => .{ .r = 205, .g = 205, .b = 0 },
            4 => .{ .r = 0, .g = 0, .b = 238 },
            5 => .{ .r = 205, .g = 0, .b = 205 },
            6 => .{ .r = 0, .g = 205, .b = 205 },
            7 => .{ .r = 229, .g = 229, .b = 229 },
            8 => .{ .r = 127, .g = 127, .b = 127 },
            9 => .{ .r = 255, .g = 0, .b = 0 },
            10 => .{ .r = 0, .g = 255, .b = 0 },
            11 => .{ .r = 255, .g = 255, .b = 0 },
            12 => .{ .r = 92, .g = 92, .b = 255 },
            13 => .{ .r = 255, .g = 0, .b = 255 },
            14 => .{ .r = 0, .g = 255, .b = 255 },
            else => .{ .r = 255, .g = 255, .b = 255 },
        };
    }
    if (color >= 232) {
        const level = @as(u8, @intCast(8 + (color - 232) * 10));
        return .{ .r = level, .g = level, .b = level };
    }
    const idx = color - 16;
    const r = idx / 36;
    const g = (idx % 36) / 6;
    const b = idx % 6;
    const component = struct {
        fn level(v: u8) u8 {
            return if (v == 0) 0 else @as(u8, @intCast(55 + v * 40));
        }
    };
    return .{ .r = component.level(r), .g = component.level(g), .b = component.level(b) };
}

pub fn writeStyle(writer: anytype, style: Style) !void {
    try writer.writeAll("\x1b[0m");
    if (style.fg) |fg| {
        try writer.print("\x1b[38;5;{d}m", .{fg});
    }
    if (style.bg) |bg| {
        try writer.print("\x1b[48;5;{d}m", .{bg});
    }
    if (style.bold) {
        try writer.writeAll("\x1b[1m");
    }
    if (style.dim) {
        try writer.writeAll("\x1b[2m");
    }
}

pub fn writeStyledText(writer: anytype, style: Style, text: []const u8) !void {
    try writeStyle(writer, style);
    try writer.writeAll(text);
}

pub fn renderOverlayTitle(writer: anytype, style: Style, cols: usize, title: []const u8) !void {
    try writeStyle(writer, style);
    try writer.writeByte(' ');
    const title_text = clipText(title, if (cols > 1) cols - 1 else 0);
    try writer.writeAll(title_text);
    const title_width = displayWidth(title_text) + 1;
    try padToColumns(writer, title_width, cols);
    try writer.writeAll("\x1b[0m");
}

pub fn renderOverlayLine(writer: anytype, style: Style, cols: usize, line: ?[]const u8) !void {
    try writeStyle(writer, style);
    if (line) |body| {
        try writer.writeByte(' ');
        try writer.writeAll(clipText(body, if (cols > 1) cols - 1 else 0));
    } else {
        try writer.writeByte(' ');
    }
    try padToColumns(writer, 1, cols);
    try writer.writeAll("\x1b[0m");
}

pub fn renderBlankRow(writer: anytype, style: Style, cols: usize) !void {
    try writeStyle(writer, style);
    try writer.writeByte(' ');
    try padToColumns(writer, 1, cols);
    try writer.writeAll("\x1b[0m");
}

pub fn padToColumns(writer: anytype, width: usize, cols: usize) !void {
    if (cols > width) {
        var padding = cols - width;
        while (padding > 0) : (padding -= 1) {
            try writer.writeByte(' ');
        }
    }
}

pub fn utf8CharLen(byte: u8) usize {
    return if (byte < 0x80) 1 else if ((byte & 0xe0) == 0xc0) 2 else if ((byte & 0xf0) == 0xe0) 3 else if ((byte & 0xf8) == 0xf0) 4 else 1;
}

pub fn displayWidth(text: []const u8) usize {
    var width: usize = 0;
    var idx: usize = 0;
    while (idx < text.len) {
        const len = utf8CharLen(text[idx]);
        idx += @min(len, text.len - idx);
        width += 1;
    }
    return width;
}

pub fn clipText(text: []const u8, width: usize) []const u8 {
    if (width == 0) return "";
    var idx: usize = 0;
    var used: usize = 0;
    while (idx < text.len and used < width) {
        const len = utf8CharLen(text[idx]);
        if (idx + len > text.len) break;
        idx += len;
        used += 1;
    }
    return text[0..idx];
}

test "theme resolution keeps beam default and recognizes nvchad" {
    const beam_theme = Theme.resolve("beam", "terminal", false, 100);
    const fallback_theme = Theme.resolve("unknown", "#101010", true, 80);
    const nvchad_theme = Theme.resolve("nvchad", "81", false, 100);

    try std.testing.expectEqualStrings("beam", beam_theme.name);
    try std.testing.expectEqualStrings("beam", fallback_theme.name);
    try std.testing.expectEqualStrings("nvchad", nvchad_theme.name);
    try std.testing.expect(beam_theme.content_bg == null);
    try std.testing.expect(fallback_theme.content_bg != null);
    try std.testing.expect(nvchad_theme.content_bg != null);
}

test "overlay title clips to the available width" {
    var backing: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&backing);

    try renderOverlayTitle(stream.writer(), .{ .fg = 252, .bg = 235 }, 6, "plugins");

    const rendered = stream.getWritten();
    try std.testing.expect(rendered.len < backing.len);
    try std.testing.expect(std.mem.indexOf(u8, rendered, " plugi") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, " plugins") == null);
}

test "overlay body line pads within bounds" {
    var backing: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&backing);

    try renderOverlayLine(stream.writer(), .{ .fg = 252, .bg = 235 }, 8, "> hello");

    const rendered = stream.getWritten();
    try std.testing.expect(rendered.len < backing.len);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "> hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[0m") != null);
}
