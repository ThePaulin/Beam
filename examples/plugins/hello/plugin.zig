const std = @import("std");
const beam = @import("beam");

export fn beam_plugin_init(host: *const beam.Host) callconv(.c) c_int {
    host.registerCommand("hello-plugin", "announce that the hello plugin is loaded", helloCommand) catch return 1;
    host.registerEvent("buffer_open", helloBufferOpen) catch return 1;
    host.setExtensionStatus("hello plugin loaded") catch return 1;
    host.setPluginActivity("hello plugin is ready") catch return 1;
    return 0;
}

export fn beam_plugin_deinit(host: *const beam.Host) callconv(.c) void {
    host.setExtensionStatus("hello plugin unloaded") catch {};
    host.setPluginActivity("hello plugin unloaded") catch {};
}

fn helloCommand(ctx: *anyopaque, args: []const []const u8) !void {
    _ = args;
    const host: *const beam.Host = @ptrCast(@alignCast(ctx));
    try host.setPluginActivity("hello plugin command ran");
    try host.setExtensionStatus("hello plugin command invoked");
}

fn helloBufferOpen(ctx: *anyopaque, payload: []const u8) !void {
    _ = payload;
    const host: *const beam.Host = @ptrCast(@alignCast(ctx));
    try host.setPluginActivity("hello plugin saw buffer open");
    try host.setExtensionStatus("hello plugin saw buffer open");
}

test "example plugin exports the beam ABI" {
    try std.testing.expectEqualStrings("beam_plugin_init", beam.InitSymbol);
    try std.testing.expectEqualStrings("beam_plugin_deinit", beam.DeinitSymbol);
}
