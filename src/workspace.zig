const std = @import("std");

pub const Session = struct {
    open_buffers: std.array_list.Managed([]u8),
    split_ratio: usize = 50,
    active_index: usize = 0,
    split_index: ?usize = null,
    split_focus_right: bool = false,
    selected_picker_index: usize = 0,
    selected_diagnostics_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Session {
        return .{
            .open_buffers = std.array_list.Managed([]u8).init(allocator),
        };
    }
};

pub const Workspace = struct {
    allocator: std.mem.Allocator,
    root_path: []u8,
    session_path: []u8,
    session: Session,
    session_generation: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) !Workspace {
        const root_path = try std.fs.cwd().realpathAlloc(allocator, ".");
        errdefer allocator.free(root_path);
        const session_path = try std.fs.path.join(allocator, &[_][]const u8{ root_path, ".beam", "session.txt" });
        errdefer allocator.free(session_path);
        var workspace = Workspace{
            .allocator = allocator,
            .root_path = root_path,
            .session_path = session_path,
            .session = Session.init(allocator),
        };
        try workspace.loadSession();
        return workspace;
    }

    pub fn deinit(self: *Workspace) void {
        self.saveSession() catch {};
        for (self.session.open_buffers.items) |path| self.allocator.free(path);
        self.session.open_buffers.deinit();
        self.allocator.free(self.root_path);
        self.allocator.free(self.session_path);
    }

    pub fn recordOpenBuffer(self: *Workspace, path: []const u8) !void {
        for (self.session.open_buffers.items) |existing| {
            if (std.mem.eql(u8, existing, path)) return;
        }
        try self.session.open_buffers.append(try self.allocator.dupe(u8, path));
        self.session_generation += 1;
    }

    pub fn noteSessionChange(self: *Workspace) void {
        self.session_generation += 1;
    }

    pub fn gitBranchName(self: *Workspace, allocator: std.mem.Allocator) ![]u8 {
        const head_path = try std.fs.path.join(allocator, &[_][]const u8{ self.root_path, ".git", "HEAD" });
        defer allocator.free(head_path);
        const raw = std.fs.cwd().readFileAlloc(allocator, head_path, 1024) catch return try allocator.dupe(u8, "");
        defer allocator.free(raw);
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, "ref: ")) {
            const ref = std.mem.trim(u8, trimmed["ref: ".len ..], " \t\r\n");
            const branch = std.fs.path.basename(ref);
            return try allocator.dupe(u8, branch);
        }
        return try allocator.dupe(u8, "detached");
    }

    pub fn loadSession(self: *Workspace) !void {
        const file = std.fs.cwd().openFile(self.session_path, .{ .mode = .read_only }) catch return;
        defer file.close();
        const raw = try file.readToEndAlloc(self.allocator, 1 << 20);
        defer self.allocator.free(raw);
        try self.parseSession(raw);
    }

    pub fn saveSession(self: *Workspace) !void {
        try std.fs.cwd().makePath(std.fs.path.dirname(self.session_path) orelse ".beam");
        var out = std.array_list.Managed(u8).init(self.allocator);
        defer out.deinit();
        var writer = out.writer();
        try out.appendSlice("api_version=1\n");
        try writer.print("split_ratio={d}\n", .{self.session.split_ratio});
        try writer.print("active_index={d}\n", .{self.session.active_index});
        if (self.session.split_index) |idx| try writer.print("split_index={d}\n", .{idx});
        try writer.print("split_focus_right={s}\n", .{if (self.session.split_focus_right) "true" else "false"});
        try writer.print("selected_picker_index={d}\n", .{self.session.selected_picker_index});
        try writer.print("selected_diagnostics_index={d}\n", .{self.session.selected_diagnostics_index});
        for (self.session.open_buffers.items) |path| {
            try out.appendSlice("open=");
            try out.appendSlice(path);
            try out.appendSlice("\n");
        }
        try std.fs.cwd().writeFile(.{ .sub_path = self.session_path, .data = out.items });
    }

    fn parseSession(self: *Workspace, raw: []const u8) !void {
        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "open=")) {
                const path = trimmed["open=".len ..];
                try self.session.open_buffers.append(try self.allocator.dupe(u8, path));
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "split_ratio=")) {
                self.session.split_ratio = try std.fmt.parseUnsigned(usize, trimmed["split_ratio=".len ..], 10);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "active_index=")) {
                self.session.active_index = try std.fmt.parseUnsigned(usize, trimmed["active_index=".len ..], 10);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "split_index=")) {
                self.session.split_index = try std.fmt.parseUnsigned(usize, trimmed["split_index=".len ..], 10);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "split_focus_right=")) {
                const value = trimmed["split_focus_right=".len ..];
                self.session.split_focus_right = std.mem.eql(u8, value, "true");
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "selected_picker_index=")) {
                self.session.selected_picker_index = try std.fmt.parseUnsigned(usize, trimmed["selected_picker_index=".len ..], 10);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "selected_diagnostics_index=")) {
                self.session.selected_diagnostics_index = try std.fmt.parseUnsigned(usize, trimmed["selected_diagnostics_index=".len ..], 10);
                continue;
            }
        }
    }
};

test "workspace session save and load round trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    var ws = try Workspace.init(std.testing.allocator);
    defer ws.deinit();
    try ws.recordOpenBuffer("alpha.txt");
    ws.session.split_ratio = 40;
    ws.session.selected_picker_index = 2;
    ws.session.selected_diagnostics_index = 3;
    try ws.saveSession();

    var ws2 = try Workspace.init(std.testing.allocator);
    defer ws2.deinit();
    try std.testing.expectEqual(@as(usize, 1), ws2.session.open_buffers.items.len);
    try std.testing.expectEqualStrings("alpha.txt", ws2.session.open_buffers.items[0]);
    try std.testing.expectEqual(@as(usize, 40), ws2.session.split_ratio);
    try std.testing.expectEqual(@as(usize, 2), ws2.session.selected_picker_index);
    try std.testing.expectEqual(@as(usize, 3), ws2.session.selected_diagnostics_index);
}
