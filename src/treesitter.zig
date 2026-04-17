const std = @import("std");
const buffer_mod = @import("buffer.zig");

pub const DirtyRange = struct {
    start_row: usize,
    end_row: usize,
};

pub const NodeKind = enum {
    root,
    block,
    function,
    scope,
    word,
};

pub const Node = struct {
    kind: NodeKind,
    start: buffer_mod.Position,
    end: buffer_mod.Position,
};

pub const FoldRange = struct {
    start_row: usize,
    end_row: usize,
};

pub const TextRange = struct {
    start: buffer_mod.Position,
    end: buffer_mod.Position,
};

const SnapshotState = struct {
    buffer_id: u64,
    generation: u64,
    text: []u8,
    dirty_range: ?DirtyRange = null,
};

pub const Service = struct {
    allocator: std.mem.Allocator,
    snapshots: std.array_list.Managed(SnapshotState),

    pub fn init(allocator: std.mem.Allocator) Service {
        return .{
            .allocator = allocator,
            .snapshots = std.array_list.Managed(SnapshotState).init(allocator),
        };
    }

    pub fn deinit(self: *Service) void {
        self.clear();
        self.snapshots.deinit();
    }

    pub fn clear(self: *Service) void {
        for (self.snapshots.items) |snapshot| {
            self.allocator.free(snapshot.text);
        }
        self.snapshots.clearRetainingCapacity();
    }

    pub fn clearBuffer(self: *Service, buffer_id: u64) void {
        var idx: usize = 0;
        while (idx < self.snapshots.items.len) {
            if (self.snapshots.items[idx].buffer_id == buffer_id) {
                const snapshot = self.snapshots.orderedRemove(idx);
                self.allocator.free(snapshot.text);
                continue;
            }
            idx += 1;
        }
    }

    pub fn updateSnapshot(self: *Service, snapshot: buffer_mod.ReadSnapshot) !void {
        const duplicate = try self.allocator.dupe(u8, snapshot.text);
        errdefer self.allocator.free(duplicate);

        const dirty_range = self.computeDirtyRange(snapshot.buffer_id, duplicate);
        if (self.findSnapshotIndex(snapshot.buffer_id)) |idx| {
            self.allocator.free(self.snapshots.items[idx].text);
            self.snapshots.items[idx] = .{
                .buffer_id = snapshot.buffer_id,
                .generation = snapshot.generation,
                .text = duplicate,
                .dirty_range = dirty_range,
            };
            return;
        }
        try self.snapshots.append(.{
            .buffer_id = snapshot.buffer_id,
            .generation = snapshot.generation,
            .text = duplicate,
            .dirty_range = dirty_range,
        });
    }

    pub fn dirtyRangeForBuffer(self: *const Service, buffer_id: u64) ?DirtyRange {
        if (self.findSnapshotIndex(buffer_id)) |idx| {
            return self.snapshots.items[idx].dirty_range;
        }
        return null;
    }

    pub fn foldRangeForSnapshot(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?FoldRange {
        _ = self;
        return foldRangeFromText(snapshot.text, snapshot.cursor);
    }

    pub fn nodeAtCursor(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?Node {
        _ = self;
        return nodeAtCursorFromText(snapshot.text, snapshot.cursor);
    }

    pub fn enclosingScope(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?FoldRange {
        _ = self;
        return enclosingScopeFromText(snapshot.text, snapshot.cursor);
    }

    pub fn indentForRow(self: *const Service, snapshot: buffer_mod.ReadSnapshot, row: usize) usize {
        _ = self;
        return indentForRowFromText(snapshot.text, row);
    }

    pub fn textObjectRange(self: *const Service, snapshot: buffer_mod.ReadSnapshot, inner: bool) ?TextRange {
        _ = self;
        return blockObjectRangeFromText(snapshot.text, snapshot.cursor, inner);
    }

    fn findSnapshotIndex(self: *const Service, buffer_id: u64) ?usize {
        for (self.snapshots.items, 0..) |snapshot, idx| {
            if (snapshot.buffer_id == buffer_id) return idx;
        }
        return null;
    }

    fn computeDirtyRange(self: *const Service, buffer_id: u64, next_text: []const u8) ?DirtyRange {
        const idx = self.findSnapshotIndex(buffer_id) orelse return null;
        const prev = self.snapshots.items[idx].text;
        const prev_lines = lineCount(prev);
        const next_lines = lineCount(next_text);
        const line_limit = @max(prev_lines, next_lines);
        var first: ?usize = null;
        var last: ?usize = null;
        var row: usize = 0;
        while (row < line_limit) : (row += 1) {
            const prev_line = lineAt(prev, row);
            const next_line = lineAt(next_text, row);
            if (!std.mem.eql(u8, prev_line, next_line)) {
                if (first == null) first = row;
                last = row;
            }
        }
        if (first == null) return null;
        return .{ .start_row = first.?, .end_row = last.? };
    }
};

fn nodeAtCursorFromText(text: []const u8, cursor: buffer_mod.Position) ?Node {
    const scope = enclosingScopeFromText(text, cursor) orelse return null;
    const line = lineAt(text, cursor.row);
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    const kind: NodeKind = if (std.mem.startsWith(u8, trimmed, "fn ") or std.mem.startsWith(u8, trimmed, "pub fn "))
        .function
    else if (scope.start_row != scope.end_row)
        .block
    else
        .word;
    return .{
        .kind = kind,
        .start = .{ .row = scope.start_row, .col = 0 },
        .end = .{ .row = scope.end_row, .col = lineAt(text, scope.end_row).len },
    };
}

fn foldRangeFromText(text: []const u8, cursor: buffer_mod.Position) ?FoldRange {
    return enclosingScopeFromText(text, cursor);
}

fn enclosingScopeFromText(text: []const u8, cursor: buffer_mod.Position) ?FoldRange {
    if (text.len == 0) return null;
    const row_count = lineCount(text);
    if (row_count == 0) return null;
    const row = @min(cursor.row, row_count - 1);
    var start: ?usize = null;
    var depth: isize = 0;
    var scan_row: usize = row + 1;
    while (scan_row > 0) : (scan_row -= 1) {
        const current_row = scan_row - 1;
        const line = lineAt(text, current_row);
        for (line, 0..) |byte, idx| {
            _ = idx;
            switch (byte) {
                '}' => depth += 1,
                '{' => {
                    if (depth == 0) {
                        start = current_row;
                        break;
                    }
                    depth -= 1;
                },
                else => {},
            }
        }
        if (start != null) break;
    }
    const begin = start orelse paragraphStart(text, row);
    var end_row = paragraphEnd(text, row);
    if (begin < end_row) {
        var open_depth: isize = 0;
        var idx_row: usize = begin;
        while (idx_row <= end_row) : (idx_row += 1) {
            const line = lineAt(text, idx_row);
            for (line) |byte| {
                switch (byte) {
                    '{' => open_depth += 1,
                    '}' => {
                        if (open_depth > 0) open_depth -= 1;
                    },
                    else => {},
                }
            }
            if (open_depth == 0 and idx_row > begin) {
                end_row = idx_row;
                break;
            }
        }
    }
    if (end_row <= begin) return null;
    return .{ .start_row = begin, .end_row = end_row };
}

fn blockObjectRangeFromText(text: []const u8, cursor: buffer_mod.Position, inner: bool) ?TextRange {
    const scope = enclosingScopeFromText(text, cursor) orelse return null;
    const start_row = scope.start_row;
    const end_row = scope.end_row;
    if (inner) {
        return .{
            .start = .{ .row = start_row, .col = 1 },
            .end = .{ .row = end_row, .col = @max(lineAt(text, end_row).len, 1) - 1 },
        };
    }
    return .{
        .start = .{ .row = start_row, .col = 0 },
        .end = .{ .row = end_row, .col = lineAt(text, end_row).len },
    };
}

fn indentForRowFromText(text: []const u8, row: usize) usize {
    const row_count = lineCount(text);
    if (row_count == 0) return 0;
    const current = @min(row, row_count - 1);
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx < current) : (idx += 1) {
        const line = lineAt(text, idx);
        for (line) |byte| {
            switch (byte) {
                '{' => depth += 1,
                '}' => {
                    if (depth > 0) depth -= 1;
                },
                else => {},
            }
        }
    }
    return depth * 2;
}

fn paragraphStart(text: []const u8, row: usize) usize {
    var start = @min(row, lineCount(text) - 1);
    while (start > 0 and lineAt(text, start - 1).len != 0) : (start -= 1) {}
    return start;
}

fn paragraphEnd(text: []const u8, row: usize) usize {
    const total = lineCount(text);
    var end = @min(row, total - 1);
    while (end + 1 < total and lineAt(text, end + 1).len != 0) : (end += 1) {}
    return end;
}

fn lineCount(text: []const u8) usize {
    if (text.len == 0) return 1;
    var count: usize = 1;
    for (text) |byte| {
        if (byte == '\n') count += 1;
    }
    return count;
}

fn lineAt(text: []const u8, row: usize) []const u8 {
    var current: usize = 0;
    var start: usize = 0;
    while (start <= text.len) {
        const rel_end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        if (current == row) return text[start..rel_end];
        if (rel_end >= text.len) break;
        start = rel_end + 1;
        current += 1;
    }
    return "";
}

fn positionToOffset(text: []const u8, pos: buffer_mod.Position) usize {
    var row: usize = 0;
    var offset: usize = 0;
    var start: usize = 0;
    while (start <= text.len) {
        const rel_end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const line = text[start..rel_end];
        if (row == pos.row) return offset + @min(pos.col, line.len);
        offset += line.len;
        if (rel_end < text.len) offset += 1;
        if (rel_end >= text.len) break;
        start = rel_end + 1;
        row += 1;
    }
    return text.len;
}

fn offsetToPosition(text: []const u8, offset: usize) buffer_mod.Position {
    var remaining = @min(offset, text.len);
    var row: usize = 0;
    var start: usize = 0;
    while (start <= text.len) {
        const rel_end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const line = text[start..rel_end];
        if (remaining <= line.len) {
            return .{ .row = row, .col = remaining };
        }
        remaining -= line.len;
        if (rel_end >= text.len) break;
        if (remaining == 0) return .{ .row = row, .col = line.len };
        remaining -= 1;
        start = rel_end + 1;
        row += 1;
    }
    return .{ .row = row, .col = 0 };
}

test "syntax service tracks snapshots and dirty ranges" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot1 = buffer_mod.ReadSnapshot{
        .buffer_id = 1,
        .generation = 1,
        .cursor = .{ .row = 1, .col = 2 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "fn demo() {\n    one\n}\n"),
    };
    defer std.testing.allocator.free(snapshot1.text);
    try service.updateSnapshot(snapshot1);

    const snapshot2 = buffer_mod.ReadSnapshot{
        .buffer_id = 1,
        .generation = 2,
        .cursor = .{ .row = 1, .col = 2 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "fn demo() {\n    two\n}\n"),
    };
    defer std.testing.allocator.free(snapshot2.text);
    try service.updateSnapshot(snapshot2);

    const dirty = service.dirtyRangeForBuffer(1) orelse return error.TestExpected;
    try std.testing.expectEqual(@as(usize, 1), dirty.start_row);
    try std.testing.expectEqual(@as(usize, 1), dirty.end_row);
}

test "syntax service provides fold and text object ranges" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();
    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 1,
        .generation = 1,
        .cursor = .{ .row = 1, .col = 4 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "fn demo() {\n    value\n}\n"),
    };
    defer std.testing.allocator.free(snapshot.text);

    const fold = service.foldRangeForSnapshot(snapshot) orelse return error.TestExpected;
    try std.testing.expectEqual(@as(usize, 0), fold.start_row);
    try std.testing.expectEqual(@as(usize, 2), fold.end_row);

    const object = service.textObjectRange(snapshot, true) orelse return error.TestExpected;
    try std.testing.expectEqual(@as(usize, 0), object.start.row);
}
