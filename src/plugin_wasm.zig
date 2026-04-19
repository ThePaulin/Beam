const std = @import("std");
const builtins_mod = @import("builtins.zig");
const plugin_mod = @import("plugin.zig");

const c = @cImport({
    @cInclude("wasmtime.h");
});

const host_module_name = "beam_host";
const memory_export_name = "memory";
const alloc_export_name = "beam_alloc";
const init_export_name = "beam_plugin_init";
const deinit_export_name = "beam_plugin_deinit";
const command_export_name = "beam_plugin_handle_command";
const event_export_name = "beam_plugin_handle_event";

const GuestRange = struct {
    offset: usize,
    len: usize,
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    host: plugin_mod.Host,
    name: []u8,
    engine: *c.wasm_engine_t,
    store: *c.wasmtime_store_t,
    linker: *c.wasmtime_linker_t,
    module: ?*c.wasmtime_module_t,
    instance: c.wasmtime_instance_t,
    memory: c.wasmtime_memory_t,
    alloc_fn: c.wasmtime_func_t,
    init_fn: c.wasmtime_func_t,
    deinit_fn: ?c.wasmtime_func_t,
    command_fn: ?c.wasmtime_func_t,
    event_fn: ?c.wasmtime_func_t,
    commands: std.array_list.Managed(CommandRegistration),
    events: std.array_list.Managed(EventRegistration),

    pub fn init(allocator: std.mem.Allocator, host: *const plugin_mod.Host, manifest: plugin_mod.Manifest, wasm_path: []const u8) !*Runtime {
        const runtime = try allocator.create(Runtime);
        errdefer allocator.destroy(runtime);

        const engine = c.wasm_engine_new() orelse return error.OutOfMemory;
        errdefer c.wasm_engine_delete(engine);

        const store = c.wasmtime_store_new(engine, null, null) orelse return error.OutOfMemory;
        errdefer c.wasmtime_store_delete(store);

        const linker = c.wasmtime_linker_new(engine) orelse return error.OutOfMemory;
        errdefer c.wasmtime_linker_delete(linker);

        runtime.* = .{
            .allocator = allocator,
            .host = host.*,
            .name = try allocator.dupe(u8, manifest.name),
            .engine = engine,
            .store = store,
            .linker = linker,
            .module = null,
            .instance = undefined,
            .memory = undefined,
            .alloc_fn = undefined,
            .init_fn = undefined,
            .deinit_fn = null,
            .command_fn = null,
            .event_fn = null,
            .commands = std.array_list.Managed(CommandRegistration).init(allocator),
            .events = std.array_list.Managed(EventRegistration).init(allocator),
        };
        errdefer runtime.deinit();

        try runtime.defineHostFunctions();

        const wasm_bytes = try std.fs.cwd().readFileAlloc(allocator, wasm_path, 1 << 20);
        defer allocator.free(wasm_bytes);

        var bytes: c.wasm_byte_vec_t = undefined;
        c.wasm_byte_vec_new(&bytes, wasm_bytes.len, wasm_bytes.ptr);
        defer c.wasm_byte_vec_delete(&bytes);

        var module: ?*c.wasmtime_module_t = null;
        try consumeWasmtimeError(c.wasmtime_module_new(engine, bytes.data, bytes.size, &module));
        runtime.module = module orelse return error.InvalidWasm;

        var trap: ?*c.wasm_trap_t = null;
        const instantiate_error = c.wasmtime_linker_instantiate(runtime.linker, runtime.context(), runtime.module.?, &runtime.instance, &trap);
        defer if (trap) |inst_trap| c.wasm_trap_delete(inst_trap);
        try consumeWasmtimeError(instantiate_error);
        if (trap != null) return error.PermissionDenied;

        runtime.memory = try runtime.requireMemoryExport(memory_export_name);
        runtime.alloc_fn = try runtime.requireFuncExport(alloc_export_name);
        runtime.init_fn = try runtime.requireFuncExport(init_export_name);
        runtime.deinit_fn = runtime.findFuncExport(deinit_export_name);
        runtime.command_fn = runtime.findFuncExport(command_export_name);
        runtime.event_fn = runtime.findFuncExport(event_export_name);

        const init_rc = try runtime.callIntFunction(runtime.init_fn, &.{});
        if (init_rc != 0) return error.PermissionDenied;

        try runtime.registerBindings();
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        if (self.deinit_fn) |deinit_fn| {
            _ = self.callVoidFunction(deinit_fn, &.{}) catch {};
        }
        for (self.commands.items) |command| {
            self.allocator.free(command.name);
            self.allocator.free(command.description);
        }
        self.commands.deinit();
        for (self.events.items) |event| self.allocator.free(event.name);
        self.events.deinit();
        self.allocator.free(self.name);
        if (self.module) |module| c.wasmtime_module_delete(module);
        c.wasmtime_linker_delete(self.linker);
        c.wasmtime_store_delete(self.store);
        c.wasm_engine_delete(self.engine);
        self.allocator.destroy(self);
    }

    pub fn invokeCommand(self: *Runtime, command_name: []const u8, args: []const []const u8) !void {
        const func = self.command_fn orelse return error.NotFound;
        var joined = std.array_list.Managed(u8).init(self.allocator);
        defer joined.deinit();
        for (args, 0..) |arg, idx| {
            if (idx != 0) try joined.append('\n');
            try joined.appendSlice(arg);
        }

        const command_ptr = try self.writeGuestBytes(command_name);
        const args_ptr = try self.writeGuestBytes(joined.items);
        _ = try self.callIntFunction(func, &.{
            @intCast(command_ptr),
            @intCast(command_name.len),
            @intCast(args_ptr),
            @intCast(joined.items.len),
        });
    }

    pub fn invokeEvent(self: *Runtime, event_name: []const u8, payload: []const u8) !void {
        const func = self.event_fn orelse return error.NotFound;
        const event_ptr = try self.writeGuestBytes(event_name);
        const payload_ptr = try self.writeGuestBytes(payload);
        _ = try self.callIntFunction(func, &.{
            @intCast(event_ptr),
            @intCast(event_name.len),
            @intCast(payload_ptr),
            @intCast(payload.len),
        });
    }

    fn registerBindings(self: *Runtime) !void {
        for (self.commands.items) |command| {
            const binding = try self.allocator.create(CommandBinding);
            binding.* = .{
                .runtime = self,
                .name = try self.allocator.dupe(u8, command.name),
            };
            try self.host.registerCommandWithContext(command.name, command.description, wasmCommandHandler, binding, freeCommandBinding);
        }

        for (self.events.items) |event| {
            const binding = try self.allocator.create(EventBinding);
            binding.* = .{
                .runtime = self,
                .name = try self.allocator.dupe(u8, event.name),
            };
            try self.host.registerEventWithContext(event.name, wasmEventHandler, binding, freeEventBinding);
        }
    }

    fn defineHostFunctions(self: *Runtime) !void {
        try self.defineI32HostFunction("beam_register_command", 4, hostRegisterCommand);
        try self.defineI32HostFunction("beam_register_event", 2, hostRegisterEvent);
        try self.defineI32HostFunction("beam_set_extension_status", 2, hostSetExtensionStatus);
        try self.defineI32HostFunction("beam_set_plugin_activity", 2, hostSetPluginActivity);
    }

    fn defineI32HostFunction(self: *Runtime, name: []const u8, param_count: usize, callback: c.wasmtime_func_callback_t) !void {
        var params: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new_uninitialized(&params, param_count);
        for (0..param_count) |idx| {
            params.data[idx] = c.wasm_valtype_new(c.WASM_I32);
        }
        var results: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new_uninitialized(&results, 1);
        results.data[0] = c.wasm_valtype_new(c.WASM_I32);
        const ty = c.wasm_functype_new(&params, &results) orelse return error.OutOfMemory;
        defer c.wasm_functype_delete(ty);
        try consumeWasmtimeError(c.wasmtime_linker_define_func(
            self.linker,
            host_module_name.ptr,
            host_module_name.len,
            name.ptr,
            name.len,
            ty,
            callback,
            self,
            null,
        ));
    }

    fn requireMemoryExport(self: *Runtime, name: []const u8) !c.wasmtime_memory_t {
        var ext: c.wasmtime_extern_t = undefined;
        if (!c.wasmtime_instance_export_get(self.context(), &self.instance, name.ptr, name.len, &ext)) return error.NotFound;
        if (ext.kind != c.WASMTIME_EXTERN_MEMORY) return error.NotFound;
        return ext.of.memory;
    }

    fn requireFuncExport(self: *Runtime, name: []const u8) !c.wasmtime_func_t {
        return self.findFuncExport(name) orelse error.NotFound;
    }

    fn findFuncExport(self: *Runtime, name: []const u8) ?c.wasmtime_func_t {
        var ext: c.wasmtime_extern_t = undefined;
        if (!c.wasmtime_instance_export_get(self.context(), &self.instance, name.ptr, name.len, &ext)) return null;
        if (ext.kind != c.WASMTIME_EXTERN_FUNC) return null;
        return ext.of.func;
    }

    fn callVoidFunction(self: *Runtime, func: c.wasmtime_func_t, args: []const i32) !void {
        var values = try self.allocator.alloc(c.wasmtime_val_t, args.len);
        defer self.allocator.free(values);
        for (args, 0..) |arg, idx| values[idx] = makeI32(arg);
        var trap: ?*c.wasm_trap_t = null;
        defer if (trap) |call_trap| c.wasm_trap_delete(call_trap);
        try consumeWasmtimeError(c.wasmtime_func_call(self.context(), &func, if (values.len == 0) null else values.ptr, values.len, null, 0, &trap));
        if (trap != null) return error.PermissionDenied;
    }

    fn callIntFunction(self: *Runtime, func: c.wasmtime_func_t, args: []const i32) !i32 {
        var values = try self.allocator.alloc(c.wasmtime_val_t, args.len);
        defer self.allocator.free(values);
        for (args, 0..) |arg, idx| values[idx] = makeI32(arg);
        var result: [1]c.wasmtime_val_t = .{makeI32(0)};
        var trap: ?*c.wasm_trap_t = null;
        defer if (trap) |call_trap| c.wasm_trap_delete(call_trap);
        try consumeWasmtimeError(c.wasmtime_func_call(self.context(), &func, if (values.len == 0) null else values.ptr, values.len, &result, result.len, &trap));
        if (trap != null) return error.PermissionDenied;
        return result[0].of.i32;
    }

    fn writeGuestBytes(self: *Runtime, bytes: []const u8) !u32 {
        if (bytes.len == 0) return 0;
        const ptr = try self.callIntFunction(self.alloc_fn, &.{@intCast(bytes.len)});
        const range = try validateGuestRange(ptr, bytes.len, self.memoryData().len);
        var memory = self.memoryData();
        @memcpy(memory[range.offset .. range.offset + range.len], bytes);
        return @intCast(range.offset);
    }

    fn memoryData(self: *Runtime) []u8 {
        const size = c.wasmtime_memory_data_size(self.context(), &self.memory);
        const data = c.wasmtime_memory_data(self.context(), &self.memory);
        return data[0..size];
    }

    fn readCallerBytes(self: *Runtime, caller: *c.wasmtime_caller_t, ptr: i32, len: i32) ![]const u8 {
        _ = self;
        var ext: c.wasmtime_extern_t = undefined;
        if (!c.wasmtime_caller_export_get(caller, memory_export_name.ptr, memory_export_name.len, &ext)) return error.NotFound;
        if (ext.kind != c.WASMTIME_EXTERN_MEMORY) return error.NotFound;
        const caller_context = c.wasmtime_caller_context(caller);
        const size = c.wasmtime_memory_data_size(caller_context, &ext.of.memory);
        const data = c.wasmtime_memory_data(caller_context, &ext.of.memory);
        const range = try validateGuestRange(ptr, len, size);
        return data[range.offset .. range.offset + range.len];
    }

    fn context(self: *Runtime) *c.wasmtime_context_t {
        return c.wasmtime_store_context(self.store).?;
    }
};

const CommandRegistration = struct {
    name: []u8,
    description: []u8,
};

const EventRegistration = struct {
    name: []u8,
};

const CommandBinding = struct {
    runtime: *Runtime,
    name: []u8,
};

const EventBinding = struct {
    runtime: *Runtime,
    name: []u8,
};

fn wasmCommandHandler(ctx: *anyopaque, args: []const []const u8) !void {
    const binding: *CommandBinding = @ptrCast(@alignCast(ctx));
    try binding.runtime.invokeCommand(binding.name, args);
}

fn wasmEventHandler(ctx: *anyopaque, payload: []const u8) !void {
    const binding: *EventBinding = @ptrCast(@alignCast(ctx));
    try binding.runtime.invokeEvent(binding.name, payload);
}

fn freeCommandBinding(allocator: std.mem.Allocator, ctx: *anyopaque) void {
    const binding: *CommandBinding = @ptrCast(@alignCast(ctx));
    allocator.free(binding.name);
    allocator.destroy(binding);
}

fn freeEventBinding(allocator: std.mem.Allocator, ctx: *anyopaque) void {
    const binding: *EventBinding = @ptrCast(@alignCast(ctx));
    allocator.free(binding.name);
    allocator.destroy(binding);
}

fn hostRegisterCommand(env: ?*anyopaque, caller: ?*c.wasmtime_caller_t, args: [*c]const c.wasmtime_val_t, nargs: usize, results: [*c]c.wasmtime_val_t, nresults: usize) callconv(.c) ?*c.wasm_trap_t {
    setI32Result(results, nresults, 0, 1);
    if (env == null or caller == null or nargs != 4) return null;
    const runtime: *Runtime = @ptrCast(@alignCast(env.?));
    if (!runtime.host.caps.allows(.command)) return null;
    const name = runtime.readCallerBytes(caller.?, args[0].of.i32, args[1].of.i32) catch return null;
    const description = runtime.readCallerBytes(caller.?, args[2].of.i32, args[3].of.i32) catch return null;
    const command = CommandRegistration{
        .name = runtime.allocator.dupe(u8, name) catch return null,
        .description = runtime.allocator.dupe(u8, description) catch return null,
    };
    runtime.commands.append(command) catch {
        runtime.allocator.free(command.name);
        runtime.allocator.free(command.description);
        return null;
    };
    setI32Result(results, nresults, 0, 0);
    return null;
}

fn hostRegisterEvent(env: ?*anyopaque, caller: ?*c.wasmtime_caller_t, args: [*c]const c.wasmtime_val_t, nargs: usize, results: [*c]c.wasmtime_val_t, nresults: usize) callconv(.c) ?*c.wasm_trap_t {
    setI32Result(results, nresults, 0, 1);
    if (env == null or caller == null or nargs != 2) return null;
    const runtime: *Runtime = @ptrCast(@alignCast(env.?));
    if (!runtime.host.caps.allows(.event)) return null;
    const name = runtime.readCallerBytes(caller.?, args[0].of.i32, args[1].of.i32) catch return null;
    runtime.events.append(.{
        .name = runtime.allocator.dupe(u8, name) catch return null,
    }) catch return null;
    setI32Result(results, nresults, 0, 0);
    return null;
}

fn hostSetExtensionStatus(env: ?*anyopaque, caller: ?*c.wasmtime_caller_t, args: [*c]const c.wasmtime_val_t, nargs: usize, results: [*c]c.wasmtime_val_t, nresults: usize) callconv(.c) ?*c.wasm_trap_t {
    setI32Result(results, nresults, 0, 1);
    if (env == null or caller == null or nargs != 2) return null;
    const runtime: *Runtime = @ptrCast(@alignCast(env.?));
    const text = runtime.readCallerBytes(caller.?, args[0].of.i32, args[1].of.i32) catch return null;
    runtime.host.setExtensionStatus(text) catch return null;
    setI32Result(results, nresults, 0, 0);
    return null;
}

fn hostSetPluginActivity(env: ?*anyopaque, caller: ?*c.wasmtime_caller_t, args: [*c]const c.wasmtime_val_t, nargs: usize, results: [*c]c.wasmtime_val_t, nresults: usize) callconv(.c) ?*c.wasm_trap_t {
    setI32Result(results, nresults, 0, 1);
    if (env == null or caller == null or nargs != 2) return null;
    const runtime: *Runtime = @ptrCast(@alignCast(env.?));
    const text = runtime.readCallerBytes(caller.?, args[0].of.i32, args[1].of.i32) catch return null;
    runtime.host.setPluginActivity(text) catch return null;
    setI32Result(results, nresults, 0, 0);
    return null;
}

fn makeI32(value: i32) c.wasmtime_val_t {
    var result: c.wasmtime_val_t = undefined;
    result.kind = c.WASMTIME_I32;
    result.of.i32 = value;
    return result;
}

fn setI32Result(results: [*c]c.wasmtime_val_t, nresults: usize, index: usize, value: i32) void {
    if (nresults <= index) return;
    results[index] = makeI32(value);
}

fn consumeWasmtimeError(err: ?*c.wasmtime_error_t) !void {
    if (err == null) return;
    defer c.wasmtime_error_delete(err);
    return error.WasmRuntimeUnavailable;
}

fn validateGuestRange(ptr: i32, len: anytype, memory_len: usize) !GuestRange {
    const range_len: usize = switch (@TypeOf(len)) {
        i32 => blk: {
            if (len < 0) return error.InvalidWasm;
            break :blk @intCast(len);
        },
        usize => len,
        else => @compileError("unsupported guest range length type"),
    };
    if (ptr < 0) return error.OutOfMemory;
    const offset: usize = @intCast(ptr);
    const end = std.math.add(usize, offset, range_len) catch return error.InvalidWasm;
    if (end > memory_len) return error.InvalidWasm;
    return .{ .offset = offset, .len = range_len };
}

test "guest range validation rejects failed allocations and invalid caller spans" {
    const alloc_failure = validateGuestRange(-1, @as(usize, 4), 32);
    try std.testing.expectError(error.OutOfMemory, alloc_failure);

    const negative_len = validateGuestRange(4, @as(i32, -1), 32);
    try std.testing.expectError(error.InvalidWasm, negative_len);

    const past_end = validateGuestRange(30, @as(i32, 4), 32);
    try std.testing.expectError(error.InvalidWasm, past_end);

    const ok = try validateGuestRange(8, @as(usize, 6), 32);
    try std.testing.expectEqual(@as(usize, 8), ok.offset);
    try std.testing.expectEqual(@as(usize, 6), ok.len);
}

test "wasm runtime loads the hello-wasm example and routes command and event callbacks" {
    if (!plugin_mod.wasm_runtime_enabled) return error.SkipZigTest;

    const TestState = struct {
        registry: builtins_mod.Registry,
        extension_status: []u8 = &.{},
        plugin_activity: []u8 = &.{},

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.extension_status.len > 0) allocator.free(self.extension_status);
            if (self.plugin_activity.len > 0) allocator.free(self.plugin_activity);
            self.registry.deinit();
        }

        fn setStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            _ = ctx;
            _ = text;
        }

        fn setExtensionStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
            const state: *@This() = @ptrCast(@alignCast(ctx));
            if (state.extension_status.len > 0) std.testing.allocator.free(state.extension_status);
            state.extension_status = try std.testing.allocator.dupe(u8, text);
        }

        fn setPluginActivity(ctx: *anyopaque, text: []const u8) anyerror!void {
            const state: *@This() = @ptrCast(@alignCast(ctx));
            if (state.plugin_activity.len > 0) std.testing.allocator.free(state.plugin_activity);
            state.plugin_activity = try std.testing.allocator.dupe(u8, text);
        }

        fn registerCommandWithContext(ctx: *anyopaque, name: []const u8, description: []const u8, handler: plugin_mod.CommandHandler, handler_ctx: *anyopaque, handler_ctx_free: ?plugin_mod.HandlerContextFreeFn) anyerror!void {
            const state: *@This() = @ptrCast(@alignCast(ctx));
            try state.registry.registerExtensionCommandWithContext(name, description, handler, handler_ctx, handler_ctx_free);
        }

        fn registerEventWithContext(ctx: *anyopaque, event: []const u8, handler: plugin_mod.EventHandler, handler_ctx: *anyopaque, handler_ctx_free: ?plugin_mod.HandlerContextFreeFn) anyerror!void {
            const state: *@This() = @ptrCast(@alignCast(ctx));
            try state.registry.registerExtensionEventWithContext(event, handler, handler_ctx, handler_ctx_free);
        }
    };

    var state = TestState{
        .registry = builtins_mod.Registry.init(std.testing.allocator),
    };
    defer state.deinit(std.testing.allocator);

    var host = plugin_mod.Host{
        .ctx = &state,
        .caps = .{ .status = true, .command = true, .event = true },
        .set_status = TestState.setStatus,
        .set_extension_status = TestState.setExtensionStatus,
        .set_plugin_activity = TestState.setPluginActivity,
        .register_command_with_context = TestState.registerCommandWithContext,
        .register_event_with_context = TestState.registerEventWithContext,
    };
    const manifest: plugin_mod.Manifest = .{
        .name = "hello-wasm",
        .version = "0.1.0",
        .runtime = .wasm,
        .capabilities = .{ .command = true, .event = true, .status = true },
    };
    try std.fs.cwd().access("zig-out/plugins/hello-wasm/plugin.wasm", .{});

    const runtime = try Runtime.init(std.testing.allocator, &host, manifest, "zig-out/plugins/hello-wasm/plugin.wasm");
    try std.testing.expectEqual(@as(usize, 1), state.registry.extension_commands.items.len);
    try std.testing.expectEqual(@as(usize, 2), state.registry.extension_events.items.len);
    try std.testing.expectEqualStrings("hello wasm plugin loaded", state.extension_status);
    try std.testing.expectEqualStrings("hello wasm plugin is ready", state.plugin_activity);

    try std.testing.expect(try state.registry.invokeCommand(&host, "hello-wasm", &.{"alpha"}));
    try std.testing.expectEqualStrings("hello wasm plugin command invoked", state.extension_status);
    try std.testing.expectEqualStrings("hello wasm plugin command ran", state.plugin_activity);

    state.registry.emit(&host, "buffer_open", "{}");
    try std.testing.expectEqualStrings("hello wasm plugin saw buffer open", state.extension_status);

    runtime.deinit();
    try std.testing.expectEqualStrings("hello wasm plugin unloaded", state.extension_status);
    try std.testing.expectEqualStrings("hello wasm plugin unloaded", state.plugin_activity);
}
