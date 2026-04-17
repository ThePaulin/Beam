const std = @import("std");

var next_buffer_id: u64 = 1;

pub const Position = struct {
    row: usize = 0,
    col: usize = 0,
};

pub const Selection = struct {
    start: Position,
    end: Position,
};

pub const LineEnding = enum {
    lf,
    crlf,
    cr,
    unknown,
};

pub const Fold = struct {
    start_row: usize,
    end_row: usize,
    closed: bool = true,
};

pub const ReadSnapshot = struct {
    buffer_id: u64,
    generation: u64,
    cursor: Position,
    scroll_row: usize,
    text: []u8,
    filetype: []const u8,
    selection: ?Selection = null,
};

const UndoSnapshot = struct {
    text: []u8,
    row: usize,
    col: usize,
};

pub const EditTransaction = struct {
    buffer: *Buffer,
    original_text: []u8,
    working_text: std.array_list.Managed(u8),
    cursor: Position,
    committed: bool = false,

    fn init(buffer: *Buffer) !EditTransaction {
        const text = try buffer.serialize();
        var working_text = std.array_list.Managed(u8).init(buffer.allocator);
        try working_text.appendSlice(text);
        return .{
            .buffer = buffer,
            .original_text = text,
            .working_text = working_text,
            .cursor = buffer.cursor,
        };
    }

    pub fn deinit(self: *EditTransaction) void {
        if (!self.committed) {
            self.working_text.deinit();
            self.buffer.allocator.free(self.original_text);
        }
    }

    pub fn replaceRange(self: *EditTransaction, start: Position, end: Position, replacement: []const u8) !void {
        const updated = try self.buffer.buildReplacementText(self.working_text.items, start, end, replacement);
        defer self.buffer.allocator.free(updated);
        self.working_text.clearRetainingCapacity();
        try self.working_text.appendSlice(updated);
        self.cursor = self.buffer.positionAfterReplacement(start, replacement);
    }

    pub fn insertText(self: *EditTransaction, at: Position, bytes: []const u8) !void {
        try self.replaceRange(at, at, bytes);
    }

    pub fn commit(self: *EditTransaction) !void {
        if (self.committed) return;
        try self.buffer.pushUndoSnapshotText(self.original_text, self.buffer.cursor);
        try self.buffer.setText(self.working_text.items);
        self.buffer.cursor = self.cursor;
        self.buffer.bumpGeneration();
        self.buffer.dirty = true;
        self.committed = true;
        self.working_text.deinit();
        self.buffer.allocator.free(self.original_text);
    }
};

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    id: u64,
    generation: u64 = 1,
    path: ?[]u8 = null,
    filetype: []u8,
    encoding: []u8,
    line_ending: LineEnding = .lf,
    lines: std.array_list.Managed([]u8),
    cursor: Position = .{},
    scroll_row: usize = 0,
    fold_enabled: bool = true,
    folds: std.array_list.Managed(Fold),
    undo_stack: std.array_list.Managed(UndoSnapshot),
    redo_stack: std.array_list.Managed(UndoSnapshot),
    dirty: bool = false,

    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        var lines = std.array_list.Managed([]u8).init(allocator);
        try lines.append(try allocator.dupe(u8, ""));
        const id = next_buffer_id;
        next_buffer_id += 1;
        return .{
            .allocator = allocator,
            .id = id,
            .filetype = try allocator.dupe(u8, "text"),
            .encoding = try allocator.dupe(u8, "utf-8"),
            .lines = lines,
            .scroll_row = 0,
            .fold_enabled = true,
            .folds = std.array_list.Managed(Fold).init(allocator),
            .undo_stack = std.array_list.Managed(UndoSnapshot).init(allocator),
            .redo_stack = std.array_list.Managed(UndoSnapshot).init(allocator),
        };
    }

    pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Buffer {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();
        const data = try file.readToEndAlloc(allocator, 1 << 26);
        defer allocator.free(data);

        var buffer = try initEmpty(allocator);
        errdefer buffer.deinit();
        try buffer.replacePath(path);
        buffer.line_ending = detectLineEnding(data);
        try buffer.setText(data);
        buffer.dirty = false;
        return buffer;
    }

    pub fn beginTransaction(self: *Buffer) !EditTransaction {
        return try EditTransaction.init(self);
    }

    pub fn readSnapshot(self: *const Buffer) !ReadSnapshot {
        return .{
            .buffer_id = self.id,
            .generation = self.generation,
            .cursor = self.cursor,
            .scroll_row = self.scroll_row,
            .text = try self.serialize(),
            .filetype = self.filetype,
        };
    }

    pub fn isFresh(self: *const Buffer, read_snapshot: ReadSnapshot) bool {
        return read_snapshot.buffer_id == self.id and read_snapshot.generation == self.generation;
    }

    pub fn freeReadSnapshot(self: *const Buffer, read_snapshot: ReadSnapshot) void {
        self.allocator.free(read_snapshot.text);
    }

    pub fn deinit(self: *Buffer) void {
        self.clearLines();
        self.clearFolds();
        if (self.path) |p| self.allocator.free(p);
        self.allocator.free(self.filetype);
        self.allocator.free(self.encoding);
        self.clearHistory(&self.undo_stack);
        self.clearHistory(&self.redo_stack);
        self.folds.deinit();
        self.undo_stack.deinit();
        self.redo_stack.deinit();
        self.lines.deinit();
    }

    pub fn replacePath(self: *Buffer, path: []const u8) !void {
        if (self.path) |old| self.allocator.free(old);
        self.path = try self.allocator.dupe(u8, path);
        try self.updateFiletype();
        self.bumpGeneration();
    }

    pub fn setText(self: *Buffer, text: []const u8) !void {
        self.clearLines();
        try self.loadTextIntoLines(text);
        self.cursor = .{};
        self.scroll_row = 0;
        self.clearFolds();
        self.bumpGeneration();
        self.dirty = false;
    }

    pub fn save(self: *Buffer) !void {
        const path = self.path orelse return error.MissingPath;
        const text = try self.serialize();
        defer self.allocator.free(text);
        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = text });
        self.dirty = false;
    }

    pub fn saveAs(self: *Buffer, path: []const u8) !void {
        try self.replacePath(path);
        try self.save();
    }

    pub fn filetypeText(self: *const Buffer) []const u8 {
        return self.filetype;
    }

    pub fn encodingText(self: *const Buffer) []const u8 {
        return self.encoding;
    }

    pub fn lineEndingText(self: *const Buffer) []const u8 {
        return switch (self.line_ending) {
            .lf => "lf",
            .crlf => "crlf",
            .cr => "cr",
            .unknown => "unknown",
        };
    }

    pub fn setCursor(self: *Buffer, row: usize, col: usize) void {
        if (self.lines.items.len == 0) {
            self.cursor = .{};
            return;
        }
        self.cursor.row = @min(row, self.lines.items.len - 1);
        self.cursor.col = @min(col, self.lines.items[self.cursor.row].len);
    }

    pub fn currentLine(self: *const Buffer) []const u8 {
        return self.lines.items[self.cursor.row];
    }

    pub fn lineCount(self: *const Buffer) usize {
        return self.lines.items.len;
    }

    pub fn clearFolds(self: *Buffer) void {
        self.folds.clearRetainingCapacity();
    }

    pub fn foldAtRow(self: *const Buffer, row: usize) ?Fold {
        if (!self.fold_enabled) return null;
        for (self.folds.items) |fold| {
            if (row >= fold.start_row and row <= fold.end_row) return fold;
        }
        return null;
    }

    pub fn createParagraphFold(self: *Buffer) !void {
        const range = self.paragraphFoldRange() orelse return;
        try self.createFoldRange(range.start_row, range.end_row);
    }

    pub fn createFoldRange(self: *Buffer, start_row: usize, end_row: usize) !void {
        if (end_row <= start_row) return;
        if (start_row >= self.lines.items.len) return;
        try self.folds.append(.{ .start_row = start_row, .end_row = @min(end_row, self.lines.items.len - 1), .closed = true });
        self.bumpGeneration();
    }

    pub fn createFoldRangeClamped(self: *Buffer, start_row: usize, end_row: usize) !void {
        if (end_row <= start_row) return;
        try self.createFoldRange(start_row, end_row);
    }

    pub fn deleteFoldAtRow(self: *Buffer, row: usize) bool {
        for (self.folds.items, 0..) |fold, idx| {
            if (row >= fold.start_row and row <= fold.end_row) {
                _ = self.folds.orderedRemove(idx);
                self.bumpGeneration();
                return true;
            }
        }
        return false;
    }

    pub fn toggleFoldAtRow(self: *Buffer, row: usize) bool {
        for (self.folds.items) |*fold| {
            if (row >= fold.start_row and row <= fold.end_row) {
                fold.closed = !fold.closed;
                self.bumpGeneration();
                return true;
            }
        }
        return false;
    }

    pub fn openFoldAtRow(self: *Buffer, row: usize) bool {
        for (self.folds.items) |*fold| {
            if (row >= fold.start_row and row <= fold.end_row) {
                fold.closed = false;
                self.bumpGeneration();
                return true;
            }
        }
        return false;
    }

    pub fn closeFoldAtRow(self: *Buffer, row: usize) bool {
        for (self.folds.items) |*fold| {
            if (row >= fold.start_row and row <= fold.end_row) {
                fold.closed = true;
                self.bumpGeneration();
                return true;
            }
        }
        return false;
    }

    pub fn openAllFolds(self: *Buffer) void {
        for (self.folds.items) |*fold| fold.closed = false;
        self.bumpGeneration();
    }

    pub fn closeAllFolds(self: *Buffer) void {
        for (self.folds.items) |*fold| fold.closed = true;
        self.bumpGeneration();
    }

    pub fn toggleFolding(self: *Buffer) void {
        self.fold_enabled = !self.fold_enabled;
        self.bumpGeneration();
    }

    pub fn replaceLine(self: *Buffer, row: usize, text: []const u8) !void {
        if (row >= self.lines.items.len) return;
        try self.pushUndoSnapshot();
        self.allocator.free(self.lines.items[row]);
        self.lines.items[row] = try self.allocator.dupe(u8, text);
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn moveLeft(self: *Buffer) void {
        if (self.cursor.col > 0) {
            self.cursor.col -= 1;
        } else if (self.cursor.row > 0) {
            self.cursor.row -= 1;
            self.cursor.col = self.lines.items[self.cursor.row].len;
        }
    }

    pub fn moveRight(self: *Buffer) void {
        const line = self.currentLine();
        if (self.cursor.col < line.len) {
            self.cursor.col += 1;
        } else if (self.cursor.row + 1 < self.lines.items.len) {
            self.cursor.row += 1;
            self.cursor.col = 0;
        }
    }

    pub fn moveUp(self: *Buffer) void {
        if (self.cursor.row > 0) {
            self.cursor.row -= 1;
            self.cursor.col = @min(self.cursor.col, self.currentLine().len);
        }
    }

    pub fn moveDown(self: *Buffer) void {
        if (self.cursor.row + 1 < self.lines.items.len) {
            self.cursor.row += 1;
            self.cursor.col = @min(self.cursor.col, self.currentLine().len);
        }
    }

    pub fn moveLineStart(self: *Buffer) void {
        self.cursor.col = 0;
    }

    pub fn moveLineEnd(self: *Buffer) void {
        const line = self.currentLine();
        self.cursor.col = if (line.len > 0) line.len - 1 else 0;
    }

    pub fn moveToFirstNonBlank(self: *Buffer) void {
        const line = self.currentLine();
        var col: usize = 0;
        while (col < line.len and std.ascii.isWhitespace(line[col])) : (col += 1) {}
        self.cursor.col = col;
    }

    pub fn moveToLastNonBlank(self: *Buffer) void {
        const line = self.currentLine();
        if (line.len == 0) {
            self.cursor.col = 0;
            return;
        }
        var col = line.len;
        while (col > 0 and std.ascii.isWhitespace(line[col - 1])) : (col -= 1) {}
        self.cursor.col = if (col > 0) col - 1 else 0;
    }

    pub fn moveToDocumentStart(self: *Buffer) void {
        self.cursor = .{};
    }

    pub fn moveToDocumentEnd(self: *Buffer) void {
        if (self.lines.items.len == 0) {
            self.cursor = .{};
            return;
        }
        self.cursor.row = self.lines.items.len - 1;
        self.cursor.col = 0;
    }

    pub fn moveToLine(self: *Buffer, row: usize) void {
        if (self.lines.items.len == 0) {
            self.cursor = .{};
            return;
        }
        self.cursor.row = @min(row, self.lines.items.len - 1);
        self.cursor.col = 0;
    }

    pub fn moveToLineNonBlank(self: *Buffer, row: usize) void {
        self.moveToLine(row);
        self.moveToFirstNonBlank();
    }

    pub fn moveWordForward(self: *Buffer, big: bool) void {
        const line = self.currentLine();
        self.cursor.col = nextWordStartInLine(line, self.cursor.col, big);
    }

    pub fn moveWordBackward(self: *Buffer, big: bool) void {
        const line = self.currentLine();
        self.cursor.col = prevWordStartInLine(line, self.cursor.col, big);
    }

    pub fn moveWordEnd(self: *Buffer, big: bool) void {
        const line = self.currentLine();
        self.cursor.col = nextWordEndInLine(line, self.cursor.col, big);
    }

    pub fn moveWordEndBackward(self: *Buffer, big: bool) void {
        const line = self.currentLine();
        self.cursor.col = prevWordEndInLine(line, self.cursor.col, big);
    }

    pub fn moveParagraphForward(self: *Buffer) void {
        var row = self.cursor.row + 1;
        while (row < self.lines.items.len and self.lines.items[row].len != 0) : (row += 1) {}
        while (row < self.lines.items.len and self.lines.items[row].len == 0) : (row += 1) {}
        if (row < self.lines.items.len) {
            self.cursor.row = row;
            self.cursor.col = 0;
        } else {
            self.moveToDocumentEnd();
        }
    }

    pub fn moveParagraphBackward(self: *Buffer) void {
        if (self.cursor.row == 0) {
            self.moveToDocumentStart();
            return;
        }
        var row = self.cursor.row - 1;
        while (row > 0 and self.lines.items[row].len != 0) : (row -= 1) {}
        while (row > 0 and self.lines.items[row].len == 0) : (row -= 1) {}
        self.cursor.row = row;
        self.cursor.col = 0;
    }

    pub fn currentWord(self: *const Buffer) []const u8 {
        const line = self.currentLine();
        if (line.len == 0) return line;
        var start = @min(self.cursor.col, line.len);
        if (start == line.len and start > 0) start -= 1;
        while (start > 0 and isWordChar(line[start - 1])) : (start -= 1) {}
        var end = @min(self.cursor.col, line.len);
        while (end < line.len and isWordChar(line[end])) : (end += 1) {}
        return line[start..end];
    }

    pub fn replaceCurrentCharacter(self: *Buffer, byte: u8) !void {
        const line = self.lines.items[self.cursor.row];
        if (self.cursor.col >= line.len) return;
        try self.pushUndoSnapshot();
        var new_line = try self.allocator.dupe(u8, line);
        new_line[self.cursor.col] = byte;
        self.allocator.free(line);
        self.lines.items[self.cursor.row] = new_line;
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn replaceCurrentWord(self: *Buffer, replacement: []const u8) !void {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const bounds = self.wordBounds() orelse return;
        try self.replaceRange(bounds.start, bounds.end, replacement, text);
    }

    pub fn deleteCurrentWord(self: *Buffer) ![]u8 {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const bounds = self.wordBounds() orelse return try self.allocator.dupe(u8, "");
        return try self.extractRangeAndReplace(bounds.start, bounds.end, "", text);
    }

    pub fn deleteToLineEnd(self: *Buffer) ![]u8 {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const line = self.lines.items[self.cursor.row];
        const start = Position{ .row = self.cursor.row, .col = self.cursor.col };
        const end = Position{ .row = self.cursor.row, .col = line.len };
        return try self.extractRangeAndReplace(start, end, "", text);
    }

    pub fn deleteToLineStart(self: *Buffer) ![]u8 {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const start = Position{ .row = self.cursor.row, .col = 0 };
        const end = Position{ .row = self.cursor.row, .col = self.cursor.col };
        return try self.extractRangeAndReplace(start, end, "", text);
    }

    pub fn deleteLine(self: *Buffer, count: usize) ![]u8 {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const start_row = self.cursor.row;
        const end_row = @min(self.lines.items.len, start_row + count);
        const start = Position{ .row = start_row, .col = 0 };
        const end = if (end_row < self.lines.items.len)
            Position{ .row = end_row, .col = 0 }
        else
            Position{ .row = self.lines.items.len - 1, .col = self.lines.items[self.lines.items.len - 1].len };
        return try self.extractRangeAndReplace(start, end, "", text);
    }

    pub fn yankLine(self: *Buffer, count: usize) ![]u8 {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const start_row = self.cursor.row;
        const end_row = @min(self.lines.items.len, start_row + count);
        const start = Position{ .row = start_row, .col = 0 };
        const end = if (end_row < self.lines.items.len)
            Position{ .row = end_row, .col = 0 }
        else
            Position{ .row = self.lines.items.len - 1, .col = self.lines.items[self.lines.items.len - 1].len };
        return try self.sliceRange(text, start, end);
    }

    pub fn insertTextAtCursor(self: *Buffer, bytes: []const u8) !void {
        const text = try self.serialize();
        defer self.allocator.free(text);
        const start = self.cursor;
        try self.replaceRange(start, start, bytes, text);
    }

    pub fn insertLinewiseText(self: *Buffer, before: bool, text: []const u8) !void {
        try self.pushUndoSnapshot();

        const insert_row = if (before) self.cursor.row else @min(self.cursor.row + 1, self.lines.items.len);
        var row = insert_row;
        var inserted: usize = 0;
        errdefer {
            while (inserted > 0) : (inserted -= 1) {
                const removed = self.lines.orderedRemove(insert_row);
                self.allocator.free(removed);
            }
        }
        if (text.len == 0) {
            try self.lines.insert(row, try self.allocator.dupe(u8, ""));
            inserted = 1;
        } else {
            var it = std.mem.splitScalar(u8, text, '\n');
            while (it.next()) |line| : (row += 1) {
                try self.lines.insert(row, try self.allocator.dupe(u8, line));
                inserted += 1;
            }
        }

        self.cursor.row = insert_row;
        self.cursor.col = 0;
        self.clearHistory(&self.redo_stack);
        self.dirty = true;
    }

    pub fn deleteRange(self: *Buffer, start: Position, end: Position) ![]u8 {
        const text = try self.serialize();
        defer self.allocator.free(text);
        return try self.extractRangeAndReplace(start, end, "", text);
    }

    pub fn replaceRangeWithText(self: *Buffer, start: Position, end: Position, replacement: []const u8) !void {
        const text = try self.serialize();
        defer self.allocator.free(text);
        try self.replaceRange(start, end, replacement, text);
    }

    pub fn wordBounds(self: *const Buffer) ?struct { start: Position, end: Position } {
        const line = self.currentLine();
        if (line.len == 0) return null;
        var start_col = @min(self.cursor.col, line.len);
        if (start_col == line.len and start_col > 0) start_col -= 1;
        while (start_col > 0 and isWordChar(line[start_col - 1])) : (start_col -= 1) {}
        var end_col = @min(self.cursor.col, line.len);
        while (end_col < line.len and isWordChar(line[end_col])) : (end_col += 1) {}
        return .{
            .start = .{ .row = self.cursor.row, .col = start_col },
            .end = .{ .row = self.cursor.row, .col = end_col },
        };
    }

    pub fn cursorOffset(self: *const Buffer) usize {
        var offset: usize = 0;
        var row: usize = 0;
        while (row < self.cursor.row and row < self.lines.items.len) : (row += 1) {
            offset += self.lines.items[row].len;
            if (row + 1 < self.lines.items.len) offset += 1;
        }
        offset += @min(self.cursor.col, self.lines.items[self.cursor.row].len);
        return offset;
    }

    fn setCursorFromOffset(self: *Buffer, offset: usize) void {
        var remaining = offset;
        var row: usize = 0;
        while (row < self.lines.items.len) : (row += 1) {
            const line = self.lines.items[row];
            if (remaining <= line.len) {
                self.cursor.row = row;
                self.cursor.col = remaining;
                return;
            }
            remaining -= line.len;
            if (row + 1 < self.lines.items.len) {
                if (remaining == 0) {
                    self.cursor.row = row;
                    self.cursor.col = line.len;
                    return;
                }
                remaining -= 1;
            }
        }
        self.moveToDocumentEnd();
    }

    fn replaceRange(self: *Buffer, start: Position, end: Position, replacement: []const u8, original_text: []const u8) !void {
        try self.pushUndoSnapshot();
        const new_text = try self.buildReplacementText(original_text, start, end, replacement);
        defer self.allocator.free(new_text);
        try self.setText(new_text);
        self.cursor = self.positionAfterReplacement(start, replacement);
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    fn extractRangeAndReplace(self: *Buffer, start: Position, end: Position, replacement: []const u8, original_text: []const u8) ![]u8 {
        try self.pushUndoSnapshot();
        const removed = try self.sliceRange(original_text, start, end);
        errdefer self.allocator.free(removed);
        const new_text = try self.buildReplacementText(original_text, start, end, replacement);
        defer self.allocator.free(new_text);
        try self.setText(new_text);
        self.cursor = self.positionAfterReplacement(start, replacement);
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
        return removed;
    }

    fn positionAfterReplacement(self: *const Buffer, start: Position, replacement: []const u8) Position {
        _ = self;
        var pos = start;
        var it = std.mem.splitScalar(u8, replacement, '\n');
        var first = true;
        while (it.next()) |part| {
            if (first) {
                pos.col += part.len;
                first = false;
            } else {
                pos.row += 1;
                pos.col = part.len;
            }
        }
        return pos;
    }

    fn buildReplacementText(self: *const Buffer, original_text: []const u8, start: Position, end: Position, replacement: []const u8) ![]u8 {
        const start_offset = self.offsetFromText(original_text, start);
        const end_offset = self.offsetFromText(original_text, end);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        try out.appendSlice(original_text[0..start_offset]);
        try out.appendSlice(replacement);
        try out.appendSlice(original_text[end_offset..]);
        return try out.toOwnedSlice();
    }

    fn sliceRange(self: *const Buffer, original_text: []const u8, start: Position, end: Position) ![]u8 {
        const start_offset = self.offsetFromText(original_text, start);
        const end_offset = self.offsetFromText(original_text, end);
        return try self.allocator.dupe(u8, original_text[start_offset..end_offset]);
    }

    fn offsetFromText(self: *const Buffer, text: []const u8, pos: Position) usize {
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

    pub fn insertByte(self: *Buffer, byte: u8) !void {
        try self.pushUndoSnapshot();
        if (byte == '\n') {
            try self.insertNewline();
        } else {
            try self.insertIntoLine(byte);
        }
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn insertSlice(self: *Buffer, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.insertByte(byte);
        }
    }

    pub fn backspace(self: *Buffer) !void {
        if (self.cursor.row == 0 and self.cursor.col == 0) return;
        try self.pushUndoSnapshot();
        if (self.cursor.col > 0) {
            const line = self.lines.items[self.cursor.row];
            const remove_index = self.cursor.col - 1;
            const before = try self.allocator.dupe(u8, line[0..remove_index]);
            const after = try self.allocator.dupe(u8, line[self.cursor.col..]);
            self.allocator.free(line);
            var merged = try self.allocator.alloc(u8, before.len + after.len);
            @memcpy(merged[0..before.len], before);
            @memcpy(merged[before.len..], after);
            self.allocator.free(before);
            self.allocator.free(after);
            self.lines.items[self.cursor.row] = merged;
            self.cursor.col -= 1;
        } else {
            const prev_row = self.cursor.row - 1;
            const prev_line = self.lines.items[prev_row];
            const curr_line = self.lines.items[self.cursor.row];
            const prev_len = prev_line.len;
            const merged_len = prev_line.len + curr_line.len;
            var merged = try self.allocator.alloc(u8, merged_len);
            @memcpy(merged[0..prev_line.len], prev_line);
            @memcpy(merged[prev_line.len..], curr_line);
            self.allocator.free(prev_line);
            self.allocator.free(curr_line);
            self.lines.items[prev_row] = merged;
            _ = self.lines.orderedRemove(self.cursor.row);
            self.cursor.row = prev_row;
            self.cursor.col = prev_len;
        }
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn deleteForward(self: *Buffer) !void {
        try self.pushUndoSnapshot();
        const line = self.lines.items[self.cursor.row];
        if (self.cursor.col < line.len) {
            const before = try self.allocator.dupe(u8, line[0..self.cursor.col]);
            const after = try self.allocator.dupe(u8, line[self.cursor.col + 1 ..]);
            self.allocator.free(line);
            var merged = try self.allocator.alloc(u8, before.len + after.len);
            @memcpy(merged[0..before.len], before);
            @memcpy(merged[before.len..], after);
            self.allocator.free(before);
            self.allocator.free(after);
            self.lines.items[self.cursor.row] = merged;
        } else if (self.cursor.row + 1 < self.lines.items.len) {
            const next = self.lines.items[self.cursor.row + 1];
            var merged = try self.allocator.alloc(u8, line.len + next.len);
            @memcpy(merged[0..line.len], line);
            @memcpy(merged[line.len..], next);
            self.allocator.free(line);
            self.allocator.free(next);
            self.lines.items[self.cursor.row] = merged;
            _ = self.lines.orderedRemove(self.cursor.row + 1);
        }
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn insertNewline(self: *Buffer) !void {
        const line = self.lines.items[self.cursor.row];
        const left = try self.allocator.dupe(u8, line[0..self.cursor.col]);
        const right = try self.allocator.dupe(u8, line[self.cursor.col..]);
        self.allocator.free(line);
        self.lines.items[self.cursor.row] = left;
        try self.lines.insert(self.cursor.row + 1, right);
        self.cursor.row += 1;
        self.cursor.col = 0;
        self.bumpGeneration();
    }

    pub fn insertBlankLineBelow(self: *Buffer) !void {
        try self.pushUndoSnapshot();
        const empty = try self.allocator.dupe(u8, "");
        try self.lines.insert(self.cursor.row + 1, empty);
        self.cursor.row += 1;
        self.cursor.col = 0;
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn insertBlankLineBelowIndented(self: *Buffer, indent: usize) !void {
        try self.pushUndoSnapshot();
        const blank = try self.allocator.alloc(u8, indent);
        @memset(blank, ' ');
        try self.lines.insert(self.cursor.row + 1, blank);
        self.cursor.row += 1;
        self.cursor.col = indent;
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn insertBlankLineAbove(self: *Buffer) !void {
        try self.pushUndoSnapshot();
        const empty = try self.allocator.dupe(u8, "");
        try self.lines.insert(self.cursor.row, empty);
        self.cursor.col = 0;
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn insertBlankLineAboveIndented(self: *Buffer, indent: usize) !void {
        try self.pushUndoSnapshot();
        const blank = try self.allocator.alloc(u8, indent);
        @memset(blank, ' ');
        try self.lines.insert(self.cursor.row, blank);
        self.cursor.col = indent;
        self.clearHistory(&self.redo_stack);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn undo(self: *Buffer) !void {
        if (self.undo_stack.items.len == 0) return;
        const current = try self.captureUndoSnapshot();
        try self.redo_stack.append(current);
        const snap = self.undo_stack.pop() orelse return;
        try self.restoreSnapshot(snap);
        self.freeSnapshot(snap);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn redo(self: *Buffer) !void {
        if (self.redo_stack.items.len == 0) return;
        const current = try self.captureUndoSnapshot();
        try self.undo_stack.append(current);
        const snap = self.redo_stack.pop() orelse return;
        try self.restoreSnapshot(snap);
        self.freeSnapshot(snap);
        self.bumpGeneration();
        self.dirty = true;
    }

    pub fn search(self: *const Buffer, needle: []const u8) ?Position {
        if (needle.len == 0) return null;
        var row: usize = 0;
        while (row < self.lines.items.len) : (row += 1) {
            if (std.mem.indexOf(u8, self.lines.items[row], needle)) |col| {
                return .{ .row = row, .col = col };
            }
        }
        return null;
    }

    fn pushUndoSnapshot(self: *Buffer) !void {
        try self.undo_stack.append(try self.captureUndoSnapshot());
    }

    fn pushUndoSnapshotText(self: *Buffer, text: []const u8, cursor: Position) !void {
        try self.undo_stack.append(.{
            .text = try self.allocator.dupe(u8, text),
            .row = cursor.row,
            .col = cursor.col,
        });
    }

    fn paragraphFoldRange(self: *const Buffer) ?struct { start_row: usize, end_row: usize } {
        if (self.lines.items.len == 0) return null;
        const row = @min(self.cursor.row, self.lines.items.len - 1);
        if (self.lines.items[row].len == 0) return null;
        var start = row;
        while (start > 0 and self.lines.items[start - 1].len != 0) : (start -= 1) {}
        var end = row;
        while (end + 1 < self.lines.items.len and self.lines.items[end + 1].len != 0) : (end += 1) {}
        return .{ .start_row = start, .end_row = end };
    }

    fn captureUndoSnapshot(self: *const Buffer) !UndoSnapshot {
        const text = try self.serialize();
        return .{ .text = text, .row = self.cursor.row, .col = self.cursor.col };
    }

    fn restoreSnapshot(self: *Buffer, snap: UndoSnapshot) !void {
        try self.setText(snap.text);
        self.cursor = .{ .row = snap.row, .col = snap.col };
        self.dirty = true;
        self.bumpGeneration();
    }

    fn freeSnapshot(self: *Buffer, snap: UndoSnapshot) void {
        self.allocator.free(snap.text);
    }

    fn clearHistory(self: *Buffer, history: *std.array_list.Managed(UndoSnapshot)) void {
        for (history.items) |snap| {
            self.allocator.free(snap.text);
        }
        history.clearRetainingCapacity();
    }

    fn bumpGeneration(self: *Buffer) void {
        self.generation += 1;
    }

    fn updateFiletype(self: *Buffer) !void {
        const next = if (self.path) |path| deriveFiletype(path) else "text";
        self.allocator.free(self.filetype);
        self.filetype = try self.allocator.dupe(u8, next);
    }

    fn clearLines(self: *Buffer) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
    }

    fn loadTextIntoLines(self: *Buffer, text: []const u8) !void {
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            try self.lines.append(try self.allocator.dupe(u8, line));
        }
        if (self.lines.items.len == 0) {
            try self.lines.append(try self.allocator.dupe(u8, ""));
        }
    }

    fn insertIntoLine(self: *Buffer, byte: u8) !void {
        const line = self.lines.items[self.cursor.row];
        const new_len = line.len + 1;
        var new_line = try self.allocator.alloc(u8, new_len);
        @memcpy(new_line[0..self.cursor.col], line[0..self.cursor.col]);
        new_line[self.cursor.col] = byte;
        @memcpy(new_line[self.cursor.col + 1 ..], line[self.cursor.col..]);
        self.allocator.free(line);
        self.lines.items[self.cursor.row] = new_line;
        self.cursor.col += 1;
    }

    pub fn serialize(self: *const Buffer) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        for (self.lines.items, 0..) |line, idx| {
            try out.appendSlice(line);
            if (idx + 1 < self.lines.items.len) {
                try out.append('\n');
            }
        }
        return try out.toOwnedSlice();
    }
};

fn deriveFiletype(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return "text";
    return ext[1..];
}

fn detectLineEnding(text: []const u8) LineEnding {
    if (std.mem.indexOf(u8, text, "\r\n") != null) return .crlf;
    if (std.mem.indexOfScalar(u8, text, '\r') != null) return .cr;
    if (text.len > 0) return .lf;
    return .unknown;
}

test "buffer edit and undo" {
    var buffer = try Buffer.initEmpty(std.testing.allocator);
    defer buffer.deinit();

    try buffer.insertSlice("abc");
    try std.testing.expectEqualStrings("abc", buffer.currentLine());
    try buffer.backspace();
    try std.testing.expectEqualStrings("ab", buffer.currentLine());
    try buffer.undo();
    try std.testing.expectEqualStrings("abc", buffer.currentLine());
}

test "buffer search" {
    var buffer = try Buffer.initEmpty(std.testing.allocator);
    defer buffer.deinit();
    try buffer.setText("hello\nworld\nzig");
    const found = buffer.search("wor") orelse return error.TestExpected;
    try std.testing.expectEqual(@as(usize, 1), found.row);
    try std.testing.expectEqual(@as(usize, 0), found.col);
}

test "buffer cursor clamps to available lines and columns" {
    var buffer = try Buffer.initEmpty(std.testing.allocator);
    defer buffer.deinit();
    try buffer.setText("alpha\nbeta");

    buffer.setCursor(99, 99);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor.col);

    buffer.moveToLine(99);
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);

    buffer.moveToDocumentEnd();
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor.col);

    buffer.moveLineEnd();
    try std.testing.expectEqual(@as(usize, 1), buffer.cursor.row);
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor.col);
}

test "buffer tracks file metadata from its path" {
    var buffer = try Buffer.initEmpty(std.testing.allocator);
    defer buffer.deinit();

    try std.testing.expectEqualStrings("text", buffer.filetypeText());
    try std.testing.expectEqualStrings("utf-8", buffer.encodingText());
    try std.testing.expectEqualStrings("lf", buffer.lineEndingText());

    try buffer.replacePath("src/main.zig");
    try std.testing.expectEqualStrings("zig", buffer.filetypeText());
}

fn isWordChar(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn isBigWordChar(byte: u8) bool {
    return !std.ascii.isWhitespace(byte);
}

fn nextWordStartInLine(line: []const u8, col: usize, big: bool) usize {
    if (line.len == 0) return 0;
    var idx = @min(col, line.len);
    const pred: *const fn (u8) bool = if (big) isBigWordChar else isWordChar;
    while (idx < line.len and !pred(line[idx])) : (idx += 1) {}
    while (idx < line.len and pred(line[idx])) : (idx += 1) {}
    while (idx < line.len and !pred(line[idx])) : (idx += 1) {}
    return @min(idx, line.len);
}

fn prevWordStartInLine(line: []const u8, col: usize, big: bool) usize {
    if (line.len == 0 or col == 0) return 0;
    const pred: *const fn (u8) bool = if (big) isBigWordChar else isWordChar;
    var idx = @min(col, line.len);
    if (idx > 0) idx -= 1;
    while (idx > 0 and !pred(line[idx])) : (idx -= 1) {}
    while (idx > 0 and pred(line[idx - 1])) : (idx -= 1) {}
    return idx;
}

fn nextWordEndInLine(line: []const u8, col: usize, big: bool) usize {
    if (line.len == 0) return 0;
    const pred: *const fn (u8) bool = if (big) isBigWordChar else isWordChar;
    var idx = @min(col, line.len);
    if (idx < line.len and !pred(line[idx])) {
        while (idx < line.len and !pred(line[idx])) : (idx += 1) {}
    }
    while (idx < line.len and pred(line[idx])) : (idx += 1) {}
    if (idx > 0) idx -= 1;
    return idx;
}

fn prevWordEndInLine(line: []const u8, col: usize, big: bool) usize {
    if (line.len == 0 or col == 0) return 0;
    const pred: *const fn (u8) bool = if (big) isBigWordChar else isWordChar;
    var idx = @min(col, line.len);
    if (idx > 0) idx -= 1;
    while (idx > 0 and !pred(line[idx])) : (idx -= 1) {}
    while (idx > 0 and pred(line[idx - 1])) : (idx -= 1) {}
    while (idx < line.len and pred(line[idx])) : (idx += 1) {}
    if (idx > 0) idx -= 1;
    return idx;
}
