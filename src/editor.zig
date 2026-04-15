const std = @import("std");
const builtin = @import("builtin");
const buffer_mod = @import("buffer.zig");
const config_mod = @import("config.zig");
const plugin_mod = @import("plugin.zig");
const terminal_mod = @import("terminal.zig");

const NormalAction = enum {
    move_left,
    move_down,
    move_up,
    move_right,
    move_line_start,
    move_line_nonblank,
    move_line_last_nonblank,
    move_line_end,
    move_doc_start,
    move_doc_middle,
    move_doc_end,
    tab_next,
    tab_prev,
    window_split_horizontal,
    window_split_vertical,
    window_new,
    window_switch,
    window_close,
    window_exchange,
    window_resize_increase,
    window_resize_decrease,
    window_resize_wider,
    window_resize_narrower,
    window_maximize_width,
    window_maximize_height,
    window_equalize,
    window_to_tab,
    window_left,
    window_right,
    window_up,
    window_down,
    window_far_left,
    window_far_right,
    window_far_bottom,
    window_far_top,
    fold_create,
    fold_delete,
    fold_toggle,
    fold_open,
    fold_close,
    fold_open_all,
    fold_close_all,
    fold_toggle_enabled,
    fold_delete_all,
    diff_get,
    diff_put,
    diff_this,
    diff_off,
    diff_update,
    diff_next_change,
    diff_prev_change,
    move_word_forward,
    move_word_forward_big,
    move_word_backward,
    move_word_backward_big,
    move_word_end,
    move_word_end_big,
    move_word_end_backward,
    move_word_end_backward_big,
    move_paragraph_forward,
    move_paragraph_backward,
    move_sentence_forward,
    move_sentence_backward,
    scroll_up,
    scroll_down,
    jump_history_forward,
    jump_history_backward,
    switch_previous_buffer,
    find_forward,
    find_backward,
    find_forward_before,
    find_backward_before,
    repeat_find_forward,
    repeat_find_backward,
    delete_char,
    replace_char,
    substitute_char,
    substitute_line,
    insert_before,
    insert_at_bol,
    append_after,
    append_eol,
    open_below,
    open_above,
    delete_line,
    delete_to_bol,
    yank_line,
    paste_after,
    paste_before,
    undo,
    redo,
    delete_word,
    yank_word,
    delete_to_eol,
    change_word,
    change_line,
    change_to_eol,
    join_line_space,
    join_line_nospace,
    paste_after_keep_cursor,
    paste_before_keep_cursor,
    indent_line,
    dedent_line,
    toggle_case_char,
    toggle_case_word,
    lowercase_word,
    uppercase_word,
    viewport_top,
    viewport_middle,
    viewport_bottom,
    save,
    save_as,
    close,
    terminal,
    help,
    jump_local_declaration,
    jump_global_declaration,
    jump_matching_character,
    search_next,
    search_prev,
    search_word_forward,
    search_word_backward,
    registers,
    open,
    open_file_under_cursor,
    open_link_under_cursor,
    split,
    tab_new,
    tab_close,
    tab_only,
    tab_move,
    visual_restore,
    set_mark,
    jump_mark,
    jump_mark_exact,
    repeat_last_command,
    reload_config,
    quit,
    force_quit,
    macro_record,
    macro_run,
    visual_char,
    visual_line,
    visual_block,
    exit_visual,
    visual_yank,
    visual_delete,
    not_implemented,
};

const QuickfixEntry = struct {
    path: []u8,
    position: buffer_mod.Position,
    line: []u8,
};

const NormalBinding = struct {
    sequence: []const u8,
    action: NormalAction,
    help: []const u8,
};

const normal_bindings = [_]NormalBinding{
    .{ .sequence = "h", .action = .move_left, .help = "move cursor left" },
    .{ .sequence = "j", .action = .move_down, .help = "move cursor down" },
    .{ .sequence = "k", .action = .move_up, .help = "move cursor up" },
    .{ .sequence = "l", .action = .move_right, .help = "move cursor right" },
    .{ .sequence = "0", .action = .move_line_start, .help = "jump to the start of the line" },
    .{ .sequence = "^", .action = .move_line_nonblank, .help = "jump to first non-blank character" },
    .{ .sequence = "$", .action = .move_line_end, .help = "jump to the end of the line" },
    .{ .sequence = "gg", .action = .move_doc_start, .help = "go to the first line" },
    .{ .sequence = "G", .action = .move_doc_end, .help = "go to the last line" },
    .{ .sequence = "gt", .action = .tab_next, .help = "move to the next tab" },
    .{ .sequence = "gT", .action = .tab_prev, .help = "move to the previous tab" },
    .{ .sequence = "\x17s", .action = .window_split_horizontal, .help = "split window" },
    .{ .sequence = "\x17v", .action = .window_split_vertical, .help = "split window vertically" },
    .{ .sequence = "\x17n", .action = .window_new, .help = "open a new empty window" },
    .{ .sequence = "\x17w", .action = .window_switch, .help = "switch windows" },
    .{ .sequence = "\x17q", .action = .window_close, .help = "quit a window" },
    .{ .sequence = "\x17x", .action = .window_exchange, .help = "exchange current window with next one" },
    .{ .sequence = "\x17+", .action = .window_resize_increase, .help = "increase window size" },
    .{ .sequence = "\x17-", .action = .window_resize_decrease, .help = "decrease window size" },
    .{ .sequence = "\x17>", .action = .window_resize_wider, .help = "make window wider" },
    .{ .sequence = "\x17<", .action = .window_resize_narrower, .help = "make window narrower" },
    .{ .sequence = "\x17\\", .action = .window_maximize_width, .help = "maximize window width" },
    .{ .sequence = "\x17|", .action = .window_maximize_width, .help = "maximize window width" },
    .{ .sequence = "\x17_", .action = .window_maximize_height, .help = "maximize window height" },
    .{ .sequence = "\x17=", .action = .window_equalize, .help = "make all windows equal height and width" },
    .{ .sequence = "\x17T", .action = .window_to_tab, .help = "move the current split into its own tab" },
    .{ .sequence = "\x17h", .action = .window_left, .help = "move cursor to the left window" },
    .{ .sequence = "\x17l", .action = .window_right, .help = "move cursor to the right window" },
    .{ .sequence = "\x17k", .action = .window_up, .help = "move cursor to the window above" },
    .{ .sequence = "\x17j", .action = .window_down, .help = "move cursor to the window below" },
    .{ .sequence = "\x17H", .action = .window_far_left, .help = "make current window full height at far left" },
    .{ .sequence = "\x17L", .action = .window_far_right, .help = "make current window full height at far right" },
    .{ .sequence = "\x17J", .action = .window_far_bottom, .help = "make current window full width at the very bottom" },
    .{ .sequence = "\x17K", .action = .window_far_top, .help = "make current window full width at the very top" },
    .{ .sequence = "zf", .action = .fold_create, .help = "manually define a fold" },
    .{ .sequence = "zd", .action = .fold_delete, .help = "delete fold under the cursor" },
    .{ .sequence = "zE", .action = .fold_delete_all, .help = "delete all folds" },
    .{ .sequence = "za", .action = .fold_toggle, .help = "toggle fold under the cursor" },
    .{ .sequence = "zo", .action = .fold_open, .help = "open fold under the cursor" },
    .{ .sequence = "zc", .action = .fold_close, .help = "close fold under the cursor" },
    .{ .sequence = "zr", .action = .fold_open_all, .help = "reduce folds by opening all folds" },
    .{ .sequence = "zm", .action = .fold_close_all, .help = "fold more by closing all folds" },
    .{ .sequence = "zi", .action = .fold_toggle_enabled, .help = "toggle folding functionality" },
    .{ .sequence = "do", .action = .diff_get, .help = "obtain difference from the other buffer" },
    .{ .sequence = "dp", .action = .diff_put, .help = "put difference to the other buffer" },
    .{ .sequence = "]c", .action = .diff_next_change, .help = "jump to the start of the next change" },
    .{ .sequence = "[c", .action = .diff_prev_change, .help = "jump to the start of the previous change" },
    .{ .sequence = "w", .action = .move_word_forward, .help = "jump forwards to the start of a word" },
    .{ .sequence = "W", .action = .move_word_forward_big, .help = "jump forwards to the start of a WORD" },
    .{ .sequence = "b", .action = .move_word_backward, .help = "jump backwards to the start of a word" },
    .{ .sequence = "B", .action = .move_word_backward_big, .help = "jump backwards to the start of a WORD" },
    .{ .sequence = "e", .action = .move_word_end, .help = "jump forwards to the end of a word" },
    .{ .sequence = "E", .action = .move_word_end_big, .help = "jump forwards to the end of a WORD" },
    .{ .sequence = "ge", .action = .move_word_end_backward, .help = "jump backwards to the end of a word" },
    .{ .sequence = "gE", .action = .move_word_end_backward_big, .help = "jump backwards to the end of a WORD" },
    .{ .sequence = "}", .action = .move_paragraph_forward, .help = "jump to next paragraph" },
    .{ .sequence = "{", .action = .move_paragraph_backward, .help = "jump to previous paragraph" },
    .{ .sequence = ")", .action = .move_sentence_forward, .help = "jump to next sentence" },
    .{ .sequence = "(", .action = .move_sentence_backward, .help = "jump to previous sentence" },
    .{ .sequence = "gj", .action = .move_down, .help = "move cursor down on wrapped text" },
    .{ .sequence = "gk", .action = .move_up, .help = "move cursor up on wrapped text" },
    .{ .sequence = "g_", .action = .move_line_last_nonblank, .help = "jump to the last non-blank character" },
    .{ .sequence = "gd", .action = .jump_local_declaration, .help = "move to local declaration" },
    .{ .sequence = "gD", .action = .jump_global_declaration, .help = "move to global declaration" },
    .{ .sequence = "gf", .action = .open_file_under_cursor, .help = "open file under cursor" },
    .{ .sequence = "gx", .action = .open_link_under_cursor, .help = "open link under cursor" },
    .{ .sequence = "n", .action = .search_next, .help = "jump to the next search match" },
    .{ .sequence = "N", .action = .search_prev, .help = "jump to the previous search match" },
    .{ .sequence = "*", .action = .search_word_forward, .help = "search word under cursor forward" },
    .{ .sequence = "#", .action = .search_word_backward, .help = "search word under cursor backward" },
    .{ .sequence = "f", .action = .find_forward, .help = "jump to next occurrence of a character" },
    .{ .sequence = "F", .action = .find_backward, .help = "jump to previous occurrence of a character" },
    .{ .sequence = "t", .action = .find_forward_before, .help = "jump before next occurrence of a character" },
    .{ .sequence = "T", .action = .find_backward_before, .help = "jump after previous occurrence of a character" },
    .{ .sequence = ";", .action = .repeat_find_forward, .help = "repeat the previous find command" },
    .{ .sequence = ",", .action = .repeat_find_backward, .help = "repeat the previous find command backwards" },
    .{ .sequence = "m", .action = .set_mark, .help = "set a mark" },
    .{ .sequence = "'", .action = .jump_mark, .help = "jump to a mark's line" },
    .{ .sequence = "`", .action = .jump_mark_exact, .help = "jump to a mark's exact position" },
    .{ .sequence = "gp", .action = .paste_after_keep_cursor, .help = "put and leave cursor after the new text" },
    .{ .sequence = "gP", .action = .paste_before_keep_cursor, .help = "put before cursor and leave cursor after the new text" },
    .{ .sequence = "g~", .action = .toggle_case_word, .help = "switch case up to motion" },
    .{ .sequence = "gu", .action = .lowercase_word, .help = "change to lowercase up to motion" },
    .{ .sequence = "gU", .action = .uppercase_word, .help = "change to uppercase up to motion" },
    .{ .sequence = ".", .action = .repeat_last_command, .help = "repeat the last command" },
    .{ .sequence = "x", .action = .delete_char, .help = "delete a single character" },
    .{ .sequence = "r", .action = .replace_char, .help = "replace a single character" },
    .{ .sequence = "s", .action = .substitute_char, .help = "delete character and substitute text" },
    .{ .sequence = "S", .action = .substitute_line, .help = "delete line and substitute text" },
    .{ .sequence = "i", .action = .insert_before, .help = "insert before the cursor" },
    .{ .sequence = "I", .action = .insert_at_bol, .help = "insert at the beginning of the line" },
    .{ .sequence = "a", .action = .append_after, .help = "append after the cursor" },
    .{ .sequence = "A", .action = .append_eol, .help = "append at the end of the line" },
    .{ .sequence = "o", .action = .open_below, .help = "open a new line below" },
    .{ .sequence = "O", .action = .open_above, .help = "open a new line above" },
    .{ .sequence = "u", .action = .undo, .help = "undo" },
    .{ .sequence = "\x12", .action = .redo, .help = "redo" },
    .{ .sequence = "\x15", .action = .scroll_up, .help = "scroll up" },
    .{ .sequence = "\x04", .action = .scroll_down, .help = "scroll down" },
    .{ .sequence = "\x09", .action = .jump_history_forward, .help = "move forward in jump list" },
    .{ .sequence = "\x0f", .action = .jump_history_backward, .help = "move backward in jump list" },
    .{ .sequence = "\x1e", .action = .switch_previous_buffer, .help = "toggle between current and previous file" },
    .{ .sequence = "zz", .action = .viewport_middle, .help = "center cursor on screen" },
    .{ .sequence = "zt", .action = .viewport_top, .help = "position cursor on top of the screen" },
    .{ .sequence = "zb", .action = .viewport_bottom, .help = "position cursor on bottom of the screen" },
    .{ .sequence = "H", .action = .move_doc_start, .help = "move to the top of the screen" },
    .{ .sequence = "M", .action = .move_doc_middle, .help = "move to the middle of the screen" },
    .{ .sequence = "L", .action = .move_doc_end, .help = "move to the bottom of the screen" },
    .{ .sequence = "dd", .action = .delete_line, .help = "delete a line" },
    .{ .sequence = "d0", .action = .delete_to_bol, .help = "delete to beginning of line" },
    .{ .sequence = "yy", .action = .yank_line, .help = "yank a line" },
    .{ .sequence = "p", .action = .paste_after, .help = "put after cursor" },
    .{ .sequence = "P", .action = .paste_before, .help = "put before cursor" },
    .{ .sequence = "dw", .action = .delete_word, .help = "delete a word" },
    .{ .sequence = "diw", .action = .delete_word, .help = "delete inner word" },
    .{ .sequence = "cw", .action = .change_word, .help = "change word" },
    .{ .sequence = "ce", .action = .change_word, .help = "change to end of word" },
    .{ .sequence = "ciw", .action = .change_word, .help = "change inner word" },
    .{ .sequence = "cc", .action = .change_line, .help = "change entire line" },
    .{ .sequence = "C", .action = .change_to_eol, .help = "change to end of line" },
    .{ .sequence = "d$", .action = .delete_to_eol, .help = "delete to end of line" },
    .{ .sequence = "D", .action = .delete_to_eol, .help = "delete to end of line" },
    .{ .sequence = "yw", .action = .yank_word, .help = "yank a word" },
    .{ .sequence = "yiw", .action = .yank_word, .help = "yank inner word" },
    .{ .sequence = "yaw", .action = .yank_word, .help = "yank around word" },
    .{ .sequence = "y$", .action = .yank_word, .help = "yank to end of line" },
    .{ .sequence = "Y", .action = .yank_word, .help = "yank to end of line" },
    .{ .sequence = "J", .action = .join_line_space, .help = "join lines with a space" },
    .{ .sequence = "gJ", .action = .join_line_nospace, .help = "join lines without a space" },
    .{ .sequence = ">", .action = .indent_line, .help = "shift text right" },
    .{ .sequence = "<", .action = .dedent_line, .help = "shift text left" },
    .{ .sequence = "~", .action = .toggle_case_char, .help = "switch case" },
    .{ .sequence = "v", .action = .visual_char, .help = "start visual character mode" },
    .{ .sequence = "V", .action = .visual_line, .help = "start visual line mode" },
    .{ .sequence = "\x16", .action = .visual_block, .help = "start visual block mode" },
    .{ .sequence = "gv", .action = .visual_restore, .help = "reselect the previous visual area" },
    .{ .sequence = "y", .action = .visual_yank, .help = "yank selected text" },
    .{ .sequence = "d", .action = .visual_delete, .help = "delete selected text" },
    .{ .sequence = "q", .action = .macro_record, .help = "record macro" },
    .{ .sequence = "@", .action = .macro_run, .help = "run macro" },
    .{ .sequence = "%", .action = .jump_matching_character, .help = "move cursor to matching character" },
    .{ .sequence = "K", .action = .help, .help = "open help for the word under the cursor" },
};

const SplitFocus = enum { left, right };
const Mode = enum { normal, insert, command, search, visual };

// First-pass gaps we will tackle after the redesigned bar lands.
const status_bar_todo = [_][]const u8{
    "git branch / repository state",
    "diagnostics / LSP counts",
    "filetype / encoding / line endings",
    "macro recording indicator",
};

const Style = struct {
    fg: ?u8 = null,
    bg: ?u8 = null,
    bold: bool = false,
    dim: bool = false,
};

const Theme = struct {
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

    fn resolve(name: []const u8, background_color: []const u8, blur: bool, opacity: usize) Theme {
        const content_bg = resolveBackgroundColor(background_color, opacity);
        if (std.ascii.eqlIgnoreCase(name, "nvchad") or std.ascii.eqlIgnoreCase(name, "chad")) {
            return Theme.nvchad(content_bg, blur, opacity);
        }
        return Theme.beam(content_bg, blur, opacity);
    }

    fn modeStyle(self: Theme, mode: Mode) Style {
        return switch (mode) {
            .normal => .{ .fg = self.contrast_fg, .bg = self.accent, .bold = true },
            .insert => .{ .fg = self.contrast_fg, .bg = self.accent_alt, .bold = true },
            .command => .{ .fg = self.contrast_fg, .bg = self.prompt_bg, .bold = true },
            .search => .{ .fg = self.contrast_fg, .bg = self.search_bg, .bold = true },
            .visual => .{ .fg = self.contrast_fg, .bg = self.visual_bg, .bold = true },
        };
    }

    fn textStyle(self: Theme, active: bool) Style {
        return .{
            .fg = if (active) self.text else self.muted,
            .bg = self.contentBg(),
            .dim = self.glassMode(),
        };
    }

    fn lineNumberStyle(self: Theme, active: bool) Style {
        return .{
            .fg = if (active) self.line_no_active else if (self.glassMode()) self.muted else self.line_no,
            .bg = self.contentBg(),
            .dim = self.glassMode(),
        };
    }

    fn searchStyle(self: Theme) Style {
        return .{ .fg = if (self.glassMode()) self.muted else self.search_fg, .bg = self.search_bg, .bold = !self.glassMode(), .dim = self.glassMode() };
    }

    fn visualStyle(self: Theme) Style {
        return .{ .fg = if (self.glassMode()) self.muted else self.visual_fg, .bg = self.visual_bg, .bold = !self.glassMode(), .dim = self.glassMode() };
    }

    fn separatorStyle(self: Theme) Style {
        return .{ .fg = if (self.glassMode()) self.muted else self.border, .bg = self.contentBg(), .dim = self.glassMode() };
    }

    fn statusStyle(self: Theme) Style {
        return .{ .fg = self.status_fg, .bg = self.status_bg };
    }

    fn promptStyle(self: Theme) Style {
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

fn resolveBackgroundColor(spec: []const u8, opacity: usize) ?u8 {
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

fn writeStyle(writer: anytype, style: Style) !void {
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

fn writeStyledText(writer: anytype, style: Style, text: []const u8) !void {
    try writeStyle(writer, style);
    try writer.writeAll(text);
}

fn utf8CharLen(byte: u8) usize {
    return if (byte < 0x80) 1 else if ((byte & 0xe0) == 0xc0) 2 else if ((byte & 0xf0) == 0xe0) 3 else if ((byte & 0xf8) == 0xf0) 4 else 1;
}

fn displayWidth(text: []const u8) usize {
    var width: usize = 0;
    var idx: usize = 0;
    while (idx < text.len) {
        const len = utf8CharLen(text[idx]);
        idx += @min(len, text.len - idx);
        width += 1;
    }
    return width;
}

fn clipText(text: []const u8, width: usize) []const u8 {
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

fn modeIconText(self: *App, mode: Mode) []const u8 {
    return switch (mode) {
        .normal => if (std.mem.eql(u8, self.config.status_bar_icon, "default")) "\u{e795}" else self.config.status_bar_icon,
        .insert => self.config.status_bar_insert_icon,
        .command => "",
        .search => "",
        .visual => self.config.status_bar_visual_icon,
    };
}

fn modeLabel(mode: Mode) []const u8 {
    return switch (mode) {
        .normal => "NORMAL",
        .insert => "INSERT",
        .command => "COMMAND",
        .search => "SEARCH",
        .visual => "VISUAL",
    };
}

fn normalActionHelp(sequence: []const u8) ?[]const u8 {
    for (normal_bindings) |binding| {
        if (std.mem.eql(u8, binding.sequence, sequence)) return binding.help;
    }
    return null;
}

fn normalActionHasPrefix(prefix: []const u8) bool {
    for (normal_bindings) |binding| {
        if (binding.sequence.len > prefix.len and std.mem.startsWith(u8, binding.sequence, prefix)) return true;
    }
    return false;
}

fn normalActionFor(sequence: []const u8) ?NormalAction {
    for (normal_bindings) |binding| {
        if (std.mem.eql(u8, binding.sequence, sequence)) return binding.action;
    }
    return null;
}

pub const App = struct {
    allocator: std.mem.Allocator,
    args: []const [:0]u8,
    config_path: []u8,
    config: config_mod.Config,
    theme: Theme,
    buffers: std.array_list.Managed(buffer_mod.Buffer),
    active_index: usize = 0,
    previous_active_index: ?usize = null,
    split_index: ?usize = null,
    split_focus: SplitFocus = .left,
    mode: Mode = .normal,
    command_buffer: std.array_list.Managed(u8),
    search_buffer: std.array_list.Managed(u8),
    normal_sequence: std.array_list.Managed(u8),
    status: std.array_list.Managed(u8),
    raw_mode: ?terminal_mod.RawMode = null,
    plugin_host: plugin_mod.PluginHost,
    should_quit: bool = false,
    file_to_open: ?[]u8 = null,
    draining_plugin_actions: bool = false,
    interactive_command_hook: ?*const fn (self: *App, argv: []const []const u8) bool = null,
    last_interactive_command: ?[]u8 = null,
    jump_history: std.array_list.Managed(buffer_mod.Position),
    jump_history_index: ?usize = null,
    change_history: std.array_list.Managed(buffer_mod.Position),
    quickfix_list: std.array_list.Managed(QuickfixEntry),
    quickfix_index: usize = 0,
    diff_peer_index: ?usize = null,
    diff_mode: bool = false,
    change_jump_index: ?usize = null,
    macro_recording: ?u8 = null,
    macro_ignore_next: bool = false,
    macro_playing: bool = false,
    macros: [26]?[]u8 = [_]?[]u8{null} ** 26,
    last_render_height: usize = 24,
    pending_prefix: PendingPrefix = .none,
    pending_register: ?u8 = null,
    insert_register_prefix: bool = false,
    count_prefix: usize = 0,
    count_active: bool = false,
    visual_mode: VisualMode = .none,
    visual_anchor: ?buffer_mod.Position = null,
    visual_select_mode: bool = false,
    visual_select_restore: bool = false,
    visual_pending: ?VisualPending = null,
    last_visual_state: ?VisualState = null,
    visual_block_insert: ?VisualBlockInsert = null,
    search_highlight: ?[]u8 = null,
    search_preview_highlight: ?[]u8 = null,
    last_find: ?FindState = null,
    last_normal_action: ?NormalAction = null,
    last_normal_count: usize = 1,
    registers: RegisterStore,
    marks: [26]?buffer_mod.Position = [_]?buffer_mod.Position{null} ** 26,

    const VisualMode = enum { none, character, line, block };
    const VisualPending = enum { ctrl_backslash, g_prefix, replace_char, textobject_outer, textobject_inner };
    const PendingPrefix = enum { none, register, replace_char, find_forward, find_forward_before, find_backward, find_backward_before, macro_record, macro_run, mark_set, mark_jump, mark_jump_exact };
    const FindState = struct {
        char: u8,
        forward: bool,
        before: bool,
    };
    const VisualState = struct {
        mode: VisualMode,
        anchor: buffer_mod.Position,
        cursor: buffer_mod.Position,
        select_mode: bool,
        select_restore: bool,
    };
    const VisualBlockInsert = struct {
        start_row: usize,
        end_row: usize,
        column: usize,
        before: bool,
        text: std.array_list.Managed(u8),
    };

    const RegisterStore = struct {
        allocator: std.mem.Allocator,
        values: [256]?[]u8 = [_]?[]u8{null} ** 256,

        fn init(allocator: std.mem.Allocator) RegisterStore {
            return .{ .allocator = allocator };
        }

        fn deinit(self: *RegisterStore) void {
            for (self.values) |item| {
                if (item) |value| self.allocator.free(value);
            }
        }

        fn set(self: *RegisterStore, key: u8, value: []const u8) !void {
            if (self.values[key]) |existing| self.allocator.free(existing);
            self.values[key] = try self.allocator.dupe(u8, value);
        }

        fn get(self: *const RegisterStore, key: u8) ?[]const u8 {
            return self.values[key];
        }

        fn formatSummary(self: *const RegisterStore, allocator: std.mem.Allocator) ![]u8 {
            var out = std.array_list.Managed(u8).init(allocator);
            errdefer out.deinit();
            var any = false;
            for (self.values, 0..) |item, idx| {
                if (item) |value| {
                    any = true;
                    if (out.items.len > 0) try out.appendSlice(" | ");
                    const piece = try std.fmt.allocPrint(allocator, "\"{c}={s}", .{ @as(u8, @intCast(idx)), value });
                    defer allocator.free(piece);
                    try out.appendSlice(piece);
                }
            }
            if (!any) try out.appendSlice("registers empty");
            return try out.toOwnedSlice();
        }
    };

    pub fn init(allocator: std.mem.Allocator, args: []const [:0]u8) !App {
        var config_path = try allocator.dupe(u8, "beam.toml");
        errdefer allocator.free(config_path);
        var file_to_open: ?[]u8 = null;
        errdefer if (file_to_open) |f| allocator.free(f);

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--config") and i + 1 < args.len) {
                allocator.free(config_path);
                config_path = try allocator.dupe(u8, args[i + 1]);
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--help")) {
                try printHelp();
                return error.HelpRequested;
            }
            if (args[i][0] != '-') {
                if (file_to_open) |f| allocator.free(f);
                file_to_open = try allocator.dupe(u8, args[i]);
            }
        }

        var diag = config_mod.Diagnostics{};
        const config = config_mod.load(allocator, config_path, &diag) catch |err| {
            if (err == error.FileNotFound) {
                const cfg = try config_mod.Config.init(allocator);
                return .{
                    .allocator = allocator,
                    .args = args,
                    .config_path = config_path,
                    .config = cfg,
                    .theme = Theme.resolve(cfg.theme, cfg.background_color, cfg.blur, cfg.opacity),
                    .buffers = std.array_list.Managed(buffer_mod.Buffer).init(allocator),
                    .command_buffer = std.array_list.Managed(u8).init(allocator),
                    .search_buffer = std.array_list.Managed(u8).init(allocator),
                    .normal_sequence = std.array_list.Managed(u8).init(allocator),
                    .status = std.array_list.Managed(u8).init(allocator),
                    .plugin_host = plugin_mod.PluginHost.init(allocator, ".beam/plugins"),
                    .file_to_open = file_to_open,
                    .jump_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
                    .change_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
                    .quickfix_list = std.array_list.Managed(QuickfixEntry).init(allocator),
                    .registers = RegisterStore.init(allocator),
                };
            }
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ config_path, diag.line, diag.column, diag.message });
            return err;
        };

        return .{
            .allocator = allocator,
            .args = args,
            .config_path = config_path,
            .config = config,
            .theme = Theme.resolve(config.theme, config.background_color, config.blur, config.opacity),
            .buffers = std.array_list.Managed(buffer_mod.Buffer).init(allocator),
            .command_buffer = std.array_list.Managed(u8).init(allocator),
            .search_buffer = std.array_list.Managed(u8).init(allocator),
            .normal_sequence = std.array_list.Managed(u8).init(allocator),
            .status = std.array_list.Managed(u8).init(allocator),
            .plugin_host = plugin_mod.PluginHost.init(allocator, config.plugin_dir),
            .file_to_open = file_to_open,
            .jump_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
            .change_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
            .quickfix_list = std.array_list.Managed(QuickfixEntry).init(allocator),
            .registers = RegisterStore.init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.exitTerminal() catch {};
        for (self.buffers.items) |*buf| buf.deinit();
        self.buffers.deinit();
        self.command_buffer.deinit();
        self.search_buffer.deinit();
        self.normal_sequence.deinit();
        self.status.deinit();
        self.plugin_host.deinit();
        if (self.search_highlight) |needle| self.allocator.free(needle);
        if (self.search_preview_highlight) |needle| self.allocator.free(needle);
        if (self.last_interactive_command) |cmd| self.allocator.free(cmd);
        if (self.visual_block_insert) |*block| {
            block.text.deinit();
            self.visual_block_insert = null;
        }
        for (self.macros, 0..) |item, idx| {
            if (item) |value| self.allocator.free(value);
            self.macros[idx] = null;
        }
        self.jump_history.deinit();
        self.change_history.deinit();
        self.clearQuickfix();
        self.quickfix_list.deinit();
        self.registers.deinit();
        self.config.deinit();
        self.allocator.free(self.config_path);
        if (self.file_to_open) |f| self.allocator.free(f);
    }

    pub fn run(self: *App) !void {
        try self.initTerminal();
        defer self.exitTerminal() catch {};

        try self.loadInitialBuffers();
        try self.plugin_host.discoverAndStart(self.config.plugins.enabled.items, self.config.plugins.auto_start);
        try self.setStatus("ready");
        try self.eventLoop();
    }

    fn loadInitialBuffers(self: *App) !void {
        if (self.file_to_open) |path| {
            try self.buffers.append(buffer_mod.Buffer.loadFile(self.allocator, path) catch |err| switch (err) {
                error.FileNotFound => blk: {
                    var buf = try buffer_mod.Buffer.initEmpty(self.allocator);
                    try buf.replacePath(path);
                    break :blk buf;
                },
                else => return err,
            });
        } else {
            try self.buffers.append(try buffer_mod.Buffer.initEmpty(self.allocator));
        }
    }

    fn initTerminal(self: *App) !void {
        const stdin_file = std.fs.File.stdin();
        self.raw_mode = try terminal_mod.RawMode.enable(stdin_file);
        const stdout_file = std.fs.File.stdout();
        var out_buf: [4096]u8 = undefined;
        var out_writer = stdout_file.writer(&out_buf);
        const out = &out_writer.interface;
        try terminal_mod.enterAltScreen(out);
        try terminal_mod.showCursor(out);
        try terminal_mod.setCursorShape(out, true);
        try out.flush();
    }

    fn exitTerminal(self: *App) !void {
        const stdout_file = std.fs.File.stdout();
        var out_buf: [4096]u8 = undefined;
        var out_writer = stdout_file.writer(&out_buf);
        const out = &out_writer.interface;
        try terminal_mod.showCursor(out);
        try terminal_mod.setCursorShape(out, true);
        try terminal_mod.leaveAltScreen(out);
        try out.flush();
        if (self.raw_mode) |*mode| mode.disable();
        self.raw_mode = null;
    }

    fn eventLoop(self: *App) !void {
        const stdin_file = std.fs.File.stdin();
        var input_buf: [1]u8 = undefined;
        while (!self.should_quit) {
            try self.render();
            const n = stdin_file.read(&input_buf) catch break;
            if (n == 0) break;
            try self.handleByte(input_buf[0], stdin_file);
        }
    }

    fn handleByte(self: *App, byte: u8, stdin_file: std.fs.File) !void {
        _ = stdin_file;
        switch (self.mode) {
            .insert => switch (byte) {
                0x1b => {
                    if (self.visual_block_insert) |*block| {
                        try self.commitVisualBlockInsert(block);
                    }
                    self.mode = .normal;
                },
                0x12 => {
                    self.insert_register_prefix = true;
                },
                0x17 => {
                    if (self.visual_block_insert) |*block| {
                        while (block.text.items.len > 0 and std.ascii.isWhitespace(block.text.items[block.text.items.len - 1])) {
                            _ = block.text.pop();
                        }
                        while (block.text.items.len > 0 and !std.ascii.isWhitespace(block.text.items[block.text.items.len - 1])) {
                            _ = block.text.pop();
                        }
                    } else {
                        try self.deleteInsertPreviousWord();
                    }
                },
                0x7f => {
                    if (self.visual_block_insert) |*block| {
                        if (block.text.items.len > 0) _ = block.text.pop();
                    } else {
                        try self.activeBuffer().backspace();
                    }
                },
                '\r', '\n' => {
                    if (self.visual_block_insert) |*block| {
                        try block.text.append('\n');
                    } else {
                        try self.activeBuffer().insertByte('\n');
                    }
                },
                else => try self.handleInsertByte(byte),
            },
            .command => switch (byte) {
                0x1b => self.clearPrompt(.command),
                0x7f => {
                    if (self.command_buffer.items.len > 0) _ = self.command_buffer.pop();
                },
                '\r', '\n' => try self.executeCommand(),
                else => try self.command_buffer.append(byte),
            },
            .search => switch (byte) {
                0x1b => {
                    self.clearPrompt(.search);
                    self.clearSearchPreview();
                },
                0x7f => {
                    if (self.search_buffer.items.len > 0) _ = self.search_buffer.pop();
                    try self.updateSearchPreview(self.search_buffer.items);
                },
                '\r', '\n' => try self.executeSearch(),
                else => {
                    try self.search_buffer.append(byte);
                    try self.updateSearchPreview(self.search_buffer.items);
                },
            },
            .visual => try self.handleVisualByte(byte),
            .normal => try self.handleNormalByte(byte),
        }
    }

    fn handleInsertByte(self: *App, byte: u8) !void {
        if (self.visual_block_insert) |*block| {
            if (self.insert_register_prefix) {
                self.insert_register_prefix = false;
                const value = self.registers.get(byte) orelse "";
                try block.text.appendSlice(value);
                return;
            }
            try block.text.append(byte);
            return;
        }
        if (self.insert_register_prefix) {
            self.insert_register_prefix = false;
            const value = self.registers.get(byte) orelse "";
            try self.activeBuffer().insertTextAtCursor(value);
            return;
        }
        try self.activeBuffer().insertByte(byte);
    }

    fn clearPrompt(self: *App, mode: Mode) void {
        if (mode == .command) self.command_buffer.clearRetainingCapacity();
        if (mode == .search) self.search_buffer.clearRetainingCapacity();
        self.mode = .normal;
    }

    fn clearSearchPreview(self: *App) void {
        if (self.search_preview_highlight) |needle| self.allocator.free(needle);
        self.search_preview_highlight = null;
    }

    fn updateSearchHighlight(self: *App, slot: *?[]u8, needle: []const u8) !void {
        if (slot.*) |existing| {
            self.allocator.free(existing);
            slot.* = null;
        }
        if (needle.len == 0) return;
        slot.* = try self.allocator.dupe(u8, needle);
    }

    fn updateSearchPreview(self: *App, needle: []const u8) !void {
        try self.updateSearchHighlight(&self.search_preview_highlight, needle);
    }

    fn executeCommand(self: *App) !void {
        const raw = std.mem.trim(u8, self.command_buffer.items, " \t\r\n");
        self.mode = .normal;
        if (raw.len == 0) return;

        const command = if (raw[0] == ':') raw[1..] else raw;
        const command_no_range = stripVisualRangePrefix(command);
        const has_visual_range = command_no_range.len != command.len;
        if (has_visual_range and command_no_range.len > 0 and (command_no_range[0] == '!' or command_no_range[0] == '=')) {
            const filter = std.mem.trim(u8, command_no_range[1..], " \t");
            if (filter.len == 0) {
                try self.setStatus("visual filter requires a command");
                return;
            }
            try self.runVisualFilter(filter);
            return;
        }
        const arg_split = std.mem.indexOfScalar(u8, command_no_range, ' ');
        const head = if (arg_split) |idx| command_no_range[0..idx] else command_no_range;
        const tail = if (arg_split) |idx| std.mem.trim(u8, command_no_range[idx + 1 ..], " \t") else "";

        if (try self.tryExecuteSubstitute(command_no_range, has_visual_range)) {
            return;
        }

        if (matchesCommand(head, &.{ "h", "help" }, self.config.keymap.help)) {
            if (tail.len == 0) {
                try self.showReferenceHelp();
            } else {
                try self.helpForKeyword(tail);
            }
            return;
        }
        if (matchesCommand(head, &.{ "sav", "saveas" }, self.config.keymap.save_as)) {
            _ = self.commandSaveAs(if (tail.len > 0) tail else null);
            return;
        }
        if (matchesCommand(head, &.{ "clo", "close" }, self.config.keymap.close)) {
            try self.closeCurrentPane();
            return;
        }
        if (matchesCommand(head, &.{ "ter", "terminal" }, self.config.keymap.terminal)) {
            try self.performNormalAction(.terminal, 1);
            return;
        }
        if (matchesCommand(head, &.{ "reg", "registers" }, self.config.keymap.registers)) {
            try self.showRegisters();
            return;
        }
        if (matchesCommand(head, &.{ "ma", "marks" }, "marks")) {
            try self.showMarks();
            return;
        }
        if (std.mem.eql(u8, head, "delmarks!") or std.mem.eql(u8, head, "delmarks")) {
            for (0..self.marks.len) |idx| {
                self.marks[idx] = null;
            }
            try self.setStatus("marks deleted");
            return;
        }
        if (matchesCommand(head, &.{ "ju", "jumps" }, "jumps")) {
            try self.showJumps();
            return;
        }
        if (matchesCommand(head, &.{ "vimgrep", "vimgrep" }, "vimgrep")) {
            try self.runQuickfixSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"grep"}, "grep")) {
            try self.runProjectSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"sort"}, "sort")) {
            try self.sortCurrentBuffer(tail);
            return;
        }
        if (matchesCommand(head, &.{ "cn", "cnext" }, "cnext")) {
            try self.quickfixNext();
            return;
        }
        if (matchesCommand(head, &.{ "cp", "cprevious" }, "cprevious")) {
            try self.quickfixPrev();
            return;
        }
        if (matchesCommand(head, &.{ "cope", "copen" }, "cope")) {
            try self.showQuickfix();
            return;
        }
        if (matchesCommand(head, &.{ "ccl", "cclose" }, "cclose")) {
            self.clearQuickfix();
            try self.setStatus("quickfix cleared");
            return;
        }
        if (matchesCommand(head, &.{"diffthis"}, "diffthis")) {
            try self.enableDiffMode();
            return;
        }
        if (matchesCommand(head, &.{ "diffoff", "diffo" }, "diffoff")) {
            self.disableDiffMode();
            try self.setStatus("diff off");
            return;
        }
        if (matchesCommand(head, &.{ "diffupdate", "diffu" }, "diffupdate")) {
            try self.updateDiffSummary();
            return;
        }
        if (matchesCommand(head, &.{"diffget"}, "diffget")) {
            try self.diffGet();
            return;
        }
        if (matchesCommand(head, &.{"diffput"}, "diffput")) {
            try self.diffPut();
            return;
        }
        if (matchesCommand(head, &.{"changes"}, "changes")) {
            try self.showChanges();
            return;
        }
        if (matchesCommand(head, &.{"open"}, self.config.keymap.open)) {
            if (tail.len == 0) return self.setStatus("open requires a path");
            try self.openPath(tail);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{ "e", "edit" }, "edit")) {
            if (tail.len == 0) return self.setStatus("edit requires a path");
            try self.openPath(tail);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{ "bn", "bnext" }, "bnext")) {
            try self.switchFocusedBuffer(true, 1);
            return;
        }
        if (matchesCommand(head, &.{ "bp", "bprevious" }, "bprevious")) {
            try self.switchFocusedBuffer(false, 1);
            return;
        }
        if (matchesCommand(head, &.{ "bd", "bdelete" }, "bdelete")) {
            try self.closeCurrentPane();
            return;
        }
        if (matchesCommand(head, &.{ "buffer", "b" }, "buffer")) {
            if (tail.len == 0) {
                try self.setStatus("buffer requires an index or path");
            } else {
                try self.selectBufferByArgument(tail);
            }
            return;
        }
        if (matchesCommand(head, &.{ "buffers", "ls" }, "buffers")) {
            try self.showBuffers();
            return;
        }
        if (matchesCommand(head, &.{"tabnew"}, "tabnew")) {
            try self.openNewTab(if (tail.len > 0) tail else null);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{ "tabc", "tabclose" }, "tabclose")) {
            try self.tabCloseCurrent();
            return;
        }
        if (matchesCommand(head, &.{ "tabo", "tabonly" }, "tabonly")) {
            try self.tabOnlyCurrent();
            return;
        }
        if (matchesCommand(head, &.{"tabmove"}, "tabmove")) {
            if (tail.len == 0) {
                try self.setStatus("tabmove requires a number");
            } else {
                try self.tabMoveCurrent(tail);
            }
            return;
        }
        if (matchesCommand(head, &.{"split"}, self.config.keymap.split)) {
            try self.openSplitOrClone(tail);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{ "sp", "split" }, "split")) {
            try self.openSplitOrClone(tail);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{ "vs", "vsplit" }, "vsplit")) {
            try self.openSplitOrClone(tail);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{"plugin"}, "plugin")) {
            if (tail.len == 0) return self.setStatus("plugin requires a command name");
            const result = self.plugin_host.invokeCommand(tail, &.{}) catch {
                try self.setStatus("unknown plugin command");
                return;
            };
            defer self.allocator.free(result);
            try self.setStatus(result);
            try self.maybeDrainPluginActions();
            return;
        }
        if (matchesCommand(head, &.{"reload-config"}, self.config.keymap.reload)) {
            try self.reloadConfig();
            return;
        }
        if (matchesCommand(head, &.{"w"}, self.config.keymap.save)) {
            _ = self.saveActiveBuffer();
            return;
        }
        if (matchesCommand(head, &.{ "wq", "x" }, "wq")) {
            if (self.saveActiveBuffer()) self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"wqa"}, "wqa")) {
            for (self.buffers.items) |*buf| {
                if (buf.dirty) try buf.save();
            }
            self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"q!"}, self.config.keymap.force_quit)) {
            self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{ "q", "quit" }, self.config.keymap.quit)) {
            try self.requestQuit(false);
            return;
        }
        if (std.mem.eql(u8, head, "!")) {
            try self.runBangCommand(tail);
            return;
        }
        if (matchesCommand(head, &.{"ZZ"}, "ZZ")) {
            if (self.saveActiveBuffer()) self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"ZQ"}, "ZQ")) {
            self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"help"}, self.config.keymap.help)) {
            try self.showReferenceHelp();
            return;
        }

        if (std.mem.startsWith(u8, command, "saveas ")) {
            _ = self.commandSaveAs(std.mem.trim(u8, command[7..], " \t"));
            return;
        }

        try self.setStatus("unknown command");
    }

    fn handleNormalByte(self: *App, byte: u8) anyerror!void {
        if (self.pending_prefix != .none) {
            try self.handlePendingPrefix(byte);
            return;
        }

        if (self.macro_recording != null and !self.macro_playing and byte != 'q' and byte != '@') {
            try self.appendMacroByte(byte);
        }

        switch (byte) {
            0x1b, 0x03 => {
                self.resetNormalInput();
                self.visual_mode = .none;
                self.visual_anchor = null;
                return;
            },
            ':' => {
                self.resetNormalInput();
                self.mode = .command;
                self.command_buffer.clearRetainingCapacity();
                return;
            },
            '/' => {
                self.resetNormalInput();
                self.mode = .search;
                self.search_buffer.clearRetainingCapacity();
                return;
            },
            '"' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .register;
                return;
            },
            'q' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .macro_record;
                return;
            },
            '@' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .macro_run;
                return;
            },
            'm' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .mark_set;
                return;
            },
            '\'' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .mark_jump;
                return;
            },
            '`' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .mark_jump_exact;
                return;
            },
            'f' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_forward;
                return;
            },
            'F' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_backward;
                return;
            },
            't' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_forward_before;
                return;
            },
            'T' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_backward_before;
                return;
            },
            0x12 => {
                try self.performNormalAction(.redo, 1);
                return;
            },
            '\t' => {
                try self.performNormalAction(.jump_history_forward, 1);
                return;
            },
            0x15 => {
                try self.performNormalAction(.scroll_up, 1);
                return;
            },
            0x04 => {
                try self.performNormalAction(.scroll_down, 1);
                return;
            },
            0x0f => {
                try self.performNormalAction(.jump_history_backward, 1);
                return;
            },
            0x1e => {
                try self.performNormalAction(.switch_previous_buffer, 1);
                return;
            },
            '0' => {
                if (self.normal_sequence.items.len == 0) {
                    if (self.count_active) {
                        self.count_prefix *= 10;
                        return;
                    }
                    try self.performNormalAction(.move_line_start, 1);
                    return;
                }
            },
            '1'...'9' => {
                if (self.normal_sequence.items.len == 0) {
                    self.count_active = true;
                    self.count_prefix = self.count_prefix * 10 + @as(usize, byte - '0');
                    return;
                }
            },
            else => {},
        }

        try self.normal_sequence.append(byte);
        try self.resolveNormalSequence();
    }

    fn handleVisualByte(self: *App, byte: u8) !void {
        if (self.visual_pending) |pending| {
            self.visual_pending = null;
            switch (pending) {
                .ctrl_backslash => switch (byte) {
                    'n', 'g' => {
                        self.exitVisual();
                        return;
                    },
                    else => return,
                },
                .textobject_outer => {
                    try self.selectVisualTextObject(byte, false);
                    return;
                },
                .textobject_inner => {
                    try self.selectVisualTextObject(byte, true);
                    return;
                },
                .g_prefix => switch (byte) {
                    'v' => {
                        try self.restoreLastVisual();
                        return;
                    },
                    'J' => {
                        try self.visualJoin(false);
                        return;
                    },
                    'q' => {
                        try self.visualFormat();
                        return;
                    },
                    '\x01' => {
                        try self.visualAdjustNumber(true, 1);
                        return;
                    },
                    '\x18' => {
                        try self.visualAdjustNumber(false, 1);
                        return;
                    },
                    else => {
                        try self.setStatus("visual command not implemented");
                        return;
                    },
                },
                .replace_char => {
                    if (byte == 0x1b or byte == 0x03) return;
                    try self.visualReplaceChar(byte);
                    return;
                },
            }
        }

        switch (byte) {
            0x1b, 0x03 => self.exitVisual(),
            0x1c => self.visual_pending = .ctrl_backslash,
            0x07 => {
                self.visual_select_mode = !self.visual_select_mode;
                self.visual_select_restore = false;
                try self.setStatus(if (self.visual_select_mode) "select mode" else "visual mode");
            },
            0x0f => {
                if (self.visual_select_mode) {
                    self.visual_select_mode = false;
                    self.visual_select_restore = true;
                    try self.setStatus("visual mode");
                    return;
                }
            },
            0x08, 0x7f => {
                try self.visualDelete();
                self.exitVisual();
            },
            0x16 => {
                if (self.visual_mode == .block) {
                    self.exitVisual();
                } else {
                    self.visual_mode = .block;
                    self.visual_select_mode = false;
                }
            },
            'v' => {
                if (self.visual_mode == .character) {
                    self.exitVisual();
                } else {
                    self.visual_mode = .character;
                    self.visual_select_mode = false;
                }
            },
            'V' => {
                if (self.visual_mode == .line) {
                    self.exitVisual();
                } else {
                    self.visual_mode = .line;
                    self.visual_select_mode = false;
                }
            },
            'g' => self.visual_pending = .g_prefix,
            'a' => self.visual_pending = .textobject_outer,
            'i' => self.visual_pending = .textobject_inner,
            'h' => self.activeBuffer().moveLeft(),
            'j' => self.activeBuffer().moveDown(),
            'k' => self.activeBuffer().moveUp(),
            'l' => self.activeBuffer().moveRight(),
            '0' => self.activeBuffer().moveLineStart(),
            '^' => self.activeBuffer().moveToFirstNonBlank(),
            '$' => self.activeBuffer().moveLineEnd(),
            'w' => self.activeBuffer().moveWordForward(false),
            'W' => self.activeBuffer().moveWordForward(true),
            'b' => self.activeBuffer().moveWordBackward(false),
            'B' => self.activeBuffer().moveWordBackward(true),
            'e' => self.activeBuffer().moveWordEnd(false),
            'E' => self.activeBuffer().moveWordEnd(true),
            'o', 'O' => self.swapVisualCorners(),
            'y' => {
                try self.visualYank();
                self.exitVisual();
            },
            'Y' => {
                try self.visualYank();
                self.exitVisual();
            },
            'p' => try self.visualPaste(false, false),
            'P' => try self.visualPaste(true, true),
            'd', 'D', 'x', 'X' => {
                try self.visualDelete();
                self.exitVisual();
            },
            'c', 'C', 's', 'S', 'R' => try self.visualChange(),
            'u' => try self.visualCase(.lower),
            'U' => try self.visualCase(.upper),
            '~' => try self.visualCase(.toggle),
            '>' => try self.visualIndent(true),
            '<' => try self.visualIndent(false),
            'J' => try self.visualJoin(true),
            'A' => try self.visualBlockInsert(true),
            'I' => try self.visualBlockInsert(false),
            'K' => try self.visualVisualHelp(),
            0x1d => try self.visualJumpTag(),
            'r' => self.visual_pending = .replace_char,
            '!' => {
                self.mode = .command;
                self.command_buffer.clearRetainingCapacity();
                try self.command_buffer.appendSlice("'<,'>!");
            },
            '=' => try self.visualEqualPrg(),
            ':' => {
                self.mode = .command;
                self.command_buffer.clearRetainingCapacity();
                try self.command_buffer.appendSlice("'<,'>");
            },
            0x01 => try self.visualAdjustNumber(true, 1),
            0x18 => try self.visualAdjustNumber(false, 1),
            else => try self.setStatus("visual command not implemented"),
        }
        if (self.visual_select_restore and self.mode == .visual and self.visual_pending == null) {
            self.visual_select_restore = false;
            self.visual_select_mode = true;
            try self.setStatus("select mode");
        }
    }

    fn handlePendingPrefix(self: *App, byte: u8) anyerror!void {
        switch (self.pending_prefix) {
            .register => {
                self.pending_prefix = .none;
                self.pending_register = byte;
                const msg = try std.fmt.allocPrint(self.allocator, "register \"{c}", .{byte});
                defer self.allocator.free(msg);
                try self.setStatus(msg);
            },
            .replace_char => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.activeBuffer().replaceCurrentCharacter(byte);
            },
            .find_forward, .find_forward_before, .find_backward, .find_backward_before => {
                const count = self.consumeCount();
                const forward = self.pending_prefix == .find_forward or self.pending_prefix == .find_forward_before;
                const before = self.pending_prefix == .find_forward_before or self.pending_prefix == .find_backward_before;
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                self.last_find = .{ .char = byte, .forward = forward, .before = before };
                try self.performFind(byte, forward, before, count);
            },
            .macro_record => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                if (self.macro_recording) |current| {
                    if (current == byte) {
                        self.macro_recording = null;
                        try self.setStatus("macro stopped");
                        return;
                    }
                }
                try self.startMacroRecording(byte);
            },
            .macro_run => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.runMacro(byte);
            },
            .mark_set => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.setMark(byte);
            },
            .mark_jump => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.jumpMark(byte, false);
            },
            .mark_jump_exact => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.jumpMark(byte, true);
            },
            else => unreachable,
        }
    }

    fn resolveNormalSequence(self: *App) !void {
        const sequence = self.normal_sequence.items;
        if (sequence.len == 0) return;

        if (normalActionFor(sequence)) |action| {
            if (normalActionHasPrefix(sequence)) return;
            const count = self.consumeCount();
            self.normal_sequence.clearRetainingCapacity();
            try self.performNormalAction(action, count);
            if (action != .repeat_last_command) {
                self.last_normal_action = action;
                self.last_normal_count = count;
            }
            return;
        }

        if (normalActionHasPrefix(sequence)) {
            return;
        }

        self.normal_sequence.clearRetainingCapacity();
        self.count_active = false;
        self.count_prefix = 0;
        try self.setStatus("unknown command");
    }

    fn resetNormalInput(self: *App) void {
        self.normal_sequence.clearRetainingCapacity();
        self.pending_prefix = .none;
        self.pending_register = null;
        self.count_prefix = 0;
        self.count_active = false;
    }

    fn consumeCount(self: *App) usize {
        const count = if (self.count_active and self.count_prefix > 0) self.count_prefix else 1;
        self.count_prefix = 0;
        self.count_active = false;
        return count;
    }

    fn performNormalAction(self: *App, action: NormalAction, count: usize) !void {
        const buf = self.activeBuffer();
        const start_cursor = self.activeBuffer().cursor;
        var text_changed = false;
        var record_jump = true;
        switch (action) {
            .move_left => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveLeft();
            },
            .move_down => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveDown();
            },
            .move_up => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveUp();
            },
            .move_right => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveRight();
            },
            .move_line_start => buf.moveLineStart(),
            .move_line_nonblank => buf.moveToFirstNonBlank(),
            .move_line_last_nonblank => buf.moveToLastNonBlank(),
            .move_line_end => buf.moveLineEnd(),
            .move_doc_start => {
                if (count > 1) {
                    buf.moveToLine(@min(count - 1, buf.lineCount() - 1));
                } else {
                    buf.moveToDocumentStart();
                }
            },
            .move_doc_middle => {
                const middle = if (buf.lineCount() > 0) (buf.lineCount() - 1) / 2 else 0;
                buf.moveToLine(middle);
            },
            .move_doc_end => {
                if (count > 1) {
                    buf.moveToLine(@min(count - 1, buf.lineCount() - 1));
                } else {
                    buf.moveToDocumentEnd();
                }
            },
            .tab_next => try self.switchFocusedBuffer(true, count),
            .tab_prev => try self.switchFocusedBuffer(false, count),
            .window_split_horizontal, .window_split_vertical => try self.openSplitFromCurrentBuffer(),
            .window_new => try self.openNewWindow(),
            .window_switch => self.toggleSplitFocus(),
            .window_close => try self.closeCurrentPane(),
            .window_exchange => try self.exchangeFocusedBuffers(),
            .window_resize_increase, .window_resize_wider => try self.resizeSplitBy(10),
            .window_resize_decrease, .window_resize_narrower => try self.resizeSplitBy(-10),
            .window_maximize_width, .window_maximize_height => try self.maximizeSplit(),
            .window_to_tab => try self.splitToTab(),
            .window_left, .window_up => self.focusWindow(.left),
            .window_right, .window_down => self.focusWindow(.right),
            .window_far_left => self.focusWindow(.left),
            .window_far_right => self.focusWindow(.right),
            .window_far_bottom => self.focusWindow(.right),
            .window_far_top => self.focusWindow(.left),
            .window_equalize => try self.equalizeWindows(),
            .fold_create => try self.createFoldAtCursor(),
            .fold_delete => self.deleteFoldAtCursor(),
            .fold_toggle => self.toggleFoldAtCursor(),
            .fold_open => self.openFoldAtCursor(),
            .fold_close => self.closeFoldAtCursor(),
            .fold_open_all => self.activeBuffer().openAllFolds(),
            .fold_close_all => self.activeBuffer().closeAllFolds(),
            .fold_toggle_enabled => self.activeBuffer().toggleFolding(),
            .fold_delete_all => {
                self.activeBuffer().clearFolds();
                try self.setStatus("all folds deleted");
            },
            .diff_get => try self.diffGet(),
            .diff_put => try self.diffPut(),
            .diff_this => try self.enableDiffMode(),
            .diff_off => self.disableDiffMode(),
            .diff_update => try self.updateDiffSummary(),
            .diff_next_change => try self.jumpChangeHistory(true),
            .diff_prev_change => try self.jumpChangeHistory(false),
            .move_word_forward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordForward(false);
            },
            .move_word_forward_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordForward(true);
            },
            .move_word_backward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordBackward(false);
            },
            .move_word_backward_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordBackward(true);
            },
            .move_word_end => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEnd(false);
            },
            .move_word_end_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEnd(true);
            },
            .move_word_end_backward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEndBackward(false);
            },
            .move_word_end_backward_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEndBackward(true);
            },
            .move_paragraph_forward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveParagraphForward();
            },
            .move_paragraph_backward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveParagraphBackward();
            },
            .move_sentence_forward => try self.moveSentence(true, count),
            .move_sentence_backward => try self.moveSentence(false, count),
            .scroll_up => try self.scrollViewport(false, count),
            .scroll_down => try self.scrollViewport(true, count),
            .jump_history_forward => try self.jumpHistory(true, count),
            .jump_history_backward => try self.jumpHistory(false, count),
            .switch_previous_buffer => self.togglePreviousBuffer(),
            .find_forward, .find_backward, .find_forward_before, .find_backward_before => unreachable,
            .repeat_find_forward => {
                if (self.last_find) |find| try self.performFind(find.char, find.forward, find.before, count);
            },
            .repeat_find_backward => {
                if (self.last_find) |find| try self.performFind(find.char, !find.forward, find.before, count);
            },
            .delete_char => {
                try buf.deleteForward();
                try self.setStatus("deleted");
            },
            .replace_char => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .replace_char;
                try self.setStatus("replace a single character");
            },
            .substitute_char => {
                try buf.deleteForward();
                self.mode = .insert;
            },
            .substitute_line => {
                const removed = try buf.deleteLine(1);
                defer self.allocator.free(removed);
                self.mode = .insert;
            },
            .insert_before => self.mode = .insert,
            .insert_at_bol => {
                buf.moveToFirstNonBlank();
                self.mode = .insert;
            },
            .append_after => {
                buf.moveRight();
                self.mode = .insert;
            },
            .append_eol => {
                buf.moveLineEnd();
                self.mode = .insert;
            },
            .open_below => {
                try buf.insertNewline();
                self.mode = .insert;
            },
            .open_above => {
                buf.moveUp();
                buf.moveLineStart();
                try buf.insertNewline();
                buf.moveUp();
                self.mode = .insert;
            },
            .delete_line => {
                const removed = try buf.deleteLine(count);
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
                try self.setStatus("deleted line");
            },
            .delete_to_bol => {
                const removed = try buf.deleteToLineStart();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
                try self.setStatus("deleted line start");
            },
            .yank_line => {
                const yanked = try buf.yankLine(count);
                defer self.allocator.free(yanked);
                try self.storeRegisterForYank(yanked);
                try self.setStatus("yanked line");
            },
            .paste_after => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(false, key);
                self.pending_register = null;
            },
            .paste_before => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(true, key);
                self.pending_register = null;
            },
            .paste_after_keep_cursor => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(false, key);
                self.pending_register = null;
            },
            .paste_before_keep_cursor => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(true, key);
                self.pending_register = null;
            },
            .undo => {
                var i: usize = 0;
                while (i < count) : (i += 1) try buf.undo();
            },
            .redo => {
                var i: usize = 0;
                while (i < count) : (i += 1) try buf.redo();
            },
            .delete_word => {
                const removed = try buf.deleteCurrentWord();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
            },
            .change_word => {
                const removed = try buf.deleteCurrentWord();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
                self.mode = .insert;
            },
            .change_line => {
                const removed = try buf.deleteLine(count);
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
                self.mode = .insert;
            },
            .change_to_eol => {
                const removed = try buf.deleteToLineEnd();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
                self.mode = .insert;
            },
            .yank_word => {
                const word = buf.currentWord();
                try self.storeRegisterForYank(word);
            },
            .delete_to_eol => {
                const removed = try buf.deleteToLineEnd();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed);
            },
            .indent_line => {
                try self.shiftCurrentLine(true, count);
                text_changed = true;
            },
            .dedent_line => {
                try self.shiftCurrentLine(false, count);
                text_changed = true;
            },
            .toggle_case_char => {
                try self.toggleCurrentCharacter();
                text_changed = true;
            },
            .toggle_case_word => {
                try self.transformCurrentWord(.toggle);
                text_changed = true;
            },
            .lowercase_word => {
                try self.transformCurrentWord(.lower);
                text_changed = true;
            },
            .uppercase_word => {
                try self.transformCurrentWord(.upper);
                text_changed = true;
            },
            .viewport_top => self.setViewport(.top),
            .viewport_middle => self.setViewport(.middle),
            .viewport_bottom => self.setViewport(.bottom),
            .join_line_space => try self.joinCurrentLine(true),
            .join_line_nospace => try self.joinCurrentLine(false),
            .save => {
                _ = self.saveActiveBuffer();
            },
            .save_as => {
                _ = self.commandSaveAs(null);
            },
            .close => try self.closeCurrentPane(),
            .terminal => try self.openTerminalShell(),
            .help => try self.openManPageForCurrentWord(),
            .jump_local_declaration => try self.jumpToDeclaration(false),
            .jump_global_declaration => try self.jumpToDeclaration(true),
            .jump_matching_character => try self.jumpToMatchingCharacter(),
            .search_next => try self.repeatSearch(true),
            .search_prev => try self.repeatSearch(false),
            .search_word_forward => try self.searchWordUnderCursor(true),
            .search_word_backward => try self.searchWordUnderCursor(false),
            .registers => try self.showRegisters(),
            .open => try self.setStatus("use :open PATH"),
            .open_file_under_cursor => try self.openCursorPath(false),
            .open_link_under_cursor => try self.openCursorPath(true),
            .split => try self.setStatus("use :split PATH"),
            .set_mark => try self.setStatus("use m{mark}"),
            .jump_mark => try self.setStatus("use '{mark}"),
            .jump_mark_exact => try self.setStatus("use `{mark}"),
            .repeat_last_command => try self.repeatLastCommand(),
            .reload_config => try self.reloadConfig(),
            .quit => try self.requestQuit(false),
            .force_quit => try self.requestQuit(true),
            .visual_char => self.startVisual(.character),
            .visual_line => self.startVisual(.line),
            .visual_block => {
                self.startVisual(.block);
                try self.setStatus("visual block mode is partial");
            },
            .exit_visual => self.exitVisual(),
            .visual_yank => try self.visualYank(),
            .visual_delete => try self.visualDelete(),
            .visual_restore => try self.restoreLastVisual(),
            .not_implemented => try self.setStatus("not implemented"),
            .macro_record => try self.setStatus("use q<reg> in normal mode"),
            .macro_run => try self.setStatus("use @<reg> in normal mode"),
            .tab_new => try self.openNewTab(null),
            .tab_close => try self.tabCloseCurrent(),
            .tab_only => try self.tabOnlyCurrent(),
            .tab_move => try self.setStatus("use :tabmove N"),
        }
        if (text_changed or actionIsEditing(action)) try self.recordChange(start_cursor);
        if (action == .scroll_up or action == .scroll_down or action == .jump_history_forward or action == .jump_history_backward or action == .switch_previous_buffer or action == .repeat_last_command) {
            record_jump = false;
        }
        const end_cursor = self.activeBuffer().cursor;
        if (record_jump and (end_cursor.row != start_cursor.row or end_cursor.col != start_cursor.col)) try self.recordJump(start_cursor);
        self.pending_register = null;
    }

    fn performFind(self: *App, needle: u8, forward: bool, before: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (line.len == 0) return;
        var idx = buf.cursor.col;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (forward) {
                var start = if (idx < line.len) idx + 1 else line.len;
                var found: ?usize = null;
                while (start < line.len) : (start += 1) {
                    if (line[start] == needle) {
                        found = start;
                        break;
                    }
                }
                if (found) |pos| {
                    idx = if (before and pos > 0) pos - 1 else pos;
                }
            } else {
                if (idx == 0) break;
                var start: usize = idx - 1;
                var found: ?usize = null;
                while (true) {
                    if (line[start] == needle) {
                        found = start;
                        break;
                    }
                    if (start == 0) break;
                    start -= 1;
                }
                if (found) |pos| {
                    idx = if (!before and pos + 1 < line.len) pos + 1 else pos;
                }
            }
        }
        buf.cursor.col = @min(idx, line.len);
        self.last_find = .{ .char = needle, .forward = forward, .before = before };
    }

    fn saveActiveBuffer(self: *App) bool {
        self.activeBuffer().save() catch |err| {
            self.setStatus(@errorName(err)) catch {};
            return false;
        };
        self.plugin_host.broadcastEvent("buffer_save", "{}");
        self.setStatus("saved") catch {};
        self.maybeDrainPluginActions() catch {};
        return true;
    }

    fn commandSaveAs(self: *App, path: ?[]const u8) bool {
        const actual = path orelse {
            self.setStatus("saveas requires a path") catch {};
            return false;
        };
        self.activeBuffer().saveAs(actual) catch |err| {
            self.setStatus(@errorName(err)) catch {};
            return false;
        };
        self.setStatus("saved as") catch {};
        return true;
    }

    fn requestQuit(self: *App, force: bool) !void {
        if (!force and self.anyDirty()) {
            try self.setStatus("buffer modified, use :q! or :wq");
            return;
        }
        self.should_quit = true;
    }

    fn anyDirty(self: *const App) bool {
        for (self.buffers.items) |buf| {
            if (buf.dirty) return true;
        }
        return false;
    }

    fn startVisual(self: *App, mode: VisualMode) void {
        self.last_visual_state = null;
        self.mode = .visual;
        self.visual_mode = mode;
        self.visual_select_mode = false;
        self.visual_select_restore = false;
        self.visual_pending = null;
        self.visual_anchor = self.activeBuffer().cursor;
    }

    fn exitVisual(self: *App) void {
        if (self.visual_anchor) |anchor| {
            self.last_visual_state = .{
                .mode = self.visual_mode,
                .anchor = anchor,
                .cursor = self.activeBuffer().cursor,
                .select_mode = self.visual_select_mode,
                .select_restore = self.visual_select_restore,
            };
        }
        self.visual_mode = .none;
        self.visual_anchor = null;
        self.visual_select_mode = false;
        self.visual_select_restore = false;
        self.visual_pending = null;
        self.mode = .normal;
    }

    const VisualSelection = struct {
        start: buffer_mod.Position,
        end: buffer_mod.Position,
    };

    fn visualSelection(self: *App) ?VisualSelection {
        const anchor = self.visual_anchor orelse return null;
        const cursor = self.activeBuffer().cursor;
        const ordered: VisualSelection = if (anchor.row < cursor.row or (anchor.row == cursor.row and anchor.col <= cursor.col))
            .{ .start = anchor, .end = cursor }
        else
            .{ .start = cursor, .end = anchor };
        return switch (self.visual_mode) {
            .line => .{
                .start = .{ .row = ordered.start.row, .col = 0 },
                .end = .{ .row = ordered.end.row, .col = self.activeBuffer().lines.items[ordered.end.row].len },
            },
            else => ordered,
        };
    }

    const VisualBlockBounds = struct {
        start_row: usize,
        end_row: usize,
        start_col: usize,
        end_col: usize,
    };

    fn visualBlockBounds(self: *App) ?VisualBlockBounds {
        if (self.visual_mode != .block) return null;
        const anchor = self.visual_anchor orelse return null;
        const cursor = self.activeBuffer().cursor;
        return .{
            .start_row = @min(anchor.row, cursor.row),
            .end_row = @max(anchor.row, cursor.row),
            .start_col = @min(anchor.col, cursor.col),
            .end_col = @max(anchor.col, cursor.col),
        };
    }

    fn swapVisualCorners(self: *App) void {
        if (self.visual_anchor) |anchor| {
            const current = self.activeBuffer().cursor;
            self.activeBuffer().cursor = anchor;
            self.visual_anchor = current;
        }
    }

    fn restoreLastVisual(self: *App) !void {
        const saved = self.last_visual_state orelse {
            try self.setStatus("no previous visual area");
            return;
        };
        self.mode = .visual;
        self.visual_mode = saved.mode;
        self.visual_anchor = saved.anchor;
        self.activeBuffer().cursor = saved.cursor;
        self.visual_select_mode = saved.select_mode;
        self.visual_select_restore = saved.select_restore;
    }

    fn commitVisualBlockInsert(self: *App, block: *VisualBlockInsert) !void {
        const inserted = try block.text.toOwnedSlice();
        defer self.allocator.free(inserted);
        var row = block.start_row;
        while (row <= block.end_row) : (row += 1) {
            const pos = buffer_mod.Position{ .row = row, .col = block.column };
            try self.activeBuffer().replaceRangeWithText(pos, pos, inserted);
        }
        block.text.clearRetainingCapacity();
        self.visual_block_insert = null;
        self.exitVisual();
    }

    fn visualYank(self: *App) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockYank();
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(text);
        try self.storeRegisterForYank(text);
    }

    fn visualDelete(self: *App) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockDelete();
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed);
    }

    fn visualReplaceChar(self: *App, byte: u8) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockReplaceChar(byte);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        if (start >= end) return;
        const replacement = try self.allocator.alloc(u8, end - start);
        defer self.allocator.free(replacement);
        @memset(replacement, byte);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, replacement);
        self.exitVisual();
    }

    fn visualPaste(self: *App, before: bool, preserve_registers: bool) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockPaste(before);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const key = self.pending_register orelse '"';
        const value = self.registers.get(key) orelse {
            try self.setStatus("register empty");
            return;
        };
        if (!preserve_registers) {
            const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
            defer self.allocator.free(removed);
            try self.storeRegisterForDelete(removed);
            try self.activeBuffer().replaceRangeWithText(selection.start, selection.start, value);
        } else {
            try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, value);
        }
        self.exitVisual();
    }

    fn visualBlockPaste(self: *App, before: bool) !void {
        _ = before;
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        const key = self.pending_register orelse '"';
        const value = self.registers.get(key) orelse {
            try self.setStatus("register empty");
            return;
        };
        var removed = std.array_list.Managed(u8).init(self.allocator);
        errdefer removed.deinit();
        var row = bounds.start_row;
        var line_index: usize = 0;
        while (row <= bounds.end_row) : (row += 1) {
            const segment = splitRegisterLine(value, line_index);
            const line = self.activeBuffer().lines.items[row];
            const removed_piece = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(removed_piece);
            if (row > bounds.start_row) try removed.append('\n');
            try removed.appendSlice(removed_piece);
            try self.replaceBlockRowSlice(row, bounds, segment);
            line_index += 1;
        }
        const removed_text = try removed.toOwnedSlice();
        defer self.allocator.free(removed_text);
        try self.storeRegisterForDelete(removed_text);
        self.exitVisual();
    }

    fn visualChange(self: *App) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed);
        self.exitVisual();
        self.mode = .insert;
    }

    fn visualCase(self: *App, mode: CaseMode) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockCase(mode);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        if (start >= end) return;
        const piece = try self.allocator.dupe(u8, text[start..end]);
        defer self.allocator.free(piece);
        for (piece) |*ch| {
            ch.* = switch (mode) {
                .toggle => toggleAsciiCase(ch.*),
                .lower => std.ascii.toLower(ch.*),
                .upper => std.ascii.toUpper(ch.*),
            };
        }
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, piece);
        self.exitVisual();
    }

    fn visualIndent(self: *App, right: bool) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        if (selection.start.row != selection.end.row) {
            const start_row = selection.start.row;
            const end_row = selection.end.row;
            var row: usize = start_row;
            while (row <= end_row) : (row += 1) {
                try self.shiftCurrentLineSelection(row, right, 1);
            }
            self.exitVisual();
            return;
        }
        try self.applyVisualIndent(right);
    }

    fn shiftCurrentLineSelection(self: *App, row: usize, right: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const line = buf.lines.items[row];
        const start = buffer_mod.Position{ .row = row, .col = 0 };
        const end = buffer_mod.Position{ .row = row, .col = line.len };
        const width = self.config.tab_width * count;
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        if (right) {
            try out.appendNTimes(' ', width);
            try out.appendSlice(line);
        } else {
            var trim = line;
            var removed: usize = 0;
            while (removed < width and trim.len > 0 and trim[0] == ' ') : (removed += 1) {
                trim = trim[1..];
            }
            try out.appendSlice(trim);
        }
        try buf.replaceRangeWithText(start, end, try out.toOwnedSlice());
    }

    fn visualJoin(self: *App, with_space: bool) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        if (selection.start.row == selection.end.row) return;
        const buf = self.activeBuffer();
        var line = selection.start.row;
        const end_row = selection.end.row;
        var combined = std.array_list.Managed(u8).init(self.allocator);
        defer combined.deinit();
        while (line <= end_row) : (line += 1) {
            if (line > selection.start.row) {
                if (with_space) try combined.append(' ');
            }
            try combined.appendSlice(buf.lines.items[line]);
        }
        try buf.replaceRangeWithText(.{ .row = selection.start.row, .col = 0 }, .{ .row = selection.end.row, .col = buf.lines.items[selection.end.row].len }, try combined.toOwnedSlice());
        self.exitVisual();
    }

    fn runVisualFilter(self: *App, command: []const u8) !void {
        if (self.visual_mode == .block) {
            try self.runVisualBlockFilter(command);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const input = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(input);
        const output = try self.runCommandWithInput(command, input);
        defer self.allocator.free(output);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, output);
        self.exitVisual();
    }

    fn runVisualBlockFilter(self: *App, command: []const u8) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            const line = self.activeBuffer().lines.items[row];
            const input = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(input);
            const output = try self.runCommandWithInput(command, input);
            defer self.allocator.free(output);
            const normalized = trimTrailingNewline(output);
            try self.replaceBlockRowSlice(row, bounds, normalized);
        }
        self.exitVisual();
    }

    fn runCommandWithInput(self: *App, command: []const u8, input: []const u8) ![]u8 {
        const argv = if (builtin.os.tag == .windows) blk: {
            const shell = try self.defaultShell();
            defer if (shell.owned) self.allocator.free(shell.path);
            break :blk &[_][]const u8{ shell.path, "/C", command };
        } else &[_][]const u8{ "sh", "-c", command };

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();
        if (child.stdin) |*stdin_file| {
            try stdin_file.writeAll(input);
            stdin_file.close();
            child.stdin = null;
        }

        const output = if (child.stdout) |*stdout_file| blk: {
            const text = try stdout_file.readToEndAlloc(self.allocator, 1 << 20);
            stdout_file.close();
            child.stdout = null;
            break :blk text;
        } else try self.allocator.dupe(u8, "");
        errdefer self.allocator.free(output);
        _ = try child.wait();
        return output;
    }

    fn trimTrailingNewline(bytes: []const u8) []const u8 {
        return if (bytes.len > 0 and bytes[bytes.len - 1] == '\n') bytes[0 .. bytes.len - 1] else bytes;
    }

    fn splitRegisterLine(text: []const u8, index: usize) []const u8 {
        var start: usize = 0;
        var line_index: usize = 0;
        while (start <= text.len) {
            const rel_end = std.mem.indexOfScalar(u8, text[start..], '\n');
            const end = if (rel_end) |idx| start + idx else text.len;
            if (line_index == index) return text[start..end];
            if (end >= text.len) return text[start..end];
            start = end + 1;
            line_index += 1;
        }
        return text;
    }

    fn blockSliceForLine(self: *App, line: []const u8, bounds: VisualBlockBounds) ![]u8 {
        const width = bounds.end_col - bounds.start_col;
        var out = try self.allocator.alloc(u8, width);
        @memset(out, ' ');
        const src_start = @min(bounds.start_col, line.len);
        const src_end = @min(bounds.end_col, line.len);
        if (src_start < src_end) {
            @memcpy(out[src_start - bounds.start_col .. src_end - bounds.start_col], line[src_start..src_end]);
        }
        return out;
    }

    fn replaceBlockRowSlice(self: *App, row: usize, bounds: VisualBlockBounds, replacement: []const u8) !void {
        const buf = self.activeBuffer();
        const line = buf.lines.items[row];
        const start_col = @min(bounds.start_col, line.len);
        const end_col = @min(bounds.end_col, line.len);
        const start = buffer_mod.Position{ .row = row, .col = start_col };
        const end = buffer_mod.Position{ .row = row, .col = end_col };
        try buf.replaceRangeWithText(start, end, replacement);
    }

    fn visualBlockYank(self: *App) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            if (row > bounds.start_row) try out.append('\n');
            const line = self.activeBuffer().lines.items[row];
            const slice = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(slice);
            try out.appendSlice(slice);
        }
        const text = try out.toOwnedSlice();
        defer self.allocator.free(text);
        try self.storeRegisterForYank(text);
    }

    fn visualBlockDelete(self: *App) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            if (row > bounds.start_row) try out.append('\n');
            const line = self.activeBuffer().lines.items[row];
            const slice = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(slice);
            try out.appendSlice(slice);
            try self.replaceBlockRowSlice(row, bounds, "");
        }
        const removed = try out.toOwnedSlice();
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed);
    }

    fn visualBlockReplaceChar(self: *App, byte: u8) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            const line = self.activeBuffer().lines.items[row];
            const start_col = @min(bounds.start_col, line.len);
            const end_col = @min(bounds.end_col, line.len);
            if (start_col >= end_col) continue;
            const width = end_col - start_col;
            const replacement = try self.allocator.alloc(u8, width);
            defer self.allocator.free(replacement);
            @memset(replacement, byte);
            try self.replaceBlockRowSlice(row, bounds, replacement);
        }
        self.exitVisual();
    }

    fn visualBlockCase(self: *App, mode: CaseMode) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            const line = self.activeBuffer().lines.items[row];
            const start_col = @min(bounds.start_col, line.len);
            const end_col = @min(bounds.end_col, line.len);
            if (start_col >= end_col) continue;
            const selection = line[start_col..end_col];
            const replacement = try self.allocator.dupe(u8, selection);
            defer self.allocator.free(replacement);
            for (replacement) |*ch| {
                ch.* = switch (mode) {
                    .toggle => toggleAsciiCase(ch.*),
                    .lower => std.ascii.toLower(ch.*),
                    .upper => std.ascii.toUpper(ch.*),
                };
            }
            try self.replaceBlockRowSlice(row, bounds, replacement);
        }
        self.exitVisual();
    }

    fn visualBlockInsert(self: *App, before: bool) !void {
        if (self.visual_mode != .block) {
            try self.setStatus("block insert only works in block mode");
            return;
        }
        const bounds = self.visualBlockBounds() orelse {
            try self.setStatus("no selection");
            return;
        };
        if (self.visual_block_insert) |*block| {
            block.text.clearRetainingCapacity();
            block.start_row = bounds.start_row;
            block.end_row = bounds.end_row;
            block.column = if (before) bounds.start_col else bounds.end_col;
            block.before = before;
        } else {
            var text = std.array_list.Managed(u8).init(self.allocator);
            errdefer text.deinit();
            self.visual_block_insert = .{
                .start_row = bounds.start_row,
                .end_row = bounds.end_row,
                .column = if (before) bounds.start_col else bounds.end_col,
                .before = before,
                .text = text,
            };
        }
        self.exitVisual();
        self.mode = .insert;
        try self.setStatus("block insert");
    }

    fn visualFormat(self: *App) !void {
        try self.visualJoin(true);
    }

    fn visualEqualPrg(self: *App) !void {
        try self.runVisualFilter(self.config.equalprg);
    }

    fn visualVisualHelp(self: *App) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(text);
        if (text.len == 0) {
            try self.setStatus("no selection");
            return;
        }
        if (!self.runInteractiveCommand(&.{ "man", text })) {
            try self.setStatus("man page not available");
        } else {
            try self.setStatus("returned from man");
        }
    }

    fn visualJumpTag(self: *App) !void {
        const selection = self.visualSelection() orelse {
            try self.setStatus("no selection");
            return;
        };
        const selected = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(selected);
        var token_it = std.mem.tokenizeAny(u8, selected, " \t\r\n");
        const tag = token_it.next() orelse {
            try self.setStatus("no tag under cursor");
            return;
        };
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const found = findWordOccurrence(text, tag, cursor_offset, true) orelse {
            try self.setStatus("tag not found");
            return;
        };
        buf.cursor = self.offsetToPosition(text, found);
        self.exitVisual();
    }

    fn selectVisualTextObject(self: *App, byte: u8, inner: bool) !void {
        const range = try self.resolveVisualTextObject(byte, inner) orelse {
            try self.setStatus("text object not found");
            return;
        };
        self.setVisualRange(range);
    }

    const VisualTextRange = struct {
        start: buffer_mod.Position,
        end: buffer_mod.Position,
    };

    fn resolveVisualTextObject(self: *App, byte: u8, inner: bool) !?VisualTextRange {
        return switch (byte) {
            'w' => self.wordObjectRange(false, inner),
            'W' => self.wordObjectRange(true, inner),
            '(', ')', 'b' => self.pairedObjectRange('(', ')', inner),
            '[', ']' => self.pairedObjectRange('[', ']', inner),
            '{', '}', 'B' => self.pairedObjectRange('{', '}', inner),
            '<', '>' => self.angleObjectRange(inner),
            '"' => self.quoteObjectRange('"', inner),
            '\'' => self.quoteObjectRange('\'', inner),
            '`' => self.quoteObjectRange('`', inner),
            'p' => self.paragraphObjectRange(inner),
            's' => self.sentenceObjectRange(inner),
            't' => self.tagObjectRange(inner),
            else => null,
        };
    }

    fn setVisualRange(self: *App, range: VisualTextRange) void {
        self.mode = .visual;
        self.visual_mode = .character;
        self.visual_select_mode = false;
        self.visual_pending = null;
        self.visual_anchor = range.start;
        self.activeBuffer().cursor = range.end;
    }

    fn wordObjectRange(self: *App, big: bool, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (line.len == 0) return null;
        const cursor = @min(buf.cursor.col, line.len);
        var start = cursor;
        if (start == line.len and start > 0) start -= 1;
        while (start > 0 and isObjectWordChar(line[start - 1], big)) : (start -= 1) {}
        var end = cursor;
        while (end < line.len and isObjectWordChar(line[end], big)) : (end += 1) {}
        if (!inner) {
            while (end < line.len and std.ascii.isWhitespace(line[end])) : (end += 1) {}
        }
        if (start == end) return null;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn pairedObjectRange(self: *App, open: u8, close: u8, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const text = buf.serialize() catch return null;
        defer self.allocator.free(text);
        const cursor = self.positionToOffset(buf.cursor, text);
        const left = findPairBoundary(text, cursor, open, close, true) orelse return null;
        const right = findPairBoundary(text, cursor, open, close, false) orelse return null;
        const start = if (inner and left + 1 <= right) left + 1 else left;
        const end = if (inner and right > start) right else right + 1;
        return .{
            .start = self.offsetToPosition(text, start),
            .end = self.offsetToPosition(text, end),
        };
    }

    fn quoteObjectRange(self: *App, quote: u8, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const cursor = @min(buf.cursor.col, line.len);
        var left: ?usize = null;
        if (line.len > 0) {
            var idx: usize = @min(cursor, line.len - 1);
            while (true) {
                if (line[idx] == quote) {
                    left = idx;
                    break;
                }
                if (idx == 0) break;
                idx -= 1;
            }
        }
        var right: ?usize = null;
        var idx: usize = cursor;
        while (idx < line.len) : (idx += 1) {
            if (line[idx] == quote) {
                right = idx;
                break;
            }
        }
        const l = left orelse return null;
        const r = right orelse return null;
        const start = if (inner) l + 1 else l;
        const end = if (inner) r else r + 1;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn angleObjectRange(self: *App, inner: bool) ?VisualTextRange {
        return self.pairedObjectRange('<', '>', inner);
    }

    fn paragraphObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        if (buf.lineCount() == 0) return null;
        var start_row = buf.cursor.row;
        while (start_row > 0 and buf.lines.items[start_row - 1].len != 0) : (start_row -= 1) {}
        var end_row = buf.cursor.row;
        while (end_row + 1 < buf.lineCount() and buf.lines.items[end_row + 1].len != 0) : (end_row += 1) {}
        if (inner) {
            while (start_row < end_row and buf.lines.items[start_row].len == 0) : (start_row += 1) {}
            while (end_row > start_row and buf.lines.items[end_row].len == 0) : (end_row -= 1) {}
        }
        return .{
            .start = .{ .row = start_row, .col = 0 },
            .end = .{ .row = end_row, .col = buf.lines.items[end_row].len },
        };
    }

    fn sentenceObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (line.len == 0) return null;
        const cursor = @min(buf.cursor.col, line.len);
        var start: usize = 0;
        var i: usize = cursor;
        while (i > 0) : (i -= 1) {
            if (line[i - 1] == '.' or line[i - 1] == '!' or line[i - 1] == '?') {
                start = i;
                break;
            }
        }
        while (start < line.len and std.ascii.isWhitespace(line[start])) : (start += 1) {}
        var end: usize = line.len;
        i = cursor;
        while (i < line.len) : (i += 1) {
            if (line[i] == '.' or line[i] == '!' or line[i] == '?') {
                end = i + 1;
                break;
            }
        }
        if (inner) {
            while (end > start and std.ascii.isWhitespace(line[end - 1])) : (end -= 1) {}
        }
        if (start >= end) return null;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn tagObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const cursor = @min(buf.cursor.col, line.len);
        var left: ?usize = null;
        var right: ?usize = null;
        if (line.len > 0) {
            var i: usize = @min(cursor, line.len - 1);
            while (true) {
                if (line[i] == '<') {
                    left = i;
                    break;
                }
                if (i == 0) break;
                i -= 1;
            }
        }
        var i: usize = cursor;
        while (i < line.len) : (i += 1) {
            if (line[i] == '>') {
                right = i;
                break;
            }
        }
        const l = left orelse return null;
        const r = right orelse return null;
        const start = if (inner) l + 1 else l;
        const end = if (inner) r else r + 1;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn isObjectWordChar(byte: u8, big: bool) bool {
        return if (big) !std.ascii.isWhitespace(byte) else isWordChar(byte);
    }

    fn findPairBoundary(text: []const u8, cursor: usize, open: u8, close: u8, left: bool) ?usize {
        if (left) {
            var depth: usize = 0;
            if (text.len == 0) return null;
            var idx = @min(cursor, text.len - 1);
            while (true) {
                const ch = text[idx];
                if (ch == open) {
                    if (depth == 0) return idx;
                    depth -= 1;
                } else if (ch == close) {
                    depth += 1;
                }
                if (idx == 0) break;
                idx -= 1;
            }
            return null;
        }
        var depth: usize = 0;
        var idx: usize = cursor;
        while (idx < text.len) : (idx += 1) {
            const ch = text[idx];
            if (ch == close) {
                if (depth == 0) return idx;
                depth -= 1;
            } else if (ch == open) {
                depth += 1;
            }
        }
        return null;
    }

    fn visualAdjustNumber(self: *App, add: bool, amount: usize) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        if (start >= end) return;
        var piece = try self.allocator.dupe(u8, text[start..end]);
        defer self.allocator.free(piece);
        var i: usize = 0;
        while (i < piece.len and !std.ascii.isDigit(piece[i]) and piece[i] != '-') : (i += 1) {}
        if (i >= piece.len) {
            try self.setStatus("no number in selection");
            return;
        }
        const num_start = i;
        if (piece[i] == '-') i += 1;
        while (i < piece.len and std.ascii.isDigit(piece[i])) : (i += 1) {}
        const value = std.fmt.parseInt(i64, piece[num_start..i], 10) catch {
            try self.setStatus("invalid number");
            return;
        };
        const delta: i64 = @intCast(amount);
        const next = if (add) value + delta else value - delta;
        const number = try std.fmt.allocPrint(self.allocator, "{d}", .{next});
        defer self.allocator.free(number);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        try out.appendSlice(piece[0..num_start]);
        try out.appendSlice(number);
        try out.appendSlice(piece[i..]);
        const replacement = try out.toOwnedSlice();
        defer self.allocator.free(replacement);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, replacement);
        self.exitVisual();
    }

    fn selectedText(self: *App, start: buffer_mod.Position, end: buffer_mod.Position) ![]u8 {
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start_index = self.positionToOffset(start, text);
        const end_index = self.positionToOffset(end, text);
        return try self.allocator.dupe(u8, text[start_index..end_index]);
    }

    fn positionToOffset(self: *App, pos: buffer_mod.Position, text: []const u8) usize {
        _ = self;
        var row: usize = 0;
        var offset: usize = 0;
        var start: usize = 0;
        while (start <= text.len) {
            const rel_end = std.mem.indexOfScalar(u8, text[start..], '\n');
            const end = if (rel_end) |idx| start + idx else text.len;
            if (row == pos.row) {
                return offset + @min(pos.col, end - start);
            }
            offset += end - start;
            if (end < text.len) offset += 1;
            if (end >= text.len) break;
            start = end + 1;
            row += 1;
        }
        return text.len;
    }

    fn storeRegisterForYank(self: *App, bytes: []const u8) !void {
        try self.registers.set('"', bytes);
        try self.registers.set('0', bytes);
        if (self.pending_register) |reg| try self.registers.set(reg, bytes);
    }

    fn storeRegisterForDelete(self: *App, bytes: []const u8) !void {
        try self.registers.set('"', bytes);
        if (self.pending_register) |reg| try self.registers.set(reg, bytes);
    }

    fn pasteRegister(self: *App, before: bool) !void {
        try self.pasteRegisterKey(before, self.pending_register orelse '"');
        self.pending_register = null;
    }

    fn pasteRegisterKey(self: *App, before: bool, key: u8) !void {
        const value = self.registers.get(key) orelse {
            try self.setStatus("register empty");
            return;
        };
        if (before) {
            try self.activeBuffer().insertTextAtCursor(value);
        } else {
            self.activeBuffer().moveRight();
            try self.activeBuffer().insertTextAtCursor(value);
        }
    }

    fn joinCurrentLine(self: *App, with_space: bool) !void {
        const buf = self.activeBuffer();
        if (buf.cursor.row + 1 >= buf.lineCount()) return;
        const current = buf.lines.items[buf.cursor.row];
        const next = buf.lines.items[buf.cursor.row + 1];
        const sep = if (with_space and current.len > 0 and next.len > 0) " " else "";
        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ current, sep, next });
        self.allocator.free(buf.lines.items[buf.cursor.row]);
        self.allocator.free(buf.lines.items[buf.cursor.row + 1]);
        buf.lines.items[buf.cursor.row] = combined;
        _ = buf.lines.orderedRemove(buf.cursor.row + 1);
        buf.dirty = true;
    }

    fn showRegisters(self: *App) !void {
        const summary = try self.registers.formatSummary(self.allocator);
        defer self.allocator.free(summary);
        try self.setStatus(summary);
    }

    fn showReferenceHelp(self: *App) !void {
        try self.setStatus("help: :help keyword | :w | :wq | :q | :q! | :saveas PATH | :close | :terminal | :edit PATH | :open PATH | :bd | :bn | :bp | :buffer N|PATH | :buffers | :split PATH | :sp PATH | :vs PATH | :tabnew | :tabclose | :tabonly | :tabmove N | :vimgrep /pat/ [path] | :grep PAT [path] | :sort [u] | :!cmd | :cn | :cp | :cope | :ccl | :marks | :delmarks! | :zf | :za | :zo | :zc | :zE | :zr | :zm | :zi | :diffthis | :diffoff | :diffupdate | :diffget | :diffput | ]c/[c | () | n/N | * / # | m/'/` | Ctrl+u/d/i/o/^ | Ctrl+w s/v/n/q/x/+/-/</>/\\/|/_/=/T | :registers");
    }

    fn showHelpForCurrentWord(self: *App) !void {
        const word = self.activeBuffer().currentWord();
        if (word.len == 0) {
            try self.setStatus("no word under cursor");
            return;
        }
        if (!self.runInteractiveCommand(&.{ "man", word })) {
            try self.setStatus("man page not available");
        } else {
            try self.setStatus("returned from man");
        }
    }

    fn showMarks(self: *App) !void {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var any = false;
        for (self.marks, 0..) |mark, idx| {
            if (mark) |pos| {
                any = true;
                if (out.items.len > 0) try out.appendSlice(" | ");
                const piece = try std.fmt.allocPrint(self.allocator, "{c}:{d},{d}", .{ @as(u8, @intCast('a' + idx)), pos.row + 1, pos.col + 1 });
                defer self.allocator.free(piece);
                try out.appendSlice(piece);
            }
        }
        if (!any) try out.appendSlice("marks empty");
        const summary = try out.toOwnedSlice();
        defer self.allocator.free(summary);
        try self.setStatus(summary);
    }

    fn showJumps(self: *App) !void {
        try self.setStatus(try self.formatPositionList(&self.jump_history, "jumps empty"));
    }

    fn showChanges(self: *App) !void {
        try self.setStatus(try self.formatPositionList(&self.change_history, "changes empty"));
    }

    fn formatPositionList(self: *App, positions: *const std.array_list.Managed(buffer_mod.Position), empty_text: []const u8) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        if (positions.items.len == 0) {
            try out.appendSlice(empty_text);
            return try out.toOwnedSlice();
        }
        var count: usize = 0;
        var idx: usize = positions.items.len;
        while (idx > 0 and count < 8) : (count += 1) {
            idx -= 1;
            const pos = positions.items[idx];
            if (out.items.len > 0) try out.appendSlice(" | ");
            const piece = try std.fmt.allocPrint(self.allocator, "{d}:{d}", .{ pos.row + 1, pos.col + 1 });
            defer self.allocator.free(piece);
            try out.appendSlice(piece);
        }
        return try out.toOwnedSlice();
    }

    fn recordJump(self: *App, pos: buffer_mod.Position) !void {
        try self.jump_history.append(pos);
        self.jump_history_index = null;
    }

    fn recordChange(self: *App, pos: buffer_mod.Position) !void {
        try self.change_history.append(pos);
        self.change_jump_index = null;
    }

    fn actionIsEditing(action: NormalAction) bool {
        return switch (action) {
            .delete_char, .replace_char, .substitute_char, .substitute_line, .insert_before, .insert_at_bol, .append_after, .append_eol, .open_below, .open_above, .delete_line, .yank_line, .paste_after, .paste_before, .paste_after_keep_cursor, .paste_before_keep_cursor, .delete_word, .yank_word, .delete_to_eol, .change_word, .change_line, .change_to_eol, .join_line_space, .join_line_nospace, .indent_line, .dedent_line, .toggle_case_char, .toggle_case_word, .lowercase_word, .uppercase_word, .diff_get, .diff_put, .visual_yank, .visual_delete => true,
            else => false,
        };
    }

    fn setViewport(self: *App, mode: enum { top, middle, bottom }) void {
        const buf = self.activeBuffer();
        const height = self.last_render_height;
        const line_count = buf.lineCount();
        const cursor_row = buf.cursor.row;
        const target = switch (mode) {
            .top => cursor_row,
            .middle => if (height > 0) cursor_row -| (height / 2) else cursor_row,
            .bottom => if (height > 0) cursor_row -| (height - 1) else cursor_row,
        };
        buf.scroll_row = if (line_count == 0) 0 else @min(target, line_count - 1);
        if (line_count == 0) buf.scroll_row = 0;
    }

    fn startMacroRecording(self: *App, key: u8) !void {
        const idx = macroIndex(key) orelse {
            try self.setStatus("macro register must be a-z");
            return;
        };
        if (self.macros[idx]) |existing| {
            self.allocator.free(existing);
            self.macros[idx] = null;
        }
        self.macro_recording = key;
        self.macro_ignore_next = true;
        try self.setStatus("macro recording");
        self.macros[idx] = try self.allocator.dupe(u8, "");
    }

    fn appendMacroByte(self: *App, byte: u8) !void {
        const key = self.macro_recording orelse return;
        const idx = macroIndex(key) orelse return;
        const current = self.macros[idx] orelse return;
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        try out.appendSlice(current);
        try out.append(byte);
        self.allocator.free(current);
        self.macros[idx] = try out.toOwnedSlice();
    }

    fn runMacro(self: *App, key: u8) anyerror!void {
        const idx = macroIndex(key) orelse {
            try self.setStatus("macro register must be a-z");
            return;
        };
        const seq = self.macros[idx] orelse {
            try self.setStatus("macro empty");
            return;
        };
        self.macro_playing = true;
        defer self.macro_playing = false;
        var i: usize = 0;
        while (i < seq.len) : (i += 1) {
            try self.handleNormalByte(seq[i]);
        }
    }

    fn macroIndex(key: u8) ?usize {
        if (key >= 'a' and key <= 'z') return key - 'a';
        if (key >= 'A' and key <= 'Z') return key - 'A';
        return null;
    }

    fn shiftCurrentLine(self: *App, right: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const start = buffer_mod.Position{ .row = buf.cursor.row, .col = 0 };
        const end = buffer_mod.Position{ .row = buf.cursor.row, .col = line.len };
        const width = self.config.tab_width * count;
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        if (right) {
            try out.appendNTimes(' ', width);
            try out.appendSlice(line);
        } else {
            var trim = line;
            var removed: usize = 0;
            while (removed < width and trim.len > 0 and trim[0] == ' ') : (removed += 1) {
                trim = trim[1..];
            }
            try out.appendSlice(trim);
        }
        try buf.replaceRangeWithText(start, end, try out.toOwnedSlice());
    }

    const CaseMode = enum { toggle, lower, upper };

    fn transformCurrentWord(self: *App, mode: CaseMode) !void {
        const buf = self.activeBuffer();
        const bounds = buf.wordBounds() orelse return;
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const word = try self.allocator.dupe(u8, text[self.positionToOffset(bounds.start, text)..self.positionToOffset(bounds.end, text)]);
        defer self.allocator.free(word);
        for (word) |*ch| {
            ch.* = switch (mode) {
                .toggle => toggleAsciiCase(ch.*),
                .lower => std.ascii.toLower(ch.*),
                .upper => std.ascii.toUpper(ch.*),
            };
        }
        try buf.replaceRangeWithText(bounds.start, bounds.end, word);
    }

    fn toggleCurrentCharacter(self: *App) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (buf.cursor.col >= line.len) return;
        var ch = line[buf.cursor.col];
        ch = toggleAsciiCase(ch);
        try buf.replaceCurrentCharacter(ch);
    }

    fn applyVisualIndent(self: *App, right: bool) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        const slice = text[start..end];
        const transformed = try self.indentBlock(slice, right);
        defer self.allocator.free(transformed);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, transformed);
        self.exitVisual();
    }

    fn applyVisualCase(self: *App, mode: CaseMode) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        const piece = try self.allocator.dupe(u8, text[start..end]);
        defer self.allocator.free(piece);
        for (piece) |*ch| {
            ch.* = switch (mode) {
                .toggle => toggleAsciiCase(ch.*),
                .lower => std.ascii.toLower(ch.*),
                .upper => std.ascii.toUpper(ch.*),
            };
        }
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, piece);
        self.exitVisual();
    }

    fn indentBlock(self: *App, slice: []const u8, right: bool) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var lines = std.mem.splitScalar(u8, slice, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (!first) try out.append('\n');
            first = false;
            if (right) {
                try out.appendNTimes(' ', self.config.tab_width);
                try out.appendSlice(line);
            } else {
                var trimmed = line;
                var removed: usize = 0;
                while (removed < self.config.tab_width and trimmed.len > 0 and trimmed[0] == ' ') : (removed += 1) {
                    trimmed = trimmed[1..];
                }
                try out.appendSlice(trimmed);
            }
        }
        return try out.toOwnedSlice();
    }

    fn toggleAsciiCase(byte: u8) u8 {
        if (std.ascii.isUpper(byte)) return std.ascii.toLower(byte);
        if (std.ascii.isLower(byte)) return std.ascii.toUpper(byte);
        return byte;
    }

    fn closeCurrentPane(self: *App) !void {
        if (self.activeBuffer().dirty) {
            try self.setStatus("buffer modified, save first or use :q!");
            return;
        }
        self.disableDiffMode();
        if (self.split_index) |idx| {
            if (self.split_focus == .right) {
                self.buffers.items[idx].deinit();
                _ = self.buffers.orderedRemove(idx);
            } else {
                self.buffers.items[self.active_index].deinit();
                _ = self.buffers.orderedRemove(self.active_index);
            }
            self.split_index = null;
            self.split_focus = .left;
            if (self.buffers.items.len == 0) {
                try self.buffers.append(try buffer_mod.Buffer.initEmpty(self.allocator));
            }
            self.active_index = 0;
            try self.setStatus("pane closed");
            return;
        }
        if (self.buffers.items.len > 1) {
            self.buffers.items[self.active_index].deinit();
            _ = self.buffers.orderedRemove(self.active_index);
        } else {
            self.buffers.items[0].deinit();
            self.buffers.items[0] = try buffer_mod.Buffer.initEmpty(self.allocator);
        }
        self.active_index = 0;
        try self.setStatus("buffer closed");
    }

    fn focusedBufferIndex(self: *const App) usize {
        if (self.split_index) |idx| {
            return switch (self.split_focus) {
                .left => self.active_index,
                .right => idx,
            };
        }
        return self.active_index;
    }

    fn focusBufferIndex(self: *App, index: usize) void {
        const current = self.focusedBufferIndex();
        if (current != index) self.previous_active_index = current;
        if (self.split_index != null and self.split_focus == .right) {
            self.split_index = index;
        } else {
            self.active_index = index;
        }
    }

    fn switchFocusedBuffer(self: *App, forward: bool, count: usize) !void {
        if (self.buffers.items.len <= 1) return;
        var index = self.focusedBufferIndex();
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            index = if (forward)
                (index + 1) % self.buffers.items.len
            else
                (index + self.buffers.items.len - 1) % self.buffers.items.len;
        }
        self.focusBufferIndex(index);
    }

    fn openNewTab(self: *App, path: ?[]const u8) !void {
        if (path) |actual| {
            try self.openPath(actual);
            return;
        }
        self.disableDiffMode();
        const buf = try buffer_mod.Buffer.initEmpty(self.allocator);
        try self.buffers.append(buf);
        self.focusBufferIndex(self.buffers.items.len - 1);
        self.plugin_host.broadcastEvent("buffer_open", "{}");
    }

    fn cloneActiveBuffer(self: *App) !buffer_mod.Buffer {
        const src = self.activeBuffer();
        var clone = try buffer_mod.Buffer.initEmpty(self.allocator);
        errdefer clone.deinit();
        const text = try src.serialize();
        defer self.allocator.free(text);
        try clone.setText(text);
        if (src.path) |path| try clone.replacePath(path);
        clone.cursor = src.cursor;
        clone.scroll_row = src.scroll_row;
        clone.dirty = src.dirty;
        clone.fold_enabled = src.fold_enabled;
        for (src.folds.items) |fold| {
            try clone.folds.append(fold);
        }
        return clone;
    }

    fn openSplitFromCurrentBuffer(self: *App) !void {
        self.disableDiffMode();
        const clone = try self.cloneActiveBuffer();
        if (self.split_index) |idx| {
            self.buffers.items[idx].deinit();
            self.buffers.items[idx] = clone;
        } else {
            try self.buffers.append(clone);
            self.split_index = self.buffers.items.len - 1;
        }
        self.split_focus = .right;
        self.plugin_host.broadcastEvent("buffer_open", "{}");
    }

    fn openNewWindow(self: *App) !void {
        self.disableDiffMode();
        const buf = try buffer_mod.Buffer.initEmpty(self.allocator);
        if (self.split_index) |idx| {
            self.buffers.items[idx].deinit();
            self.buffers.items[idx] = buf;
        } else {
            try self.buffers.append(buf);
            self.split_index = self.buffers.items.len - 1;
        }
        self.split_focus = .right;
        self.plugin_host.broadcastEvent("buffer_open", "{}");
        try self.setStatus("new window");
    }

    fn splitToTab(self: *App) !void {
        if (self.split_index == null) {
            try self.setStatus("no split to move");
            return;
        }
        self.disableDiffMode();
        const clone = try self.cloneActiveBuffer();
        try self.buffers.append(clone);
        self.split_index = null;
        self.split_focus = .left;
        self.active_index = self.buffers.items.len - 1;
        self.plugin_host.broadcastEvent("buffer_open", "{}");
        try self.setStatus("split moved to tab");
    }

    fn openSplitOrClone(self: *App, path: []const u8) !void {
        if (path.len == 0) {
            try self.openSplitFromCurrentBuffer();
        } else {
            try self.openSplit(path);
        }
    }

    fn focusWindow(self: *App, side: SplitFocus) void {
        if (self.split_index == null) return;
        self.split_focus = side;
    }

    fn exchangeFocusedBuffers(self: *App) !void {
        const other_index = self.split_index orelse {
            try self.setStatus("no other window");
            return;
        };
        self.disableDiffMode();
        const current_index = self.focusedBufferIndex();
        if (current_index == other_index) return;
        std.mem.swap(buffer_mod.Buffer, &self.buffers.items[current_index], &self.buffers.items[other_index]);
        if (self.active_index == current_index) {
            self.active_index = other_index;
        } else if (self.active_index == other_index) {
            self.active_index = current_index;
        }
        if (self.split_index) |*idx| {
            if (idx.* == current_index) {
                idx.* = other_index;
            } else if (idx.* == other_index) {
                idx.* = current_index;
            }
        }
        try self.setStatus("windows exchanged");
    }

    fn selectBufferByArgument(self: *App, arg: []const u8) !void {
        const parsed = std.fmt.parseInt(usize, arg, 10) catch null;
        if (parsed) |num| {
            if (num == 0 or num > self.buffers.items.len) {
                try self.setStatus("buffer index out of range");
                return;
            }
            self.focusBufferIndex(num - 1);
            return;
        }
        for (self.buffers.items, 0..) |buf, idx| {
            if (buf.path) |path| {
                if (std.mem.eql(u8, path, arg)) {
                    self.focusBufferIndex(idx);
                    return;
                }
            }
        }
        try self.setStatus("buffer not found");
    }

    fn showBuffers(self: *App) !void {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        for (self.buffers.items, 0..) |buf, idx| {
            if (idx > 0) try out.appendSlice(" | ");
            if (idx == self.active_index or (self.split_index != null and self.split_index.? == idx and self.split_focus == .right)) {
                try out.appendSlice("*");
            } else {
                try out.appendSlice(" ");
            }
            const name = buf.path orelse "[No Name]";
            const piece = try std.fmt.allocPrint(self.allocator, "{d}:{s}", .{ idx + 1, name });
            defer self.allocator.free(piece);
            try out.appendSlice(piece);
        }
        if (self.buffers.items.len == 0) try out.appendSlice("buffers empty");
        const summary = try out.toOwnedSlice();
        defer self.allocator.free(summary);
        try self.setStatus(summary);
    }

    fn enableDiffMode(self: *App) !void {
        if (self.buffers.items.len <= 1) {
            try self.setStatus("no diff peer available");
            return;
        }
        const current = self.focusedBufferIndex();
        const fallback: usize = if (current == 0) 1 else 0;
        const peer: usize = if (self.split_index) |idx| if (idx != current) idx else fallback else fallback;
        if (peer >= self.buffers.items.len or peer == current) {
            try self.setStatus("no diff peer available");
            return;
        }
        self.diff_mode = true;
        self.diff_peer_index = peer;
        try self.updateDiffSummary();
    }

    fn disableDiffMode(self: *App) void {
        self.diff_mode = false;
        self.diff_peer_index = null;
    }

    fn diffPeerBuffer(self: *App) ?*buffer_mod.Buffer {
        const idx = self.diff_peer_index orelse return null;
        if (idx >= self.buffers.items.len) return null;
        return &self.buffers.items[idx];
    }

    fn updateDiffSummary(self: *App) !void {
        const peer = self.diffPeerBuffer() orelse {
            try self.setStatus("diff off");
            return;
        };
        const active = self.activeBuffer();
        const msg = try std.fmt.allocPrint(self.allocator, "diff on with {d} vs {d} lines", .{ active.lineCount(), peer.lineCount() });
        defer self.allocator.free(msg);
        try self.setStatus(msg);
    }

    fn diffGet(self: *App) !void {
        const peer = self.diffPeerBuffer() orelse {
            try self.setStatus("no diff peer");
            return;
        };
        const row = self.activeBuffer().cursor.row;
        if (row >= peer.lineCount()) {
            try self.setStatus("no corresponding line");
            return;
        }
        const text = peer.lines.items[row];
        try self.activeBuffer().replaceLine(row, text);
        try self.setStatus("diff got");
    }

    fn diffPut(self: *App) !void {
        const peer = self.diffPeerBuffer() orelse {
            try self.setStatus("no diff peer");
            return;
        };
        const row = self.activeBuffer().cursor.row;
        if (row >= peer.lineCount()) {
            try self.setStatus("no corresponding line");
            return;
        }
        const text = self.activeBuffer().lines.items[row];
        try peer.replaceLine(row, text);
        try self.setStatus("diff put");
    }

    fn jumpChangeHistory(self: *App, forward: bool) !void {
        if (self.change_history.items.len == 0) {
            try self.setStatus("changes empty");
            return;
        }
        const len = self.change_history.items.len;
        var index = self.change_jump_index orelse if (forward) len - 1 else 0;
        if (forward) {
            index = (index + 1) % len;
        } else if (index == 0) {
            index = len - 1;
        } else {
            index -= 1;
        }
        self.change_jump_index = index;
        const pos = self.change_history.items[index];
        self.activeBuffer().cursor = pos;
    }

    fn jumpHistory(self: *App, forward: bool, count: usize) !void {
        if (self.jump_history.items.len == 0) {
            try self.setStatus("jumps empty");
            return;
        }
        const len = self.jump_history.items.len;
        var index = self.jump_history_index orelse if (forward) len - 1 else 0;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (forward) {
                index = @min(index + 1, len - 1);
            } else if (index == 0) {
                index = 0;
            } else {
                index -= 1;
            }
        }
        self.jump_history_index = index;
        self.activeBuffer().cursor = self.jump_history.items[index];
    }

    fn togglePreviousBuffer(self: *App) void {
        const prev = self.previous_active_index orelse return;
        const current = self.focusedBufferIndex();
        if (prev >= self.buffers.items.len or prev == current) return;
        self.focusBufferIndex(prev);
        self.previous_active_index = current;
    }

    fn moveSentence(self: *App, forward: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        var offset = self.positionToOffset(buf.cursor, text);
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            offset = self.nextSentenceOffset(text, offset, forward) orelse if (forward) text.len else 0;
        }
        buf.cursor = self.offsetToPosition(text, offset);
    }

    fn nextSentenceOffset(self: *App, text: []const u8, offset: usize, forward: bool) ?usize {
        _ = self;
        if (text.len == 0) return null;
        if (forward) {
            var idx = @min(offset + 1, text.len);
            while (idx < text.len) : (idx += 1) {
                if (text[idx] == '.' or text[idx] == '!' or text[idx] == '?') {
                    var next = idx + 1;
                    while (next < text.len and std.ascii.isWhitespace(text[next])) : (next += 1) {}
                    return next;
                }
            }
            return null;
        }
        if (offset == 0) return 0;
        var idx = offset - 1;
        while (true) {
            if (text[idx] == '.' or text[idx] == '!' or text[idx] == '?') {
                var start = idx;
                while (start > 0 and std.ascii.isWhitespace(text[start - 1])) : (start -= 1) {}
                while (start > 0 and text[start - 1] != '.' and text[start - 1] != '!' and text[start - 1] != '?') : (start -= 1) {}
                while (start < text.len and std.ascii.isWhitespace(text[start])) : (start += 1) {}
                return start;
            }
            if (idx == 0) break;
            idx -= 1;
        }
        return null;
    }

    fn scrollViewport(self: *App, down: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const step = @max(@as(usize, 1), self.last_render_height / 2);
        const amount = step * count;
        const max_scroll = if (buf.lineCount() > 0) buf.lineCount() - 1 else 0;
        if (down) {
            buf.scroll_row = @min(buf.scroll_row +| amount, max_scroll);
        } else {
            buf.scroll_row = buf.scroll_row -| amount;
        }
    }

    fn setMark(self: *App, mark: u8) !void {
        const idx = markIndex(mark) orelse {
            try self.setStatus("mark must be a-z or A-Z");
            return;
        };
        self.marks[idx] = self.activeBuffer().cursor;
        try self.setStatus("mark set");
    }

    fn jumpMark(self: *App, mark: u8, exact: bool) !void {
        const idx = markIndex(mark) orelse {
            try self.setStatus("mark must be a-z or A-Z");
            return;
        };
        const pos = self.marks[idx] orelse {
            try self.setStatus("mark not set");
            return;
        };
        self.activeBuffer().cursor = if (exact) pos else .{ .row = pos.row, .col = 0 };
    }

    fn markIndex(mark: u8) ?usize {
        if (mark >= 'a' and mark <= 'z') return mark - 'a';
        if (mark >= 'A' and mark <= 'Z') return mark - 'A';
        return null;
    }

    fn searchWordUnderCursor(self: *App, forward: bool) !void {
        const buf = self.activeBuffer();
        const bounds = buf.wordBounds() orelse {
            try self.setStatus("no word under cursor");
            return;
        };
        const word = try self.selectedText(bounds.start, bounds.end);
        defer self.allocator.free(word);
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = if (forward)
            self.positionToOffset(bounds.end, text)
        else
            self.positionToOffset(bounds.start, text);
        const found = if (forward)
            findWordOccurrence(text, word, cursor_offset, true)
        else
            findWordOccurrence(text, word, cursor_offset, false);
        if (found) |offset| {
            try self.updateSearchHighlight(&self.search_highlight, word);
            buf.cursor = self.offsetToPosition(text, offset);
        } else {
            try self.setStatus("word not found");
        }
    }

    fn repeatSearch(self: *App, forward: bool) !void {
        const needle = self.activeSearchHighlight(true) orelse {
            try self.setStatus("no search term");
            return;
        };
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const found = findSubstringOccurrence(text, needle, cursor_offset, forward);
        if (found) |offset| {
            buf.cursor = self.offsetToPosition(text, offset);
        } else {
            try self.setStatus("not found");
        }
    }

    fn openCursorPath(self: *App, link: bool) !void {
        const token = self.pathTokenUnderCursor(link);
        if (token.len == 0) {
            try self.setStatus("no path under cursor");
            return;
        }
        if (link and (std.mem.startsWith(u8, token, "http://") or std.mem.startsWith(u8, token, "https://"))) {
            if (!self.openExternalLink(token)) {
                try self.setStatus("link opener unavailable");
            } else {
                try self.setStatus("opened link");
            }
            return;
        }
        try self.openPath(token);
        try self.maybeDrainPluginActions();
    }

    fn pathTokenUnderCursor(self: *App, allow_url: bool) []const u8 {
        const line = self.activeBuffer().currentLine();
        if (line.len == 0) return line;
        const cursor = @min(self.activeBuffer().cursor.col, line.len);
        const is_path_char = struct {
            fn f(byte: u8, url: bool) bool {
                return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == '.' or byte == '/' or byte == '~' or byte == ':' or byte == '?' or byte == '#' or byte == '=' or byte == '&' or byte == '%' or byte == '+' or byte == '@' or (url and byte == ':');
            }
        }.f;
        var start = cursor;
        if (start == line.len and start > 0) start -= 1;
        while (start > 0 and is_path_char(line[start - 1], allow_url)) : (start -= 1) {}
        var end = cursor;
        while (end < line.len and is_path_char(line[end], allow_url)) : (end += 1) {}
        return line[start..end];
    }

    fn openExternalLink(self: *App, url: []const u8) bool {
        const argv = switch (builtin.os.tag) {
            .windows => &[_][]const u8{ "cmd.exe", "/C", "start", "", url },
            .macos => &[_][]const u8{ "open", url },
            else => &[_][]const u8{ "xdg-open", url },
        };
        return self.runInteractiveCommand(argv);
    }

    const SubstituteSpec = struct {
        pattern: []u8,
        replacement: []u8,
        global: bool,

        fn deinit(self: *const SubstituteSpec, allocator: std.mem.Allocator) void {
            allocator.free(self.pattern);
            allocator.free(self.replacement);
        }
    };

    fn tryExecuteSubstitute(self: *App, command: []const u8, has_visual_range: bool) !bool {
        const spec = if (command.len > 0 and command[0] == '%')
            self.parseSubstituteSpec(command[1..]) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return false,
            }
        else if (command.len > 0 and command[0] == 's')
            self.parseSubstituteSpec(command) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return false,
            }
        else
            return false;

        if (spec == null) return false;
        defer spec.?.deinit(self.allocator);

        if (spec.?.pattern.len == 0) {
            try self.setStatus("substitute requires a pattern");
            return true;
        }

        if (command[0] == '%') {
            try self.substituteWholeDocument(spec.?);
        } else if (has_visual_range) {
            try self.substituteVisualSelection(spec.?);
        } else {
            try self.substituteCurrentLine(spec.?);
        }
        return true;
    }

    fn parseSubstituteSpec(self: *App, command: []const u8) !?SubstituteSpec {
        if (command.len < 3 or command[0] != 's') return null;
        const delim = command[1];
        const pattern_end = self.findSubstituteSegmentEnd(command, 2, delim) orelse return null;
        const replacement_start = pattern_end + 1;
        const replacement_end = self.findSubstituteSegmentEnd(command, replacement_start, delim) orelse return null;
        const flags = if (replacement_end + 1 < command.len) command[replacement_end + 1 ..] else "";
        return .{
            .pattern = try self.unescapeSubstituteSegment(command[2..pattern_end], delim),
            .replacement = try self.unescapeSubstituteSegment(command[replacement_start..replacement_end], delim),
            .global = std.mem.indexOfScalar(u8, flags, 'g') != null,
        };
    }

    fn findSubstituteSegmentEnd(self: *App, command: []const u8, start: usize, delim: u8) ?usize {
        _ = self;
        var idx = start;
        while (idx < command.len) : (idx += 1) {
            if (command[idx] == delim and (idx == start or command[idx - 1] != '\\')) return idx;
        }
        return null;
    }

    fn unescapeSubstituteSegment(self: *App, segment: []const u8, delim: u8) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var idx: usize = 0;
        while (idx < segment.len) {
            if (segment[idx] == '\\' and idx + 1 < segment.len and (segment[idx + 1] == delim or segment[idx + 1] == '\\')) {
                try out.append(segment[idx + 1]);
                idx += 2;
                continue;
            }
            try out.append(segment[idx]);
            idx += 1;
        }
        return try out.toOwnedSlice();
    }

    fn substituteWholeDocument(self: *App, spec: SubstituteSpec) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const replaced = try self.substituteText(text, spec);
        defer self.allocator.free(replaced);
        const end_row = buf.lines.items.len - 1;
        try buf.replaceRangeWithText(.{ .row = 0, .col = 0 }, .{ .row = end_row, .col = buf.lines.items[end_row].len }, replaced);
        try self.setStatus("substituted");
    }

    fn substituteCurrentLine(self: *App, spec: SubstituteSpec) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const replaced = try self.substituteText(line, spec);
        defer self.allocator.free(replaced);
        const row = buf.cursor.row;
        try buf.replaceRangeWithText(.{ .row = row, .col = 0 }, .{ .row = row, .col = line.len }, replaced);
        try self.setStatus("substituted");
    }

    fn substituteVisualSelection(self: *App, spec: SubstituteSpec) !void {
        const selection = self.visualSelection() orelse {
            try self.setStatus("no selection");
            return;
        };
        const input = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(input);
        const replaced = try self.substituteText(input, spec);
        defer self.allocator.free(replaced);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, replaced);
        self.exitVisual();
        try self.setStatus("substituted");
    }

    fn substituteText(self: *App, input: []const u8, spec: SubstituteSpec) ![]u8 {
        if (spec.pattern.len == 0) return try self.allocator.dupe(u8, input);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var changed: usize = 0;
        var lines = std.mem.splitScalar(u8, input, '\n');
        var first_line = true;
        while (lines.next()) |line| {
            if (!first_line) try out.append('\n');
            first_line = false;
            const replaced = try self.replaceLiteralInLine(line, spec.pattern, spec.replacement, spec.global, &changed);
            defer self.allocator.free(replaced);
            try out.appendSlice(replaced);
        }
        if (changed == 0) return try self.allocator.dupe(u8, input);
        return try out.toOwnedSlice();
    }

    fn replaceLiteralInLine(self: *App, line: []const u8, needle: []const u8, replacement: []const u8, global: bool, changed: *usize) ![]u8 {
        if (needle.len == 0) return try self.allocator.dupe(u8, line);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var idx: usize = 0;
        var replaced_once = false;
        while (idx <= line.len) {
            const hit = std.mem.indexOfPos(u8, line, idx, needle) orelse break;
            try out.appendSlice(line[idx..hit]);
            try out.appendSlice(replacement);
            changed.* += 1;
            idx = hit + needle.len;
            replaced_once = true;
            if (!global) break;
        }
        if (!replaced_once) return try self.allocator.dupe(u8, line);
        try out.appendSlice(line[idx..]);
        return try out.toOwnedSlice();
    }

    fn deleteInsertPreviousWord(self: *App) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const end = self.positionToOffset(buf.cursor, text);
        var start = end;
        while (start > 0 and std.ascii.isWhitespace(text[start - 1])) : (start -= 1) {}
        while (start > 0 and !std.ascii.isWhitespace(text[start - 1])) : (start -= 1) {}
        if (start == end) return;
        const start_pos = self.offsetToPosition(text, start);
        try buf.replaceRangeWithText(start_pos, buf.cursor, "");
    }

    fn findSubstringOccurrence(text: []const u8, needle: []const u8, start_offset: usize, forward: bool) ?usize {
        if (needle.len == 0 or text.len < needle.len) return null;
        if (forward) {
            var idx = @min(start_offset + 1, text.len);
            while (idx + needle.len <= text.len) : (idx += 1) {
                if (std.mem.eql(u8, text[idx .. idx + needle.len], needle)) return idx;
            }
            return null;
        }
        var idx = @min(start_offset, text.len);
        while (idx > 0) : (idx -= 1) {
            if (idx >= needle.len and std.mem.eql(u8, text[idx - needle.len .. idx], needle)) return idx - needle.len;
        }
        return null;
    }

    fn repeatLastCommand(self: *App) anyerror!void {
        const action = self.last_normal_action orelse {
            try self.setStatus("no repeatable command");
            return;
        };
        try self.performNormalAction(action, self.last_normal_count);
    }

    fn createFoldAtCursor(self: *App) !void {
        try self.activeBuffer().createParagraphFold();
        try self.setStatus("fold created");
    }

    fn deleteFoldAtCursor(self: *App) void {
        if (self.activeBuffer().deleteFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold deleted") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn toggleFoldAtCursor(self: *App) void {
        if (self.activeBuffer().toggleFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold toggled") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn openFoldAtCursor(self: *App) void {
        if (self.activeBuffer().openFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold opened") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn closeFoldAtCursor(self: *App) void {
        if (self.activeBuffer().closeFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold closed") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn clearQuickfix(self: *App) void {
        for (self.quickfix_list.items) |entry| {
            self.allocator.free(entry.path);
            self.allocator.free(entry.line);
        }
        self.quickfix_list.clearRetainingCapacity();
        self.quickfix_index = 0;
    }

    fn showQuickfix(self: *App) !void {
        if (self.quickfix_list.items.len == 0) {
            try self.setStatus("quickfix empty");
            return;
        }
        const entry = self.quickfix_list.items[@min(self.quickfix_index, self.quickfix_list.items.len - 1)];
        const msg = try std.fmt.allocPrint(self.allocator, "{d}/{d} {s}:{d}:{d} {s}", .{
            @min(self.quickfix_index + 1, self.quickfix_list.items.len),
            self.quickfix_list.items.len,
            entry.path,
            entry.position.row + 1,
            entry.position.col + 1,
            entry.line,
        });
        defer self.allocator.free(msg);
        try self.setStatus(msg);
    }

    fn quickfixNext(self: *App) !void {
        if (self.quickfix_list.items.len == 0) {
            try self.setStatus("quickfix empty");
            return;
        }
        self.quickfix_index = (self.quickfix_index + 1) % self.quickfix_list.items.len;
        try self.openQuickfixEntry(self.quickfix_list.items[self.quickfix_index]);
    }

    fn quickfixPrev(self: *App) !void {
        if (self.quickfix_list.items.len == 0) {
            try self.setStatus("quickfix empty");
            return;
        }
        if (self.quickfix_index == 0) {
            self.quickfix_index = self.quickfix_list.items.len - 1;
        } else {
            self.quickfix_index -= 1;
        }
        try self.openQuickfixEntry(self.quickfix_list.items[self.quickfix_index]);
    }

    fn openQuickfixEntry(self: *App, entry: QuickfixEntry) !void {
        try self.openOrFocusPath(entry.path);
        const buf = self.activeBuffer();
        buf.cursor = entry.position;
        try self.setStatus("quickfix jump");
    }

    fn openOrFocusPath(self: *App, path: []const u8) !void {
        for (self.buffers.items, 0..) |buf, idx| {
            if (buf.path) |current| {
                if (std.mem.eql(u8, current, path)) {
                    self.focusBufferIndex(idx);
                    return;
                }
            }
        }
        try self.openPath(path);
    }

    fn runQuickfixSearch(self: *App, tail: []const u8) !void {
        const spec = std.mem.trim(u8, tail, " \t");
        const parsed = parseQuickfixSpec(spec) orelse {
            try self.setStatus("use :vimgrep /pattern/ [path]");
            return;
        };
        self.clearQuickfix();
        try self.collectQuickfixMatches(parsed.pattern, parsed.pathspec);
        if (self.quickfix_list.items.len == 0) {
            try self.setStatus("no matches");
            return;
        }
        self.quickfix_index = 0;
        try self.showQuickfix();
    }

    fn runProjectSearch(self: *App, tail: []const u8) !void {
        const spec = std.mem.trim(u8, tail, " \t");
        if (spec.len == 0) {
            try self.setStatus("grep requires a pattern");
            return;
        }
        const split = std.mem.indexOfScalar(u8, spec, ' ');
        const pattern = if (split) |idx| spec[0..idx] else spec;
        const pathspec = if (split) |idx| std.mem.trim(u8, spec[idx + 1 ..], " \t") else "";
        self.clearQuickfix();
        try self.collectQuickfixMatches(pattern, pathspec);
        if (self.quickfix_list.items.len == 0) {
            try self.setStatus("no matches");
            return;
        }
        self.quickfix_index = 0;
        try self.showQuickfix();
    }

    fn sortCurrentBuffer(self: *App, tail: []const u8) !void {
        const unique = std.mem.containsAtLeast(u8, tail, 1, "u");
        const buf = self.activeBuffer();
        if (buf.lines.items.len == 0) return;
        var lines = std.array_list.Managed([]u8).init(self.allocator);
        defer lines.deinit();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            try lines.append(try self.allocator.dupe(u8, line));
        }
        const Cmp = struct {
            fn lessThan(_: void, a: []u8, b: []u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        };
        std.mem.sort([]u8, lines.items, {}, Cmp.lessThan);
        if (unique and lines.items.len > 1) {
            var write_idx: usize = 1;
            var read_idx: usize = 1;
            while (read_idx < lines.items.len) : (read_idx += 1) {
                if (!std.mem.eql(u8, lines.items[read_idx], lines.items[write_idx - 1])) {
                    lines.items[write_idx] = lines.items[read_idx];
                    write_idx += 1;
                } else {
                    self.allocator.free(lines.items[read_idx]);
                }
            }
            lines.items.len = write_idx;
        }
        defer {
            for (lines.items) |line| self.allocator.free(line);
        }
        var out = std.array_list.Managed(u8).init(self.allocator);
        defer out.deinit();
        for (lines.items, 0..) |line, idx| {
            if (idx > 0) try out.append('\n');
            try out.appendSlice(line);
        }
        const sorted = try out.toOwnedSlice();
        defer self.allocator.free(sorted);
        try buf.setText(sorted);
        try self.setStatus("sorted");
    }

    fn runBangCommand(self: *App, tail: []const u8) !void {
        const cmd = std.mem.trim(u8, tail, " \t");
        if (cmd.len == 0) {
            try self.setStatus("bang command requires a shell command");
            return;
        }
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const path = buf.path orelse "";
        var command = std.array_list.Managed(u8).init(self.allocator);
        defer command.deinit();
        var idx: usize = 0;
        while (idx < cmd.len) {
            if (cmd[idx] == '%' and idx + 1 <= cmd.len) {
                try command.appendSlice(path);
                idx += 1;
                continue;
            }
            try command.append(cmd[idx]);
            idx += 1;
        }
        const output = try self.runCommandWithInput(command.items, text);
        defer self.allocator.free(output);
        const summary = trimTrailingNewline(output);
        if (summary.len == 0) {
            try self.setStatus("command complete");
        } else {
            try self.setStatus(summary);
        }
    }

    const QuickfixSpec = struct {
        pattern: []const u8,
        pathspec: []const u8,
    };

    fn parseQuickfixSpec(spec: []const u8) ?QuickfixSpec {
        if (spec.len == 0 or spec[0] != '/') return null;
        const end = std.mem.indexOfScalarPos(u8, spec, 1, '/') orelse return null;
        const pattern = spec[1..end];
        const pathspec = std.mem.trim(u8, spec[end + 1 ..], " \t");
        return .{ .pattern = pattern, .pathspec = pathspec };
    }

    fn collectQuickfixMatches(self: *App, pattern: []const u8, pathspec: []const u8) !void {
        var walker = try std.fs.cwd().walk(self.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (pathspec.len > 0 and !quickfixPathMatches(entry.path, pathspec)) continue;
            const text = std.fs.cwd().readFileAlloc(self.allocator, entry.path, 1 << 20) catch continue;
            defer self.allocator.free(text);
            var row: usize = 0;
            var start: usize = 0;
            while (start <= text.len) {
                const rel_end = std.mem.indexOfScalar(u8, text[start..], '\n');
                const end = if (rel_end) |idx| start + idx else text.len;
                const line = text[start..end];
                var search: usize = 0;
                while (search <= line.len) {
                    const hit = std.mem.indexOfPos(u8, line, search, pattern) orelse break;
                    try self.appendQuickfixMatch(entry.path, row, hit, line);
                    search = hit + @max(1, pattern.len);
                }
                if (end >= text.len) break;
                start = end + 1;
                row += 1;
            }
        }
    }

    fn appendQuickfixMatch(self: *App, path: []const u8, row: usize, col: usize, line: []const u8) !void {
        try self.quickfix_list.append(.{
            .path = try self.allocator.dupe(u8, path),
            .position = .{ .row = row, .col = col },
            .line = try self.allocator.dupe(u8, line),
        });
    }

    fn quickfixPathMatches(path: []const u8, spec: []const u8) bool {
        if (std.mem.eql(u8, spec, ".") or std.mem.eql(u8, spec, "**/*") or std.mem.eql(u8, spec, "*")) return true;
        const cleaned = std.mem.trim(u8, spec, " \t");
        if (cleaned.len == 0) return true;
        if (std.mem.indexOf(u8, cleaned, "*") != null) {
            const prefix = std.mem.trimRight(u8, cleaned, "*");
            return std.mem.startsWith(u8, path, prefix);
        }
        return std.mem.indexOf(u8, path, cleaned) != null;
    }

    fn tabCloseCurrent(self: *App) !void {
        try self.closeCurrentPane();
    }

    fn tabOnlyCurrent(self: *App) !void {
        if (self.activeBuffer().dirty) {
            try self.setStatus("buffer modified, save first or use :q!");
            return;
        }
        self.disableDiffMode();
        const keep_index = self.focusedBufferIndex();
        var idx = self.buffers.items.len;
        while (idx > 0) : (idx -= 1) {
            const remove_index = idx - 1;
            if (remove_index == keep_index) continue;
            self.buffers.items[remove_index].deinit();
            _ = self.buffers.orderedRemove(remove_index);
        }
        self.split_index = null;
        self.split_focus = .left;
        self.active_index = 0;
        try self.setStatus("tab only");
    }

    fn tabMoveCurrent(self: *App, target_text: []const u8) !void {
        const parsed = std.fmt.parseInt(usize, target_text, 10) catch {
            try self.setStatus("tabmove requires a number");
            return;
        };
        if (self.buffers.items.len <= 1) return;
        self.disableDiffMode();
        const current = self.focusedBufferIndex();
        const target = @min(parsed, self.buffers.items.len - 1);
        if (current == target) {
            try self.setStatus("tab moved");
            return;
        }
        const item = self.buffers.items[current];
        if (current < target) {
            std.mem.copyForwards(buffer_mod.Buffer, self.buffers.items[current..target], self.buffers.items[current + 1 .. target + 1]);
        } else {
            std.mem.copyBackwards(buffer_mod.Buffer, self.buffers.items[target + 1 .. current + 1], self.buffers.items[target..current]);
        }
        self.buffers.items[target] = item;

        if (self.active_index == current) self.active_index = target;
        if (self.split_index) |*idx| {
            if (idx.* == current) {
                idx.* = target;
            } else if (current < target and idx.* > current and idx.* <= target) {
                idx.* -= 1;
            } else if (current > target and idx.* >= target and idx.* < current) {
                idx.* += 1;
            }
        }
        try self.setStatus("tab moved");
    }

    fn helpForKeyword(self: *App, keyword: []const u8) !void {
        const stripped = if (keyword.len > 0 and keyword[0] == ':') keyword[1..] else keyword;
        if (stripped.len == 0) {
            try self.setStatus("help: use :help keyword");
            return;
        }
        if (normalActionHelp(stripped)) |doc| {
            try self.setStatus(doc);
            return;
        }
        if (std.mem.eql(u8, stripped, "w") or std.mem.eql(u8, stripped, "save")) {
            try self.setStatus("write the current buffer");
            return;
        }
        if (std.mem.eql(u8, stripped, "saveas") or std.mem.eql(u8, stripped, "sav")) {
            try self.setStatus("save the current buffer under a new path");
            return;
        }
        if (std.mem.eql(u8, stripped, "close") or std.mem.eql(u8, stripped, "clo")) {
            try self.setStatus("close the current pane");
            return;
        }
        if (std.mem.eql(u8, stripped, "terminal") or std.mem.eql(u8, stripped, "ter")) {
            try self.setStatus("open a terminal pane");
            return;
        }
        if (std.mem.eql(u8, stripped, "registers") or std.mem.eql(u8, stripped, "reg")) {
            try self.setStatus("show register contents");
            return;
        }
        if (std.mem.eql(u8, stripped, "open")) {
            try self.setStatus("open a path in a new buffer");
            return;
        }
        if (std.mem.eql(u8, stripped, "split")) {
            try self.setStatus("open a path in a split pane");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabnew")) {
            try self.setStatus("open a path in a new tab");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabclose") or std.mem.eql(u8, stripped, "tabc")) {
            try self.setStatus("close the current tab");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabonly") or std.mem.eql(u8, stripped, "tabo")) {
            try self.setStatus("keep only the current tab");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabmove")) {
            try self.setStatus("move the current tab to a new index");
            return;
        }
        if (std.mem.eql(u8, stripped, "marks")) {
            try self.setStatus("list marks");
            return;
        }
        if (std.mem.eql(u8, stripped, "jumps")) {
            try self.setStatus("list jumps");
            return;
        }
        if (std.mem.eql(u8, stripped, "changes")) {
            try self.setStatus("list changes");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffthis")) {
            try self.setStatus("enable diff mode for this window");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffoff")) {
            try self.setStatus("disable diff mode");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffupdate")) {
            try self.setStatus("update diff summary");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffget") or std.mem.eql(u8, stripped, "do")) {
            try self.setStatus("get the line from the diff peer");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffput") or std.mem.eql(u8, stripped, "dp")) {
            try self.setStatus("put the current line into the diff peer");
            return;
        }
        if (std.mem.eql(u8, stripped, "q") or std.mem.eql(u8, stripped, "quit")) {
            try self.setStatus("quit the editor");
            return;
        }
        try self.setStatus("no help found");
    }

    fn openManPageForCurrentWord(self: *App) !void {
        const word = self.activeBuffer().currentWord();
        if (word.len == 0) {
            try self.setStatus("no word under cursor");
            return;
        }
        if (!self.runInteractiveCommand(&.{ "man", word })) {
            try self.setStatus("man page not available");
        } else {
            try self.setStatus("returned from man");
        }
    }

    fn openTerminalShell(self: *App) !void {
        const shell = try self.defaultShell();
        defer if (shell.owned) self.allocator.free(shell.path);
        if (!self.runInteractiveCommand(&.{shell.path})) {
            try self.setStatus("terminal unavailable");
        } else {
            try self.setStatus("returned from terminal");
        }
    }

    const ShellRef = struct {
        path: []const u8,
        owned: bool,
    };

    fn defaultShell(self: *App) !ShellRef {
        if (builtin.os.tag == .windows) {
            return .{ .path = "cmd.exe", .owned = false };
        }
        const owned = std.process.getEnvVarOwned(self.allocator, "SHELL") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return .{ .path = "sh", .owned = false },
            else => return err,
        };
        return .{ .path = owned, .owned = true };
    }

    fn runInteractiveCommand(self: *App, argv: []const []const u8) bool {
        if (self.interactive_command_hook) |hook| {
            return hook(self, argv);
        }
        const had_raw = self.raw_mode != null;
        if (had_raw) self.exitTerminal() catch return false;
        defer if (had_raw) self.initTerminal() catch {};

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        child.spawn() catch return false;
        _ = child.wait() catch return false;
        return true;
    }

    fn jumpToMatchingCharacter(self: *App) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const candidate = if (cursor_offset < text.len and isMatchPair(text[cursor_offset])) text[cursor_offset] else if (cursor_offset > 0 and isMatchPair(text[cursor_offset - 1])) text[cursor_offset - 1] else 0;
        if (candidate == 0) {
            try self.setStatus("no matching character under cursor");
            return;
        }
        const jump_offset = findMatchingPairOffset(text, cursor_offset, candidate) orelse {
            try self.setStatus("matching character not found");
            return;
        };
        buf.cursor = self.offsetToPosition(text, jump_offset);
    }

    fn jumpToDeclaration(self: *App, global: bool) !void {
        const buf = self.activeBuffer();
        const word = buf.currentWord();
        if (word.len == 0) {
            try self.setStatus("no word under cursor");
            return;
        }
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const found = if (global)
            findWordOccurrence(text, word, 0, true)
        else
            findWordOccurrence(text, word, cursor_offset, false);
        if (found) |offset| {
            buf.cursor = self.offsetToPosition(text, offset);
        } else {
            try self.setStatus("declaration not found");
        }
    }

    fn findMatchingPairOffset(text: []const u8, cursor_offset: usize, ch: u8) ?usize {
        const pair = matchingPair(ch) orelse return null;
        const open = pair[0];
        const close = pair[1];
        if (ch == open) {
            var depth: usize = 0;
            var idx = @min(cursor_offset + 1, text.len);
            while (idx < text.len) : (idx += 1) {
                const byte = text[idx];
                if (byte == open) depth += 1;
                if (byte == close) {
                    if (depth == 0) return idx;
                    depth -= 1;
                }
            }
            return null;
        }

        var depth: usize = 0;
        var idx = if (cursor_offset > 0) cursor_offset - 1 else return null;
        while (true) {
            const byte = text[idx];
            if (byte == close) {
                depth += 1;
            } else if (byte == open) {
                if (depth == 0) return idx;
                depth -= 1;
            }
            if (idx == 0) break;
            idx -= 1;
        }
        return null;
    }

    fn findWordOccurrence(text: []const u8, word: []const u8, start_offset: usize, forward: bool) ?usize {
        if (word.len == 0 or text.len < word.len) return null;
        if (forward) {
            var idx = start_offset;
            while (idx + word.len <= text.len) : (idx += 1) {
                if (std.mem.eql(u8, text[idx .. idx + word.len], word) and isWordBoundary(text, idx, word.len)) return idx;
            }
            return null;
        }
        var idx = @min(start_offset, text.len);
        while (idx > 0) : (idx -= 1) {
            if (idx >= word.len and std.mem.eql(u8, text[idx - word.len .. idx], word) and isWordBoundary(text, idx - word.len, word.len)) return idx - word.len;
        }
        return null;
    }

    fn isWordBoundary(text: []const u8, start: usize, len: usize) bool {
        const before_ok = start == 0 or !isWordChar(text[start - 1]);
        const after_index = start + len;
        const after_ok = after_index >= text.len or !isWordChar(text[after_index]);
        return before_ok and after_ok;
    }

    fn offsetToPosition(self: *App, text: []const u8, offset: usize) buffer_mod.Position {
        _ = self;
        var row: usize = 0;
        var col: usize = 0;
        var idx: usize = 0;
        while (idx < text.len and idx < offset) : (idx += 1) {
            if (text[idx] == '\n') {
                row += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return .{ .row = row, .col = col };
    }

    fn matchingPair(ch: u8) ?[2]u8 {
        return switch (ch) {
            '(' => .{ '(', ')' },
            ')' => .{ '(', ')' },
            '[' => .{ '[', ']' },
            ']' => .{ '[', ']' },
            '{' => .{ '{', '}' },
            '}' => .{ '{', '}' },
            else => null,
        };
    }

    fn isMatchPair(ch: u8) bool {
        return matchingPair(ch) != null;
    }

    fn isWordChar(byte: u8) bool {
        return std.ascii.isAlphanumeric(byte) or byte == '_';
    }

    fn matchesCommand(head: []const u8, aliases: []const []const u8, configured: []const u8) bool {
        const cfg = if (configured.len > 0 and configured[0] == ':') configured[1..] else configured;
        if (std.mem.eql(u8, head, cfg) or std.mem.eql(u8, head, configured)) return true;
        for (aliases) |alias| {
            if (std.mem.eql(u8, head, alias)) return true;
        }
        return false;
    }

    fn stripVisualRangePrefix(command: []const u8) []const u8 {
        if (std.mem.startsWith(u8, command, "'<,'>")) return std.mem.trimLeft(u8, command["'<,'>".len..], " \t");
        if (std.mem.startsWith(u8, command, "'<,'")) return std.mem.trimLeft(u8, command["'<,'".len..], " \t");
        return command;
    }

    fn executeSearch(self: *App) !void {
        const needle = self.search_buffer.items;
        self.mode = .normal;
        self.clearSearchPreview();
        if (needle.len == 0) return;
        try self.updateSearchHighlight(&self.search_highlight, needle);
        if (self.activeBuffer().search(needle)) |pos| {
            self.activeBuffer().cursor = pos;
            try self.setStatus("match found");
        } else {
            try self.setStatus("not found");
        }
    }

    fn reloadConfig(self: *App) !void {
        var diag = config_mod.Diagnostics{};
        const new_config = config_mod.load(self.allocator, self.config_path, &diag) catch {
            const msg = try std.fmt.allocPrint(self.allocator, "config error {d}:{d} {s}", .{ diag.line, diag.column, diag.message });
            defer self.allocator.free(msg);
            try self.setStatus(msg);
            return;
        };
        self.config.deinit();
        self.config = new_config;
        self.plugin_host.plugin_dir = self.config.plugin_dir;
        try self.plugin_host.discoverAndStart(self.config.plugins.enabled.items, self.config.plugins.auto_start);
        try self.setStatus("config reloaded");
    }

    fn openPath(self: *App, path: []const u8) !void {
        self.disableDiffMode();
        const buf = buffer_mod.Buffer.loadFile(self.allocator, path) catch |err| switch (err) {
            error.FileNotFound => blk: {
                var empty = try buffer_mod.Buffer.initEmpty(self.allocator);
                try empty.replacePath(path);
                break :blk empty;
            },
            else => return err,
        };
        try self.buffers.append(buf);
        self.focusBufferIndex(self.buffers.items.len - 1);
        self.plugin_host.broadcastEvent("buffer_open", "{}");
    }

    fn openSplit(self: *App, path: []const u8) !void {
        self.disableDiffMode();
        const buf = buffer_mod.Buffer.loadFile(self.allocator, path) catch |err| switch (err) {
            error.FileNotFound => blk: {
                var empty = try buffer_mod.Buffer.initEmpty(self.allocator);
                try empty.replacePath(path);
                break :blk empty;
            },
            else => return err,
        };
        if (self.split_index) |idx| {
            self.buffers.items[idx].deinit();
            self.buffers.items[idx] = buf;
        } else {
            try self.buffers.append(buf);
            self.split_index = self.buffers.items.len - 1;
        }
        self.split_focus = .right;
        self.plugin_host.broadcastEvent("buffer_open", "{}");
    }

    fn render(self: *App) !void {
        const stdout_file = std.fs.File.stdout();
        const size = terminal_mod.size(stdout_file);
        var out_buf: [4096]u8 = undefined;
        var out_writer = stdout_file.writer(&out_buf);
        const writer = &out_writer.interface;
        try terminal_mod.clear(writer);
        try terminal_mod.showCursor(writer);
        try terminal_mod.setCursorShape(writer, self.mode == .normal);

        const show_bottom_bar = self.config.status_bar or self.mode == .command or self.mode == .search;
        const render_height = if (show_bottom_bar and size.rows > 0) size.rows - 1 else size.rows;
        self.last_render_height = render_height;
        const has_split = self.split_index != null and size.cols > 1;
        const separator_width: usize = if (has_split) 1 else 0;
        const available_width = if (size.cols > separator_width) size.cols - separator_width else size.cols;
        var left_width: usize = available_width;
        var right_width: usize = 0;
        var right_x: usize = 0;
        const split_width = if (self.config.split_ratio > 0 and self.config.split_ratio < 100)
            (available_width * self.config.split_ratio) / 100
        else
            available_width / 2;
        if (has_split and available_width > 1) {
            left_width = @min(available_width - 1, @max(20, split_width));
            if (left_width + separator_width < available_width) {
                right_width = available_width - left_width - separator_width;
                right_x = left_width + separator_width;
            }
        }
        if (right_width == 0) {
            left_width = available_width;
        }

        try self.renderPane(writer, self.activeBuffer(), 0, left_width, render_height, self.split_focus == .left);
        if (has_split and right_width > 0) {
            try self.renderPaneSeparator(writer, left_width, render_height);
            if (self.split_index) |idx| {
                try self.renderPane(writer, &self.buffers.items[idx], right_x, right_width, render_height, self.split_focus == .right);
            }
        }

        if (show_bottom_bar and size.rows > 0) {
            if (self.mode == .command or self.mode == .search) {
                try self.renderPromptBar(writer, size.cols, size.rows);
            } else if (self.config.status_bar) {
                try self.renderStatusBar(writer, size.cols, size.rows);
            }
        }

        switch (self.mode) {
            .command, .search => {},
            else => {},
        }

        const buf = self.activeBuffer();
        const gutter_width: usize = if (self.config.show_line_numbers) 7 else 0;
        const cursor_row: usize = if (render_height > 0)
            @min(buf.cursor.row + 1, render_height)
        else if (size.rows > 0)
            1
        else
            0;
        const cursor_col = @min(buf.cursor.col + 1 + gutter_width, if (self.split_index != null and self.split_focus == .right and right_width > 0) right_width else left_width);
        const base_col = if (self.split_index != null and self.split_focus == .right and right_width > 0) right_x + 1 else 1;
        if (cursor_row > 0 and cursor_col > 0) {
            try writer.print("\x1b[{d};{d}H", .{ cursor_row, base_col + cursor_col - 1 });
        }
        try writer.flush();
    }

    fn renderStatusBar(self: *App, writer: anytype, cols: usize, row: usize) !void {
        const section_gap: usize = 2;
        const render_safety: usize = 2;
        const right_budget_floor: usize = 12;
        const mode_pill_width = displayWidth(modeIconText(self, self.mode)) + displayWidth(modeLabel(self.mode)) + 5;
        const available = if (cols > mode_pill_width + section_gap * 2 + render_safety)
            cols - mode_pill_width - section_gap * 2 - render_safety
        else
            0;
        const right_budget = if (available == 0) 0 else @min(available, @max(right_budget_floor, available / 3));
        const right_text = try self.statusBarRightText(self.allocator, right_budget);
        defer self.allocator.free(right_text);
        const mode_style = self.theme.modeStyle(self.mode);
        const mode_icon = modeIconText(self, self.mode);
        const right_width = displayWidth(right_text);
        const left_budget = if (available > right_width) available - right_width else 0;
        const left_text = try self.statusBarLeftText(self.allocator, left_budget);
        defer self.allocator.free(left_text);

        try writer.print("\x1b[{d};1H", .{row});
        try writeStyle(writer, self.theme.statusStyle());
        try writer.writeByte(' ');
        try writeStyledText(writer, mode_style, " ");
        try writeStyledText(writer, mode_style, mode_icon);
        try writer.writeByte(' ');
        try writeStyledText(writer, mode_style, modeLabel(self.mode));
        try writeStyledText(writer, mode_style, " ");
        try writeStyle(writer, self.theme.statusStyle());
        try writer.writeByte(' ');
        try writeStyledText(writer, self.theme.statusStyle(), left_text);

        var used: usize = mode_pill_width + section_gap + displayWidth(left_text);
        if (right_width > 0 and used + right_width < cols) {
            while (used + section_gap + right_width < cols) : (used += 1) {
                try writer.writeByte(' ');
            }
        }
        if (right_width > 0) {
            try writeStyledText(writer, self.theme.statusStyle(), right_text);
            used += right_width;
        }
        while (used < cols) : (used += 1) {
            try writer.writeByte(' ');
        }
        try writer.writeAll("\x1b[0m");
    }

    fn renderPromptBar(self: *App, writer: anytype, cols: usize, row: usize) !void {
        const detail = try self.promptBarText(self.allocator);
        defer self.allocator.free(detail);

        try writer.print("\x1b[{d};1H", .{row});
        try writeStyle(writer, self.theme.promptStyle());
        try writer.writeByte(' ');
        try writeStyledText(writer, self.theme.modeStyle(self.mode), modeLabel(self.mode));
        try writer.writeByte(' ');
        try writeStyledText(writer, .{ .fg = self.theme.border, .bg = self.theme.prompt_bg }, "|");
        try writer.writeByte(' ');
        try writeStyledText(writer, self.theme.promptStyle(), detail);
        var used: usize = 2 + modeLabel(self.mode).len + 3 + detail.len;
        while (used < cols) : (used += 1) {
            try writer.writeByte(' ');
        }
        try writer.writeAll("\x1b[0m");
    }

    fn renderPaneSeparator(self: *App, writer: anytype, x: usize, height: usize) !void {
        var row: usize = 0;
        while (row < height) : (row += 1) {
            try writer.print("\x1b[{d};{d}H", .{ row + 1, x + 1 });
            try writeStyledText(writer, self.theme.separatorStyle(), "|");
        }
    }

    fn renderPane(self: *App, writer: anytype, buffer: *buffer_mod.Buffer, x: usize, width: usize, height: usize, active: bool) !void {
        const start_row = if (buffer.lines.items.len == 0) 0 else @min(buffer.scroll_row, buffer.lines.items.len - 1);
        const active_search = self.activeSearchHighlight(active);
        const active_visual = if (active and self.mode == .visual) self.visualSelection() else null;
        var screen_row: usize = 0;
        var row = start_row;
        while (screen_row < height and row < buffer.lines.items.len) {
            if (buffer.foldAtRow(row)) |fold| {
                if (buffer.fold_enabled and fold.closed) {
                    if (row > fold.start_row) {
                        row = fold.end_row + 1;
                        continue;
                    }
                    try writer.print("\x1b[{d};{d}H", .{ screen_row + 1, x + 1 });
                    if (self.config.show_line_numbers) {
                        try writeStyle(writer, self.theme.lineNumberStyle(active));
                        try writer.print("{d: >4}", .{row + 1});
                        try writeStyle(writer, self.theme.separatorStyle());
                        try writer.writeAll(" | ");
                    }
                    const line = buffer.lines.items[row];
                    const gutter_width: usize = if (self.config.show_line_numbers) 7 else 0;
                    const available = if (width > gutter_width) width - gutter_width else 0;
                    try writeStyle(writer, self.theme.textStyle(active));
                    const suffix = "  [+fold]";
                    const room = if (available > suffix.len) available - suffix.len else 0;
                    try self.renderHighlightedLine(writer, line[0..@min(line.len, room)], row, available, active_search, active_visual, active);
                    try writeStyle(writer, self.theme.separatorStyle());
                    try writer.writeAll(suffix);
                    try writer.writeAll("\x1b[0m");
                    screen_row += 1;
                    row = fold.end_row + 1;
                    continue;
                }
            }
            try writer.print("\x1b[{d};{d}H", .{ screen_row + 1, x + 1 });
            if (self.config.show_line_numbers) {
                try writeStyle(writer, self.theme.lineNumberStyle(active));
                try writer.print("{d: >4}", .{row + 1});
                try writeStyle(writer, self.theme.separatorStyle());
                try writer.writeAll(" | ");
            }
            const line = buffer.lines.items[row];
            const gutter_width: usize = if (self.config.show_line_numbers) 7 else 0;
            const available = if (width > gutter_width) width - gutter_width else 0;
            try self.renderHighlightedLine(writer, line, row, available, active_search, active_visual, active);
            screen_row += 1;
            row += 1;
        }
    }

    const HighlightKind = enum { base, search, visual };
    const TextRange = struct { start: usize, end: usize };

    fn renderHighlightedLine(
        self: *App,
        writer: anytype,
        line: []const u8,
        row: usize,
        available: usize,
        search: ?[]const u8,
        visual: ?VisualSelection,
        active: bool,
    ) !void {
        const limit = @min(line.len, available);
        const visual_range = if (visual) |selection| self.visualRangeForRow(selection, row, line.len) else null;
        const search_needle = search orelse "";
        var search_range = if (search) |needle| self.nextSearchRange(line, needle, 0) else null;
        var col: usize = 0;
        const base_style = self.theme.textStyle(active);
        var current: HighlightKind = .base;
        try writeStyle(writer, base_style);
        while (col < limit) : (col += 1) {
            while (search_range) |range| {
                if (col < range.start) break;
                if (col >= range.end) {
                    search_range = self.nextSearchRange(line, search_needle, range.end);
                    continue;
                }
                break;
            }

            const in_visual = if (visual_range) |range| col >= range.start and col < range.end else false;
            const in_search = if (search_range) |span| col >= span.start and col < span.end else false;
            const kind: HighlightKind = if (in_visual) .visual else if (in_search) .search else .base;

            if (kind != current) {
                switch (kind) {
                    .base => try writeStyle(writer, base_style),
                    .search => try writeStyle(writer, self.theme.searchStyle()),
                    .visual => try writeStyle(writer, self.theme.visualStyle()),
                }
                current = kind;
            }
            try writer.writeByte(line[col]);
        }
        try writer.writeAll("\x1b[0m");
    }

    fn nextSearchRange(self: *App, line: []const u8, needle: []const u8, start: usize) ?TextRange {
        _ = self;
        if (needle.len == 0 or start > line.len) return null;
        const hit = std.mem.indexOfPos(u8, line, start, needle) orelse return null;
        return .{ .start = hit, .end = hit + needle.len };
    }

    fn visualRangeForRow(self: *App, selection: VisualSelection, row: usize, line_len: usize) ?TextRange {
        return switch (self.visual_mode) {
            .block => if (self.visualBlockBounds()) |bounds| blk: {
                if (row < bounds.start_row or row > bounds.end_row) break :blk null;
                break :blk .{ .start = @min(bounds.start_col, line_len), .end = @min(bounds.end_col, line_len) };
            } else null,
            .line => if (row < selection.start.row or row > selection.end.row)
                null
            else
                .{ .start = 0, .end = line_len },
            else => if (row < selection.start.row or row > selection.end.row)
                null
            else if (selection.start.row == selection.end.row)
                .{ .start = @min(selection.start.col, line_len), .end = @min(selection.end.col, line_len) }
            else if (row == selection.start.row)
                .{ .start = @min(selection.start.col, line_len), .end = line_len }
            else if (row == selection.end.row)
                .{ .start = 0, .end = @min(selection.end.col, line_len) }
            else
                .{ .start = 0, .end = line_len },
        };
    }

    fn activeBuffer(self: *App) *buffer_mod.Buffer {
        if (self.split_index) |idx| {
            return switch (self.split_focus) {
                .left => &self.buffers.items[self.active_index],
                .right => &self.buffers.items[idx],
            };
        }
        return &self.buffers.items[self.active_index];
    }

    fn activeSearchHighlight(self: *App, active: bool) ?[]const u8 {
        if (!active) return null;
        if (self.mode == .search) return self.search_preview_highlight orelse self.search_highlight;
        return self.search_highlight;
    }

    fn statusBarText(self: *App, allocator: std.mem.Allocator) ![]u8 {
        const left = try self.statusBarLeftText(allocator, std.math.maxInt(usize));
        defer allocator.free(left);
        const right = try self.statusBarRightText(allocator, std.math.maxInt(usize));
        defer allocator.free(right);
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        try out.appendSlice(modeIconText(self, self.mode));
        try out.appendByte(' ');
        try out.appendSlice(modeLabel(self.mode));
        try out.appendSlice(" | ");
        try out.appendSlice(left);
        if (right.len > 0) {
            try out.appendSlice(" | ");
            try out.appendSlice(right);
        }
        return try out.toOwnedSlice();
    }

    fn statusBarLeftText(self: *App, allocator: std.mem.Allocator, max_width: usize) ![]u8 {
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        if (max_width == 0) return try out.toOwnedSlice();

        const name = self.activeBuffer().path orelse "[No Name]";
        const file_prefix = "󰈙 ";
        const file_prefix_width = displayWidth(file_prefix);
        if (file_prefix_width > max_width) return try out.toOwnedSlice();
        const file_budget = if (max_width > file_prefix_width) max_width - file_prefix_width else 0;
        const clipped_name = clipText(name, file_budget);
        try out.appendSlice(file_prefix);
        try out.appendSlice(clipped_name);

        var used: usize = file_prefix_width + displayWidth(clipped_name);
        const split_text = if (self.split_index != null) if (self.split_focus == .left) " [L]" else " [R]" else "";
        const dirty_text = if (self.activeBuffer().dirty) " │ ● modified" else "";
        const diff_text = if (self.diff_mode) " │ diff" else "";
        const extras = [_][]const u8{ split_text, dirty_text, diff_text };
        for (extras) |extra| {
            const extra_width = displayWidth(extra);
            if (extra_width == 0) continue;
            if (used + extra_width > max_width) break;
            try out.appendSlice(extra);
            used += extra_width;
        }
        return try out.toOwnedSlice();
    }

    fn statusBarRightText(self: *App, allocator: std.mem.Allocator, max_width: usize) ![]u8 {
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        if (max_width == 0) return try out.toOwnedSlice();

        const buf = self.activeBuffer();
        const line_count = buf.lineCount();
        const row = if (line_count == 0) 0 else @min(buf.cursor.row, line_count - 1);
        const col = if (line_count == 0) 0 else @min(buf.cursor.col, buf.lines.items[row].len);
        const percent = if (line_count <= 1) 100 else @min(100, ((row + 1) * 100) / line_count);

        const location = try std.fmt.allocPrint(allocator, "L/N {d}:{d}", .{ row + 1, col + 1 });
        defer allocator.free(location);
        const progress = try std.fmt.allocPrint(allocator, "{d}%", .{percent});
        defer allocator.free(progress);

        const app_status = self.status.items;
        const plugin_status = self.plugin_host.statusText();
        const app_prefix = "󰞋 ";
        const plugin_prefix = "󰒓 ";
        const app_width = if (app_status.len > 0) displayWidth(app_prefix) + displayWidth(app_status) else 0;
        const plugin_width = if (plugin_status.len > 0) displayWidth(plugin_prefix) + displayWidth(plugin_status) else 0;
        const location_width = displayWidth(location);
        const progress_width = displayWidth(progress);
        const sep_width: usize = displayWidth(" │ ");

        var include_app = app_width > 0 and max_width >= app_width + plugin_width + location_width + progress_width + (if (plugin_width > 0) sep_width else 0) + (if (location_width > 0 and progress_width > 0) sep_width else 0) + (if (app_width > 0 and (plugin_width > 0 or location_width > 0)) sep_width else 0);
        var include_plugin = plugin_width > 0 and max_width >= plugin_width + location_width + progress_width + (if (location_width > 0 and progress_width > 0) sep_width else 0) + (if (plugin_width > 0 and location_width > 0) sep_width else 0);

        const mandatory_width = location_width + progress_width + (if (location_width > 0 and progress_width > 0) sep_width else 0);
        if (mandatory_width > max_width) {
            const progress_budget = if (max_width > location_width + sep_width) max_width - location_width - sep_width else 0;
            const clipped_location = clipText(location, if (max_width > progress_width + sep_width) max_width - progress_width - sep_width else 0);
            try out.appendSlice(clipped_location);
            if (clipped_location.len > 0 and progress_budget > 0) {
                try out.appendSlice(" │ ");
            }
            try out.appendSlice(clipText(progress, progress_budget));
            const clipped_width = displayWidth(out.items);
            if (clipped_width <= max_width) return try out.toOwnedSlice();
            const clipped = clipText(out.items, max_width);
            var clipped_out = std.array_list.Managed(u8).init(allocator);
            errdefer clipped_out.deinit();
            try clipped_out.appendSlice(clipped);
            return try clipped_out.toOwnedSlice();
        }

        if (include_app) {
            try out.appendSlice(app_prefix);
            try out.appendSlice(app_status);
        }
        if (include_plugin) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(plugin_prefix);
            try out.appendSlice(plugin_status);
        }
        if (out.items.len > 0) try out.appendSlice(" │ ");
        try out.appendSlice(location);
        if (progress.len > 0) {
            try out.appendSlice(" │ ");
            try out.appendSlice(progress);
        }

        const final_width = displayWidth(out.items);
        if (final_width <= max_width) return try out.toOwnedSlice();

        // Drop low-priority activity fields if the right side still overflows.
        out.clearRetainingCapacity();
        include_app = false;
        include_plugin = plugin_width > 0 and max_width >= plugin_width + location_width + progress_width + sep_width * 2;
        if (include_plugin) {
            try out.appendSlice(plugin_prefix);
            try out.appendSlice(plugin_status);
            try out.appendSlice(" │ ");
        }
        try out.appendSlice(location);
        try out.appendSlice(" │ ");
        try out.appendSlice(progress);
        if (displayWidth(out.items) <= max_width) return try out.toOwnedSlice();
        const clipped = clipText(out.items, max_width);
        var clipped_out = std.array_list.Managed(u8).init(allocator);
        errdefer clipped_out.deinit();
        try clipped_out.appendSlice(clipped);
        return try clipped_out.toOwnedSlice();
    }

    fn promptBarText(self: *App, allocator: std.mem.Allocator) ![]u8 {
        const prompt = if (self.mode == .command) self.command_buffer.items else self.search_buffer.items;
        const prefix: []const u8 = if (self.mode == .command) ":" else "/";
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, prompt });
    }

    fn toggleSplitFocus(self: *App) void {
        if (self.split_index != null) {
            self.split_focus = switch (self.split_focus) {
                .left => .right,
                .right => .left,
            };
        }
    }

    fn equalizeWindows(self: *App) !void {
        if (self.split_index == null) {
            try self.setStatus("no other window");
            return;
        }
        self.config.split_ratio = 50;
        try self.setStatus("windows equalized");
    }

    fn resizeSplitBy(self: *App, delta: isize) !void {
        if (self.split_index == null) {
            try self.setStatus("no split");
            return;
        }
        const focus_delta: isize = if (self.split_focus == .left) delta else -delta;
        const current: isize = @intCast(self.config.split_ratio);
        const next = std.math.clamp(current + focus_delta, 5, 95);
        self.config.split_ratio = @intCast(next);
        try self.setStatus("window resized");
    }

    fn maximizeSplit(self: *App) !void {
        if (self.split_index == null) {
            try self.setStatus("no split");
            return;
        }
        self.config.split_ratio = if (self.split_focus == .left) 100 else 0;
        try self.setStatus("window maximized");
    }

    fn setStatus(self: *App, text: []const u8) !void {
        self.status.clearRetainingCapacity();
        try self.status.appendSlice(text);
    }

    fn drainPluginActions(self: *App) !void {
        var rounds: usize = 0;
        while (rounds < 16) : (rounds += 1) {
            const actions = try self.plugin_host.consumeActions();
            defer self.allocator.free(actions);

            if (actions.len == 0) return;

            for (actions) |action| {
                defer self.plugin_host.freeAction(action);
                switch (action.kind) {
                    .open_file => {
                        const path = action.path orelse continue;
                        try self.openPath(path);
                    },
                    .open_split => {
                        const path = action.path orelse continue;
                        try self.openSplit(path);
                    },
                    .quit => {
                        self.should_quit = true;
                    },
                }
            }
        }

        if (self.plugin_host.actions.items.len > 0) {
            try self.setStatus("plugin action limit reached");
        }
    }

    fn maybeDrainPluginActions(self: *App) !void {
        if (self.draining_plugin_actions) return;
        self.draining_plugin_actions = true;
        defer self.draining_plugin_actions = false;
        try self.drainPluginActions();
    }

    fn printHelp() !void {
        std.debug.print(
            \\Beam editor
            \\  beam [--config path] [file]
            \\Commands:
            \\  :help keyword  open help for a keyword
            \\  :w             save buffer
            \\  :wq            save and quit
            \\  :q             quit
            \\  :q!            force quit
            \\  :saveas PATH   save buffer as a new file
            \\  :close         close current pane
            \\  :terminal      open a terminal pane
            \\  :edit PATH     open path in a buffer
            \\  :open PATH     open path in a new buffer
            \\  :bd            delete the current buffer
            \\  :bn / :bp      move to next / previous buffer
            \\  :buffer N|PATH switch to a buffer by index or path
            \\  :buffers       list open buffers
            \\  :split PATH    open path in split view
            \\  :sp PATH      split and open a path
            \\  :vs PATH      vertical split and open a path
            \\  :tabnew PATH   open path in a new tab
            \\  :tabclose      close current tab
            \\  :tabonly       keep only the current tab
            \\  :tabmove N     move current tab to index N
            \\  :vimgrep /pat/ [path] search files for a pattern
            \\  :cn / :cp      next / previous quickfix item
            \\  :cope / :ccl   show / clear quickfix results
            \\  :zf / :za / :zo / :zc / :zE / :zr / :zm / :zi fold commands
            \\  :diffthis / :diffoff / :diffupdate / :diffget / :diffput
            \\  Ctrl+w s/v/n  split window / new empty window
            \\  Ctrl+w +/-    resize window narrower / wider
            \\  Ctrl+w </>    resize window narrower / wider
            \\  Ctrl+w \\ |   maximize window width
            \\  Ctrl+w _      maximize window height
            \\  Ctrl+w =      equalize window sizes
            \\  Ctrl+w w      switch windows
            \\  Ctrl+w q      quit a window
            \\  Ctrl+w T      move split into its own tab
            \\  :reload-config reload TOML config
            \\  :registers     list register contents
            \\  :plugin NAME   invoke a loaded plugin command
            \\
        , .{});
    }
};

fn testInteractiveCommandHook(app: *App, argv: []const []const u8) bool {
    if (app.last_interactive_command) |cmd| app.allocator.free(cmd);
    app.last_interactive_command = std.mem.join(app.allocator, "\t", argv) catch return false;
    return true;
}

fn makeTestApp(allocator: std.mem.Allocator, text: []const u8) !App {
    const args = [_][:0]const u8{"beam"};
    var app = try App.init(allocator, args[0..]);
    errdefer app.deinit();
    var buf = try buffer_mod.Buffer.initEmpty(allocator);
    errdefer buf.deinit();
    try buf.setText(text);
    try app.buffers.append(buf);
    app.active_index = 0;
    return app;
}

fn pressNormalKeys(app: *App, keys: []const u8) !void {
    for (keys) |key| {
        try app.handleNormalByte(key);
    }
}

fn setCursor(app: *App, row: usize, col: usize) void {
    app.activeBuffer().cursor = .{ .row = row, .col = col };
}

const VisualBindingStatus = enum { verified, todo };

const visual_binding_checklist = [_]struct {
    tag: []const u8,
    sequence: []const u8,
    status: VisualBindingStatus,
    note: []const u8,
}{
    .{ .tag = "v_CTRL-_CTRL-N", .sequence = "CTRL-\\ CTRL-N", .status = .verified, .note = "stop Visual mode" },
    .{ .tag = "v_CTRL-_CTRL-G", .sequence = "CTRL-\\ CTRL-G", .status = .verified, .note = "go to Normal mode" },
    .{ .tag = "v_CTRL-A", .sequence = "CTRL-A", .status = .verified, .note = "add N to number in highlighted text" },
    .{ .tag = "v_CTRL-C", .sequence = "CTRL-C", .status = .verified, .note = "stop Visual mode" },
    .{ .tag = "v_CTRL-G", .sequence = "CTRL-G", .status = .verified, .note = "toggle between Visual mode and Select mode" },
    .{ .tag = "v_<BS>", .sequence = "<BS>", .status = .verified, .note = "Select mode: delete highlighted area" },
    .{ .tag = "v_CTRL-H", .sequence = "CTRL-H", .status = .verified, .note = "same as <BS>" },
    .{ .tag = "v_CTRL-O", .sequence = "CTRL-O", .status = .verified, .note = "switch from Select to Visual mode for one command" },
    .{ .tag = "v_CTRL-V", .sequence = "CTRL-V", .status = .verified, .note = "make Visual mode blockwise or stop Visual mode" },
    .{ .tag = "v_CTRL-X", .sequence = "CTRL-X", .status = .verified, .note = "subtract N from number in highlighted text" },
    .{ .tag = "v_<Esc>", .sequence = "<Esc>", .status = .verified, .note = "stop Visual mode" },
    .{ .tag = "v_CTRL-]", .sequence = "CTRL-]", .status = .verified, .note = "jump to highlighted tag" },
    .{ .tag = "v_!", .sequence = "!{filter}", .status = .verified, .note = "filter the highlighted lines through {filter}" },
    .{ .tag = "v_:", .sequence = ":", .status = .verified, .note = "start a command-line with the highlighted lines as a range" },
    .{ .tag = "v_<", .sequence = "<", .status = .verified, .note = "shift the highlighted lines one shiftwidth left" },
    .{ .tag = "v_=", .sequence = "=", .status = .verified, .note = "filter the highlighted lines through equalprg" },
    .{ .tag = "v_>", .sequence = ">", .status = .verified, .note = "shift the highlighted lines one shiftwidth right" },
    .{ .tag = "v_b_A", .sequence = "A", .status = .verified, .note = "block mode append after the highlighted area" },
    .{ .tag = "v_C", .sequence = "C", .status = .verified, .note = "delete the highlighted lines and start insert" },
    .{ .tag = "v_D", .sequence = "D", .status = .verified, .note = "delete the highlighted lines" },
    .{ .tag = "v_b_I", .sequence = "I", .status = .verified, .note = "block mode insert before the highlighted area" },
    .{ .tag = "v_J", .sequence = "J", .status = .verified, .note = "join the highlighted lines" },
    .{ .tag = "v_K", .sequence = "K", .status = .verified, .note = "run keywordprg on the highlighted area" },
    .{ .tag = "v_O", .sequence = "O", .status = .verified, .note = "move horizontally to the other corner of the area" },
    .{ .tag = "v_P", .sequence = "P", .status = .verified, .note = "replace highlighted area with register contents" },
    .{ .tag = "v_R", .sequence = "R", .status = .verified, .note = "delete the highlighted lines and start insert" },
    .{ .tag = "v_S", .sequence = "S", .status = .verified, .note = "delete the highlighted lines and start insert" },
    .{ .tag = "v_U", .sequence = "U", .status = .verified, .note = "make highlighted area uppercase" },
    .{ .tag = "v_V", .sequence = "V", .status = .verified, .note = "make Visual mode linewise or stop Visual mode" },
    .{ .tag = "v_X", .sequence = "X", .status = .verified, .note = "delete the highlighted lines" },
    .{ .tag = "v_Y", .sequence = "Y", .status = .verified, .note = "yank the highlighted lines" },
    .{ .tag = "v_aquote", .sequence = "a\"", .status = .verified, .note = "extend highlighted area with a double quoted string" },
    .{ .tag = "v_a'", .sequence = "a'", .status = .verified, .note = "extend highlighted area with a single quoted string" },
    .{ .tag = "v_a(", .sequence = "a(", .status = .verified, .note = "same as ab" },
    .{ .tag = "v_a)", .sequence = "a)", .status = .verified, .note = "same as ab" },
    .{ .tag = "v_a<", .sequence = "a<", .status = .verified, .note = "extend highlighted area with a <> block" },
    .{ .tag = "v_a>", .sequence = "a>", .status = .verified, .note = "same as a<" },
    .{ .tag = "v_aB", .sequence = "aB", .status = .verified, .note = "extend highlighted area with a {} block" },
    .{ .tag = "v_aW", .sequence = "aW", .status = .verified, .note = "extend highlighted area with a WORD" },
    .{ .tag = "v_a[", .sequence = "a[", .status = .verified, .note = "extend highlighted area with a [] block" },
    .{ .tag = "v_a]", .sequence = "a]", .status = .verified, .note = "same as a[" },
    .{ .tag = "v_a", .sequence = "a", .status = .verified, .note = "extend highlighted area with a backtick quoted string" },
    .{ .tag = "v_ab", .sequence = "ab", .status = .verified, .note = "extend highlighted area with a () block" },
    .{ .tag = "v_ap", .sequence = "ap", .status = .verified, .note = "extend highlighted area with a paragraph" },
    .{ .tag = "v_as", .sequence = "as", .status = .verified, .note = "extend highlighted area with a sentence" },
    .{ .tag = "v_at", .sequence = "at", .status = .verified, .note = "extend highlighted area with a tag block" },
    .{ .tag = "v_aw", .sequence = "aw", .status = .verified, .note = "extend highlighted area with a word" },
    .{ .tag = "v_a{", .sequence = "a{", .status = .verified, .note = "same as aB" },
    .{ .tag = "v_a}", .sequence = "a}", .status = .verified, .note = "same as aB" },
    .{ .tag = "v_c", .sequence = "c", .status = .verified, .note = "delete highlighted area and start insert" },
    .{ .tag = "v_d", .sequence = "d", .status = .verified, .note = "delete highlighted area" },
    .{ .tag = "v_g_CTRL-A", .sequence = "g CTRL-A", .status = .verified, .note = "add N to number in highlighted text" },
    .{ .tag = "v_g_CTRL-X", .sequence = "g CTRL-X", .status = .verified, .note = "subtract N from number in highlighted text" },
    .{ .tag = "v_gJ", .sequence = "gJ", .status = .verified, .note = "join the highlighted lines without spaces" },
    .{ .tag = "v_gq", .sequence = "gq", .status = .verified, .note = "format the highlighted lines" },
    .{ .tag = "v_gv", .sequence = "gv", .status = .verified, .note = "exchange current and previous highlighted area" },
    .{ .tag = "v_iquote", .sequence = "i\"", .status = .verified, .note = "extend highlighted area with a double quoted string without quotes" },
    .{ .tag = "v_i'", .sequence = "i'", .status = .verified, .note = "extend highlighted area with a single quoted string without quotes" },
    .{ .tag = "v_i(", .sequence = "i(", .status = .verified, .note = "same as ib" },
    .{ .tag = "v_i)", .sequence = "i)", .status = .verified, .note = "same as ib" },
    .{ .tag = "v_i<", .sequence = "i<", .status = .verified, .note = "extend highlighted area with inner <> block" },
    .{ .tag = "v_i>", .sequence = "i>", .status = .verified, .note = "same as i<" },
    .{ .tag = "v_iB", .sequence = "iB", .status = .verified, .note = "extend highlighted area with inner {} block" },
    .{ .tag = "v_iW", .sequence = "iW", .status = .verified, .note = "extend highlighted area with inner WORD" },
    .{ .tag = "v_i[", .sequence = "i[", .status = .verified, .note = "extend highlighted area with inner [] block" },
    .{ .tag = "v_i]", .sequence = "i]", .status = .verified, .note = "same as i[" },
    .{ .tag = "v_i", .sequence = "i", .status = .verified, .note = "extend highlighted area with a backtick quoted string without the backticks" },
    .{ .tag = "v_ib", .sequence = "ib", .status = .verified, .note = "extend highlighted area with inner () block" },
    .{ .tag = "v_ip", .sequence = "ip", .status = .verified, .note = "extend highlighted area with inner paragraph" },
    .{ .tag = "v_is", .sequence = "is", .status = .verified, .note = "extend highlighted area with inner sentence" },
    .{ .tag = "v_it", .sequence = "it", .status = .verified, .note = "extend highlighted area with inner tag block" },
    .{ .tag = "v_iw", .sequence = "iw", .status = .verified, .note = "extend highlighted area with inner word" },
    .{ .tag = "v_i{", .sequence = "i{", .status = .verified, .note = "same as iB" },
    .{ .tag = "v_i}", .sequence = "i}", .status = .verified, .note = "same as iB" },
    .{ .tag = "v_o", .sequence = "o", .status = .verified, .note = "move cursor to the other corner of the area" },
    .{ .tag = "v_p", .sequence = "p", .status = .verified, .note = "replace highlighted area with register contents" },
    .{ .tag = "v_r", .sequence = "r", .status = .verified, .note = "replace highlighted area with a character" },
    .{ .tag = "v_s", .sequence = "s", .status = .verified, .note = "delete highlighted area and start insert" },
    .{ .tag = "v_u", .sequence = "u", .status = .verified, .note = "make highlighted area lowercase" },
    .{ .tag = "v_v", .sequence = "v", .status = .verified, .note = "make Visual mode charwise or stop Visual mode" },
    .{ .tag = "v_x", .sequence = "x", .status = .verified, .note = "delete the highlighted area" },
    .{ .tag = "v_y", .sequence = "y", .status = .verified, .note = "yank the highlighted area" },
    .{ .tag = "v_~", .sequence = "~", .status = .verified, .note = "swap case for the highlighted area" },
};

fn runVisualBytes(app: *App, bytes: []const u8) !void {
    for (bytes) |byte| {
        try app.handleVisualByte(byte);
    }
}

fn expectVisualExit(app: *App, bytes: []const u8) !void {
    try app.handleNormalByte('v');
    try runVisualBytes(app, bytes);
    try std.testing.expectEqual(Mode.normal, app.mode);
}

fn expectVisualMode(app: *App, initial: App.VisualMode, bytes: []const u8, app_mode: Mode, mode: App.VisualMode, select_mode: bool) !void {
    try app.handleNormalByte(switch (initial) {
        .character => 'v',
        .line => 'V',
        .block => 0x16,
        .none => 'v',
    });
    try runVisualBytes(app, bytes);
    try std.testing.expectEqual(app_mode, app.mode);
    if (app_mode == .visual) {
        try std.testing.expectEqual(mode, app.visual_mode);
        try std.testing.expectEqual(select_mode, app.visual_select_mode);
    }
}

test "command help dispatches to the documented help text" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    try app.setStatus("stale");
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":help saveas");
    try app.executeCommand();
    try std.testing.expectEqualStrings("save the current buffer under a new path", app.status.items);
}

test "command saveas writes the buffer and updates the path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.activeBuffer().replacePath("saved.txt");

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":saveas saved.txt");
    try app.executeCommand();

    try std.testing.expectEqualStrings("saved as", app.status.items);
    try std.testing.expectEqualStrings("saved.txt", app.activeBuffer().path.?);
    _ = try tmp.dir.openFile("saved.txt", .{});
}

test "command sort unique sorts the buffer lines" {
    var app = try makeTestApp(std.testing.allocator, "b\na\na");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":sort u");
    try app.executeCommand();

    try std.testing.expectEqualStrings("sorted", app.status.items);
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("a\nb", text);
}

test "command substitute replaces whole documents and visual selections" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta\nalpha");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":%s/alpha/omega/g");
    try app.executeCommand();
    const whole = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(whole);
    try std.testing.expectEqualStrings("omega beta\nomega", whole);
    try std.testing.expectEqualStrings("substituted", app.status.items);

    var app2 = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app2.deinit();
    try app2.handleNormalByte('v');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    app2.command_buffer.clearRetainingCapacity();
    try app2.command_buffer.appendSlice(":'<,'>s/alpha/omega/");
    try app2.executeCommand();
    const selected = try app2.activeBuffer().serialize();
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqualStrings("omega beta", selected);
    try std.testing.expectEqual(Mode.normal, app2.mode);
}

test "normal close command closes a pane when the buffer is clean" {
    var app = try makeTestApp(std.testing.allocator, "one");
    defer app.deinit();
    var extra = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
    errdefer extra.deinit();
    try extra.setText("two");
    try app.buffers.append(extra);
    app.split_index = 1;
    app.split_focus = .right;
    app.active_index = 0;

    try app.performNormalAction(.close, 1);
    try std.testing.expectEqual(@as(usize, 1), app.buffers.items.len);
    try std.testing.expectEqualStrings("pane closed", app.status.items);
}

test "normal help key launches man for the word under cursor" {
    var app = try makeTestApp(std.testing.allocator, "zig build");
    defer app.deinit();
    app.interactive_command_hook = testInteractiveCommandHook;

    try app.activeBuffer().moveToLine(0);
    try app.performNormalAction(.help, 1);
    try std.testing.expectEqualStrings("man\tzig", app.last_interactive_command.?);
    try std.testing.expectEqualStrings("returned from man", app.status.items);
}

test "normal terminal key launches the configured shell" {
    var app = try makeTestApp(std.testing.allocator, "shell");
    defer app.deinit();
    app.interactive_command_hook = testInteractiveCommandHook;

    const shell = try app.defaultShell();
    defer if (shell.owned) app.allocator.free(shell.path);

    try app.performNormalAction(.terminal, 1);
    try std.testing.expectEqualStrings(shell.path, app.last_interactive_command.?);
    try std.testing.expectEqualStrings("returned from terminal", app.status.items);
}

test "command terminal dispatches to the same shell launcher" {
    var app = try makeTestApp(std.testing.allocator, "shell");
    defer app.deinit();
    app.interactive_command_hook = testInteractiveCommandHook;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":terminal");
    try app.executeCommand();

    const shell = try app.defaultShell();
    defer if (shell.owned) app.allocator.free(shell.path);
    try std.testing.expectEqualStrings(shell.path, app.last_interactive_command.?);
    try std.testing.expectEqualStrings("returned from terminal", app.status.items);
}

test "matching character jump moves across parentheses" {
    var app = try makeTestApp(std.testing.allocator, "(abc)");
    defer app.deinit();
    app.activeBuffer().cursor = .{ .row = 0, .col = 0 };

    try app.performNormalAction(.jump_matching_character, 1);
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.col);
}

test "declaration jumps search current word in the buffer" {
    var app = try makeTestApp(std.testing.allocator, "foo\nbar foo");
    defer app.deinit();
    app.activeBuffer().cursor = .{ .row = 1, .col = 4 };

    try app.performNormalAction(.jump_global_declaration, 1);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
}

test "normal binding table exposes the implemented prefixes" {
    try std.testing.expect(normalActionHasPrefix("g"));
    try std.testing.expect(normalActionHasPrefix("z"));
    try std.testing.expect(normalActionFor("gd") != null);
    try std.testing.expect(normalActionFor("gf") != null);
    try std.testing.expect(normalActionFor("gx") != null);
    try std.testing.expect(normalActionFor("d0") != null);
    try std.testing.expect(normalActionFor("(") != null);
    try std.testing.expect(normalActionFor(")") != null);
    try std.testing.expect(normalActionFor("n") != null);
    try std.testing.expect(normalActionFor("N") != null);
    try std.testing.expect(normalActionFor("K") != null);
}

test "exact multi-key bindings execute once their sequence is complete" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo");
    defer app.deinit();

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "gg");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "dd");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().lineCount());
    try std.testing.expectEqualStrings("two", app.activeBuffer().currentLine());
}

test "cursor motion keys move within the buffer" {
    var app = try makeTestApp(std.testing.allocator, "  alpha\nbeta  \n  omega");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "l");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "h");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "j");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "k");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    setCursor(&app, 0, 4);
    try pressNormalKeys(&app, "0");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "^");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "$");
    try std.testing.expectEqual(@as(usize, 7), app.activeBuffer().cursor.col);

    setCursor(&app, 1, 1);
    try pressNormalKeys(&app, "g_");
    try std.testing.expectEqual(@as(usize, 3), app.activeBuffer().cursor.col);

    setCursor(&app, 2, 5);
    try pressNormalKeys(&app, "gg");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "G");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "M");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
}

test "sentence motions marks and bol delete are wired" {
    var app = try makeTestApp(std.testing.allocator, "one. two. three\nalpha beta");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, ")");
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "(");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);

    setCursor(&app, 1, 5);
    try pressNormalKeys(&app, "ma");
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "`a");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "'a");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);

    setCursor(&app, 1, 5);
    try pressNormalKeys(&app, "d0");
    try std.testing.expectEqualStrings(" beta", app.activeBuffer().currentLine());
}

test "history and previous buffer navigation keys work" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "j");
    try pressNormalKeys(&app, "k");
    try pressNormalKeys(&app, "\x0f");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "\x0f");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    var extra = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
    errdefer extra.deinit();
    try extra.setText("other");
    try app.buffers.append(extra);
    app.active_index = 1;
    app.previous_active_index = 0;
    try pressNormalKeys(&app, "\x1e");
    try std.testing.expectEqual(@as(usize, 0), app.active_index);
}

test "word motion keys follow word boundaries" {
    var app = try makeTestApp(std.testing.allocator, "foo,bar baz");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "w");
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "W");
    try std.testing.expectEqual(@as(usize, 8), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "e");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "E");
    try std.testing.expectEqual(@as(usize, 6), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 8);
    try pressNormalKeys(&app, "b");
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 8);
    try pressNormalKeys(&app, "B");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
}

test "find keys repeat forward and backward" {
    var app = try makeTestApp(std.testing.allocator, "abcabc");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "fc");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, ";");
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, ",");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
}

test "yank paste and registers work together" {
    var app = try makeTestApp(std.testing.allocator, "alpha\nbeta");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "yy");
    try std.testing.expectEqualStrings("alpha", app.registers.get('"').?);
    try std.testing.expectEqualStrings("alpha", app.registers.get('0').?);

    setCursor(&app, 1, 4);
    try pressNormalKeys(&app, "p");
    try std.testing.expectEqualStrings("betaalpha", app.activeBuffer().currentLine());
}

test "delete and undo redo keys restore text" {
    var app = try makeTestApp(std.testing.allocator, "abc");
    defer app.deinit();

    setCursor(&app, 0, 1);
    try pressNormalKeys(&app, "x");
    try std.testing.expectEqualStrings("ac", app.activeBuffer().currentLine());
    try pressNormalKeys(&app, "u");
    try std.testing.expectEqualStrings("abc", app.activeBuffer().currentLine());
    try pressNormalKeys(&app, "\x12");
    try std.testing.expectEqualStrings("ac", app.activeBuffer().currentLine());
}

test "open split and quit commands update editor state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("one.txt", .{});
        defer f.close();
        try f.writeAll("one");
    }
    {
        var f = try tmp.dir.createFile("two.txt", .{});
        defer f.close();
        try f.writeAll("two");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":open one.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":split two.txt");
    try app.executeCommand();
    try std.testing.expect(app.split_index != null);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "x");

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":q");
    try app.executeCommand();
    try std.testing.expectEqual(false, app.should_quit);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":q!");
    try app.executeCommand();
    try std.testing.expect(app.should_quit);
}

test "tab navigation keys cycle through buffers" {
    var app = try makeTestApp(std.testing.allocator, "one");
    defer app.deinit();

    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("two");
        try app.buffers.append(buf);
    }
    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("three");
        try app.buffers.append(buf);
    }

    app.active_index = 0;
    try pressNormalKeys(&app, "gt");
    try std.testing.expectEqual(@as(usize, 1), app.active_index);
    try pressNormalKeys(&app, "gt");
    try std.testing.expectEqual(@as(usize, 2), app.active_index);
    try pressNormalKeys(&app, "gT");
    try std.testing.expectEqual(@as(usize, 1), app.active_index);
}

test "tab commands create, move, and keep only the current buffer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("one.txt", .{});
        defer f.close();
        try f.writeAll("one");
    }
    {
        var f = try tmp.dir.createFile("two.txt", .{});
        defer f.close();
        try f.writeAll("two");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabnew one.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabnew two.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 3), app.buffers.items.len);
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabmove 0");
    try app.executeCommand();
    try std.testing.expectEqualStrings("two.txt", app.buffers.items[0].path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabonly");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.buffers.items.len);
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);
}

test "window split keys create and cycle a split" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    try std.testing.expect(app.split_index != null);
    try std.testing.expectEqual(.right, app.split_focus);
    try std.testing.expectEqualStrings("left", app.activeBuffer().currentLine());

    try pressNormalKeys(&app, "\x17w");
    try std.testing.expectEqual(.left, app.split_focus);

    try pressNormalKeys(&app, "\x17w");
    try std.testing.expectEqual(.right, app.split_focus);

    try pressNormalKeys(&app, "\x17h");
    try std.testing.expectEqual(.left, app.split_focus);
    try pressNormalKeys(&app, "\x17l");
    try std.testing.expectEqual(.right, app.split_focus);
    try pressNormalKeys(&app, "\x17k");
    try std.testing.expectEqual(.left, app.split_focus);
    try pressNormalKeys(&app, "\x17j");
    try std.testing.expectEqual(.right, app.split_focus);
}

test "Ctrl+wN opens a new empty window" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17n");
    try std.testing.expect(app.split_index != null);
    try std.testing.expectEqual(.right, app.split_focus);
    try std.testing.expectEqualStrings("", app.activeBuffer().currentLine());
    try std.testing.expectEqualStrings("new window", app.status.items);
}

test "Ctrl+w resize keys adjust the split safely" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    app.config.split_ratio = 50;

    try pressNormalKeys(&app, "\x17>");
    try std.testing.expectEqual(@as(usize, 60), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17<");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17+");
    try std.testing.expectEqual(@as(usize, 60), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17-");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);

    try pressNormalKeys(&app, "\x17|");
    try std.testing.expectEqual(@as(usize, 100), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17_");
    try std.testing.expectEqual(@as(usize, 100), app.config.split_ratio);

    try pressNormalKeys(&app, "\x17=");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);
    try std.testing.expectEqualStrings("windows equalized", app.status.items);
}

test "window exchange and close keys operate on the split" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    try app.activeBuffer().replaceRangeWithText(.{ .row = 0, .col = 0 }, .{ .row = 0, .col = 4 }, "right");

    try pressNormalKeys(&app, "\x17x");
    try std.testing.expectEqualStrings("windows exchanged", app.status.items);

    try pressNormalKeys(&app, "\x17q");
    try std.testing.expect(app.split_index == null);
    try std.testing.expectEqual(@as(usize, 1), app.buffers.items.len);
}

test "Ctrl+wT moves the split into a tab" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    try pressNormalKeys(&app, "\x17T");
    try std.testing.expect(app.split_index == null);
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
    try std.testing.expectEqualStrings("split moved to tab", app.status.items);
}

test "buffer commands open, navigate, list, and delete buffers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("one.txt", .{});
        defer f.close();
        try f.writeAll("one");
    }
    {
        var f = try tmp.dir.createFile("two.txt", .{});
        defer f.close();
        try f.writeAll("two");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":edit one.txt");
    try app.executeCommand();
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":open two.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 3), app.buffers.items.len);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":bn");
    try app.executeCommand();
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":bp");
    try app.executeCommand();
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":buffer 3");
    try app.executeCommand();
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":buffers");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1:") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":bd");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
}

test "split aliases duplicate or open paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("split.txt", .{});
        defer f.close();
        try f.writeAll("split");
    }

    var app = try makeTestApp(std.testing.allocator, "base");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":sp");
    try app.executeCommand();
    try std.testing.expect(app.split_index != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":vs split.txt");
    try app.executeCommand();
    try std.testing.expect(app.split_index != null);
    try std.testing.expectEqualStrings("split.txt", app.activeBuffer().path.?);
}

test "quickfix search collects matches and navigates them" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("qf.txt", .{});
        defer f.close();
        try f.writeAll("alpha\nneedle\nbeta needle\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":vimgrep /needle/");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.quickfix_list.items.len);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1/2") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":cn");
    try app.executeCommand();
    try std.testing.expectEqualStrings("qf.txt", app.activeBuffer().path.?);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.row);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":cp");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 0), app.quickfix_index);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":ccl");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 0), app.quickfix_list.items.len);
}

test "fold commands create and manipulate paragraph folds" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\n\nthree\nfour");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "zf");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().folds.items.len);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().folds.items[0].start_row);
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().folds.items[0].end_row);
    try std.testing.expect(app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "za");
    try std.testing.expect(!app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "zc");
    try std.testing.expect(app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "zo");
    try std.testing.expect(!app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "zd");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().folds.items.len);

    setCursor(&app, 3, 0);
    try pressNormalKeys(&app, "zf");
    try pressNormalKeys(&app, "zi");
    try std.testing.expect(!app.activeBuffer().fold_enabled);
    try pressNormalKeys(&app, "zi");
    try std.testing.expect(app.activeBuffer().fold_enabled);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "zE");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().folds.items.len);
    try std.testing.expectEqualStrings("all folds deleted", app.status.items);
}

test "window equalize and insert ctrl-w behave safely" {
    var app = try makeTestApp(std.testing.allocator, "");
    defer app.deinit();

    var extra = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
    errdefer extra.deinit();
    try extra.setText("pane");
    try app.buffers.append(extra);
    app.split_index = 1;
    app.split_focus = .left;
    app.config.split_ratio = 73;

    try pressNormalKeys(&app, "\x17=");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);
    try std.testing.expectEqualStrings("windows equalized", app.status.items);

    app.mode = .insert;
    try app.handleByte('a', std.fs.File.stdin());
    try app.handleByte('b', std.fs.File.stdin());
    try app.handleByte('c', std.fs.File.stdin());
    try app.handleByte(' ', std.fs.File.stdin());
    try app.handleByte('d', std.fs.File.stdin());
    try app.handleByte('e', std.fs.File.stdin());
    try app.handleByte('f', std.fs.File.stdin());
    try app.handleByte(0x17, std.fs.File.stdin());
    const line = app.activeBuffer().currentLine();
    try std.testing.expectEqualStrings("abc ", line);
}

test "diff commands copy lines and manage diff mode" {
    var app = try makeTestApp(std.testing.allocator, "left\nsame");
    defer app.deinit();

    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("right\nsame");
        try app.buffers.append(buf);
    }

    app.active_index = 0;
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diffthis");
    try app.executeCommand();
    try std.testing.expect(app.diff_mode);
    try std.testing.expect(app.diff_peer_index != null);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "do");
    try std.testing.expectEqualStrings("right", app.activeBuffer().lines.items[0]);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "dp");
    try std.testing.expectEqualStrings("right", app.buffers.items[1].lines.items[0]);

    try pressNormalKeys(&app, "]c");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    try pressNormalKeys(&app, "[c");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diffupdate");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "diff on") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diffoff");
    try app.executeCommand();
    try std.testing.expect(!app.diff_mode);
}

test "visual mode yank and delete use the selected region" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleNormalByte('l');
    try app.handleNormalByte('l');
    try app.handleNormalByte('y');
    try std.testing.expectEqualStrings("al", app.registers.get('"').?);
    try std.testing.expectEqual(false, app.mode == .visual);

    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleNormalByte('l');
    try app.handleNormalByte('d');
    try std.testing.expectEqualStrings("pha beta", app.activeBuffer().currentLine());
}

test "visual mode can switch shape and restore the previous area" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleVisualByte('V');
    try std.testing.expectEqual(Mode.visual, app.mode);
    try std.testing.expectEqual(App.VisualMode.line, app.visual_mode);

    try app.handleVisualByte('y');
    try std.testing.expectEqual(Mode.normal, app.mode);

    try pressNormalKeys(&app, "gv");
    try std.testing.expectEqual(Mode.visual, app.mode);
    try std.testing.expectEqual(App.VisualMode.line, app.visual_mode);
    try std.testing.expect(app.visual_anchor != null);
}

test "visual control keys toggle select mode and exit visual mode" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleVisualByte(0x07);
    try std.testing.expect(app.visual_select_mode);
    try app.handleVisualByte(0x0f);
    try std.testing.expect(!app.visual_select_mode);
    try std.testing.expectEqualStrings("visual mode", app.status.items);

    try app.handleVisualByte(0x1c);
    try app.handleVisualByte('n');
    try std.testing.expectEqual(Mode.normal, app.mode);

    try app.handleNormalByte('v');
    try app.handleVisualByte(0x1c);
    try app.handleVisualByte('g');
    try std.testing.expectEqual(Mode.normal, app.mode);

    try app.handleNormalByte('v');
    try app.handleVisualByte(0x07);
    try app.handleVisualByte(0x0f);
    try std.testing.expect(!app.visual_select_mode);
    try app.handleVisualByte('l');
    try std.testing.expect(app.visual_select_mode);
    try std.testing.expectEqual(Mode.visual, app.mode);
}

test "visual binding checklist tracks verified and todo entries" {
    var verified: usize = 0;
    var todo: usize = 0;
    for (visual_binding_checklist) |entry| {
        switch (entry.status) {
            .verified => verified += 1,
            .todo => todo += 1,
        }
    }
    try std.testing.expectEqual(visual_binding_checklist.len, verified);
    try std.testing.expectEqual(@as(usize, 0), todo);
}

test "visual mode exits and shape toggles are table-driven" {
    const exit_cases = [_][]const u8{
        "\x1cn",
        "\x1cg",
        "\x03",
        "\x1b",
    };
    for (exit_cases) |bytes| {
        var app = try makeTestApp(std.testing.allocator, "alpha beta");
        defer app.deinit();
        try expectVisualExit(&app, bytes);
    }

    const toggle_cases = [_]struct {
        initial: App.VisualMode,
        bytes: []const u8,
        app_mode: Mode,
        expected: App.VisualMode,
        select_mode: bool,
    }{
        .{ .initial = .character, .bytes = "v", .app_mode = .normal, .expected = .none, .select_mode = false },
        .{ .initial = .character, .bytes = "V", .app_mode = .visual, .expected = .line, .select_mode = false },
        .{ .initial = .character, .bytes = "\x16", .app_mode = .visual, .expected = .block, .select_mode = false },
        .{ .initial = .line, .bytes = "v", .app_mode = .visual, .expected = .character, .select_mode = false },
        .{ .initial = .line, .bytes = "V", .app_mode = .normal, .expected = .none, .select_mode = false },
        .{ .initial = .block, .bytes = "\x16", .app_mode = .normal, .expected = .none, .select_mode = false },
        .{ .initial = .character, .bytes = "\x07", .app_mode = .visual, .expected = .character, .select_mode = true },
        .{ .initial = .character, .bytes = "\x07\x07", .app_mode = .visual, .expected = .character, .select_mode = false },
    };
    for (toggle_cases) |case| {
        var app = try makeTestApp(std.testing.allocator, "alpha beta");
        defer app.deinit();
        try expectVisualMode(&app, case.initial, case.bytes, case.app_mode, case.expected, case.select_mode);
    }
}

fn expectVisualTextObjectYank(text: []const u8, row: usize, col: usize, keys: []const u8, expected: []const u8) !void {
    var app = try makeTestApp(std.testing.allocator, text);
    defer app.deinit();
    setCursor(&app, row, col);
    try app.handleNormalByte('v');
    try runVisualBytes(&app, keys);
    try app.handleVisualByte('y');
    try std.testing.expectEqualStrings(expected, app.registers.get('"').?);
}

test "visual text objects cover words and WORDs" {
    try expectVisualTextObjectYank("hello world", 0, 0, "aw", "hello ");
    try expectVisualTextObjectYank("hello world", 0, 0, "iw", "hello");
    try expectVisualTextObjectYank("hello world", 0, 0, "aW", "hello world");
    try expectVisualTextObjectYank("hello world", 0, 0, "iW", "hello world");
}

test "visual text objects cover paired delimiters" {
    try expectVisualTextObjectYank("(abc)", 0, 0, "ab", "(abc)");
    try expectVisualTextObjectYank("(abc)", 0, 0, "ib", "abc");
    try expectVisualTextObjectYank("(abc)", 0, 0, "a(", "(abc)");
    try expectVisualTextObjectYank("(abc)", 0, 0, "i(", "abc");
    try expectVisualTextObjectYank("(abc)", 0, 0, "a)", "(abc)");
    try expectVisualTextObjectYank("(abc)", 0, 0, "i)", "abc");
    try expectVisualTextObjectYank("[abc]", 0, 0, "a[", "[abc]");
    try expectVisualTextObjectYank("[abc]", 0, 0, "i[", "abc");
    try expectVisualTextObjectYank("[abc]", 0, 0, "a]", "[abc]");
    try expectVisualTextObjectYank("[abc]", 0, 0, "i]", "abc");
    try expectVisualTextObjectYank("{abc}", 0, 0, "aB", "{abc}");
    try expectVisualTextObjectYank("{abc}", 0, 0, "iB", "abc");
    try expectVisualTextObjectYank("{abc}", 0, 0, "a{", "{abc}");
    try expectVisualTextObjectYank("{abc}", 0, 0, "i{", "abc");
    try expectVisualTextObjectYank("{abc}", 0, 0, "a}", "{abc}");
    try expectVisualTextObjectYank("{abc}", 0, 0, "i}", "abc");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "a<", "<tag>");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "i<", "tag");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "a>", "<tag>");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "i>", "tag");
}

test "visual text objects cover quotes and backticks" {
    try expectVisualTextObjectYank("\"abc\"", 0, 0, "a\"", "\"abc\"");
    try expectVisualTextObjectYank("\"abc\"", 0, 0, "i\"", "abc");
    try expectVisualTextObjectYank("'abc'", 0, 0, "a'", "'abc'");
    try expectVisualTextObjectYank("'abc'", 0, 0, "i'", "abc");
    try expectVisualTextObjectYank("`abc`", 0, 0, "a`", "`abc`");
    try expectVisualTextObjectYank("`abc`", 0, 0, "i`", "abc");
}

test "visual text objects cover paragraphs sentences and tags" {
    try expectVisualTextObjectYank("alpha\nbeta\n\nomega", 1, 0, "ap", "alpha\nbeta");
    try expectVisualTextObjectYank("alpha\nbeta\n\nomega", 1, 0, "ip", "alpha\nbeta");
    try expectVisualTextObjectYank("One. Two!", 0, 0, "as", "One.");
    try expectVisualTextObjectYank("One. Two!", 0, 0, "is", "One.");
    try expectVisualTextObjectYank("<p>body</p>", 0, 0, "at", "<p>");
    try expectVisualTextObjectYank("<p>body</p>", 0, 0, "it", "p");
}

test "visual mode can adjust numbers inside the selection" {
    var app = try makeTestApp(std.testing.allocator, "value 10");
    defer app.deinit();

    setCursor(&app, 0, 6);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte(0x01);
    try std.testing.expectEqualStrings("value 11", app.activeBuffer().currentLine());
}

test "visual text objects expand to the requested word" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    setCursor(&app, 0, 1);
    try app.handleNormalByte('v');
    try app.handleVisualByte('i');
    try app.handleVisualByte('w');
    try app.handleVisualByte('y');
    try std.testing.expectEqualStrings("hello", app.registers.get('"').?);
}

test "visual ctrl-] uses the highlighted tag text" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta alpha");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte(0x1d);
    try std.testing.expectEqual(Mode.normal, app.mode);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 11), app.activeBuffer().cursor.col);
}

test "visual block insert prefixes every selected line" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('I');
    try app.handleByte('X', std.fs.File.stdin());
    try app.handleByte(0x1b, std.fs.File.stdin());
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Xab\nXcd", text);
}

test "visual block append applies to every selected line" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('A');
    try app.handleByte('X', std.fs.File.stdin());
    try app.handleByte(0x1b, std.fs.File.stdin());
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("aXb\ncXd", text);
}

test "visual block yank and delete operate row by row" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('y');
    try std.testing.expectEqualStrings("a\nc", app.registers.get('"').?);

    setCursor(&app, 0, 0);
    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('d');
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("b\nd", text);
}

test "visual block filter runs per line" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.runVisualFilter("tr a-z A-Z");
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Ab\nCd", text);
}

test "visual block paste inserts each register line on each row" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.registers.set('"', "X\nY");
    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('p');
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Xb\nYd", text);
}

test "visual filter commands replace the highlighted text" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('!');
    try app.handleByte('t', std.fs.File.stdin());
    try app.handleByte('r', std.fs.File.stdin());
    try app.handleByte(' ', std.fs.File.stdin());
    try app.handleByte('a', std.fs.File.stdin());
    try app.handleByte('-', std.fs.File.stdin());
    try app.handleByte('z', std.fs.File.stdin());
    try app.handleByte(' ', std.fs.File.stdin());
    try app.handleByte('A', std.fs.File.stdin());
    try app.handleByte('-', std.fs.File.stdin());
    try app.handleByte('Z', std.fs.File.stdin());
    try app.handleByte('\n', std.fs.File.stdin());
    try std.testing.expectEqualStrings("ALPHA beta", app.activeBuffer().currentLine());
}

test "search and visual highlights compute the right spans" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta\ngamma");
    defer app.deinit();

    app.search_highlight = try std.testing.allocator.dupe(u8, "be");
    defer if (app.search_highlight) |needle| std.testing.allocator.free(needle);
    app.search_preview_highlight = try std.testing.allocator.dupe(u8, "ha");
    defer if (app.search_preview_highlight) |needle| std.testing.allocator.free(needle);
    const search_range = app.nextSearchRange("alpha beta", "be", 0).?;
    try std.testing.expectEqual(@as(usize, 6), search_range.start);
    try std.testing.expectEqual(@as(usize, 8), search_range.end);
    app.mode = .search;
    try std.testing.expectEqualStrings("ha", app.activeSearchHighlight(true).?);
    app.clearSearchPreview();
    app.mode = .normal;
    try std.testing.expectEqualStrings("be", app.activeSearchHighlight(true).?);

    app.visual_mode = .character;
    app.visual_anchor = .{ .row = 0, .col = 1 };
    setCursor(&app, 0, 4);
    const char_selection = app.visualSelection().?;
    const char_range = app.visualRangeForRow(char_selection, 0, 5).?;
    try std.testing.expectEqual(@as(usize, 1), char_range.start);
    try std.testing.expectEqual(@as(usize, 4), char_range.end);

    app.visual_mode = .line;
    const line_selection = app.visualSelection().?;
    const line_range = app.visualRangeForRow(line_selection, 1, 5).?;
    try std.testing.expectEqual(@as(usize, 0), line_range.start);
    try std.testing.expectEqual(@as(usize, 5), line_range.end);
}

test "status and prompt bars compose their text" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.allocator.free(app.config.status_bar_icon);
    app.config.status_bar_icon = try app.config.allocator.dupe(u8, "N");
    app.config.allocator.free(app.config.status_bar_insert_icon);
    app.config.status_bar_insert_icon = try app.config.allocator.dupe(u8, "I");
    app.config.allocator.free(app.config.status_bar_visual_icon);
    app.config.status_bar_visual_icon = try app.config.allocator.dupe(u8, "V");
    try app.setStatus("ready");
    try app.plugin_host.setStatus("plugins idle");
    try app.buffers.append(try buffer_mod.Buffer.initEmpty(std.testing.allocator));
    app.split_index = 1;
    app.split_focus = .left;

    const status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(status);
    try std.testing.expectEqualStrings("N NORMAL | 󰈙 alpha [L] | 󰞋 ready │ 󰒓 plugins idle │  1:1 │ 100%", status);

    app.mode = .insert;
    const insert_status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(insert_status);
    try std.testing.expect(std.mem.indexOf(u8, insert_status, "I INSERT") != null);

    app.mode = .visual;
    const visual_status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(visual_status);
    try std.testing.expect(std.mem.indexOf(u8, visual_status, "V VISUAL") != null);

    app.mode = .command;
    try app.command_buffer.appendSlice("w");
    const command = try app.promptBarText(std.testing.allocator);
    defer std.testing.allocator.free(command);
    try std.testing.expectEqualStrings(":w", command);

    app.mode = .search;
    app.search_buffer.clearRetainingCapacity();
    try app.search_buffer.appendSlice("needle");
    const search = try app.promptBarText(std.testing.allocator);
    defer std.testing.allocator.free(search);
    try std.testing.expectEqualStrings("/needle", search);
}

test "status bar right side trims to keep a single line on narrow widths" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.setStatus("ready");
    try app.plugin_host.setStatus("plugins idle");
    try app.buffers.append(try buffer_mod.Buffer.initEmpty(std.testing.allocator));

    const status = try app.statusBarRightText(std.testing.allocator, 16);
    defer std.testing.allocator.free(status);
    try std.testing.expectEqualStrings("L/N 1:1 │ 100%", status);
}

test "default status bar icon uses nerd font glyph" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.allocator.free(app.config.status_bar_icon);
    app.config.status_bar_icon = try app.config.allocator.dupe(u8, "default");

    const icon = modeIconText(&app, .normal);
    try std.testing.expectEqualStrings("\u{e795}", icon);

    try app.setStatus("ready");
    try app.plugin_host.setStatus("plugins idle");
    try app.buffers.append(try buffer_mod.Buffer.initEmpty(std.testing.allocator));
    app.split_index = 1;
    app.split_focus = .left;
    const status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(status);
    try std.testing.expect(std.mem.startsWith(u8, status, "\u{e795} NORMAL"));
}

test "theme resolution keeps beam default and recognizes nvchad" {
    const beam_theme = Theme.resolve("beam", "terminal", false, 100);
    const fallback_theme = Theme.resolve("unknown", "#101010", true, 80);
    const nvchad_theme = Theme.resolve("nvchad", "81", false, 100);
    try std.testing.expectEqualStrings("beam", beam_theme.name);
    try std.testing.expectEqualStrings("beam", fallback_theme.name);
    try std.testing.expectEqualStrings("nvchad", nvchad_theme.name);
    try std.testing.expect(beam_theme.accent != nvchad_theme.accent);
    try std.testing.expect(beam_theme.content_bg == null);
    try std.testing.expect(fallback_theme.content_bg != null);
}

test "shift and case commands edit the current line and word" {
    var app = try makeTestApp(std.testing.allocator, "alpha\nMiXeD");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, ">");
    try std.testing.expectEqualStrings("    alpha", app.activeBuffer().lines.items[0]);
    try pressNormalKeys(&app, "<");
    try std.testing.expectEqualStrings("alpha", app.activeBuffer().lines.items[0]);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "~");
    try std.testing.expectEqualStrings("Alpha", app.activeBuffer().lines.items[0]);

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "gu");
    try std.testing.expectEqualStrings("mixed", app.activeBuffer().lines.items[1]);

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "gU");
    try std.testing.expectEqualStrings("MIXED", app.activeBuffer().lines.items[1]);

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "g~");
    try std.testing.expectEqualStrings("mixed", app.activeBuffer().lines.items[1]);
}

test "viewport commands update scroll position" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree\nfour\nfive");
    defer app.deinit();

    app.last_render_height = 3;
    setCursor(&app, 3, 0);
    try pressNormalKeys(&app, "zt");
    try std.testing.expectEqual(@as(usize, 3), app.activeBuffer().scroll_row);
    try pressNormalKeys(&app, "zb");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().scroll_row);
    try pressNormalKeys(&app, "zz");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().scroll_row);
}

test "macro record and playback replays recorded keys" {
    var app = try makeTestApp(std.testing.allocator, "abc");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "qalqa");
    try std.testing.expectEqual(@as(?u8, null), app.macro_recording);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "@a");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.col);
}

test "jump and change commands populate their history lists" {
    var app = try makeTestApp(std.testing.allocator, "abc\ndef");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "l");
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":jumps");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1:1") != null);

    setCursor(&app, 0, 1);
    try pressNormalKeys(&app, "x");
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":changes");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1:2") != null);
}

test "editor command aliases" {
    try std.testing.expect(App.matchesCommand("help", &.{ "h", "help" }, ":help"));
    try std.testing.expect(App.matchesCommand("wq", &.{ "wq", "x" }, ":wq"));
    try std.testing.expect(App.matchesCommand("q!", &.{"q!"}, ":q!"));
}

test "normal binding table" {
    try std.testing.expect(normalActionHasPrefix("g"));
    try std.testing.expect(normalActionHasPrefix("c"));
    try std.testing.expect(normalActionFor("gg") != null);
    try std.testing.expect(normalActionFor("gt") != null);
    try std.testing.expect(normalActionFor("gT") != null);
    try std.testing.expect(normalActionFor("\x17s") != null);
    try std.testing.expect(normalActionFor("\x17=") != null);
    try std.testing.expect(normalActionFor("\x17w") != null);
    try std.testing.expect(normalActionFor("\x17T") != null);
    try std.testing.expect(normalActionFor("zf") != null);
    try std.testing.expect(normalActionFor("zE") != null);
    try std.testing.expect(normalActionFor("do") != null);
    try std.testing.expect(normalActionFor("dp") != null);
    try std.testing.expect(normalActionFor("]c") != null);
    try std.testing.expect(normalActionFor("[c") != null);
    try std.testing.expect(normalActionFor("ciw") != null);
    try std.testing.expect(normalActionFor("K") != null);
}
