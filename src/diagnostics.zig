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

pub const Decoration = struct {
    buffer_id: u64,
    row: usize,
    col: usize,
    len: usize,
    kind: DecorationKind,
    severity: ?Severity = null,
    text: ?[]u8 = null,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.array_list.Managed(Diagnostic),
    decorations: std.array_list.Managed(Decoration),

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .diagnostics = std.array_list.Managed(Diagnostic).init(allocator),
            .decorations = std.array_list.Managed(Decoration).init(allocator),
        };
    }

    pub fn deinit(self: *Store) void {
        self.clear();
        self.diagnostics.deinit();
        self.decorations.deinit();
    }

    pub fn add(self: *Store, diagnostic: Diagnostic) !void {
        try self.diagnostics.append(diagnostic);
    }

    pub fn addDecoration(self: *Store, decoration: Decoration) !void {
        try self.decorations.append(decoration);
    }

    pub fn addDiagnosticDecoration(self: *Store, diagnostic: Diagnostic) !void {
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
            .severity = diagnostic.severity,
            .text = try self.allocator.dupe(u8, diagnostic.message),
        });
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

    pub fn decorationsForRow(self: *const Store, buffer_id: u64, row: usize) usize {
        var total: usize = 0;
        for (self.decorations.items) |decoration| {
            if (decoration.buffer_id == buffer_id and decoration.row == row) total += 1;
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

    pub fn statusText(self: *const Store, allocator: std.mem.Allocator) ![]u8 {
        const errors = self.count(.err);
        const warnings = self.count(.warning);
        const infos = self.count(.info);
        if (errors == 0 and warnings == 0 and infos == 0) return try allocator.dupe(u8, "");
        return try std.fmt.allocPrint(allocator, "E{d} W{d} I{d}", .{ errors, warnings, infos });
    }
};

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
