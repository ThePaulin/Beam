const std = @import("std");
const listpane_mod = @import("listpane.zig");

pub const SourceKind = enum {
    search,
    diagnostics,
    symbols,
    files,
    custom,
};

pub const SourceSpec = struct {
    command: []const u8,
    kind: SourceKind,
    title: []const u8,
    emit_quickfix: bool = false,
    empty_message: []const u8 = "no results",
    failure_message: []const u8 = "search failed",
    preview: PreviewMode = .detail,
};

pub const PreviewMode = enum {
    none,
    detail,
};

pub const source_specs = [_]SourceSpec{
    .{ .command = "vimgrep", .kind = .search, .title = "quickfix", .emit_quickfix = true, .empty_message = "no matches", .failure_message = "search failed", .preview = .detail },
    .{ .command = "grep", .kind = .search, .title = "quickfix", .emit_quickfix = true, .empty_message = "no matches", .failure_message = "search failed", .preview = .detail },
    .{ .command = "pickgrep", .kind = .search, .title = "picker", .emit_quickfix = true, .empty_message = "no picker matches", .failure_message = "search failed", .preview = .detail },
    .{ .command = "files", .kind = .files, .title = "files", .empty_message = "no files matched", .failure_message = "file search failed", .preview = .detail },
    .{ .command = "symbols", .kind = .symbols, .title = "symbols", .empty_message = "no symbols matched", .failure_message = "symbol search failed", .preview = .detail },
};

pub fn specForCommand(command: []const u8) ?SourceSpec {
    for (source_specs) |spec| {
        if (std.mem.eql(u8, spec.command, command)) return spec;
    }
    return null;
}

pub const SourceKey = struct {
    request_id: u64 = 0,
    snapshot_id: u64 = 0,
    workspace_generation: u64 = 0,
    buffer_id: ?u64 = null,

    pub fn matches(self: SourceKey, other: SourceKey) bool {
        return self.request_id == other.request_id and
            self.snapshot_id == other.snapshot_id and
            self.workspace_generation == other.workspace_generation and
            self.buffer_id == other.buffer_id;
    }
};

pub const AsyncListSource = struct {
    allocator: std.mem.Allocator,
    kind: SourceKind,
    key: SourceKey = .{},
    state: listpane_mod.SourceState = .idle,
    items: std.array_list.Managed(listpane_mod.Item),
    error_message: ?[]u8 = null,
    preview: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, kind: SourceKind) AsyncListSource {
        return .{
            .allocator = allocator,
            .kind = kind,
            .items = std.array_list.Managed(listpane_mod.Item).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncListSource) void {
        self.clearItems();
        if (self.error_message) |text| self.allocator.free(text);
        if (self.preview) |text| self.allocator.free(text);
        self.items.deinit();
    }

    pub fn begin(self: *AsyncListSource, key: SourceKey) void {
        self.clear();
        self.key = key;
        self.state = .loading;
    }

    pub fn cancel(self: *AsyncListSource) void {
        self.state = .idle;
        self.clearError();
    }

    pub fn append(self: *AsyncListSource, key: SourceKey, item: listpane_mod.Item) !void {
        if (!self.isFresh(key)) return error.StaleSource;
        if (self.state == .idle) return error.Canceled;
        try self.items.append(item);
    }

    pub fn complete(self: *AsyncListSource, key: SourceKey) void {
        if (!self.isFresh(key)) return;
        if (self.state == .idle) return;
        self.state = .ready;
    }

    pub fn fail(self: *AsyncListSource, key: SourceKey, message: []const u8) !void {
        if (!self.isFresh(key)) return;
        if (self.state == .idle) return;
        self.clearError();
        self.error_message = try self.allocator.dupe(u8, message);
        self.state = .failed;
    }

    pub fn setPreview(self: *AsyncListSource, preview: ?[]const u8) !void {
        if (self.preview) |text| self.allocator.free(text);
        self.preview = null;
        if (preview) |text| {
            self.preview = try self.allocator.dupe(u8, text);
        }
    }

    pub fn isFresh(self: *const AsyncListSource, key: SourceKey) bool {
        return self.key.matches(key);
    }

    pub fn clear(self: *AsyncListSource) void {
        self.clearItems();
        self.clearError();
        if (self.preview) |text| self.allocator.free(text);
        self.preview = null;
        self.state = .idle;
        self.key = .{};
    }

    pub fn clearError(self: *AsyncListSource) void {
        if (self.error_message) |text| self.allocator.free(text);
        self.error_message = null;
    }

    fn clearItems(self: *AsyncListSource) void {
        for (self.items.items) |item| {
            if (item.path) |path| self.allocator.free(path);
            self.allocator.free(item.label);
            if (item.detail) |detail| self.allocator.free(detail);
        }
        self.items.clearRetainingCapacity();
    }
};

test "async list source tracks freshness and items" {
    var source = AsyncListSource.init(std.testing.allocator, .search);
    defer source.deinit();
    const key = SourceKey{ .request_id = 1, .snapshot_id = 2, .workspace_generation = 3 };
    source.begin(key);
    try source.append(key, .{ .id = 1, .label = "alpha" });
    try std.testing.expect(source.isFresh(.{ .request_id = 1, .snapshot_id = 2, .workspace_generation = 3 }));
    try std.testing.expectEqual(@as(usize, 1), source.items.items.len);
    source.complete(key);
    try std.testing.expectEqual(listpane_mod.SourceState.ready, source.state);
}
