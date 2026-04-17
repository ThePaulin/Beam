const std = @import("std");
const buffer_mod = @import("buffer.zig");
const diagnostics_mod = @import("diagnostics.zig");
const ts = @import("tree-sitter");
const zig_ts = @import("tree-sitter-zig");
const ts_queries = @import("tree-sitter-queries");

const zig_highlights_query_source = ts_queries.zig_highlights_query_source;
const zig_locals_query_source = ts_queries.zig_locals_query_source;
const zig_folds_query_source = ts_queries.zig_folds_query_source;

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
    filetype: []u8,
    text: []u8,
    dirty_range: ?DirtyRange = null,
    parser: ?*ts.Parser = null,
    tree: ?*ts.Tree = null,
    last_error: ?[]u8 = null,
};

pub const Service = struct {
    allocator: std.mem.Allocator,
    snapshots: std.array_list.Managed(SnapshotState),
    zig_highlights_query: ?*ts.Query = null,
    zig_locals_query: ?*ts.Query = null,
    zig_folds_query: ?*ts.Query = null,

    pub fn init(allocator: std.mem.Allocator) Service {
        return .{
            .allocator = allocator,
            .snapshots = std.array_list.Managed(SnapshotState).init(allocator),
        };
    }

    pub fn deinit(self: *Service) void {
        self.clear();
        if (self.zig_highlights_query) |query| query.destroy();
        if (self.zig_locals_query) |query| query.destroy();
        if (self.zig_folds_query) |query| query.destroy();
        self.snapshots.deinit();
    }

    pub fn clear(self: *Service) void {
        for (self.snapshots.items) |*snapshot| {
            self.destroyState(snapshot);
        }
        self.snapshots.clearRetainingCapacity();
    }

    pub fn clearBuffer(self: *Service, buffer_id: u64) void {
        var idx: usize = 0;
        while (idx < self.snapshots.items.len) {
            if (self.snapshots.items[idx].buffer_id == buffer_id) {
                var snapshot = self.snapshots.orderedRemove(idx);
                self.destroyState(&snapshot);
                continue;
            }
            idx += 1;
        }
    }

    pub fn updateSnapshot(self: *Service, snapshot: buffer_mod.ReadSnapshot) !void {
        if (self.findSnapshotIndex(snapshot.buffer_id)) |idx| {
            if (self.snapshots.items[idx].generation > snapshot.generation) return;

            const next_text = try self.allocator.dupe(u8, snapshot.text);
            errdefer self.allocator.free(next_text);
            const next_filetype = try self.allocator.dupe(u8, snapshot.filetype);
            errdefer self.allocator.free(next_filetype);

            const state = &self.snapshots.items[idx];
            const previous_text = state.text;
            const previous_filetype = state.filetype;

            state.dirty_range = self.computeDirtyRange(previous_text, next_text);
            state.text = next_text;
            state.filetype = next_filetype;
            state.generation = snapshot.generation;

            if (isZigFiletype(state.filetype)) {
                self.updateZigState(state, previous_text) catch {};
            } else {
                self.clearSyntaxState(state);
                self.clearError(state);
            }

            self.allocator.free(previous_text);
            self.allocator.free(previous_filetype);
            return;
        }

        const next_text = try self.allocator.dupe(u8, snapshot.text);
        errdefer self.allocator.free(next_text);
        const next_filetype = try self.allocator.dupe(u8, snapshot.filetype);
        errdefer self.allocator.free(next_filetype);

        var state: SnapshotState = .{
            .buffer_id = snapshot.buffer_id,
            .generation = snapshot.generation,
            .filetype = next_filetype,
            .text = next_text,
            .dirty_range = null,
        };
        state.dirty_range = null;
        if (isZigFiletype(state.filetype)) {
            self.updateZigState(&state, "") catch {};
        }
        try self.snapshots.append(state);
    }

    pub fn snapshotGeneration(self: *const Service, buffer_id: u64) ?u64 {
        if (self.findSnapshotIndex(buffer_id)) |idx| {
            return self.snapshots.items[idx].generation;
        }
        return null;
    }

    pub fn isFresh(self: *const Service, snapshot: buffer_mod.ReadSnapshot) bool {
        return self.snapshotGeneration(snapshot.buffer_id) == snapshot.generation;
    }

    pub fn dirtyRangeForBuffer(self: *const Service, buffer_id: u64) ?DirtyRange {
        if (self.findSnapshotIndex(buffer_id)) |idx| {
            return self.snapshots.items[idx].dirty_range;
        }
        return null;
    }

    pub fn foldRangeForSnapshot(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?FoldRange {
        if (self.foldRangeFromTree(snapshot)) |range| return range;
        return foldRangeFromText(snapshot.text, snapshot.cursor);
    }

    pub fn nodeAtCursor(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?Node {
        if (self.nodeAtCursorFromTree(snapshot)) |node| return node;
        return nodeAtCursorFromText(snapshot.text, snapshot.cursor);
    }

    pub fn enclosingScope(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?FoldRange {
        if (self.enclosingScopeFromTree(snapshot)) |range| return range;
        return enclosingScopeFromText(snapshot.text, snapshot.cursor);
    }

    pub fn indentForRow(self: *const Service, snapshot: buffer_mod.ReadSnapshot, row: usize) usize {
        if (self.indentForRowFromTree(snapshot, row)) |indent| return indent;
        return indentForRowFromText(snapshot.text, row);
    }

    pub fn textObjectRange(self: *const Service, snapshot: buffer_mod.ReadSnapshot, inner: bool) ?TextRange {
        if (self.textObjectRangeFromTree(snapshot, inner)) |range| return range;
        return blockObjectRangeFromText(snapshot.text, snapshot.cursor, inner);
    }

    pub fn statusText(self: *const Service, allocator: std.mem.Allocator, buffer_id: u64, filetype: []const u8) ![]u8 {
        if (!isZigFiletype(filetype)) return allocator.dupe(u8, "");
        const idx = self.findSnapshotIndex(buffer_id) orelse return allocator.dupe(u8, "ts zig");
        const state = self.snapshots.items[idx];
        if (state.last_error) |err| {
            return std.fmt.allocPrint(allocator, "ts zig: {s}", .{err});
        }
        if (state.tree == null) {
            return allocator.dupe(u8, "ts zig fallback");
        }
        const parser_ready = state.parser != null;
        const queries_ready = self.zig_folds_query != null and self.zig_locals_query != null and self.zig_highlights_query != null;
        if (parser_ready and queries_ready) return allocator.dupe(u8, "ts zig parser+queries");
        if (parser_ready) return allocator.dupe(u8, "ts zig parser");
        return allocator.dupe(u8, "ts zig tree");
    }

    pub fn hasParsedTree(self: *const Service, buffer_id: u64) bool {
        const state = self.snapshotState(buffer_id) orelse return false;
        return state.tree != null;
    }

    pub fn applyDecorations(self: *Service, store: *diagnostics_mod.Store, snapshot: buffer_mod.ReadSnapshot) !void {
        store.clearBufferSource(snapshot.buffer_id, .treesitter);
        if (!isZigFiletype(snapshot.filetype)) return;

        const state = self.snapshotStateMutable(snapshot.buffer_id) orelse return;
        if (!stateMatchesSnapshot(state, snapshot) or state.tree == null) return;
        const root = state.tree.?.rootNode();

        self.ensureZigQueries() catch |err| {
            self.setError(state, "tree-sitter query failed") catch {};
            return err;
        };

        if (self.zig_locals_query) |query| {
            try self.applyQueryDecorations(store, snapshot.buffer_id, root, query, .hint);
        }
        if (self.zig_highlights_query) |query| {
            try self.applyQueryDecorations(store, snapshot.buffer_id, root, query, .highlight);
        }
    }

    fn destroyState(self: *Service, state: *SnapshotState) void {
        self.clearSyntaxState(state);
        self.clearError(state);
        self.allocator.free(state.filetype);
        self.allocator.free(state.text);
    }

    fn clearSyntaxState(self: *Service, state: *SnapshotState) void {
        _ = self;
        if (state.tree) |tree| tree.destroy();
        if (state.parser) |parser| parser.destroy();
        state.tree = null;
        state.parser = null;
    }

    fn clearError(self: *Service, state: *SnapshotState) void {
        if (state.last_error) |err| self.allocator.free(err);
        state.last_error = null;
    }

    fn setError(self: *Service, state: *SnapshotState, message: []const u8) !void {
        self.clearError(state);
        state.last_error = try self.allocator.dupe(u8, message);
    }

    fn ensureZigQueries(self: *Service) !void {
        if (self.zig_locals_query == null) {
            var error_offset: u32 = 0;
            const query = try ts.Query.create(zigLanguage(), zig_locals_query_source, &error_offset);
            self.zig_locals_query = query;
        }
        if (self.zig_highlights_query == null) {
            var error_offset: u32 = 0;
            const query = try ts.Query.create(zigLanguage(), zig_highlights_query_source, &error_offset);
            self.zig_highlights_query = query;
        }
        if (self.zig_folds_query == null) {
            var error_offset: u32 = 0;
            const query = try ts.Query.create(zigLanguage(), zig_folds_query_source, &error_offset);
            self.zig_folds_query = query;
        }
    }

    fn ensureZigParser(self: *Service, state: *SnapshotState) !void {
        if (state.parser != null) return;
        const parser = ts.Parser.create();
        errdefer parser.destroy();
        parser.setLanguage(zigLanguage()) catch {
            try self.setError(state, "tree-sitter zig language is incompatible");
            return error.IncompatibleVersion;
        };
        state.parser = parser;
    }

    fn updateZigState(self: *Service, state: *SnapshotState, previous_text: []const u8) !void {
        try self.ensureZigParser(state);
        const parser = state.parser orelse return;

        var old_tree_copy: ?*ts.Tree = null;
        if (state.tree) |tree| {
            old_tree_copy = tree.dupe();
            if (computeInputEdit(previous_text, state.text)) |edit| {
                old_tree_copy.?.edit(edit);
            }
        }

        const parsed = parser.parseString(state.text, if (old_tree_copy) |copy| copy else null);
        if (old_tree_copy) |copy| copy.destroy();

        if (parsed) |tree| {
            if (state.tree) |old_tree| old_tree.destroy();
            state.tree = tree;
            self.clearError(state);
            return;
        }

        if (state.tree) |old_tree| {
            old_tree.destroy();
            state.tree = null;
        }
        try self.setError(state, "tree-sitter parse failed");
    }

    fn applyQueryDecorations(self: *Service, store: *diagnostics_mod.Store, buffer_id: u64, root: ts.Node, query: *const ts.Query, kind: diagnostics_mod.DecorationKind) !void {
        _ = self;
        var cursor = ts.QueryCursor.create();
        defer cursor.destroy();
        cursor.exec(query, root);

        while (cursor.nextMatch()) |match| {
            for (match.captures) |capture| {
                const capture_name = query.captureNameForId(capture.index) orelse continue;
                const label = decorationLabelForCapture(capture_name) orelse continue;
                const node = capture.node;
                const start = node.startPoint();
                const end = node.endPoint();
                const start_col: usize = @intCast(start.column);
                const len: usize = if (end.column > start.column) @max(@as(usize, @intCast(end.column - start.column)), 1) else 1;
                try store.addTreeDecoration(
                    buffer_id,
                    @intCast(start.row),
                    start_col,
                    len,
                    label,
                    kind,
                );
                break;
            }
        }
    }

    fn foldRangeFromQuery(self: *const Service, root: ts.Node, cursor_pos: buffer_mod.Position) ?FoldRange {
        const query = self.zig_folds_query orelse return null;
        var cursor = ts.QueryCursor.create();
        defer cursor.destroy();
        cursor.exec(query, root);

        const point = pointFromPosition(cursor_pos);
        var best: ?FoldRange = null;
        while (cursor.nextMatch()) |match| {
            for (match.captures) |capture| {
                const node = capture.node;
                const start = node.startPoint();
                const end = node.endPoint();
                if (start.row == end.row) continue;
                if (!pointWithinRange(point, start, end)) continue;
                const range: FoldRange = .{ .start_row = start.row, .end_row = end.row };
                if (best == null or rangeSpan(range) < rangeSpan(best.?)) best = range;
                break;
            }
        }
        return best;
    }

    fn findSnapshotIndex(self: *const Service, buffer_id: u64) ?usize {
        for (self.snapshots.items, 0..) |snapshot, idx| {
            if (snapshot.buffer_id == buffer_id) return idx;
        }
        return null;
    }

    fn foldRangeFromTree(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?FoldRange {
        const state = self.snapshotState(snapshot.buffer_id) orelse return null;
        if (!stateMatchesSnapshot(state, snapshot) or state.tree == null) return null;
        if (self.foldRangeFromQuery(state.tree.?.rootNode(), snapshot.cursor)) |range| return range;
        const node = bestStructuralNodeAtPoint(state.tree.?.rootNode(), pointFromPosition(snapshot.cursor)) orelse return null;
        if (node.startPoint().row == node.endPoint().row) return null;
        return .{ .start_row = node.startPoint().row, .end_row = node.endPoint().row };
    }

    fn nodeAtCursorFromTree(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?Node {
        const state = self.snapshotState(snapshot.buffer_id) orelse return null;
        if (!stateMatchesSnapshot(state, snapshot) or state.tree == null) return null;
        const point = pointFromPosition(snapshot.cursor);
        const node = bestStructuralNodeAtPoint(state.tree.?.rootNode(), point) orelse return null;
        return mapNode(node);
    }

    fn enclosingScopeFromTree(self: *const Service, snapshot: buffer_mod.ReadSnapshot) ?FoldRange {
        return self.foldRangeFromTree(snapshot);
    }

    fn indentForRowFromTree(self: *const Service, snapshot: buffer_mod.ReadSnapshot, row: usize) ?usize {
        const state = self.snapshotState(snapshot.buffer_id) orelse return null;
        if (!stateMatchesSnapshot(state, snapshot) or state.tree == null) return null;
        const root = state.tree.?.rootNode();
        const point: ts.Point = .{ .row = @intCast(row), .column = 0 };
        const node = root.namedDescendantForPointRange(point, point) orelse root;
        var depth: usize = 0;
        var current: ?ts.Node = node;
        while (current) |value| {
            if (isIndentContainerKind(value.kind()) and value.startPoint().row < point.row and value.endPoint().row >= point.row) {
                depth += 1;
            }
            current = value.parent();
        }
        return depth * 2;
    }

    fn textObjectRangeFromTree(self: *const Service, snapshot: buffer_mod.ReadSnapshot, inner: bool) ?TextRange {
        const state = self.snapshotState(snapshot.buffer_id) orelse return null;
        if (!stateMatchesSnapshot(state, snapshot) or state.tree == null) return null;
        const point = pointFromPosition(snapshot.cursor);
        const node = bestStructuralNodeAtPoint(state.tree.?.rootNode(), point) orelse return null;
        if (!inner) {
            return .{
                .start = positionFromPoint(node.startPoint()),
                .end = positionFromPoint(node.endPoint()),
            };
        }
        if (node.namedChildCount() > 0) {
            const first = node.namedChild(0) orelse return .{
                .start = positionFromPoint(node.startPoint()),
                .end = positionFromPoint(node.endPoint()),
            };
            const last = node.namedChild(node.namedChildCount() - 1) orelse first;
            const start = positionFromPoint(first.startPoint());
            const end = positionFromPoint(last.endPoint());
            if (comparePositions(start, end) != .gt) {
                return .{ .start = start, .end = end };
            }
        }
        return .{
            .start = positionFromPoint(node.startPoint()),
            .end = positionFromPoint(node.endPoint()),
        };
    }

    fn snapshotState(self: *const Service, buffer_id: u64) ?*const SnapshotState {
        if (self.findSnapshotIndex(buffer_id)) |idx| return &self.snapshots.items[idx];
        return null;
    }

    fn snapshotStateMutable(self: *Service, buffer_id: u64) ?*SnapshotState {
        if (self.findSnapshotIndex(buffer_id)) |idx| return &self.snapshots.items[idx];
        return null;
    }

    fn stateMatchesSnapshot(state: *const SnapshotState, snapshot: buffer_mod.ReadSnapshot) bool {
        return state.buffer_id == snapshot.buffer_id and state.generation == snapshot.generation;
    }

    fn computeDirtyRange(self: *const Service, previous_text: []const u8, next_text: []const u8) ?DirtyRange {
        _ = self;
        const prev_lines = lineCount(previous_text);
        const next_lines = lineCount(next_text);
        const line_limit = @max(prev_lines, next_lines);
        var first: ?usize = null;
        var last: ?usize = null;
        var row: usize = 0;
        while (row < line_limit) : (row += 1) {
            const prev_line = lineAt(previous_text, row);
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

fn zigLanguage() *const ts.Language {
    return @ptrCast(zig_ts.language());
}

fn pointFromPosition(position: buffer_mod.Position) ts.Point {
    return .{
        .row = @intCast(position.row),
        .column = @intCast(position.col),
    };
}

fn positionFromPoint(point: ts.Point) buffer_mod.Position {
    return .{
        .row = point.row,
        .col = point.column,
    };
}

fn comparePositions(left: buffer_mod.Position, right: buffer_mod.Position) std.math.Order {
    if (left.row < right.row) return .lt;
    if (left.row > right.row) return .gt;
    if (left.col < right.col) return .lt;
    if (left.col > right.col) return .gt;
    return .eq;
}

fn pointWithinRange(point: ts.Point, start: ts.Point, end: ts.Point) bool {
    if (point.row < start.row or (point.row == start.row and point.column < start.column)) return false;
    if (point.row > end.row or (point.row == end.row and point.column > end.column)) return false;
    return true;
}

fn rangeSpan(range: FoldRange) usize {
    if (range.end_row <= range.start_row) return 0;
    return range.end_row - range.start_row;
}

fn isZigFiletype(filetype: []const u8) bool {
    return std.mem.eql(u8, filetype, "zig");
}

fn decorationLabelForCapture(capture_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, capture_name, "local.scope")) return null;
    if (std.mem.eql(u8, capture_name, "local.reference")) return "ref";
    if (std.mem.startsWith(u8, capture_name, "local.definition.")) {
        const suffix = capture_name["local.definition.".len..];
        return if (std.mem.eql(u8, suffix, "function"))
            "def fn"
        else if (std.mem.eql(u8, suffix, "parameter"))
            "def arg"
        else if (std.mem.eql(u8, suffix, "var"))
            "def var"
        else if (std.mem.eql(u8, suffix, "type"))
            "def type"
        else if (std.mem.eql(u8, suffix, "field"))
            "def field"
        else if (std.mem.eql(u8, suffix, "method"))
            "def method"
        else if (std.mem.eql(u8, suffix, "label"))
            "def label"
        else
            "def";
    }
    if (std.mem.startsWith(u8, capture_name, "keyword.")) return "kw";
    if (std.mem.eql(u8, capture_name, "function") or std.mem.startsWith(u8, capture_name, "function.")) return "fn";
    if (std.mem.eql(u8, capture_name, "type") or std.mem.startsWith(u8, capture_name, "type.")) return "type";
    if (std.mem.eql(u8, capture_name, "constant") or std.mem.startsWith(u8, capture_name, "constant.")) return "const";
    if (std.mem.eql(u8, capture_name, "variable") or std.mem.startsWith(u8, capture_name, "variable.")) return "var";
    if (std.mem.eql(u8, capture_name, "label")) return "label";
    if (std.mem.eql(u8, capture_name, "module")) return "mod";
    return null;
}

fn isStructuralKind(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "function_declaration")
        or std.mem.eql(u8, kind, "block")
        or std.mem.eql(u8, kind, "block_expression")
        or std.mem.eql(u8, kind, "if_statement")
        or std.mem.eql(u8, kind, "while_statement")
        or std.mem.eql(u8, kind, "for_statement")
        or std.mem.eql(u8, kind, "switch_expression")
        or std.mem.eql(u8, kind, "struct_declaration")
        or std.mem.eql(u8, kind, "enum_declaration")
        or std.mem.eql(u8, kind, "union_declaration")
        or std.mem.eql(u8, kind, "opaque_declaration")
        or std.mem.eql(u8, kind, "test_declaration")
        or std.mem.eql(u8, kind, "comptime_declaration")
        or std.mem.eql(u8, kind, "source_file");
}

fn isIndentContainerKind(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "block")
        or std.mem.eql(u8, kind, "block_expression")
        or std.mem.eql(u8, kind, "if_statement")
        or std.mem.eql(u8, kind, "while_statement")
        or std.mem.eql(u8, kind, "for_statement")
        or std.mem.eql(u8, kind, "switch_expression")
        or std.mem.eql(u8, kind, "struct_declaration")
        or std.mem.eql(u8, kind, "enum_declaration")
        or std.mem.eql(u8, kind, "union_declaration")
        or std.mem.eql(u8, kind, "opaque_declaration")
        or std.mem.eql(u8, kind, "test_declaration");
}

fn mapNode(node: ts.Node) Node {
    return .{
        .kind = mapNodeKind(node.kind()),
        .start = positionFromPoint(node.startPoint()),
        .end = positionFromPoint(node.endPoint()),
    };
}

fn mapNodeKind(kind: []const u8) NodeKind {
    if (std.mem.eql(u8, kind, "source_file")) return .root;
    if (std.mem.eql(u8, kind, "function_declaration") or std.mem.eql(u8, kind, "test_declaration") or std.mem.eql(u8, kind, "comptime_declaration")) return .function;
    if (std.mem.eql(u8, kind, "block") or std.mem.eql(u8, kind, "block_expression") or std.mem.eql(u8, kind, "if_statement") or std.mem.eql(u8, kind, "while_statement") or std.mem.eql(u8, kind, "for_statement") or std.mem.eql(u8, kind, "switch_expression")) return .block;
    if (isStructuralKind(kind)) return .scope;
    return .word;
}

fn bestStructuralNodeAtPoint(start: ts.Node, point: ts.Point) ?ts.Node {
    var current: ts.Node = start.namedDescendantForPointRange(point, point) orelse start;
    var best: ts.Node = current;
    while (current.parent()) |parent| {
        if (!nodeContainsPoint(parent, point)) break;
        if (isStructuralKind(parent.kind()) and !std.mem.eql(u8, parent.kind(), "source_file")) best = parent;
        current = parent;
    }
    if (!isStructuralKind(best.kind()) and best.namedChildCount() == 0 and best.childCount() == 0) {
        return current;
    }
    return best;
}

fn nodeContainsPoint(node: ts.Node, point: ts.Point) bool {
    const start = node.startPoint();
    const end = node.endPoint();
    if (point.row < start.row or (point.row == start.row and point.column < start.column)) return false;
    if (point.row > end.row or (point.row == end.row and point.column > end.column)) return false;
    return true;
}

fn computeInputEdit(previous_text: []const u8, next_text: []const u8) ?ts.InputEdit {
    if (std.mem.eql(u8, previous_text, next_text)) return null;
    var prefix: usize = 0;
    const prefix_limit = @min(previous_text.len, next_text.len);
    while (prefix < prefix_limit and previous_text[prefix] == next_text[prefix]) : (prefix += 1) {}

    var suffix: usize = 0;
    while (suffix < previous_text.len - prefix and suffix < next_text.len - prefix) : (suffix += 1) {
        if (previous_text[previous_text.len - 1 - suffix] != next_text[next_text.len - 1 - suffix]) break;
    }

    const old_end = previous_text.len - suffix;
    const new_end = next_text.len - suffix;
    return .{
        .start_byte = @intCast(prefix),
        .old_end_byte = @intCast(old_end),
        .new_end_byte = @intCast(new_end),
        .start_point = offsetToPoint(previous_text, prefix),
        .old_end_point = offsetToPoint(previous_text, old_end),
        .new_end_point = offsetToPoint(next_text, new_end),
    };
}

fn offsetToPoint(text: []const u8, offset: usize) ts.Point {
    var row: usize = 0;
    var col: usize = 0;
    var idx: usize = 0;
    while (idx < @min(offset, text.len)) : (idx += 1) {
        if (text[idx] == '\n') {
            row += 1;
            col = 0;
        } else {
            col += 1;
        }
    }
    return .{ .row = @intCast(row), .column = @intCast(col) };
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

test "syntax service parses zig code and finds the enclosing function" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 1,
        .generation = 1,
        .cursor = .{ .row = 0, .col = 7 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "pub fn demo() void {\n    const value = 1;\n}\n"),
        .filetype = "zig",
    };
    defer std.testing.allocator.free(snapshot.text);
    try service.updateSnapshot(snapshot);

    const node = service.nodeAtCursor(snapshot) orelse return error.TestExpected;
    try std.testing.expectEqual(NodeKind.function, node.kind);
    try std.testing.expectEqual(@as(usize, 0), node.start.row);
    try std.testing.expectEqual(@as(usize, 2), node.end.row);
}

test "syntax service provides real zig fold ranges" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 2,
        .generation = 1,
        .cursor = .{ .row = 1, .col = 4 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "pub fn demo() void {\n    const value = 1;\n}\n"),
        .filetype = "zig",
    };
    defer std.testing.allocator.free(snapshot.text);
    try service.updateSnapshot(snapshot);

    const fold = service.foldRangeForSnapshot(snapshot) orelse return error.TestExpected;
    try std.testing.expectEqual(@as(usize, 0), fold.start_row);
    try std.testing.expectEqual(@as(usize, 2), fold.end_row);
}

test "syntax service ignores stale snapshots" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot1 = buffer_mod.ReadSnapshot{
        .buffer_id = 3,
        .generation = 2,
        .cursor = .{},
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "alpha"),
        .filetype = "text",
    };
    defer std.testing.allocator.free(snapshot1.text);
    try service.updateSnapshot(snapshot1);

    const snapshot2 = buffer_mod.ReadSnapshot{
        .buffer_id = 3,
        .generation = 1,
        .cursor = .{},
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "beta"),
        .filetype = "text",
    };
    defer std.testing.allocator.free(snapshot2.text);
    try service.updateSnapshot(snapshot2);

    try std.testing.expectEqual(@as(?u64, 2), service.snapshotGeneration(3));
    try std.testing.expect(service.isFresh(snapshot1));
    try std.testing.expect(!service.isFresh(snapshot2));
}

test "syntax service falls back for unsupported filetypes" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 4,
        .generation = 1,
        .cursor = .{ .row = 1, .col = 4 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "fn demo() {\n    value\n}\n"),
        .filetype = "text",
    };
    defer std.testing.allocator.free(snapshot.text);
    try service.updateSnapshot(snapshot);

    const object = service.textObjectRange(snapshot, true) orelse return error.TestExpected;
    try std.testing.expectEqual(@as(usize, 0), object.start.row);
    try std.testing.expectEqual(@as(usize, 2), object.end.row);
}

test "syntax service emits treesitter decorations from zig queries" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();
    var store = diagnostics_mod.Store.init(std.testing.allocator);
    defer store.deinit();

    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 5,
        .generation = 1,
        .cursor = .{ .row = 0, .col = 7 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "pub fn demo() void {\n    const value = 1;\n}\n"),
        .filetype = "zig",
    };
    defer std.testing.allocator.free(snapshot.text);
    try service.updateSnapshot(snapshot);
    try service.applyDecorations(&store, snapshot);

    try std.testing.expect(store.decorationsForSource(.treesitter) > 0);
    const decoration = store.firstDecorationForRow(5, 0) orelse return error.TestExpected;
    try std.testing.expect(decoration.text != null);
}

test "syntax service reports parser and query status separately" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 6,
        .generation = 1,
        .cursor = .{ .row = 0, .col = 0 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "const x = 1;\n"),
        .filetype = "zig",
    };
    defer std.testing.allocator.free(snapshot.text);
    try service.updateSnapshot(snapshot);

    const parser_status = try service.statusText(std.testing.allocator, snapshot.buffer_id, snapshot.filetype);
    defer std.testing.allocator.free(parser_status);
    try std.testing.expect(std.mem.eql(u8, parser_status, "ts zig parser"));

    var store = diagnostics_mod.Store.init(std.testing.allocator);
    defer store.deinit();
    try service.applyDecorations(&store, snapshot);

    const query_status = try service.statusText(std.testing.allocator, snapshot.buffer_id, snapshot.filetype);
    defer std.testing.allocator.free(query_status);
    try std.testing.expect(std.mem.eql(u8, query_status, "ts zig parser+queries"));
}

test "syntax service reports fallback when parser state is unavailable" {
    var service = Service.init(std.testing.allocator);
    defer service.deinit();

    const snapshot = buffer_mod.ReadSnapshot{
        .buffer_id = 7,
        .generation = 1,
        .cursor = .{ .row = 0, .col = 0 },
        .scroll_row = 0,
        .text = try std.testing.allocator.dupe(u8, "const x = 1;\n"),
        .filetype = "zig",
    };
    defer std.testing.allocator.free(snapshot.text);
    try service.updateSnapshot(snapshot);
    service.clearSyntaxState(&service.snapshots.items[0]);

    const fallback_status = try service.statusText(std.testing.allocator, snapshot.buffer_id, snapshot.filetype);
    defer std.testing.allocator.free(fallback_status);
    try std.testing.expect(std.mem.eql(u8, fallback_status, "ts zig fallback"));
}
