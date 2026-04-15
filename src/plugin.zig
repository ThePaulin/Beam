const std = @import("std");
const ts_transpile = @import("ts_transpile.zig");

const c = @cImport({
    @cInclude("quickjs.h");
    @cInclude("qjs_wrap.h");
});

fn qjsUndefined() c.JSValue {
    return c.beam_qjs_undefined();
}

fn qjsException() c.JSValue {
    return c.beam_qjs_exception();
}

pub const Command = struct {
    name: []u8,
    description: []u8,
    plugin: *PluginInstance,
    handler_index: usize,
};

pub const ActionKind = enum {
    open_file,
    open_split,
    quit,
};

pub const Action = struct {
    kind: ActionKind,
    path: ?[]u8 = null,
};

pub const PluginHost = struct {
    allocator: std.mem.Allocator,
    plugin_dir: []const u8,
    plugins: std.array_list.Managed(*PluginInstance),
    commands: std.array_list.Managed(Command),
    actions: std.array_list.Managed(Action),
    status: std.array_list.Managed(u8),

    pub fn init(allocator: std.mem.Allocator, plugin_dir: []const u8) PluginHost {
        return .{
            .allocator = allocator,
            .plugin_dir = plugin_dir,
            .plugins = std.array_list.Managed(*PluginInstance).init(allocator),
            .commands = std.array_list.Managed(Command).init(allocator),
            .actions = std.array_list.Managed(Action).init(allocator),
            .status = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *PluginHost) void {
        self.stopAll();
        for (self.commands.items) |cmd| {
            self.allocator.free(cmd.name);
            self.allocator.free(cmd.description);
        }
        self.commands.deinit();
        self.clearActions();
        self.actions.deinit();
        self.status.deinit();
        self.plugins.deinit();
    }

    pub fn discoverAndStart(self: *PluginHost, enabled: []const []const u8, auto_start: bool) !void {
        if (!auto_start) return;

        var dir = std.fs.cwd().openDir(self.plugin_dir, .{ .iterate = true }) catch return;
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!isPluginFile(entry.basename)) continue;
            const name = std.fs.path.stem(entry.basename);
            if (!self.shouldLoad(name, enabled)) continue;
            if (self.isLoaded(name)) continue;
            self.loadPlugin(entry.path) catch |err| {
                std.debug.print("[beam] plugin {s} failed: {s}\n", .{ name, @errorName(err) });
                continue;
            };
        }
    }

    pub fn commandIndex(self: *const PluginHost, name: []const u8) ?usize {
        for (self.commands.items, 0..) |cmd, idx| {
            if (std.mem.eql(u8, cmd.name, name)) return idx;
        }
        return null;
    }

    pub fn invokeCommand(self: *PluginHost, name: []const u8, args: []const []const u8) ![]u8 {
        const index = self.commandIndex(name) orelse return error.UnknownCommand;
        const cmd = self.commands.items[index];
        return try cmd.plugin.invokeCommand(cmd.handler_index, args);
    }

    pub fn broadcastEvent(self: *PluginHost, kind: []const u8, payload: []const u8) void {
        for (self.plugins.items) |plugin| {
            plugin.emitEvent(kind, payload) catch |err| {
                std.debug.print("[beam] plugin {s} event {s} failed: {s}\n", .{ plugin.name, kind, @errorName(err) });
            };
        }
    }

    pub fn setStatus(self: *PluginHost, text: []const u8) !void {
        self.status.clearRetainingCapacity();
        try self.status.appendSlice(text);
    }

    pub fn consumeActions(self: *PluginHost) ![]Action {
        const owned = try self.allocator.alloc(Action, self.actions.items.len);
        @memcpy(owned, self.actions.items);
        self.actions.clearRetainingCapacity();
        return owned;
    }

    pub fn statusText(self: *const PluginHost) []const u8 {
        return self.status.items;
    }

    pub fn enqueueOpenFile(self: *PluginHost, path: []const u8) !void {
        try self.pushAction(.{ .kind = .open_file, .path = try self.allocator.dupe(u8, path) });
    }

    pub fn enqueueOpenSplit(self: *PluginHost, path: []const u8) !void {
        try self.pushAction(.{ .kind = .open_split, .path = try self.allocator.dupe(u8, path) });
    }

    pub fn enqueueQuit(self: *PluginHost) !void {
        try self.pushAction(.{ .kind = .quit });
    }

    pub fn freeAction(self: *PluginHost, action: Action) void {
        if (action.path) |path| self.allocator.free(path);
    }

    fn shouldLoad(self: *const PluginHost, name: []const u8, enabled: []const []const u8) bool {
        _ = self;
        if (enabled.len == 0) return true;
        for (enabled) |item| {
            if (std.mem.eql(u8, item, name)) return true;
        }
        return false;
    }

    fn isLoaded(self: *const PluginHost, name: []const u8) bool {
        for (self.plugins.items) |plugin| {
            if (std.mem.eql(u8, plugin.name, name)) return true;
        }
        return false;
    }

    fn loadPlugin(self: *PluginHost, rel_path: []const u8) !void {
        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.plugin_dir, rel_path });
        errdefer self.allocator.free(full_path);

        const name = try self.allocator.dupe(u8, std.fs.path.stem(rel_path));
        errdefer self.allocator.free(name);

        const initial_commands = self.commands.items.len;
        const plugin = try PluginInstance.create(self, name, full_path);
        errdefer plugin.destroy();

        plugin.loadFromFile() catch |err| {
            self.rollbackCommands(initial_commands);
            plugin.destroy();
            return err;
        };

        try self.plugins.append(plugin);
    }

    fn rollbackCommands(self: *PluginHost, len: usize) void {
        while (self.commands.items.len > len) {
            const cmd = self.commands.pop() orelse unreachable;
            self.allocator.free(cmd.name);
            self.allocator.free(cmd.description);
        }
    }

    fn stopAll(self: *PluginHost) void {
        self.rollbackCommands(0);
        for (self.plugins.items) |plugin| {
            plugin.destroy();
        }
        self.plugins.clearRetainingCapacity();
        self.clearActions();
        self.status.clearRetainingCapacity();
    }

    fn clearActions(self: *PluginHost) void {
        for (self.actions.items) |action| {
            self.freeAction(action);
        }
        self.actions.clearRetainingCapacity();
    }

    fn pushAction(self: *PluginHost, action: Action) !void {
        self.actions.append(action) catch |err| {
            if (action.path) |path| self.allocator.free(path);
            return err;
        };
    }
};

const PluginInstance = struct {
    allocator: std.mem.Allocator,
    host: *PluginHost,
    name: []u8,
    path: []u8,
    runtime: *c.JSRuntime,
    ctx: *c.JSContext,
    handlers: std.array_list.Managed(c.JSValue),
    events: std.array_list.Managed(EventHandler),

    const EventHandler = struct {
        event: []u8,
        handler: c.JSValue,
    };

    fn create(host: *PluginHost, name: []u8, path: []u8) !*PluginInstance {
        const self = try host.allocator.create(PluginInstance);
        errdefer host.allocator.destroy(self);

        const runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer c.JS_FreeRuntime(runtime);

        const ctx = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
        errdefer c.JS_FreeContext(ctx);

        self.* = .{
            .allocator = host.allocator,
            .host = host,
            .name = name,
            .path = path,
            .runtime = runtime,
            .ctx = ctx,
            .handlers = std.array_list.Managed(c.JSValue).init(host.allocator),
            .events = std.array_list.Managed(EventHandler).init(host.allocator),
        };

        _ = c.JS_AddIntrinsicBaseObjects(ctx);
        _ = c.JS_AddIntrinsicEval(ctx);
        _ = c.JS_AddIntrinsicJSON(ctx);
        _ = c.JS_AddIntrinsicPromise(ctx);
        c.JS_SetContextOpaque(ctx, self);
        try self.installBeamApi();
        return self;
    }

    fn destroy(self: *PluginInstance) void {
        for (self.handlers.items) |handler| {
            c.JS_FreeValue(self.ctx, handler);
        }
        self.handlers.deinit();

        for (self.events.items) |event_handler| {
            self.allocator.free(event_handler.event);
            c.JS_FreeValue(self.ctx, event_handler.handler);
        }
        self.events.deinit();

        c.JS_FreeContext(self.ctx);
        c.JS_FreeRuntime(self.runtime);
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    fn installBeamApi(self: *PluginInstance) !void {
        const beam = c.JS_NewObject(self.ctx);
        if (c.JS_IsException(beam)) return error.InvalidPlugin;
        errdefer c.JS_FreeValue(self.ctx, beam);

        try self.defineMethod(beam, "registerCommand", 3, 1);
        try self.defineMethod(beam, "on", 2, 2);
        try self.defineMethod(beam, "log", 1, 3);
        try self.defineMethod(beam, "setStatus", 1, 4);
        try self.defineMethod(beam, "readFile", 1, 5);
        try self.defineMethod(beam, "writeFile", 2, 6);
        try self.defineMethod(beam, "openFile", 1, 7);
        try self.defineMethod(beam, "openSplit", 1, 8);
        try self.defineMethod(beam, "quit", 0, 9);

        const global = c.JS_GetGlobalObject(self.ctx);
        defer c.JS_FreeValue(self.ctx, global);
        if (c.JS_SetPropertyStr(self.ctx, global, "beam", beam) < 0) {
            return error.InvalidPlugin;
        }
    }

    fn defineMethod(self: *PluginInstance, obj: c.JSValue, name: [:0]const u8, argc: c_int, magic: c_int) !void {
        const func = c.JS_NewCFunctionMagic(self.ctx, beamMethod, name, argc, c.JS_CFUNC_generic_magic, magic);
        if (c.JS_IsException(func)) return error.InvalidPlugin;
        if (c.JS_SetPropertyStr(self.ctx, obj, name, func) < 0) {
            c.JS_FreeValue(self.ctx, func);
            return error.InvalidPlugin;
        }
    }

    fn loadFromFile(self: *PluginInstance) !void {
        const raw = try std.fs.cwd().readFileAlloc(self.allocator, self.path, 1 << 20);
        defer self.allocator.free(raw);

        const js = try ts_transpile.transpile(self.allocator, raw);
        defer self.allocator.free(js);

        const js_z = try self.allocator.alloc(u8, js.len + 1);
        defer self.allocator.free(js_z);
        @memcpy(js_z[0..js.len], js);
        js_z[js.len] = 0;

        const filename_z = try self.allocator.alloc(u8, self.path.len + 1);
        defer self.allocator.free(filename_z);
        @memcpy(filename_z[0..self.path.len], self.path);
        filename_z[self.path.len] = 0;

        const eval_result = c.JS_Eval(self.ctx, js_z.ptr, js.len, filename_z.ptr, c.JS_EVAL_TYPE_GLOBAL);
        if (c.JS_IsException(eval_result)) {
            c.JS_FreeValue(self.ctx, eval_result);
            try self.reportJsError("evaluate");
            return error.InvalidPlugin;
        }
        c.JS_FreeValue(self.ctx, eval_result);

        const global = c.JS_GetGlobalObject(self.ctx);
        defer c.JS_FreeValue(self.ctx, global);
        const activate = c.JS_GetPropertyStr(self.ctx, global, "activate");
        if (c.JS_IsException(activate)) {
            c.JS_FreeValue(self.ctx, activate);
            try self.reportJsError("lookup activate");
            return error.InvalidPlugin;
        }
        defer c.JS_FreeValue(self.ctx, activate);

        if (c.JS_IsUndefined(activate)) return;
        if (!c.JS_IsFunction(self.ctx, activate)) {
            return error.InvalidPlugin;
        }

        const beam = try self.makeBeamObject();
        defer c.JS_FreeValue(self.ctx, beam);
        var argv = [_]c.JSValue{ beam };
        const result = try self.callMaybePromise(activate, argv[0..]);
        defer c.JS_FreeValue(self.ctx, result);
    }

    fn makeBeamObject(self: *PluginInstance) !c.JSValue {
        const beam = c.JS_NewObject(self.ctx);
        if (c.JS_IsException(beam)) return error.InvalidPlugin;
        errdefer c.JS_FreeValue(self.ctx, beam);

        try self.defineMethod(beam, "registerCommand", 3, 1);
        try self.defineMethod(beam, "on", 2, 2);
        try self.defineMethod(beam, "log", 1, 3);
        try self.defineMethod(beam, "setStatus", 1, 4);
        try self.defineMethod(beam, "readFile", 1, 5);
        try self.defineMethod(beam, "writeFile", 2, 6);
        try self.defineMethod(beam, "openFile", 1, 7);
        try self.defineMethod(beam, "openSplit", 1, 8);
        try self.defineMethod(beam, "quit", 0, 9);
        return beam;
    }

    fn registerCommand(self: *PluginInstance, name: []const u8, description: []const u8, handler: c.JSValueConst) !void {
        if (self.host.commandIndex(name) != null) return error.DuplicateCommand;

        const handler_dup = c.JS_DupValue(self.ctx, handler);
        self.handlers.append(handler_dup) catch {
            c.JS_FreeValue(self.ctx, handler_dup);
            return error.OutOfMemory;
        };
        errdefer {
            const popped = self.handlers.pop() orelse unreachable;
            c.JS_FreeValue(self.ctx, popped);
        }

        const handler_index = self.handlers.items.len - 1;

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const description_copy = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(description_copy);

        try self.host.commands.append(.{
            .name = name_copy,
            .description = description_copy,
            .plugin = self,
            .handler_index = handler_index,
        });
    }

    fn registerEvent(self: *PluginInstance, event: []const u8, handler: c.JSValueConst) !void {
        const handler_dup = c.JS_DupValue(self.ctx, handler);
        errdefer c.JS_FreeValue(self.ctx, handler_dup);
        const event_copy = try self.allocator.dupe(u8, event);
        errdefer self.allocator.free(event_copy);
        self.events.append(.{
            .event = event_copy,
            .handler = handler_dup,
        }) catch {
            return error.OutOfMemory;
        };
    }

    fn invokeCommand(self: *PluginInstance, handler_index: usize, args: []const []const u8) ![]u8 {
        const handler = self.handlers.items[handler_index];
        const js_args = try self.makeStringArgs(args);
        defer self.freeArgs(js_args);
        const result = try self.callMaybePromise(handler, js_args);
        defer c.JS_FreeValue(self.ctx, result);

        if (c.JS_IsUndefined(result) or c.JS_IsNull(result)) {
            return try self.allocator.dupe(u8, "ok");
        }
        return try self.jsValueToOwnedString(result);
    }

    fn emitEvent(self: *PluginInstance, kind: []const u8, payload: []const u8) !void {
        const payload_value = c.JS_NewStringLen(self.ctx, payload.ptr, payload.len);
        if (c.JS_IsException(payload_value)) return error.InvalidPlugin;
        defer c.JS_FreeValue(self.ctx, payload_value);

        for (self.events.items) |event_handler| {
            if (!std.mem.eql(u8, event_handler.event, kind)) continue;
            var argv = [_]c.JSValue{ c.JS_DupValue(self.ctx, payload_value) };
            const result = self.callMaybePromise(event_handler.handler, argv[0..]) catch {
                continue;
            };
            c.JS_FreeValue(self.ctx, result);
        }
    }

    fn makeStringArgs(self: *PluginInstance, args: []const []const u8) ![]c.JSValue {
        const values = try self.allocator.alloc(c.JSValue, args.len);
        errdefer self.allocator.free(values);
        var idx: usize = 0;
        while (idx < args.len) : (idx += 1) {
            values[idx] = c.JS_NewStringLen(self.ctx, args[idx].ptr, args[idx].len);
            if (c.JS_IsException(values[idx])) {
                var j: usize = idx;
                while (j > 0) {
                    j -= 1;
                    c.JS_FreeValue(self.ctx, values[j]);
                }
                return error.InvalidPlugin;
            }
        }
        return values;
    }

    fn freeArgs(self: *PluginInstance, args: []c.JSValue) void {
        for (args) |arg| {
            c.JS_FreeValue(self.ctx, arg);
        }
        self.allocator.free(args);
    }

    fn callMaybePromise(self: *PluginInstance, callee: c.JSValueConst, argv: []c.JSValue) !c.JSValue {
        const argc: c_int = @intCast(argv.len);
        var dummy_arg = qjsUndefined();
        const argv_ptr: [*c]c.JSValue = if (argv.len == 0) &dummy_arg else argv.ptr;
        const result = c.JS_Call(self.ctx, callee, qjsUndefined(), argc, argv_ptr);
        if (c.JS_IsException(result)) {
            try self.reportJsError("call");
            return error.InvalidPlugin;
        }
        return try self.resolvePromise(result);
    }

    fn resolvePromise(self: *PluginInstance, value: c.JSValue) !c.JSValue {
        if (!c.JS_IsPromise(value)) return value;

        while (true) {
            const state = c.JS_PromiseState(self.ctx, value);
            switch (state) {
                c.JS_PROMISE_PENDING => {
                    var job_ctx: ?*c.JSContext = self.ctx;
                    const ran = c.JS_ExecutePendingJob(self.runtime, &job_ctx);
                    if (ran < 0) {
                        try self.reportJsError("promise job");
                        c.JS_FreeValue(self.ctx, value);
                        return error.InvalidPlugin;
                    }
                    if (ran == 0) break;
                },
                c.JS_PROMISE_FULFILLED => {
                    const resolved = c.JS_PromiseResult(self.ctx, value);
                    c.JS_FreeValue(self.ctx, value);
                    return resolved;
                },
                c.JS_PROMISE_REJECTED => {
                    const result = c.JS_PromiseResult(self.ctx, value);
                    c.JS_FreeValue(self.ctx, value);
                    defer c.JS_FreeValue(self.ctx, result);
                    try self.reportValueError(result, "promise rejection");
                    return error.InvalidPlugin;
                },
                else => return value,
            }
        }

        if (c.JS_PromiseState(self.ctx, value) == c.JS_PROMISE_PENDING) {
            std.debug.print("[beam] plugin {s} promise pending\n", .{ self.name });
            c.JS_FreeValue(self.ctx, value);
            return error.InvalidPlugin;
        }
        return value;
    }

    fn reportJsError(self: *PluginInstance, stage: []const u8) !void {
        const exc = c.JS_GetException(self.ctx);
        defer c.JS_FreeValue(self.ctx, exc);
        try self.reportValueError(exc, stage);
    }

    fn reportValueError(self: *PluginInstance, value: c.JSValueConst, stage: []const u8) !void {
        if (c.JS_IsUndefined(value)) {
            std.debug.print("[beam] plugin {s} {s} failed\n", .{ self.name, stage });
            return;
        }
        const message = try self.jsValueToOwnedString(value);
        defer self.allocator.free(message);
        std.debug.print("[beam] plugin {s} {s} failed: {s}\n", .{ self.name, stage, message });
    }

    fn jsValueToOwnedString(self: *PluginInstance, value: c.JSValueConst) ![]u8 {
        var len: usize = 0;
        const cstr = c.JS_ToCStringLen(self.ctx, &len, value) orelse return error.InvalidPlugin;
        defer c.JS_FreeCString(self.ctx, cstr);
        return try self.allocator.dupe(u8, cstr[0..len]);
    }
};

fn getPlugin(ctx: *c.JSContext) !*PluginInstance {
    const opaque_ptr = c.JS_GetContextOpaque(ctx) orelse return error.InvalidPlugin;
    return @ptrCast(@alignCast(opaque_ptr));
}

fn beamMethod(ctx: ?*c.JSContext, this_val: c.JSValueConst, argc: c_int, argv: [*c]const c.JSValueConst, magic: c_int) callconv(.c) c.JSValue {
    _ = this_val;
    if (ctx == null) return qjsException();
    const context = ctx.?;
    const plugin = getPlugin(context) catch return qjsException();

    const count: usize = @intCast(argc);
    const args = argv[0..count];
    return switch (magic) {
        1 => registerCommandMethod(plugin, args) catch qjsException(),
        2 => onMethod(plugin, args) catch qjsException(),
        3 => logMethod(plugin, args) catch qjsException(),
        4 => setStatusMethod(plugin, args) catch qjsException(),
        5 => readFileMethod(plugin, args) catch qjsException(),
        6 => writeFileMethod(plugin, args) catch qjsException(),
        7 => openFileMethod(plugin, args) catch qjsException(),
        8 => openSplitMethod(plugin, args) catch qjsException(),
        9 => quitMethod(plugin, args) catch qjsException(),
        else => c.JS_ThrowTypeError(context, "unknown beam method"),
    };
}

fn registerCommandMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 3) return c.JS_ThrowTypeError(ctx, "registerCommand(name, description, handler) requires 3 arguments");
    if (!c.JS_IsFunction(ctx, args[2])) return c.JS_ThrowTypeError(ctx, "registerCommand handler must be a function");

    const name = try plugin.jsValueToOwnedString(args[0]);
    errdefer plugin.allocator.free(name);
    const description = try plugin.jsValueToOwnedString(args[1]);
    errdefer plugin.allocator.free(description);
    plugin.registerCommand(name, description, args[2]) catch |err| {
        if (err == error.DuplicateCommand) return c.JS_ThrowTypeError(ctx, "command already registered");
        return c.JS_ThrowInternalError(ctx, "failed to register command");
    };
    return qjsUndefined();
}

fn onMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 2) return c.JS_ThrowTypeError(ctx, "on(event, handler) requires 2 arguments");
    if (!c.JS_IsFunction(ctx, args[1])) return c.JS_ThrowTypeError(ctx, "on handler must be a function");
    const event = try plugin.jsValueToOwnedString(args[0]);
    errdefer plugin.allocator.free(event);
    try plugin.registerEvent(event, args[1]);
    return qjsUndefined();
}

fn logMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 1) return c.JS_ThrowTypeError(ctx, "log(message) requires 1 argument");
    const message = try plugin.jsValueToOwnedString(args[0]);
    defer plugin.allocator.free(message);
    std.debug.print("[beam:{s}] {s}\n", .{ plugin.name, message });
    return qjsUndefined();
}

fn setStatusMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 1) return c.JS_ThrowTypeError(ctx, "setStatus(message) requires 1 argument");
    const message = try plugin.jsValueToOwnedString(args[0]);
    defer plugin.allocator.free(message);
    plugin.host.setStatus(message) catch {};
    return qjsUndefined();
}

fn readFileMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 1) return c.JS_ThrowTypeError(ctx, "readFile(path) requires 1 argument");
    const path = try plugin.jsValueToOwnedString(args[0]);
    defer plugin.allocator.free(path);
    const contents = std.fs.cwd().readFileAlloc(plugin.allocator, path, 1 << 20) catch {
        return c.JS_ThrowTypeError(ctx, "failed to read file");
    };
    defer plugin.allocator.free(contents);
    return c.JS_NewStringLen(ctx, contents.ptr, contents.len);
}

fn writeFileMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 2) return c.JS_ThrowTypeError(ctx, "writeFile(path, contents) requires 2 arguments");
    const path = try plugin.jsValueToOwnedString(args[0]);
    defer plugin.allocator.free(path);
    const contents = try plugin.jsValueToOwnedString(args[1]);
    defer plugin.allocator.free(contents);

    var file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch {
        return c.JS_ThrowTypeError(ctx, "failed to write file");
    };
    defer file.close();
    file.writeAll(contents) catch {
        return c.JS_ThrowTypeError(ctx, "failed to write file");
    };
    return qjsUndefined();
}

fn openFileMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 1) return c.JS_ThrowTypeError(ctx, "openFile(path) requires 1 argument");
    const path = try plugin.jsValueToOwnedString(args[0]);
    defer plugin.allocator.free(path);
    try plugin.host.enqueueOpenFile(path);
    return qjsUndefined();
}

fn openSplitMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len < 1) return c.JS_ThrowTypeError(ctx, "openSplit(path) requires 1 argument");
    const path = try plugin.jsValueToOwnedString(args[0]);
    defer plugin.allocator.free(path);
    try plugin.host.enqueueOpenSplit(path);
    return qjsUndefined();
}

fn quitMethod(plugin: *PluginInstance, args: []const c.JSValueConst) !c.JSValue {
    const ctx = plugin.ctx;
    if (args.len != 0) return c.JS_ThrowTypeError(ctx, "quit() takes no arguments");
    try plugin.host.enqueueQuit();
    return qjsUndefined();
}

fn isPluginFile(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".ts") and !std.mem.endsWith(u8, name, ".d.ts");
}

test "plugin action queue" {
    var host = PluginHost.init(std.testing.allocator, ".beam/plugins");
    defer host.deinit();

    try host.enqueueOpenFile("notes.txt");
    try host.enqueueOpenSplit("split.txt");
    try host.enqueueQuit();

    const actions = try host.consumeActions();
    defer std.testing.allocator.free(actions);
    try std.testing.expectEqual(@as(usize, 3), actions.len);
    try std.testing.expect(actions[0].kind == .open_file);
    try std.testing.expectEqualStrings("notes.txt", actions[0].path.?);
    try std.testing.expect(actions[1].kind == .open_split);
    try std.testing.expectEqualStrings("split.txt", actions[1].path.?);
    try std.testing.expect(actions[2].kind == .quit);
    for (actions) |action| {
        host.freeAction(action);
    }
}
