const std = @import("std");

pub const SearchKind = enum {
    file,
    match,
    symbol,
};

pub const SearchResult = struct {
    kind: SearchKind,
    path: []u8,
    row: usize = 0,
    col: usize = 0,
    line: []u8 = "",

    pub fn deinit(self: SearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.line);
    }
};

pub const ResultSink = struct {
    ctx: *anyopaque,
    emit: *const fn (ctx: *anyopaque, result: SearchResult) anyerror!void,
};

pub const SearchIndex = struct {
    allocator: std.mem.Allocator,
    root_path: []u8,
    files: std.array_list.Managed([]u8),
    generation: u64 = 1,
    loaded: bool = false,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !SearchIndex {
        const absolute_root = try std.fs.cwd().realpathAlloc(allocator, root_path);
        return .{
            .allocator = allocator,
            .root_path = absolute_root,
            .files = std.array_list.Managed([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *SearchIndex) void {
        self.clear();
        self.files.deinit();
        self.allocator.free(self.root_path);
    }

    pub fn clear(self: *SearchIndex) void {
        for (self.files.items) |path| self.allocator.free(path);
        self.files.clearRetainingCapacity();
    }

    pub fn refresh(self: *SearchIndex) !void {
        self.clear();
        var dir = try std.fs.openDirAbsolute(self.root_path, .{ .iterate = true });
        defer dir.close();
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            try self.files.append(try self.allocator.dupe(u8, entry.path));
        }
        self.generation += 1;
        self.loaded = true;
    }

    pub fn ensureLoaded(self: *SearchIndex) !void {
        if (!self.loaded) try self.refresh();
    }

    pub fn fileCount(self: *const SearchIndex) usize {
        return self.files.items.len;
    }

    pub fn searchFiles(self: *SearchIndex, pathspec: []const u8, sink: ResultSink, limit: usize) !usize {
        try self.ensureLoaded();
        return try self.scanFiles(.match, pathspec, sink, limit);
    }

    pub fn grep(self: *SearchIndex, pattern: []const u8, pathspec: []const u8, sink: ResultSink, limit: usize) !usize {
        try self.ensureLoaded();
        return try self.scanFilesWithPattern(.match, pattern, pathspec, sink, limit);
    }

    pub fn symbols(self: *SearchIndex, pattern: []const u8, sink: ResultSink, limit: usize) !usize {
        try self.ensureLoaded();
        var emitted: usize = 0;
        var dir = try std.fs.openDirAbsolute(self.root_path, .{});
        defer dir.close();
        for (self.files.items) |path| {
            if (emitted >= limit) break;
            const text = dir.readFileAlloc(self.allocator, path, 1 << 20) catch continue;
            defer self.allocator.free(text);
            var row: usize = 0;
            var start: usize = 0;
            while (start <= text.len) {
                const rel_end = std.mem.indexOfScalar(u8, text[start..], '\n');
                const end = if (rel_end) |idx| start + idx else text.len;
                const line = text[start..end];
                if (symbolLineMatches(line, pattern)) {
                    try self.emitResult(sink, .{
                        .kind = .symbol,
                        .path = try self.allocator.dupe(u8, path),
                        .row = row,
                        .col = std.mem.indexOf(u8, line, pattern) orelse 0,
                        .line = try self.allocator.dupe(u8, line),
                    });
                    emitted += 1;
                }
                if (end >= text.len) break;
                start = end + 1;
                row += 1;
            }
        }
        return emitted;
    }

    fn scanFiles(self: *const SearchIndex, kind: SearchKind, pathspec: []const u8, sink: ResultSink, limit: usize) !usize {
        var emitted: usize = 0;
        for (self.files.items) |path| {
            if (emitted >= limit) break;
            if (pathspec.len > 0 and !pathMatches(path, pathspec)) continue;
            try self.emitResult(sink, .{
                .kind = kind,
                .path = try self.allocator.dupe(u8, path),
            });
            emitted += 1;
        }
        return emitted;
    }

    fn scanFilesWithPattern(self: *const SearchIndex, kind: SearchKind, pattern: []const u8, pathspec: []const u8, sink: ResultSink, limit: usize) !usize {
        var emitted: usize = 0;
        var dir = try std.fs.openDirAbsolute(self.root_path, .{});
        defer dir.close();
        for (self.files.items) |path| {
            if (emitted >= limit) break;
            if (pathspec.len > 0 and !pathMatches(path, pathspec)) continue;
            const text = dir.readFileAlloc(self.allocator, path, 1 << 20) catch continue;
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
                    try self.emitResult(sink, .{
                        .kind = kind,
                        .path = try self.allocator.dupe(u8, path),
                        .row = row,
                        .col = hit,
                        .line = try self.allocator.dupe(u8, line),
                    });
                    emitted += 1;
                    if (emitted >= limit) return emitted;
                    search = hit + @max(1, pattern.len);
                }
                if (end >= text.len) break;
                start = end + 1;
                row += 1;
            }
        }
        return emitted;
    }

    fn emitResult(self: *const SearchIndex, sink: ResultSink, result: SearchResult) !void {
        sink.emit(sink.ctx, result) catch |err| {
            result.deinit(self.allocator);
            return err;
        };
    }

    fn pathMatches(path: []const u8, spec: []const u8) bool {
        if (std.mem.eql(u8, spec, ".") or std.mem.eql(u8, spec, "**/*") or std.mem.eql(u8, spec, "*")) return true;
        const cleaned = std.mem.trim(u8, spec, " \t");
        if (cleaned.len == 0) return true;
        if (std.mem.indexOf(u8, cleaned, "*") != null) {
            const prefix = std.mem.trimRight(u8, cleaned, "*");
            return std.mem.startsWith(u8, path, prefix);
        }
        return std.mem.indexOf(u8, path, cleaned) != null;
    }

    fn symbolLineMatches(line: []const u8, pattern: []const u8) bool {
        if (pattern.len == 0) return false;
        if (std.mem.indexOf(u8, line, pattern) != null) return true;
        return std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "fn ") or std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "pub fn ");
    }
};

test "search index refresh and grep" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    try tmp.dir.writeFile(.{ .sub_path = "a.txt", .data = "hello needle\nworld\n" });
    try tmp.dir.writeFile(.{ .sub_path = "b.txt", .data = "needle twice needle\n" });

    var index = try SearchIndex.init(std.testing.allocator, ".");
    defer index.deinit();
    try index.refresh();
    try std.testing.expect(index.fileCount() >= 2);

    var results = std.array_list.Managed(SearchResult).init(std.testing.allocator);
    defer {
        for (results.items) |result| result.deinit(std.testing.allocator);
        results.deinit();
    }
    const Sink = struct {
        fn emit(ctx: *anyopaque, result: SearchResult) anyerror!void {
            const list: *std.array_list.Managed(SearchResult) = @ptrCast(@alignCast(ctx));
            try list.append(result);
        }
    };
    _ = try index.grep("needle", "", .{ .ctx = &results, .emit = Sink.emit }, 10);
    try std.testing.expect(results.items.len >= 2);
}
