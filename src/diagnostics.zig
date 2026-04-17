const std = @import("std");

pub const Severity = enum { info, warning, err };

pub const Diagnostic = struct {
    buffer_id: u64,
    path: ?[]u8 = null,
    row: usize,
    col: usize,
    severity: Severity,
    message: []u8,
};

pub const DecorationKind = enum { highlight, sign, virtual_text, underline, hint };

pub const DecorationSource = enum { diagnostics, lsp, treesitter, plugin, custom };

pub const DecorationOwner = struct {
    id: u64,
    name: []u8,
};

pub const Decoration = struct {
    buffer_id: u64,
    row: usize,
    col: usize,
    len: usize,
    kind: DecorationKind,
    source: DecorationSource = .custom,
    owner_id: u64 = 0,
    severity: ?Severity = null,
    text: ?[]u8 = null,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.array_list.Managed(Diagnostic),
    decorations: std.array_list.Managed(Decoration),
    owners: std.array_list.Managed(DecorationOwner),
    next_owner_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .diagnostics = std.array_list.Managed(Diagnostic).init(allocator),
            .decorations = std.array_list.Managed(Decoration).init(allocator),
            .owners = std.array_list.Managed(DecorationOwner).init(allocator),
        };
    }

    pub fn deinit(self: *Store) void {
        self.clear();
        self.diagnostics.deinit();
        self.decorations.deinit();
        for (self.owners.items) |owner| self.allocator.free(owner.name);
        self.owners.deinit();
    }

    pub fn add(self: *Store, diagnostic: Diagnostic) !void {
        try self.diagnostics.append(diagnostic);
    }

    pub fn addDecoration(self: *Store, decoration: Decoration) !void {
        try self.addDecorationOwned(0, decoration);
    }

    pub fn addDecorationOwned(self: *Store, owner_id: u64, decoration: Decoration) !void {
        var next = decoration;
        next.owner_id = owner_id;
        try self.decorations.append(next);
    }

    pub fn addDiagnosticDecoration(self: *Store, diagnostic: Diagnostic) !void {
        try self.addDiagnosticDecorationOwned(0, diagnostic);
    }

    pub fn addDiagnosticDecorationOwned(self: *Store, owner_id: u64, diagnostic: Diagnostic) !void {
        const kind: DecorationKind = switch (diagnostic.severity) {
            .err => .underline,
            .warning => .hint,
            .info => .virtual_text,
        };
        try self.decorations.append(.{
            .buffer_id = diagnostic.buffer_id,
            .row = diagnostic.row,
            .col = diagnostic.col,
            .len = @max(diagnostic.message.len, 1),
            .kind = kind,
            .source = .diagnostics,
            .owner_id = owner_id,
            .severity = diagnostic.severity,
            .text = try self.allocator.dupe(u8, diagnostic.message),
        });
    }

    pub fn addLspDecoration(self: *Store, buffer_id: u64, row: usize, col: usize, len: usize, text: []const u8, kind: DecorationKind) !void {
        try self.addLspDecorationOwned(0, buffer_id, row, col, len, text, kind);
    }

    pub fn addLspDecorationOwned(self: *Store, owner_id: u64, buffer_id: u64, row: usize, col: usize, len: usize, text: []const u8, kind: DecorationKind) !void {
        try self.decorations.append(.{
            .buffer_id = buffer_id,
            .row = row,
            .col = col,
            .len = @max(len, 1),
            .kind = kind,
            .source = .lsp,
            .owner_id = owner_id,
            .text = try self.allocator.dupe(u8, text),
        });
    }

    pub fn addTreeDecoration(self: *Store, buffer_id: u64, row: usize, col: usize, len: usize, text: []const u8, kind: DecorationKind) !void {
        try self.addTreeDecorationOwned(0, buffer_id, row, col, len, text, kind);
    }

    pub fn addTreeDecorationOwned(self: *Store, owner_id: u64, buffer_id: u64, row: usize, col: usize, len: usize, text: []const u8, kind: DecorationKind) !void {
        try self.decorations.append(.{
            .buffer_id = buffer_id,
            .row = row,
            .col = col,
            .len = @max(len, 1),
            .kind = kind,
            .source = .treesitter,
            .owner_id = owner_id,
            .text = try self.allocator.dupe(u8, text),
        });
    }

    pub fn addPluginDecoration(self: *Store, buffer_id: u64, row: usize, col: usize, len: usize, text: []const u8, kind: DecorationKind) !void {
        try self.addPluginDecorationOwned(0, buffer_id, row, col, len, text, kind);
    }

    pub fn addPluginDecorationOwned(self: *Store, owner_id: u64, buffer_id: u64, row: usize, col: usize, len: usize, text: []const u8, kind: DecorationKind) !void {
        try self.decorations.append(.{
            .buffer_id = buffer_id,
            .row = row,
            .col = col,
            .len = @max(len, 1),
            .kind = kind,
            .source = .plugin,
            .owner_id = owner_id,
            .text = try self.allocator.dupe(u8, text),
        });
    }

    pub fn registerDecorationOwner(self: *Store, name: []const u8) !u64 {
        if (self.findDecorationOwnerByName(name)) |owner| return owner.id;
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const owner_id = self.next_owner_id;
        self.next_owner_id += 1;
        try self.owners.append(.{ .id = owner_id, .name = name_copy });
        return owner_id;
    }

    pub fn clear(self: *Store) void {
        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.path) |path| self.allocator.free(path);
            self.allocator.free(diagnostic.message);
        }
        self.diagnostics.clearRetainingCapacity();
        self.clearDecorations();
    }

    pub fn clearDecorations(self: *Store) void {
        for (self.decorations.items) |decoration| {
            if (decoration.text) |text| self.allocator.free(text);
        }
        self.decorations.clearRetainingCapacity();
    }

    pub fn clearOwner(self: *Store, owner_id: u64) void {
        var i: usize = 0;
        while (i < self.decorations.items.len) {
            if (self.decorations.items[i].owner_id == owner_id) {
                const item = self.decorations.orderedRemove(i);
                if (item.text) |text| self.allocator.free(text);
                continue;
            }
            i += 1;
        }
    }

    pub fn clearBuffer(self: *Store, buffer_id: u64) void {
        var i: usize = 0;
        while (i < self.diagnostics.items.len) {
            if (self.diagnostics.items[i].buffer_id == buffer_id) {
                const item = self.diagnostics.orderedRemove(i);
                if (item.path) |path| self.allocator.free(path);
                self.allocator.free(item.message);
                continue;
            }
            i += 1;
        }
        i = 0;
        while (i < self.decorations.items.len) {
            if (self.decorations.items[i].buffer_id == buffer_id) {
                const item = self.decorations.orderedRemove(i);
                if (item.text) |text| self.allocator.free(text);
                continue;
            }
            i += 1;
        }
    }

    pub fn clearBufferOwner(self: *Store, buffer_id: u64, owner_id: u64) void {
        var i: usize = 0;
        while (i < self.decorations.items.len) {
            if (self.decorations.items[i].buffer_id == buffer_id and self.decorations.items[i].owner_id == owner_id) {
                const item = self.decorations.orderedRemove(i);
                if (item.text) |text| self.allocator.free(text);
                continue;
            }
            i += 1;
        }
    }

    pub fn clearBufferSource(self: *Store, buffer_id: u64, source: DecorationSource) void {
        var i: usize = 0;
        while (i < self.decorations.items.len) {
            if (self.decorations.items[i].buffer_id == buffer_id and self.decorations.items[i].source == source) {
                const item = self.decorations.orderedRemove(i);
                if (item.text) |text| self.allocator.free(text);
                continue;
            }
            i += 1;
        }
    }

    pub fn bestDecorationForRow(self: *const Store, buffer_id: u64, row: usize) ?Decoration {
        var best: ?Decoration = null;
        for (self.decorations.items) |decoration| {
            if (decoration.buffer_id != buffer_id or decoration.row != row) continue;
            if (best == null or decorationPriority(decoration) > decorationPriority(best.?)) {
                best = decoration;
            }
        }
        return best;
    }

    pub fn decorationsForRow(self: *const Store, buffer_id: u64, row: usize) usize {
        var total: usize = 0;
        for (self.decorations.items) |decoration| {
            if (decoration.buffer_id == buffer_id and decoration.row == row) total += 1;
        }
        return total;
    }

    pub fn decorationsForSource(self: *const Store, source: DecorationSource) usize {
        var total: usize = 0;
        for (self.decorations.items) |decoration| {
            if (decoration.source == source) total += 1;
        }
        return total;
    }

    pub fn firstDecorationForRow(self: *const Store, buffer_id: u64, row: usize) ?Decoration {
        for (self.decorations.items) |decoration| {
            if (decoration.buffer_id == buffer_id and decoration.row == row) return decoration;
        }
        return null;
    }

    pub fn count(self: *const Store, severity: Severity) usize {
        var total: usize = 0;
        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.severity == severity) total += 1;
        }
        return total;
    }

    fn findDecorationOwnerByName(self: *const Store, name: []const u8) ?DecorationOwner {
        for (self.owners.items) |owner| {
            if (std.mem.eql(u8, owner.name, name)) return owner;
        }
        return null;
    }

    pub fn statusText(self: *const Store, allocator: std.mem.Allocator) ![]u8 {
        const errors = self.count(.err);
        const warnings = self.count(.warning);
        const infos = self.count(.info);
        if (errors == 0 and warnings == 0 and infos == 0) return try allocator.dupe(u8, "");
        return try std.fmt.allocPrint(allocator, "E{d} W{d} I{d}", .{ errors, warnings, infos });
    }
};

fn decorationPriority(decoration: Decoration) u8 {
    const source_score: u8 = switch (decoration.source) {
        .diagnostics => 5,
        .lsp => 4,
        .treesitter => 3,
        .plugin => 2,
        .custom => 1,
    };
    const kind_score: u8 = switch (decoration.kind) {
        .hint => 5,
        .virtual_text => 4,
        .sign => 3,
        .highlight => 2,
        .underline => 1,
    };
    return source_score * 10 + kind_score;
}

test "diagnostics counts and buffer clearing" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    try store.add(.{
        .buffer_id = 1,
        .row = 1,
        .col = 2,
        .severity = .err,
        .message = try std.testing.allocator.dupe(u8, "boom"),
    });
    try std.testing.expectEqual(@as(usize, 1), store.count(.err));
    store.clearBuffer(1);
    try std.testing.expectEqual(@as(usize, 0), store.count(.err));
}

test "diagnostics tracks decoration sources" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const tree_owner = try store.registerDecorationOwner("treesitter");
    const plugin_owner = try store.registerDecorationOwner("plugin-hello");
    try store.addTreeDecorationOwned(tree_owner, 1, 0, 0, 4, "node", .highlight);
    try store.addPluginDecorationOwned(plugin_owner, 1, 1, 0, 3, "plug", .sign);

    try std.testing.expectEqual(@as(usize, 1), store.decorationsForSource(.treesitter));
    try std.testing.expectEqual(@as(usize, 1), store.decorationsForSource(.plugin));
}

test "diagnostics clears decorations for a single source" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const tree_owner = try store.registerDecorationOwner("treesitter");
    const plugin_owner = try store.registerDecorationOwner("plugin-hello");
    try store.addTreeDecorationOwned(tree_owner, 1, 0, 0, 4, "node", .highlight);
    try store.addPluginDecorationOwned(plugin_owner, 1, 1, 0, 3, "plug", .sign);

    store.clearBufferOwner(1, tree_owner);

    try std.testing.expectEqual(@as(usize, 0), store.decorationsForSource(.treesitter));
    try std.testing.expectEqual(@as(usize, 1), store.decorationsForSource(.plugin));
}

test "diagnostics chooses row decorations by explicit priority" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const plugin_owner = try store.registerDecorationOwner("plugin-hello");
    const tree_owner = try store.registerDecorationOwner("treesitter");
    const lsp_owner = try store.registerDecorationOwner("lsp");
    try store.addPluginDecorationOwned(plugin_owner, 1, 0, 0, 3, "plugin", .hint);
    try store.addTreeDecorationOwned(tree_owner, 1, 0, 0, 4, "tree", .highlight);
    try store.addLspDecorationOwned(lsp_owner, 1, 0, 0, 5, "lsp", .virtual_text);

    const best = store.bestDecorationForRow(1, 0) orelse return error.TestExpected;
    try std.testing.expectEqualStrings("lsp", best.text.?);
    try std.testing.expectEqual(.lsp, best.source);
}

test "diagnostics prefers tree-sitter hints over highlights on the same row" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const tree_owner = try store.registerDecorationOwner("treesitter");
    try store.addTreeDecorationOwned(tree_owner, 1, 0, 0, 2, "kw", .highlight);
    try store.addTreeDecorationOwned(tree_owner, 1, 0, 0, 3, "def", .hint);

    const best = store.bestDecorationForRow(1, 0) orelse return error.TestExpected;
    try std.testing.expectEqualStrings("def", best.text.?);
    try std.testing.expectEqual(.hint, best.kind);
}
