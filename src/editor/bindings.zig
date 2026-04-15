const std = @import("std");
const config_mod = @import("../config.zig");

pub const NormalAction = enum {
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
    replace_mode,
    substitute_char,
    substitute_line,
    insert_before,
    insert_at_bol,
    append_after,
    append_eol,
    open_below,
    open_above,
    insert_line_below,
    insert_line_above,
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
    close_prompt,
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

pub const NormalBinding = struct {
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
    .{ .sequence = "R", .action = .replace_mode, .help = "enter Replace mode" },
    .{ .sequence = "gR", .action = .replace_mode, .help = "enter Replace mode" },
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

pub fn normalActionFromName(name: []const u8) ?NormalAction {
    return std.meta.stringToEnum(NormalAction, name);
}

fn blankLineBindingFor(sequence: []const u8, leader: []const u8) ?NormalAction {
    if (leader.len == 0) return null;
    if (sequence.len == leader.len + 1 and sequence[0] == ']' and std.mem.eql(u8, sequence[1..], leader)) {
        return .insert_line_below;
    }
    if (sequence.len == leader.len + 1 and sequence[0] == '[' and std.mem.eql(u8, sequence[1..], leader)) {
        return .insert_line_above;
    }
    return null;
}

fn blankLineBindingHasPrefix(prefix: []const u8, leader: []const u8) bool {
    if (leader.len == 0 or prefix.len == 0) return false;
    if (prefix[0] != ']' and prefix[0] != '[') return false;
    if (prefix.len == 1) return true;
    if (prefix.len == leader.len + 1) return false;
    const leader_prefix_len = prefix.len - 1;
    if (leader_prefix_len > leader.len) return false;
    return std.mem.eql(u8, prefix[1..], leader[0..leader_prefix_len]);
}

fn leaderBindingFor(sequence: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) ?NormalAction {
    if (leader.len == 0 or sequence.len < leader.len) return null;
    if (!std.mem.eql(u8, sequence[0..leader.len], leader)) return null;
    const suffix = sequence[leader.len..];
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.sequence, suffix)) {
            if (normalActionFromName(binding.action)) |action| return action;
        }
    }
    return null;
}

fn leaderBindingHasPrefix(prefix: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) bool {
    if (leader.len == 0 or prefix.len == 0) return false;
    if (prefix.len < leader.len) return std.mem.startsWith(u8, leader, prefix);
    if (!std.mem.eql(u8, prefix[0..leader.len], leader)) return false;
    const suffix = prefix[leader.len..];
    if (suffix.len == 0) return bindings.len > 0;
    for (bindings) |binding| {
        if (binding.sequence.len > suffix.len and std.mem.startsWith(u8, binding.sequence, suffix)) return true;
    }
    return false;
}

fn normalActionHelpForAction(action: NormalAction) ?[]const u8 {
    for (normal_bindings) |binding| {
        if (binding.action == action) return binding.help;
    }
    return switch (action) {
        .insert_line_below => "add a blank line below without entering insert mode",
        .insert_line_above => "add a blank line above without entering insert mode",
        .close_prompt => "confirm closing the current split, tab, or buffer",
        else => null,
    };
}

pub fn normalActionHelp(sequence: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) ?[]const u8 {
    if (blankLineBindingFor(sequence, leader)) |action| {
        return normalActionHelpForAction(action);
    }
    if (leaderBindingFor(sequence, leader, bindings)) |action| {
        return normalActionHelpForAction(action);
    }
    for (normal_bindings) |binding| {
        if (std.mem.eql(u8, binding.sequence, sequence)) return binding.help;
    }
    return null;
}

pub fn normalActionHasPrefix(prefix: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) bool {
    if (blankLineBindingHasPrefix(prefix, leader)) return true;
    if (leaderBindingHasPrefix(prefix, leader, bindings)) return true;
    for (normal_bindings) |binding| {
        if (binding.sequence.len > prefix.len and std.mem.startsWith(u8, binding.sequence, prefix)) return true;
    }
    return false;
}

pub fn normalActionFor(sequence: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) ?NormalAction {
    if (blankLineBindingFor(sequence, leader)) |action| return action;
    if (leaderBindingFor(sequence, leader, bindings)) |action| return action;
    for (normal_bindings) |binding| {
        if (std.mem.eql(u8, binding.sequence, sequence)) return binding.action;
    }
    return null;
}

pub fn actionIsEditing(action: NormalAction) bool {
    return switch (action) {
        .delete_char, .replace_char, .replace_mode, .substitute_char, .substitute_line, .insert_before, .insert_at_bol, .append_after, .append_eol, .open_below, .open_above, .insert_line_below, .insert_line_above, .delete_line, .yank_line, .paste_after, .paste_before, .paste_after_keep_cursor, .paste_before_keep_cursor, .delete_word, .yank_word, .delete_to_eol, .change_word, .change_line, .change_to_eol, .join_line_space, .join_line_nospace, .indent_line, .dedent_line, .toggle_case_char, .toggle_case_word, .lowercase_word, .uppercase_word, .diff_get, .diff_put, .visual_yank, .visual_delete => true,
        else => false,
    };
}

test "normal binding table exposes the implemented prefixes" {
    var cfg = try config_mod.Config.init(std.testing.allocator);
    defer cfg.deinit();

    try std.testing.expect(normalActionHasPrefix("g", cfg.keymap.leader, cfg.keymap.leader_bindings.items));
    try std.testing.expect(normalActionHasPrefix("c", cfg.keymap.leader, cfg.keymap.leader_bindings.items));
    try std.testing.expect(normalActionFor("gg", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("gt", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("gT", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("\x17s", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("\x17=", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("\x17w", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("\x17T", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("zf", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("zE", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("do", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("dp", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("]c", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("[c", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("]:", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("[:", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionHasPrefix("]", cfg.keymap.leader, cfg.keymap.leader_bindings.items));
    try std.testing.expect(normalActionHasPrefix("[", cfg.keymap.leader, cfg.keymap.leader_bindings.items));
    try std.testing.expect(normalActionFor("ciw", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("K", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
}
