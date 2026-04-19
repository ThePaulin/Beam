const std = @import("std");
const beam = @import("beam");

var hello_pane_type_id: ?u64 = null;
var hello_pane_id: ?u64 = null;

export fn beam_plugin_init(host: *const beam.Host) callconv(.c) c_int {
    host.registerCommand("hello-plugin", "announce that the hello plugin is loaded", helloCommand) catch return 1;
    host.registerEvent("buffer_open", helloBufferOpen) catch return 1;
    host.registerEvent("buffer_save", helloBufferSave) catch return 1;
    const pane_type_id = host.registerPaneType("hello-pane", null) catch return 1;
    hello_pane_type_id = pane_type_id;
    const pane_id = host.createPaneOfType(pane_type_id, "hello pane") catch return 1;
    hello_pane_id = pane_id;
    host.updatePaneState(pane_id, "hello pane", "hello plugin is ready\n") catch return 1;
    host.addDecoration(.{
        .buffer_id = 0,
        .row = 0,
        .col = 0,
        .len = 5,
        .kind = .hint,
        .source = .plugin,
    }) catch return 1;
    host.setExtensionStatus("hello plugin loaded") catch return 1;
    host.setPluginActivity("hello plugin is ready") catch return 1;
    return 0;
}

export fn beam_plugin_deinit(host: *const beam.Host) callconv(.c) void {
    host.clearDecorations() catch {};
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
    if (hello_pane_id) |pane_id| {
        try host.updatePaneState(pane_id, "hello pane", "hello plugin saw buffer open\n");
    }
}

fn helloBufferSave(ctx: *anyopaque, payload: []const u8) !void {
    _ = payload;
    const host: *const beam.Host = @ptrCast(@alignCast(ctx));
    try host.setPluginActivity("hello plugin saw buffer save");
    try host.setExtensionStatus("hello plugin saw buffer save");
    if (hello_pane_id) |pane_id| {
        try host.updatePaneState(pane_id, "hello pane", "hello plugin saw buffer save\n");
    }
}

test "example plugin exports the beam ABI" {
    try std.testing.expectEqualStrings("beam_plugin_init", beam.InitSymbol);
    try std.testing.expectEqualStrings("beam_plugin_deinit", beam.DeinitSymbol);
}
