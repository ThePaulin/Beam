const std = @import("std");
const builtin = @import("builtin");
const diagnostics_mod = @import("diagnostics.zig");
const listpane_mod = @import("listpane.zig");

fn appendJsonEscaped(out: *std.array_list.Managed(u8), text: []const u8) !void {
    try out.append('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => try out.append(byte),
        }
    }
    try out.append('"');
}

fn payloadLooksJson(payload: []const u8) bool {
    if (payload.len == 0) return false;
    return switch (payload[0]) {
        '{', '[', '"' => true,
        else => false,
    };
}

fn buildJsonRpcMessage(allocator: std.mem.Allocator, id: ?u64, method: []const u8, payload: []const u8) ![]u8 {
    var body = std.array_list.Managed(u8).init(allocator);
    errdefer body.deinit();
    defer body.deinit();
    try body.appendSlice("{\"jsonrpc\":\"2.0\",");
    if (id) |value| {
        try body.appendSlice("\"id\":");
        try body.writer().print("{d}", .{value});
        try body.append(',');
    }
    try body.appendSlice("\"method\":");
    try appendJsonEscaped(&body, method);
    if (payload.len > 0) {
        try body.appendSlice(",\"params\":");
        if (payloadLooksJson(payload)) {
            try body.appendSlice(payload);
        } else {
            try appendJsonEscaped(&body, payload);
        }
    }
    try body.append('}');

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try out.writer().print("Content-Length: {d}\r\n\r\n", .{body.items.len});
    try out.appendSlice(body.items);
    return try out.toOwnedSlice();
}

fn buildJsonRpcResponse(allocator: std.mem.Allocator, id: u64, field: []const u8, payload: []const u8) ![]u8 {
    var body = std.array_list.Managed(u8).init(allocator);
    errdefer body.deinit();
    defer body.deinit();
    try body.appendSlice("{\"jsonrpc\":\"2.0\",\"id\":");
    try body.writer().print("{d}", .{id});
    try body.appendSlice(",\"");
    try body.appendSlice(field);
    try body.appendSlice("\":");
    if (payloadLooksJson(payload)) {
        try body.appendSlice(payload);
    } else {
        try appendJsonEscaped(&body, payload);
    }
    try body.append('}');

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try out.writer().print("Content-Length: {d}\r\n\r\n", .{body.items.len});
    try out.appendSlice(body.items);
    return try out.toOwnedSlice();
}

pub const JsonRpcTransport = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,

    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) JsonRpcTransport {
        return .{ .allocator = allocator, .file = file };
    }

    pub fn deinit(self: *JsonRpcTransport) void {
        self.file.close();
    }

    pub fn asTransport(self: *JsonRpcTransport) Transport {
        return .{
            .ctx = self,
            .send_request = sendRequest,
            .send_notification = sendNotification,
        };
    }

    fn sendRequest(ctx: *anyopaque, request: Request) anyerror!void {
        const self: *JsonRpcTransport = @ptrCast(@alignCast(ctx));
        try self.writeMessage(request.id, request.method, request.payload);
    }

    fn sendNotification(ctx: *anyopaque, notification: Notification) anyerror!void {
        const self: *JsonRpcTransport = @ptrCast(@alignCast(ctx));
        try self.writeMessage(null, notification.method, notification.payload);
    }

    fn writeMessage(self: *JsonRpcTransport, id: ?u64, method: []const u8, payload: []const u8) !void {
        const message = try buildJsonRpcMessage(self.allocator, id, method, payload);
        defer self.allocator.free(message);
        try self.file.writeAll(message);
    }
};

pub const StdioTransport = struct {
    allocator: std.mem.Allocator,
    input: std.fs.File,
    output: std.fs.File,
    input_buffer: [4096]u8 = undefined,
    input_index: usize = 0,
    input_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, input: std.fs.File, output: std.fs.File) StdioTransport {
        return .{
            .allocator = allocator,
            .input = input,
            .output = output,
            .input_buffer = undefined,
            .input_index = 0,
            .input_len = 0,
        };
    }

    pub fn deinit(self: *StdioTransport) void {
        self.input.close();
        self.output.close();
    }

    pub fn asTransport(self: *StdioTransport) Transport {
        return .{
            .ctx = self,
            .send_request = sendRequest,
            .send_notification = sendNotification,
        };
    }

    pub fn readMessage(self: *StdioTransport) !?[]u8 {
        var content_length: ?usize = null;
        var line = std.array_list.Managed(u8).init(self.allocator);
        defer line.deinit();
        while (true) {
            line.clearRetainingCapacity();
            while (true) {
                const maybe_byte = try self.readByte();
                const byte = maybe_byte orelse {
                    if (content_length == null and line.items.len == 0) return null;
                    return error.UnexpectedEndOfStream;
                };
                if (byte == '\n') break;
                try line.append(byte);
            }
            const trimmed = std.mem.trimRight(u8, line.items, "\r");
            if (trimmed.len == 0) break;
            if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
                const value = std.mem.trim(u8, trimmed["Content-Length:".len ..], " \t");
                content_length = try std.fmt.parseUnsigned(usize, value, 10);
            }
        }
        const len = content_length orelse return error.MissingContentLength;
        const message = try self.allocator.alloc(u8, len);
        errdefer self.allocator.free(message);
        var idx: usize = 0;
        while (idx < len) : (idx += 1) {
            message[idx] = (try self.readByte()).?;
        }
        return message;
    }

    fn sendRequest(ctx: *anyopaque, request: Request) anyerror!void {
        const self: *StdioTransport = @ptrCast(@alignCast(ctx));
        try self.writeMessage(request.id, request.method, request.payload);
    }

    fn sendNotification(ctx: *anyopaque, notification: Notification) anyerror!void {
        const self: *StdioTransport = @ptrCast(@alignCast(ctx));
        try self.writeMessage(null, notification.method, notification.payload);
    }

    fn writeMessage(self: *StdioTransport, id: ?u64, method: []const u8, payload: []const u8) !void {
        const message = try buildJsonRpcMessage(self.allocator, id, method, payload);
        defer self.allocator.free(message);
        try self.output.writeAll(message);
    }

    fn readByte(self: *StdioTransport) !?u8 {
        if (self.input_index >= self.input_len) {
            self.input_len = try self.input.read(self.input_buffer[0..]);
            self.input_index = 0;
            if (self.input_len == 0) return null;
        }
        const byte = self.input_buffer[self.input_index];
        self.input_index += 1;
        return byte;
    }

    pub fn pump(self: *StdioTransport, handler: MessageHandler) !void {
        while (try self.readMessage()) |body| {
            var message = try self.parseMessage(body);
            defer message.deinit(self.allocator);
            try handler.on_message(handler.ctx, message);
        }
    }

    fn parseMessage(self: *StdioTransport, body: []u8) !ParsedMessage {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        const root = switch (parsed.value) {
            .object => |object| object,
            else => return error.InvalidJsonRpcMessage,
        };

        const method_value = root.get("method");
        const id_value = root.get("id");
        const result_value = root.get("result");
        const error_value = root.get("error");

        var method: ?[]u8 = null;
        if (method_value) |value| {
            method = switch (value) {
                .string => |text| try self.allocator.dupe(u8, text),
                else => return error.InvalidJsonRpcMessage,
            };
        }

        var kind: MessageKind = undefined;
        if (method != null) {
            kind = if (id_value != null) .request else .notification;
        } else if (id_value != null and (result_value != null or error_value != null)) {
            kind = .response;
        } else {
            return error.InvalidJsonRpcMessage;
        }

        return .{
            .kind = kind,
            .method = method,
            .has_result = result_value != null,
            .has_error = error_value != null,
            .body = body,
        };
    }
};

pub const ProcessServer = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,
    transport: StdioTransport,
    messages: std.array_list.Managed(ParsedMessage),
    messages_mutex: std.Thread.Mutex = .{},
    malformed_jsonrpc: bool = false,
    thread: ?std.Thread = null,

    pub fn start(allocator: std.mem.Allocator, argv: []const []const u8) !ProcessServer {
        var child = std.process.Child.init(argv, allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        try child.spawn();

        const stdin = child.stdin orelse return error.MissingPipe;
        const stdout = child.stdout orelse return error.MissingPipe;
        child.stdin = null;
        child.stdout = null;

        return .{
            .allocator = allocator,
            .child = child,
            .transport = StdioTransport.init(allocator, stdout, stdin),
            .messages = std.array_list.Managed(ParsedMessage).init(allocator),
        };
    }

    pub fn deinit(self: *ProcessServer) void {
        if (self.thread) |thread| {
            self.transport.deinit();
            thread.join();
            self.thread = null;
        } else {
            self.transport.deinit();
        }
        self.clearMessages();
        _ = self.child.wait() catch {};
        self.messages.deinit();
    }

    pub fn takeMalformedJsonRpc(self: *ProcessServer) bool {
        self.messages_mutex.lock();
        defer self.messages_mutex.unlock();
        const seen = self.malformed_jsonrpc;
        self.malformed_jsonrpc = false;
        return seen;
    }

    pub fn transportHandle(self: *ProcessServer) Transport {
        return self.transport.asTransport();
    }

    pub fn startReaderThread(self: *ProcessServer) !void {
        if (self.thread != null) return;
        self.thread = try std.Thread.spawn(.{}, readerThreadMain, .{self});
    }

    pub fn pollMessage(self: *ProcessServer) ?ParsedMessage {
        self.messages_mutex.lock();
        defer self.messages_mutex.unlock();
        if (self.messages.items.len == 0) return null;
        return self.messages.orderedRemove(0);
    }

    pub fn pump(self: *ProcessServer, handler: MessageHandler) !void {
        try self.transport.pump(handler);
        _ = try self.child.wait();
    }

    pub fn pumpOnce(self: *ProcessServer, handler: MessageHandler) !bool {
        const body = try self.transport.readMessage() orelse return false;
        var message = try self.transport.parseMessage(body);
        defer message.deinit(self.allocator);
        try handler.on_message(handler.ctx, message);
        return true;
    }

    fn readerThreadMain(self: *ProcessServer) void {
        while (true) {
            const body = self.transport.readMessage() catch break;
            const raw = body orelse break;
            var message = self.transport.parseMessage(raw) catch {
                self.allocator.free(raw);
                self.messages_mutex.lock();
                self.malformed_jsonrpc = true;
                self.messages_mutex.unlock();
                continue;
            };
            self.messages_mutex.lock();
            defer self.messages_mutex.unlock();
            self.messages.append(message) catch {
                message.deinit(self.allocator);
                break;
            };
        }
    }

    fn clearMessages(self: *ProcessServer) void {
        for (self.messages.items) |*message| {
            message.deinit(self.allocator);
        }
        self.messages.clearRetainingCapacity();
    }
};

pub const Request = struct {
    id: u64,
    method: []const u8,
    payload: []const u8 = "",
};

pub const Notification = struct {
    method: []const u8,
    payload: []const u8 = "",
};

pub const MessageKind = enum {
    request,
    notification,
    response,
};

pub const ParsedMessage = struct {
    kind: MessageKind,
    id: ?u64 = null,
    method: ?[]u8 = null,
    has_result: bool = false,
    has_error: bool = false,
    body: []u8,

    pub fn deinit(self: *ParsedMessage, allocator: std.mem.Allocator) void {
        if (self.method) |method| allocator.free(method);
        allocator.free(self.body);
    }
};

pub const MessageHandler = struct {
    ctx: *anyopaque,
    on_message: *const fn (ctx: *anyopaque, message: ParsedMessage) anyerror!void,
};

pub const ResponseEvent = struct {
    id: u64,
    kind: u8,
    has_error: bool,
    body: []const u8,
};

pub const Transport = struct {
    ctx: *anyopaque,
    send_request: *const fn (ctx: *anyopaque, request: Request) anyerror!void,
    send_notification: *const fn (ctx: *anyopaque, notification: Notification) anyerror!void,
};

pub const ResultSink = struct {
    ctx: *anyopaque,
    emit: *const fn (ctx: *anyopaque, item: listpane_mod.Item) anyerror!void,
};

pub const Session = struct {
    pub const RequestKind = enum {
        initialize,
        shutdown,
        diagnostics,
        symbols,
        definition,
        references,
        rename,
        completion,
        hover,
        code_action,
        semantic_tokens,
        custom,
    };

    const PendingRequest = struct {
        id: u64,
        kind: RequestKind,
    };

    allocator: std.mem.Allocator,
    diagnostics: std.array_list.Managed(diagnostics_mod.Diagnostic),
    symbols: std.array_list.Managed(listpane_mod.Item),
    pending_requests: std.array_list.Managed(PendingRequest),
    transport: ?Transport = null,
    request_id: u64 = 1,
    generation: u64 = 1,
    initialized: bool = false,
    shutdown_acknowledged: bool = false,

    pub fn init(allocator: std.mem.Allocator) Session {
        return .{
            .allocator = allocator,
            .diagnostics = std.array_list.Managed(diagnostics_mod.Diagnostic).init(allocator),
            .symbols = std.array_list.Managed(listpane_mod.Item).init(allocator),
            .pending_requests = std.array_list.Managed(PendingRequest).init(allocator),
        };
    }

    pub fn deinit(self: *Session) void {
        self.clear();
        self.diagnostics.deinit();
        self.symbols.deinit();
        self.pending_requests.deinit();
    }

    pub fn attachTransport(self: *Session, transport: Transport) void {
        self.transport = transport;
    }

    pub fn detachTransport(self: *Session) void {
        self.transport = null;
    }

    pub fn publishDiagnostic(self: *Session, diagnostic: diagnostics_mod.Diagnostic) !void {
        try self.diagnostics.append(diagnostic);
        self.generation += 1;
    }

    pub fn publishSymbol(self: *Session, symbol: listpane_mod.Item) !void {
        try self.symbols.append(symbol);
        self.generation += 1;
    }

    pub fn didOpenPath(self: *Session, path: []const u8) !void {
        try self.sendNotification("textDocument/didOpen", path);
    }

    pub fn didChangePath(self: *Session, path: []const u8) !void {
        try self.sendNotification("textDocument/didChange", path);
    }

    pub fn didSavePath(self: *Session, path: []const u8) !void {
        try self.sendNotification("textDocument/didSave", path);
    }

    pub fn didClosePath(self: *Session, path: []const u8) !void {
        try self.sendNotification("textDocument/didClose", path);
    }

    pub fn request(self: *Session, method: []const u8, payload: []const u8) !u64 {
        return try self.requestWithKind(.custom, method, payload);
    }

    pub fn initialize(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.initialize, "initialize", payload);
    }

    pub fn shutdown(self: *Session) !u64 {
        return try self.requestWithKind(.shutdown, "shutdown", "{}");
    }

    pub fn requestDiagnostics(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.diagnostics, "textDocument/diagnostic", payload);
    }

    pub fn requestSymbols(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.symbols, "workspace/symbol", payload);
    }

    pub fn requestDefinition(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.definition, "textDocument/definition", payload);
    }

    pub fn requestReferences(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.references, "textDocument/references", payload);
    }

    pub fn requestRename(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.rename, "textDocument/rename", payload);
    }

    pub fn requestCompletion(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.completion, "textDocument/completion", payload);
    }

    pub fn requestHover(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.hover, "textDocument/hover", payload);
    }

    pub fn requestCodeActions(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.code_action, "textDocument/codeAction", payload);
    }

    pub fn requestSemanticTokens(self: *Session, payload: []const u8) !u64 {
        return try self.requestWithKind(.semantic_tokens, "textDocument/semanticTokens/full", payload);
    }

    pub fn cancelRequest(self: *Session, id: u64) !bool {
        const pending_index = self.findPendingRequest(id) orelse return false;
        _ = self.pending_requests.orderedRemove(pending_index);
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"id\":{d}}}", .{id});
        defer self.allocator.free(payload);
        try self.sendNotification("$/cancelRequest", payload);
        return true;
    }

    fn requestWithKind(self: *Session, kind: RequestKind, method: []const u8, payload: []const u8) !u64 {
        const id = self.request_id;
        self.request_id += 1;
        try self.sendRequest(.{ .id = id, .method = method, .payload = payload });
        try self.pending_requests.append(.{ .id = id, .kind = kind });
        return id;
    }

    pub fn clear(self: *Session) void {
        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.path) |path| self.allocator.free(path);
            self.allocator.free(diagnostic.message);
        }
        self.diagnostics.clearRetainingCapacity();
        self.clearSymbols();
        self.pending_requests.clearRetainingCapacity();
        self.initialized = false;
        self.shutdown_acknowledged = false;
    }

    pub fn clearBuffer(self: *Session, buffer_id: u64) void {
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
        while (i < self.symbols.items.len) {
            if (self.symbols.items[i].path) |path| {
                if (std.mem.eql(u8, path, "")) {
                    _ = self.symbols.orderedRemove(i);
                    continue;
                }
            }
            i += 1;
        }
    }

    pub fn clearPath(self: *Session, path: []const u8) void {
        self.clearDiagnosticsPath(path);
        self.clearSymbolsPath(path);
    }

    fn clearDiagnosticsPath(self: *Session, path: []const u8) void {
        var i: usize = 0;
        while (i < self.diagnostics.items.len) {
            const diagnostic = self.diagnostics.items[i];
            if (diagnostic.path) |diag_path| {
                if (std.mem.eql(u8, diag_path, path)) {
                    const item = self.diagnostics.orderedRemove(i);
                    if (item.path) |free_path| self.allocator.free(free_path);
                    self.allocator.free(item.message);
                    continue;
                }
            }
            i += 1;
        }
    }

    fn clearSymbolsPath(self: *Session, path: []const u8) void {
        var i: usize = 0;
        while (i < self.symbols.items.len) {
            const symbol = self.symbols.items[i];
            if (symbol.path) |symbol_path| {
                if (std.mem.eql(u8, symbol_path, path)) {
                    const item = self.symbols.orderedRemove(i);
                    if (item.path) |free_path| self.allocator.free(free_path);
                    self.allocator.free(item.label);
                    if (item.detail) |detail| self.allocator.free(detail);
                    continue;
                }
            }
            i += 1;
        }
    }

    pub fn refreshDiagnostics(self: *Session) !u64 {
        return try self.requestDiagnostics("");
    }

    pub fn refreshSymbols(self: *Session) !u64 {
        return try self.requestSymbols("");
    }

    pub fn diagnosticsCount(self: *const Session, severity: diagnostics_mod.Severity) usize {
        var total: usize = 0;
        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.severity == severity) total += 1;
        }
        return total;
    }

    pub fn statusText(self: *const Session, allocator: std.mem.Allocator) ![]u8 {
        const errors = self.diagnosticsCount(.err);
        const warnings = self.diagnosticsCount(.warning);
        const infos = self.diagnosticsCount(.info);
        if (errors == 0 and warnings == 0 and infos == 0) return try allocator.dupe(u8, "");
        return try std.fmt.allocPrint(allocator, "E{d} W{d} I{d}", .{ errors, warnings, infos });
    }

    pub fn querySymbols(self: *const Session, pattern: []const u8, sink: ResultSink, limit: usize) !usize {
        var emitted: usize = 0;
        for (self.symbols.items) |symbol| {
            if (emitted >= limit) break;
            if (!matchesSymbol(symbol, pattern)) continue;
            try sink.emit(sink.ctx, symbol);
            emitted += 1;
        }
        return emitted;
    }

    fn clearSymbols(self: *Session) void {
        for (self.symbols.items) |symbol| {
            if (symbol.path) |path| self.allocator.free(path);
            self.allocator.free(symbol.label);
            if (symbol.detail) |detail| self.allocator.free(detail);
        }
        self.symbols.clearRetainingCapacity();
    }

    pub fn handleMessage(self: *Session, message: ParsedMessage) !?ResponseEvent {
        if (message.kind == .notification) {
            try self.handleNotification(message);
            return null;
        }
        if (message.kind == .response) {
            return try self.handleResponse(message);
        }
        return null;
    }

    fn handleNotification(self: *Session, message: ParsedMessage) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, message.body, .{});
        defer parsed.deinit();
        const root = switch (parsed.value) {
            .object => |object| object,
            else => return error.InvalidJsonRpcMessage,
        };
        const method_value = root.get("method") orelse return error.InvalidJsonRpcMessage;
        const method = switch (method_value) {
            .string => |text| text,
            else => return error.InvalidJsonRpcMessage,
        };
        if (std.mem.eql(u8, method, "textDocument/publishDiagnostics")) {
            try self.handlePublishDiagnostics(root.get("params") orelse return error.InvalidJsonRpcMessage);
        }
    }

    fn handleResponse(self: *Session, message: ParsedMessage) !?ResponseEvent {
        const pending_index = self.findPendingRequest(message.id orelse return error.InvalidJsonRpcMessage) orelse return null;
        const pending = self.pending_requests.orderedRemove(pending_index);
        switch (pending.kind) {
            .initialize => {
                if (!message.has_error) {
                    self.initialized = true;
                    try self.sendNotification("initialized", "{}");
                }
            },
            .shutdown => {
                if (!message.has_error) {
                    self.shutdown_acknowledged = true;
                    try self.sendNotification("exit", "{}");
                }
            },
            .diagnostics => try self.handleDiagnosticsResult(message.body),
            .symbols => try self.handleSymbolsResult(message.body),
            .definition, .references, .rename, .completion, .hover, .code_action, .semantic_tokens, .custom => {},
        }
        return .{
            .id = pending.id,
            .kind = @intFromEnum(pending.kind),
            .has_error = message.has_error,
            .body = message.body,
        };
    }

    fn findPendingRequest(self: *Session, id: u64) ?usize {
        for (self.pending_requests.items, 0..) |pending, idx| {
            if (pending.id == id) return idx;
        }
        return null;
    }

    fn handlePublishDiagnostics(self: *Session, params: std.json.Value) !void {
        const params_object = switch (params) {
            .object => |value| value,
            else => return error.InvalidJsonRpcMessage,
        };
        const uri_value = params_object.get("uri") orelse return error.InvalidJsonRpcMessage;
        const uri = switch (uri_value) {
            .string => |text| text,
            else => return error.InvalidJsonRpcMessage,
        };
        const path = try self.uriToPath(uri);
        defer self.allocator.free(path);
        self.clearDiagnosticsPath(path);
        const diagnostics_value = params_object.get("diagnostics") orelse return;
        const diagnostics_array = switch (diagnostics_value) {
            .array => |array| array,
            else => return error.InvalidJsonRpcMessage,
        };
        for (diagnostics_array.items) |diag_value| {
            const diag_object = switch (diag_value) {
                .object => |object| object,
                else => continue,
            };
            const range_value = diag_object.get("range") orelse continue;
            const range_object = switch (range_value) {
                .object => |object| object,
                else => continue,
            };
            const start_value = range_object.get("start") orelse continue;
            const start_object = switch (start_value) {
                .object => |object| object,
                else => continue,
            };
            const row = jsonValueTousize(start_object.get("line")) orelse 0;
            const col = jsonValueTousize(start_object.get("character")) orelse 0;
            const severity = if (diag_object.get("severity")) |sev| jsonSeverity(sev) else .warning;
            const message_value = diag_object.get("message") orelse continue;
            const message_text = switch (message_value) {
                .string => |text| text,
                else => continue,
            };
            try self.publishDiagnostic(.{
                .buffer_id = 0,
                .path = try self.allocator.dupe(u8, path),
                .row = row,
                .col = col,
                .severity = severity,
                .message = try self.allocator.dupe(u8, message_text),
            });
        }
    }

    fn handleDiagnosticsResult(self: *Session, body: []const u8) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        defer parsed.deinit();
        const root = switch (parsed.value) {
            .object => |object| object,
            else => return error.InvalidJsonRpcMessage,
        };
        if (root.get("result")) |result| {
            if (result == .object) {
                try self.handlePublishDiagnostics(result);
            }
        }
    }

    fn handleSymbolsResult(self: *Session, body: []const u8) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        defer parsed.deinit();
        const root = switch (parsed.value) {
            .object => |object| object,
            else => return error.InvalidJsonRpcMessage,
        };
        const result_value = root.get("result") orelse return;
        self.clearSymbols();
        switch (result_value) {
            .array => |array| {
                for (array.items) |item| {
                    try self.appendSymbolValue(item);
                }
            },
            .object => |object| try self.appendSymbolValue(.{ .object = object }),
            else => {},
        }
    }

    fn appendSymbolValue(self: *Session, value: std.json.Value) !void {
        const object = switch (value) {
            .object => |object| object,
            else => return,
        };
        const name_value = object.get("name") orelse return;
        const name = switch (name_value) {
            .string => |text| text,
            else => return,
        };
        var path: ?[]u8 = null;
        var row: usize = 0;
        var col: usize = 0;
        if (object.get("location")) |location_value| {
            if (location_value == .object) {
                const location = location_value.object;
                if (location.get("uri")) |uri_value| {
                    if (uri_value == .string) {
                        path = try self.uriToPath(uri_value.string);
                    }
                }
                if (location.get("range")) |range_value| {
                    if (range_value == .object) {
                        const range = range_value.object;
                        if (range.get("start")) |start_value| {
                            if (start_value == .object) {
                                const start = start_value.object;
                                row = jsonValueTousize(start.get("line")) orelse 0;
                                col = jsonValueTousize(start.get("character")) orelse 0;
                            }
                        }
                    }
                }
            }
        }
        const detail = if (object.get("kind")) |kind_value| jsonValueToString(kind_value, self.allocator) else null;
        errdefer if (path) |p| self.allocator.free(p);
        try self.publishSymbol(.{
            .id = self.symbols.items.len + 1,
            .path = path,
            .row = row,
            .col = col,
            .label = try self.allocator.dupe(u8, name),
            .detail = detail,
            .score = 0,
        });
    }

    fn uriToPath(self: *Session, uri: []const u8) ![]u8 {
        if (std.mem.startsWith(u8, uri, "file://")) {
            const raw = uri["file://".len ..];
            return try self.allocator.dupe(u8, if (std.mem.startsWith(u8, raw, "/")) raw else raw);
        }
        return try self.allocator.dupe(u8, uri);
    }

    fn jsonValueToString(value: std.json.Value, allocator: std.mem.Allocator) ?[]u8 {
        return switch (value) {
            .string => |text| allocator.dupe(u8, text) catch null,
            .integer => |int_value| std.fmt.allocPrint(allocator, "{d}", .{int_value}) catch null,
            else => null,
        };
    }

    fn jsonValueTousize(value: ?std.json.Value) ?usize {
        const actual = value orelse return null;
        return switch (actual) {
            .integer => |int_value| if (int_value >= 0) @as(usize, @intCast(int_value)) else null,
            .float => |float_value| if (float_value >= 0) @as(usize, @intCast(@as(u64, @intFromFloat(float_value)))) else null,
            else => null,
        };
    }

    fn jsonSeverity(value: std.json.Value) diagnostics_mod.Severity {
        return switch (value) {
            .integer => |severity| switch (severity) {
                1 => .err,
                2 => .warning,
                3 => .info,
                else => .warning,
            },
            else => .warning,
        };
    }

    fn sendNotification(self: *Session, method: []const u8, payload: []const u8) !void {
        if (self.transport) |transport| {
            try transport.send_notification(transport.ctx, .{ .method = method, .payload = payload });
        }
    }

    fn sendRequest(self: *Session, req: Request) !void {
        if (self.transport) |transport| {
            try transport.send_request(transport.ctx, req);
        }
    }

    fn matchesSymbol(symbol: listpane_mod.Item, pattern: []const u8) bool {
        if (pattern.len == 0) return true;
        if (std.mem.indexOf(u8, symbol.label, pattern) != null) return true;
        if (symbol.path) |path| {
            if (std.mem.indexOf(u8, path, pattern) != null) return true;
        }
        if (symbol.detail) |detail| {
            if (std.mem.indexOf(u8, detail, pattern) != null) return true;
        }
        return false;
    }
};

test "lsp session stores diagnostics and symbols" {
    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    try session.publishDiagnostic(.{
        .buffer_id = 1,
        .path = try std.testing.allocator.dupe(u8, "sample.txt"),
        .row = 0,
        .col = 1,
        .severity = .warning,
        .message = try std.testing.allocator.dupe(u8, "oops"),
    });
    try session.publishSymbol(.{
        .id = 1,
        .path = try std.testing.allocator.dupe(u8, "sample.txt"),
        .row = 2,
        .col = 3,
        .label = try std.testing.allocator.dupe(u8, "alpha"),
        .detail = try std.testing.allocator.dupe(u8, "fn alpha()"),
        .score = 10,
    });
    try std.testing.expectEqual(@as(usize, 1), session.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 1), session.symbols.items.len);
    var seen: usize = 0;
    const Sink = struct {
        fn emit(ctx: *anyopaque, item: listpane_mod.Item) anyerror!void {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += if (item.path != null) 1 else 0;
        }
    };
    try std.testing.expectEqual(@as(usize, 1), try session.querySymbols("alpha", .{ .ctx = &seen, .emit = Sink.emit }, 10));
}

test "lsp session forwards transport notifications and requests" {
    const Capture = struct {
        requests: std.array_list.Managed(Request),
        notifications: std.array_list.Managed(Notification),

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .requests = std.array_list.Managed(Request).init(allocator),
                .notifications = std.array_list.Managed(Notification).init(allocator),
            };
        }

        fn deinit(self: *@This()) void {
            self.requests.deinit();
            self.notifications.deinit();
        }

        fn sendRequest(ctx: *anyopaque, request: Request) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.requests.append(request);
        }

        fn sendNotification(ctx: *anyopaque, notification: Notification) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.notifications.append(notification);
        }
    };

    var capture = Capture.init(std.testing.allocator);
    defer capture.deinit();

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    session.attachTransport(.{
        .ctx = &capture,
        .send_request = Capture.sendRequest,
        .send_notification = Capture.sendNotification,
    });

    try session.didOpenPath("alpha.txt");
    try session.didSavePath("alpha.txt");
    try session.didChangePath("alpha.txt");
    _ = try session.refreshDiagnostics();
    _ = try session.refreshSymbols();

    try std.testing.expectEqual(@as(usize, 3), capture.notifications.items.len);
    try std.testing.expectEqual(@as(usize, 2), capture.requests.items.len);
    try std.testing.expectEqualStrings("textDocument/didOpen", capture.notifications.items[0].method);
    try std.testing.expectEqualStrings("textDocument/didSave", capture.notifications.items[1].method);
    try std.testing.expectEqualStrings("textDocument/didChange", capture.notifications.items[2].method);
    try std.testing.expectEqualStrings("textDocument/diagnostic", capture.requests.items[0].method);
    try std.testing.expectEqualStrings("workspace/symbol", capture.requests.items[1].method);
}

test "lsp session exposes extended requests and cancellation" {
    const Capture = struct {
        requests: std.array_list.Managed(Request),
        notifications: std.array_list.Managed(Notification),

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .requests = std.array_list.Managed(Request).init(allocator),
                .notifications = std.array_list.Managed(Notification).init(allocator),
            };
        }

        fn deinit(self: *@This()) void {
            self.requests.deinit();
            self.notifications.deinit();
        }

        fn sendRequest(ctx: *anyopaque, request: Request) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.requests.append(request);
        }

        fn sendNotification(ctx: *anyopaque, notification: Notification) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.notifications.append(notification);
        }
    };

    var capture = Capture.init(std.testing.allocator);
    defer capture.deinit();

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    session.attachTransport(.{
        .ctx = &capture,
        .send_request = Capture.sendRequest,
        .send_notification = Capture.sendNotification,
    });

    const completion_id = try session.requestCompletion("{}");
    const hover_id = try session.requestHover("{}");
    _ = try session.requestDefinition("{}");
    _ = try session.requestReferences("{}");
    _ = try session.requestRename("{}");
    _ = try session.requestCodeActions("{}");
    _ = try session.requestSemanticTokens("{}");

    try std.testing.expect(try session.cancelRequest(hover_id));
    try std.testing.expectEqual(@as(usize, 7), capture.requests.items.len);
    try std.testing.expectEqual(@as(usize, 1), capture.notifications.items.len);
    try std.testing.expectEqualStrings("textDocument/completion", capture.requests.items[0].method);
    try std.testing.expectEqualStrings("$/cancelRequest", capture.notifications.items[0].method);
    try std.testing.expect(completion_id != hover_id);
    try std.testing.expectEqual(@as(usize, 6), session.pending_requests.items.len);
}

test "json rpc message framing escapes and prefixes content length" {
    const message = try buildJsonRpcMessage(std.testing.allocator, 7, "textDocument/didOpen", "{\"path\":\"alpha.txt\"}");
    defer std.testing.allocator.free(message);
    try std.testing.expect(std.mem.startsWith(u8, message, "Content-Length: "));
    try std.testing.expect(std.mem.indexOf(u8, message, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "\"id\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "\"method\":\"textDocument/didOpen\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "\"params\":{\"path\":\"alpha.txt\"}") != null);
}

test "stdio transport reads and writes framed messages" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const framed_in = try buildJsonRpcMessage(std.testing.allocator, 3, "test/echo", "{\"value\":1}");
    defer std.testing.allocator.free(framed_in);
    {
        var f = try tmp.dir.createFile("in.jsonrpc", .{});
        defer f.close();
        try f.writeAll(framed_in);
    }
    {
        _ = try tmp.dir.createFile("out.jsonrpc", .{});
    }

    const input = try tmp.dir.openFile("in.jsonrpc", .{ .mode = .read_only });
    const output = try tmp.dir.openFile("out.jsonrpc", .{ .mode = .write_only });
    var transport = StdioTransport.init(std.testing.allocator, input, output);

    const maybe_body = try transport.readMessage();
    try std.testing.expect(maybe_body != null);
    const body = maybe_body.?;
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"method\":\"test/echo\"") != null);

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    session.attachTransport(transport.asTransport());
    _ = try session.request("test/ping", "{\"value\":2}");

    session.detachTransport();
    transport.deinit();
    const written = try tmp.dir.readFileAlloc(std.testing.allocator, "out.jsonrpc", 1 << 20);
    defer std.testing.allocator.free(written);
    try std.testing.expect(std.mem.startsWith(u8, written, "Content-Length: "));
    try std.testing.expect(std.mem.indexOf(u8, written, "\"method\":\"test/ping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\"params\":{\"value\":2}") != null);
}

test "stdio transport parses requests, notifications, and responses" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const request_body = try buildJsonRpcMessage(std.testing.allocator, 4, "workspace/symbol", "\"alpha\"");
    defer std.testing.allocator.free(request_body);
    const notification_body = try buildJsonRpcMessage(std.testing.allocator, null, "textDocument/publishDiagnostics", "{\"items\":[]}");
    defer std.testing.allocator.free(notification_body);
    const response_body = try buildJsonRpcResponse(std.testing.allocator, 4, "result", "true");
    defer std.testing.allocator.free(response_body);

    {
        var f = try tmp.dir.createFile("in.jsonrpc", .{});
        defer f.close();
        try f.writeAll(request_body);
        try f.writeAll(notification_body);
        try f.writeAll(response_body);
    }
    {
        _ = try tmp.dir.createFile("out.jsonrpc", .{});
    }

    const input = try tmp.dir.openFile("in.jsonrpc", .{ .mode = .read_only });
    const output = try tmp.dir.openFile("out.jsonrpc", .{ .mode = .write_only });
    var transport = StdioTransport.init(std.testing.allocator, input, output);

    const first = try transport.readMessage();
    try std.testing.expect(first != null);
    var parsed_first = try transport.parseMessage(first.?);
    defer parsed_first.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(MessageKind, .request), parsed_first.kind);
    try std.testing.expectEqualStrings("workspace/symbol", parsed_first.method.?);

    const second = try transport.readMessage();
    try std.testing.expect(second != null);
    try std.testing.expect(std.mem.indexOf(u8, second.?, "\"id\":") == null);
    var parsed_second = try transport.parseMessage(second.?);
    defer parsed_second.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(MessageKind, .notification), parsed_second.kind);
    try std.testing.expectEqualStrings("textDocument/publishDiagnostics", parsed_second.method.?);

    const third = try transport.readMessage();
    try std.testing.expect(third != null);
    var parsed_third = try transport.parseMessage(third.?);
    defer parsed_third.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(MessageKind, .response), parsed_third.kind);
    try std.testing.expect(parsed_third.method == null);

    try std.testing.expect(try transport.readMessage() == null);
}

test "process server pumps messages through a live child" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const argv = &[_][]const u8{ "cat" };
    var server = try ProcessServer.start(std.testing.allocator, argv);
    defer server.deinit();

    const Capture = struct {
        kinds: std.array_list.Managed(MessageKind),
        methods: std.array_list.Managed([]u8),

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .kinds = std.array_list.Managed(MessageKind).init(allocator),
                .methods = std.array_list.Managed([]u8).init(allocator),
            };
        }

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.methods.items) |method| allocator.free(method);
            self.methods.deinit();
            self.kinds.deinit();
        }

        fn onMessage(ctx: *anyopaque, message: ParsedMessage) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.kinds.append(message.kind);
            if (message.method) |method| try self.methods.append(try std.testing.allocator.dupe(u8, method));
        }
    };

    var capture = Capture.init(std.testing.allocator);
    defer capture.deinit(std.testing.allocator);

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    session.attachTransport(server.transportHandle());

    try session.didOpenPath("alpha.txt");
    _ = try session.request("workspace/symbol", "\"alpha\"");

    try std.testing.expect(try server.pumpOnce(.{ .ctx = &capture, .on_message = Capture.onMessage }));
    try std.testing.expect(try server.pumpOnce(.{ .ctx = &capture, .on_message = Capture.onMessage }));
    try std.testing.expectEqual(@as(usize, 2), capture.kinds.items.len);
    try std.testing.expectEqual(@as(MessageKind, .notification), capture.kinds.items[0]);
    try std.testing.expectEqual(@as(MessageKind, .request), capture.kinds.items[1]);
    try std.testing.expectEqualStrings("textDocument/didOpen", capture.methods.items[0]);
    try std.testing.expectEqualStrings("workspace/symbol", capture.methods.items[1]);
}

test "lsp session initialize and shutdown sequence" {
    const Capture = struct {
        requests: std.array_list.Managed(Request),
        notifications: std.array_list.Managed(Notification),

        fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .requests = std.array_list.Managed(Request).init(allocator),
                .notifications = std.array_list.Managed(Notification).init(allocator),
            };
        }

        fn deinit(self: *@This()) void {
            self.requests.deinit();
            self.notifications.deinit();
        }

        fn sendRequest(ctx: *anyopaque, request: Request) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.requests.append(request);
        }

        fn sendNotification(ctx: *anyopaque, notification: Notification) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.notifications.append(notification);
        }
    };

    var capture = Capture.init(std.testing.allocator);
    defer capture.deinit();

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    session.attachTransport(.{
        .ctx = &capture,
        .send_request = Capture.sendRequest,
        .send_notification = Capture.sendNotification,
    });

    const initialize_id = try session.initialize("{\"capabilities\":{}}");
    try std.testing.expectEqual(@as(usize, 1), capture.requests.items.len);
    try std.testing.expectEqualStrings("initialize", capture.requests.items[0].method);

    var initialize_response = ParsedMessage{
        .kind = .response,
        .id = initialize_id,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}"),
    };
    defer initialize_response.deinit(std.testing.allocator);
    _ = try session.handleMessage(initialize_response);
    try std.testing.expect(session.initialized);
    try std.testing.expectEqual(@as(usize, 1), capture.notifications.items.len);
    try std.testing.expectEqualStrings("initialized", capture.notifications.items[0].method);

    const shutdown_id = try session.shutdown();
    try std.testing.expectEqual(@as(usize, 2), capture.requests.items.len);
    try std.testing.expectEqualStrings("shutdown", capture.requests.items[1].method);

    var shutdown_response = ParsedMessage{
        .kind = .response,
        .id = shutdown_id,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}"),
    };
    defer shutdown_response.deinit(std.testing.allocator);
    _ = try session.handleMessage(shutdown_response);
    try std.testing.expect(session.shutdown_acknowledged);
    try std.testing.expectEqual(@as(usize, 2), capture.notifications.items.len);
    try std.testing.expectEqualStrings("exit", capture.notifications.items[1].method);
}

test "lsp session correlates responses by request id" {
    var session = Session.init(std.testing.allocator);
    defer session.deinit();

    const diagnostics_id = try session.requestDiagnostics("{}");
    const symbols_id = try session.requestSymbols("{}");

    var symbols_response = ParsedMessage{
        .kind = .response,
        .id = symbols_id,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":[{\"name\":\"alpha\",\"location\":{\"uri\":\"file:///tmp/alpha.zig\",\"range\":{\"start\":{\"line\":3,\"character\":4}}},\"kind\":\"fn\"}]}"),
    };
    defer symbols_response.deinit(std.testing.allocator);
    _ = try session.handleMessage(symbols_response);
    try std.testing.expectEqual(@as(usize, 1), session.symbols.items.len);
    try std.testing.expectEqualStrings("alpha", session.symbols.items[0].label);
    try std.testing.expectEqual(@as(usize, 0), session.diagnostics.items.len);

    var diagnostics_response = ParsedMessage{
        .kind = .response,
        .id = diagnostics_id,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"uri\":\"file:///tmp/alpha.zig\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":5,\"character\":6}},\"severity\":1,\"message\":\"boom\"}]}}"),
    };
    defer diagnostics_response.deinit(std.testing.allocator);
    _ = try session.handleMessage(diagnostics_response);
    try std.testing.expectEqual(@as(usize, 1), session.diagnostics.items.len);
    try std.testing.expectEqualStrings("boom", session.diagnostics.items[0].message);
    try std.testing.expectEqual(@as(usize, 1), session.symbols.items.len);
}

test "lsp publishDiagnostics replaces diagnostics for the same path" {
    var session = Session.init(std.testing.allocator);
    defer session.deinit();

    var first = ParsedMessage{
        .kind = .notification,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///tmp/alpha.zig\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":1,\"character\":2}},\"severity\":2,\"message\":\"first\"},{\"range\":{\"start\":{\"line\":3,\"character\":4}},\"severity\":1,\"message\":\"second\"}]}}"),
    };
    defer first.deinit(std.testing.allocator);
    _ = try session.handleMessage(first);
    try std.testing.expectEqual(@as(usize, 2), session.diagnostics.items.len);

    var second = ParsedMessage{
        .kind = .notification,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///tmp/alpha.zig\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":7,\"character\":8}},\"severity\":3,\"message\":\"replacement\"}]}}"),
    };
    defer second.deinit(std.testing.allocator);
    _ = try session.handleMessage(second);
    try std.testing.expectEqual(@as(usize, 1), session.diagnostics.items.len);
    try std.testing.expectEqualStrings("replacement", session.diagnostics.items[0].message);
    try std.testing.expectEqualStrings("/tmp/alpha.zig", session.diagnostics.items[0].path.?);
}

test "lsp workspace symbol responses replace the symbol cache" {
    var session = Session.init(std.testing.allocator);
    defer session.deinit();

    const first_id = try session.requestSymbols("{}");
    var first = ParsedMessage{
        .kind = .response,
        .id = first_id,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[{\"name\":\"alpha\",\"location\":{\"uri\":\"file:///tmp/alpha.zig\",\"range\":{\"start\":{\"line\":0,\"character\":0}}},\"kind\":\"fn\"}]}"),
    };
    defer first.deinit(std.testing.allocator);
    _ = try session.handleMessage(first);
    try std.testing.expectEqual(@as(usize, 1), session.symbols.items.len);
    try std.testing.expectEqualStrings("alpha", session.symbols.items[0].label);

    const second_id = try session.requestSymbols("{}");
    var second = ParsedMessage{
        .kind = .response,
        .id = second_id,
        .body = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":[{\"name\":\"beta\",\"location\":{\"uri\":\"file:///tmp/beta.zig\",\"range\":{\"start\":{\"line\":1,\"character\":1}}},\"kind\":\"fn\"},{\"name\":\"gamma\",\"location\":{\"uri\":\"file:///tmp/gamma.zig\",\"range\":{\"start\":{\"line\":2,\"character\":2}}},\"kind\":\"fn\"}]}"),
    };
    defer second.deinit(std.testing.allocator);
    _ = try session.handleMessage(second);
    try std.testing.expectEqual(@as(usize, 2), session.symbols.items.len);
    try std.testing.expectEqualStrings("beta", session.symbols.items[0].label);
    try std.testing.expectEqualStrings("gamma", session.symbols.items[1].label);
}
