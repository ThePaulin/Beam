const std = @import("std");

pub const Diagnostics = struct {
    line: usize = 0,
    column: usize = 0,
    message: []const u8 = "",
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    tab_width: usize = 4,
    show_line_numbers: bool = true,
    status_bar: bool = true,
    status_bar_icon: []u8,
    status_bar_insert_icon: []u8,
    status_bar_visual_icon: []u8,
    split_ratio: usize = 50,
    background_color: []u8,
    blur: bool = false,
    opacity: usize = 100,
    keywordprg: []u8,
    equalprg: []u8,
    theme: []u8,
    keymap: Keymap,
    builtins: Builtins,

    pub const Keymap = struct {
        pub const LeaderBinding = struct {
            sequence: []u8,
            action: []u8,
        };

        leader: []u8,
        help: []u8,
        save: []u8,
        save_as: []u8,
        close: []u8,
        terminal: []u8,
        quit: []u8,
        force_quit: []u8,
        split: []u8,
        open: []u8,
        reload: []u8,
        registers: []u8,
        leader_bindings: std.array_list.Managed(LeaderBinding),
    };

    pub const Builtins = struct {
        enabled: std.array_list.Managed([]u8),
    };

    pub fn init(allocator: std.mem.Allocator) !Config {
        return .{
            .allocator = allocator,
            .status_bar_icon = try allocator.dupe(u8, "\u{e795}"),
            .status_bar_insert_icon = try allocator.dupe(u8, "󰘶"),
            .status_bar_visual_icon = try allocator.dupe(u8, "󰒉"),
            .background_color = try allocator.dupe(u8, "terminal"),
            .keywordprg = try allocator.dupe(u8, "man"),
            .equalprg = try allocator.dupe(u8, "cat"),
            .theme = try allocator.dupe(u8, "beam"),
            .keymap = .{
                .leader = try allocator.dupe(u8, ":"),
                .help = try allocator.dupe(u8, ":help"),
                .save = try allocator.dupe(u8, ":w"),
                .save_as = try allocator.dupe(u8, ":saveas"),
                .close = try allocator.dupe(u8, ":close"),
                .terminal = try allocator.dupe(u8, ":terminal"),
                .quit = try allocator.dupe(u8, ":q"),
                .force_quit = try allocator.dupe(u8, ":q!"),
                .split = try allocator.dupe(u8, ":split"),
                .open = try allocator.dupe(u8, ":open"),
                .reload = try allocator.dupe(u8, ":reload-config"),
                .registers = try allocator.dupe(u8, ":registers"),
                .leader_bindings = std.array_list.Managed(Keymap.LeaderBinding).init(allocator),
            },
            .builtins = .{
                .enabled = std.array_list.Managed([]u8).init(allocator),
            },
        };
    }

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.background_color);
        self.allocator.free(self.status_bar_icon);
        self.allocator.free(self.status_bar_insert_icon);
        self.allocator.free(self.status_bar_visual_icon);
        self.allocator.free(self.theme);
        self.allocator.free(self.keywordprg);
        self.allocator.free(self.equalprg);
        self.allocator.free(self.keymap.leader);
        self.allocator.free(self.keymap.help);
        self.allocator.free(self.keymap.save);
        self.allocator.free(self.keymap.save_as);
        self.allocator.free(self.keymap.close);
        self.allocator.free(self.keymap.terminal);
        self.allocator.free(self.keymap.quit);
        self.allocator.free(self.keymap.force_quit);
        self.allocator.free(self.keymap.split);
        self.allocator.free(self.keymap.open);
        self.allocator.free(self.keymap.reload);
        self.allocator.free(self.keymap.registers);
        for (self.keymap.leader_bindings.items) |binding| {
            self.allocator.free(binding.sequence);
            self.allocator.free(binding.action);
        }
        self.keymap.leader_bindings.deinit();
        for (self.builtins.enabled.items) |item| {
            self.allocator.free(item);
        }
        self.builtins.enabled.deinit();
    }
};

pub fn load(allocator: std.mem.Allocator, path: []const u8, diag: *Diagnostics) !Config {
    var config = try Config.init(allocator);
    errdefer config.deinit();

    const raw = std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return err,
        else => return err,
    };
    defer allocator.free(raw);

    try parseInto(&config, raw, diag);
    return config;
}

fn parseInto(config: *Config, text: []const u8, diag: *Diagnostics) !void {
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = stripComment(std.mem.trim(u8, raw_line, " \t\r"));
        if (line.len == 0) continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            section = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse {
            diag.* = .{ .line = line_no, .column = 1, .message = "expected key = value" };
            return error.InvalidToml;
        };
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        try apply(config, section, key, value, diag, line_no);
    }
}

fn apply(config: *Config, section: []const u8, key: []const u8, value: []const u8, diag: *Diagnostics, line_no: usize) !void {
    const scope = if (section.len == 0) key else key;
    if (std.mem.eql(u8, section, "editor") or std.mem.eql(u8, section, "")) {
        if (std.mem.eql(u8, scope, "keywordprg")) {
            try replaceString(config.allocator, &config.keywordprg, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "equalprg")) {
            try replaceString(config.allocator, &config.equalprg, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "tab_width")) {
            config.tab_width = try parseInt(value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "show_line_numbers")) {
            config.show_line_numbers = try parseBool(value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "status_bar")) {
            config.status_bar = try parseBool(value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "status_bar_icon")) {
            try replaceString(config.allocator, &config.status_bar_icon, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "status_bar_insert_icon")) {
            try replaceString(config.allocator, &config.status_bar_insert_icon, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "status_bar_visual_icon")) {
            try replaceString(config.allocator, &config.status_bar_visual_icon, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "split_ratio")) {
            config.split_ratio = try parseInt(value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "background_color")) {
            try replaceString(config.allocator, &config.background_color, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "blur")) {
            config.blur = try parseBool(value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "opacity")) {
            config.opacity = try parseInt(value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "theme")) {
            try replaceString(config.allocator, &config.theme, value, line_no, diag);
            return;
        }
    }

    if (std.mem.eql(u8, section, "builtins")) {
        if (std.mem.eql(u8, scope, "enabled")) {
            try parseStringArray(config, value, diag, line_no);
            return;
        }
    }

    if (std.mem.eql(u8, section, "keymap")) {
        if (std.mem.eql(u8, scope, "leader")) {
            try replaceString(config.allocator, &config.keymap.leader, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "help")) {
            try replaceString(config.allocator, &config.keymap.help, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "save")) {
            try replaceString(config.allocator, &config.keymap.save, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "save_as")) {
            try replaceString(config.allocator, &config.keymap.save_as, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "close")) {
            try replaceString(config.allocator, &config.keymap.close, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "terminal")) {
            try replaceString(config.allocator, &config.keymap.terminal, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "quit")) {
            try replaceString(config.allocator, &config.keymap.quit, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "force_quit")) {
            try replaceString(config.allocator, &config.keymap.force_quit, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "split")) {
            try replaceString(config.allocator, &config.keymap.split, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "open")) {
            try replaceString(config.allocator, &config.keymap.open, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "reload")) {
            try replaceString(config.allocator, &config.keymap.reload, value, line_no, diag);
            return;
        }
        if (std.mem.eql(u8, scope, "registers")) {
            try replaceString(config.allocator, &config.keymap.registers, value, line_no, diag);
            return;
        }
    }

    if (std.mem.eql(u8, section, "keymap.leader")) {
        const sequence = try parseKey(scope, line_no, diag);
        const action = try parseString(value, line_no, diag);
        try config.keymap.leader_bindings.append(.{
            .sequence = try config.allocator.dupe(u8, sequence),
            .action = try config.allocator.dupe(u8, action),
        });
        return;
    }

    diag.* = .{ .line = line_no, .column = 1, .message = "unknown config key" };
    return error.InvalidToml;
}

fn parseStringArray(config: *Config, value: []const u8, diag: *Diagnostics, line_no: usize) !void {
    if (value.len < 2 or value[0] != '[' or value[value.len - 1] != ']') {
        diag.* = .{ .line = line_no, .column = 1, .message = "expected [\"a\", \"b\"]" };
        return error.InvalidToml;
    }
    const inner = std.mem.trim(u8, value[1 .. value.len - 1], " \t");
    if (inner.len == 0) return;
    var it = splitComma(inner);
    while (it.next()) |entry| {
        const parsed = try parseString(entry, line_no, diag);
        try config.builtins.enabled.append(try config.allocator.dupe(u8, parsed));
    }
}

fn replaceString(allocator: std.mem.Allocator, dest: *[]u8, value: []const u8, line_no: usize, diag: *Diagnostics) !void {
    const parsed = try parseString(value, line_no, diag);
    allocator.free(dest.*);
    dest.* = try allocator.dupe(u8, parsed);
}

fn parseKey(value: []const u8, line_no: usize, diag: *Diagnostics) ![]const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return parseString(value, line_no, diag);
    }
    return value;
}

fn parseString(value: []const u8, line_no: usize, diag: *Diagnostics) ![]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
        diag.* = .{ .line = line_no, .column = 1, .message = "expected quoted string" };
        return error.InvalidToml;
    }
    return unescape(value[1 .. value.len - 1], diag, line_no);
}

fn unescape(value: []const u8, diag: *Diagnostics, line_no: usize) ![]const u8 {
    _ = diag;
    _ = line_no;
    return value;
}

fn parseBool(value: []const u8, line_no: usize, diag: *Diagnostics) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    diag.* = .{ .line = line_no, .column = 1, .message = "expected true or false" };
    return error.InvalidToml;
}

fn parseInt(value: []const u8, line_no: usize, diag: *Diagnostics) !usize {
    return std.fmt.parseUnsigned(usize, value, 10) catch {
        diag.* = .{ .line = line_no, .column = 1, .message = "expected integer" };
        return error.InvalidToml;
    };
}

fn stripComment(line: []const u8) []const u8 {
    var in_string = false;
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        const c = line[idx];
        if (c == '"' and (idx == 0 or line[idx - 1] != '\\')) {
            in_string = !in_string;
        } else if (c == '#' and !in_string) {
            return line[0..idx];
        }
    }
    return line;
}

fn splitComma(value: []const u8) std.mem.TokenIterator(u8, .scalar) {
    return std.mem.tokenizeScalar(u8, value, ',');
}

test "config parse" {
    var diag = Diagnostics{};
    var cfg = try Config.init(std.testing.allocator);
    defer cfg.deinit();
    try parseInto(&cfg,
        \\[editor]
        \\tab_width = 2
        \\show_line_numbers = false
        \\status_bar_icon = ""
        \\status_bar_insert_icon = "󰘶"
        \\status_bar_visual_icon = "󰒉"
        \\background_color = "terminal"
        \\blur = true
        \\opacity = 75
        \\
        \\[builtins]
        \\enabled = ["hello"]
    , &diag);
    try std.testing.expectEqual(@as(usize, 2), cfg.tab_width);
    try std.testing.expect(!cfg.show_line_numbers);
    try std.testing.expectEqualStrings("", cfg.status_bar_icon);
    try std.testing.expectEqualStrings("󰘶", cfg.status_bar_insert_icon);
    try std.testing.expectEqualStrings("󰒉", cfg.status_bar_visual_icon);
    try std.testing.expect(cfg.blur);
    try std.testing.expectEqual(@as(usize, 75), cfg.opacity);
    try std.testing.expectEqualStrings("terminal", cfg.background_color);
    try std.testing.expectEqualStrings("hello", cfg.builtins.enabled.items[0]);
}

test "config parse status bar icon default sentinel" {
    var diag = Diagnostics{};
    var cfg = try Config.init(std.testing.allocator);
    defer cfg.deinit();
    try parseInto(&cfg,
        \\[editor]
        \\status_bar_icon = "default"
    , &diag);
    try std.testing.expectEqualStrings("default", cfg.status_bar_icon);
}

test "config parse leader bindings" {
    var diag = Diagnostics{};
    var cfg = try Config.init(std.testing.allocator);
    defer cfg.deinit();
    try parseInto(&cfg,
        \\[keymap.leader]
        \\"w" = "save"
        \\"[" = "window_split_vertical"
    , &diag);
    try std.testing.expectEqual(@as(usize, 2), cfg.keymap.leader_bindings.items.len);
    try std.testing.expectEqualStrings("w", cfg.keymap.leader_bindings.items[0].sequence);
    try std.testing.expectEqualStrings("save", cfg.keymap.leader_bindings.items[0].action);
    try std.testing.expectEqualStrings("[", cfg.keymap.leader_bindings.items[1].sequence);
    try std.testing.expectEqualStrings("window_split_vertical", cfg.keymap.leader_bindings.items[1].action);
}
