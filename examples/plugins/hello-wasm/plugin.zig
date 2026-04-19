const std = @import("std");

extern "beam_host" fn beam_register_command(name_ptr: u32, name_len: u32, description_ptr: u32, description_len: u32) i32;
extern "beam_host" fn beam_register_event(name_ptr: u32, name_len: u32) i32;
extern "beam_host" fn beam_set_extension_status(text_ptr: u32, text_len: u32) i32;
extern "beam_host" fn beam_set_plugin_activity(text_ptr: u32, text_len: u32) i32;

const command_name = "hello-wasm";
const command_description = "announce that the hello wasm plugin is loaded";
const buffer_open_event = "buffer_open";
const buffer_save_event = "buffer_save";

const loaded_status = "hello wasm plugin loaded";
const ready_activity = "hello wasm plugin is ready";
const unloaded_status = "hello wasm plugin unloaded";
const unloaded_activity = "hello wasm plugin unloaded";
const command_status = "hello wasm plugin command invoked";
const command_activity = "hello wasm plugin command ran";
const open_status = "hello wasm plugin saw buffer open";
const save_status = "hello wasm plugin saw buffer save";

var scratch: [8192]u8 = undefined;
var scratch_used: usize = 0;

export fn beam_plugin_init() i32 {
    if (beam_register_command(ptrOf(command_name), command_name.len, ptrOf(command_description), command_description.len) != 0) return 1;
    if (beam_register_event(ptrOf(buffer_open_event), buffer_open_event.len) != 0) return 1;
    if (beam_register_event(ptrOf(buffer_save_event), buffer_save_event.len) != 0) return 1;
    if (beam_set_extension_status(ptrOf(loaded_status), loaded_status.len) != 0) return 1;
    if (beam_set_plugin_activity(ptrOf(ready_activity), ready_activity.len) != 0) return 1;
    return 0;
}

export fn beam_plugin_deinit() void {
    _ = beam_set_extension_status(ptrOf(unloaded_status), unloaded_status.len);
    _ = beam_set_plugin_activity(ptrOf(unloaded_activity), unloaded_activity.len);
}

export fn beam_plugin_handle_command(name_ptr: u32, name_len: u32, args_ptr: u32, args_len: u32) i32 {
    _ = args_ptr;
    _ = args_len;
    const name = readBytes(name_ptr, name_len);
    if (!std.mem.eql(u8, name, command_name)) return 1;
    if (beam_set_extension_status(ptrOf(command_status), command_status.len) != 0) return 1;
    if (beam_set_plugin_activity(ptrOf(command_activity), command_activity.len) != 0) return 1;
    return 0;
}

export fn beam_plugin_handle_event(event_ptr: u32, event_len: u32, payload_ptr: u32, payload_len: u32) i32 {
    _ = payload_ptr;
    _ = payload_len;
    const event_name = readBytes(event_ptr, event_len);
    if (std.mem.eql(u8, event_name, buffer_open_event)) {
        return beam_set_extension_status(ptrOf(open_status), open_status.len);
    }
    if (std.mem.eql(u8, event_name, buffer_save_event)) {
        return beam_set_extension_status(ptrOf(save_status), save_status.len);
    }
    return 0;
}

export fn beam_alloc(len: u32) i32 {
    const needed: usize = @intCast(len);
    if (needed == 0) return 0;
    if (needed > scratch.len) return -1;
    if (scratch_used + needed > scratch.len) scratch_used = 0;
    const slice = scratch[scratch_used .. scratch_used + needed];
    scratch_used += needed;
    return @intCast(@intFromPtr(slice.ptr));
}

fn ptrOf(bytes: []const u8) u32 {
    return @intCast(@intFromPtr(bytes.ptr));
}

fn readBytes(ptr: u32, len: u32) []const u8 {
    const start: usize = @intCast(ptr);
    const count: usize = @intCast(len);
    return @as([*]const u8, @ptrFromInt(start))[0..count];
}
