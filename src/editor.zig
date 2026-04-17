const std = @import("std");
const builtin = @import("builtin");
const buffer_mod = @import("buffer.zig");
const diagnostics_mod = @import("diagnostics.zig");
const config_mod = @import("config.zig");
const builtins_mod = @import("builtins.zig");
const bindings_mod = @import("editor/bindings.zig");
const commands_mod = @import("editor/commands.zig");
const lsp_mod = @import("lsp.zig");
const render_mod = @import("editor/render.zig");
const pane_mod = @import("pane.zig");
const listsource_mod = @import("listsource.zig");
const listpane_mod = @import("listpane.zig");
const picker_mod = @import("picker.zig");
const plugin_mod = @import("plugin.zig");
const plugin_catalog_mod = @import("plugin_catalog.zig");
const search_mod = @import("search.zig");
const scheduler_mod = @import("scheduler.zig");
const syntax_mod = @import("treesitter.zig");
const workspace_mod = @import("workspace.zig");
const terminal_mod = @import("terminal.zig");

const NormalAction = bindings_mod.NormalAction;
const Style = render_mod.Style;
const Theme = render_mod.Theme;
const Mode = render_mod.Mode;

fn writeStyle(writer: anytype, style: Style) !void {
    return render_mod.writeStyle(writer, style);
}

fn writeStyledText(writer: anytype, style: Style, text: []const u8) !void {
    return render_mod.writeStyledText(writer, style, text);
}

fn displayWidth(text: []const u8) usize {
    return render_mod.displayWidth(text);
}

fn clipText(text: []const u8, width: usize) []const u8 {
    return render_mod.clipText(text, width);
}

fn modeIconText(self: *App, mode: Mode) []const u8 {
    return render_mod.modeIconText(&self.config, mode);
}

fn modeLabel(mode: Mode) []const u8 {
    return render_mod.modeLabel(mode);
}

fn normalActionHelp(sequence: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) ?[]const u8 {
    return bindings_mod.normalActionHelp(sequence, leader, bindings);
}

fn normalActionHasPrefix(prefix: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) bool {
    return bindings_mod.normalActionHasPrefix(prefix, leader, bindings);
}

fn normalActionFor(sequence: []const u8, leader: []const u8, bindings: []const config_mod.Config.Keymap.LeaderBinding) ?NormalAction {
    return bindings_mod.normalActionFor(sequence, leader, bindings);
}

fn matchesCommand(head: []const u8, aliases: []const []const u8, configured: []const u8) bool {
    return commands_mod.matchesCommand(head, aliases, configured);
}

fn stripVisualRangePrefix(command: []const u8) []const u8 {
    return commands_mod.stripVisualRangePrefix(command);
}

const SplitFocus = enum { left, right };

const OperatorKind = enum { delete, change, yank };

const MotionSpec = union(enum) {
    line_start,
    line_nonblank,
    line_last_nonblank,
    line_end,
    doc_start,
    doc_middle,
    doc_end,
    current_line,
    left,
    down,
    up,
    right,
    word_forward: bool,
    word_backward: bool,
    word_end_forward: bool,
    word_end_backward: bool,
    paragraph_forward,
    paragraph_backward,
    sentence_forward,
    sentence_backward,
    matching_character,
    find_forward: struct { needle: u8, before: bool },
    find_backward: struct { needle: u8, before: bool },
    text_object: struct { byte: u8, inner: bool },
};

const OperatorRecipe = struct {
    kind: OperatorKind,
    operator_count: usize = 1,
    motion_count: usize = 1,
    motion: MotionSpec,
};

const RepeatableEdit = union(enum) {
    action: struct { action: NormalAction, count: usize },
    operator: OperatorRecipe,
};

// First-pass gaps we will tackle after the redesigned bar lands.
const status_bar_todo = [_][]const u8{
    "git branch / repository state",
    "diagnostics / LSP counts",
    "filetype / encoding / line endings",
    "macro recording indicator",
};

pub const App = struct {
    allocator: std.mem.Allocator,
    args: []const [:0]u8,
    config_path: []u8,
    config: config_mod.Config,
    theme: Theme,
    buffers: std.array_list.Managed(buffer_mod.Buffer),
    active_index: usize = 0,
    previous_active_index: ?usize = null,
    split_index: ?usize = null,
    split_focus: SplitFocus = .left,
    mode: Mode = .normal,
    command_buffer: std.array_list.Managed(u8),
    search_buffer: std.array_list.Managed(u8),
    normal_sequence: std.array_list.Managed(u8),
    status: std.array_list.Managed(u8),
    raw_mode: ?terminal_mod.RawMode = null,
    builtins: builtins_mod.Registry,
    plugin_catalog: plugin_catalog_mod.Catalog,
    scheduler: scheduler_mod.Scheduler,
    diagnostics: diagnostics_mod.Store,
    lsp: lsp_mod.Session,
    lsp_server: ?lsp_mod.ProcessServer,
    syntax: syntax_mod.Service,
    diagnostics_list: listpane_mod.ListPane,
    picker: picker_mod.Picker,
    plugins_list: listpane_mod.ListPane,
    plugin_detail_rows: std.array_list.Managed(PluginDetailRow),
    panes: pane_mod.Manager,
    diagnostics_pane_id: ?u64 = null,
    picker_pane_id: ?u64 = null,
    plugins_pane_id: ?u64 = null,
    plugin_details_pane_id: ?u64 = null,
    plugin_detail_selected: usize = 0,
    plugin_detail_context: ?[]u8 = null,
    plugin_activity: std.array_list.Managed(u8),
    picker_source_key: ?listsource_mod.SourceKey = null,
    picker_source_spec: ?listsource_mod.SourceSpec = null,
    picker_source_pattern: ?[]u8 = null,
    picker_source_pathspec: ?[]u8 = null,
    picker_job_id: ?u64 = null,
    search: search_mod.SearchIndex,
    workspace: workspace_mod.Workspace,
    should_quit: bool = false,
    file_to_open: ?[]u8 = null,
    interactive_command_hook: ?*const fn (self: *App, argv: []const []const u8) bool = null,
    clipboard_get_hook: ?*const fn (self: *App) ?[]const u8 = null,
    clipboard_set_hook: ?*const fn (self: *App, text: []const u8) bool = null,
    clipboard_contents: ?[]u8 = null,
    last_interactive_command: ?[]u8 = null,
    jump_history: std.array_list.Managed(buffer_mod.Position),
    jump_history_index: ?usize = null,
    change_history: std.array_list.Managed(buffer_mod.Position),
    quickfix_list: listpane_mod.ListPane,
    diff_peer_index: ?usize = null,
    diff_mode: bool = false,
    change_jump_index: ?usize = null,
    macro_recording: ?u8 = null,
    macro_ignore_next: bool = false,
    macro_playing: bool = false,
    macros: [26]?[]u8 = [_]?[]u8{null} ** 26,
    last_render_height: usize = 24,
    pending_prefix: PendingPrefix = .none,
    pending_register: ?u8 = null,
    insert_register_prefix: bool = false,
    count_prefix: usize = 0,
    count_active: bool = false,
    visual_mode: VisualMode = .none,
    visual_anchor: ?buffer_mod.Position = null,
    visual_select_mode: bool = false,
    visual_select_restore: bool = false,
    visual_pending: ?VisualPending = null,
    last_visual_state: ?VisualState = null,
    visual_block_insert: ?VisualBlockInsert = null,
    close_confirm: ?CloseTarget = null,
    search_highlight: ?[]u8 = null,
    search_preview_highlight: ?[]u8 = null,
    search_forward: bool = true,
    last_find: ?FindState = null,
    last_repeatable_edit: ?RepeatableEdit = null,
    registers: RegisterStore,
    marks: [26]?buffer_mod.Position = [_]?buffer_mod.Position{null} ** 26,

    const VisualMode = enum { none, character, line, block };
    const VisualPending = enum { ctrl_backslash, g_prefix, replace_char, textobject_outer, textobject_inner };
    const PendingPrefix = enum { none, register, replace_char, find_forward, find_forward_before, find_backward, find_backward_before, macro_record, macro_run, mark_set, mark_jump, mark_jump_exact };
    const CloseTarget = enum { split, tab, buffer };
    const PluginDetailAction = enum { none, run_command };
    const PluginDetailRow = struct {
        label: []u8,
        detail: ?[]u8 = null,
        action: PluginDetailAction = .none,
        command_name: ?[]u8 = null,
    };
    const FindState = struct {
        char: u8,
        forward: bool,
        before: bool,
    };
    const VisualState = struct {
        mode: VisualMode,
        anchor: buffer_mod.Position,
        cursor: buffer_mod.Position,
        select_mode: bool,
        select_restore: bool,
    };
    const VisualBlockInsert = struct {
        start_row: usize,
        end_row: usize,
        column: usize,
        before: bool,
        text: std.array_list.Managed(u8),
    };

    const RegisterStore = struct {
        const RegisterEntry = struct {
            text: []u8,
            linewise: bool = false,
        };

        allocator: std.mem.Allocator,
        values: [256]?RegisterEntry = [_]?RegisterEntry{null} ** 256,

        fn init(allocator: std.mem.Allocator) RegisterStore {
            return .{ .allocator = allocator };
        }

        fn deinit(self: *RegisterStore) void {
            for (self.values) |item| {
                if (item) |value| self.allocator.free(value.text);
            }
        }

        fn set(self: *RegisterStore, key: u8, value: []const u8) !void {
            try self.setWithKind(key, value, false);
        }

        fn setWithKind(self: *RegisterStore, key: u8, value: []const u8, linewise: bool) !void {
            if (self.values[key]) |existing| self.allocator.free(existing.text);
            self.values[key] = .{
                .text = try self.allocator.dupe(u8, value),
                .linewise = linewise,
            };
        }

        fn get(self: *const RegisterStore, key: u8) ?[]const u8 {
            if (self.values[key]) |entry| return entry.text;
            return null;
        }

        fn isLinewise(self: *const RegisterStore, key: u8) bool {
            return if (self.values[key]) |entry| entry.linewise else false;
        }

        fn formatSummary(self: *const RegisterStore, allocator: std.mem.Allocator) ![]u8 {
            var out = std.array_list.Managed(u8).init(allocator);
            errdefer out.deinit();
            var any = false;
            for (self.values, 0..) |item, idx| {
                if (item) |value| {
                    any = true;
                    if (out.items.len > 0) try out.appendSlice(" | ");
                    const piece = try std.fmt.allocPrint(allocator, "\"{c}={s}", .{ @as(u8, @intCast(idx)), value.text });
                    defer allocator.free(piece);
                    try out.appendSlice(piece);
                }
            }
            if (!any) try out.appendSlice("registers empty");
            return try out.toOwnedSlice();
        }
    };

    pub fn init(allocator: std.mem.Allocator, args: []const [:0]u8) !App {
        var workspace = try workspace_mod.Workspace.init(allocator);
        errdefer workspace.deinit();
        var search = try search_mod.SearchIndex.init(allocator, workspace.root_path);
        errdefer search.deinit();
        var config_path = try allocator.dupe(u8, "beam.toml");
        errdefer allocator.free(config_path);
        var file_to_open: ?[]u8 = null;
        errdefer if (file_to_open) |f| allocator.free(f);

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--config") and i + 1 < args.len) {
                allocator.free(config_path);
                config_path = try allocator.dupe(u8, args[i + 1]);
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--help")) {
                try printHelp();
                return error.HelpRequested;
            }
            if (args[i][0] != '-') {
                if (file_to_open) |f| allocator.free(f);
                file_to_open = try allocator.dupe(u8, args[i]);
            }
        }

        var diag = config_mod.Diagnostics{};
        const config = config_mod.load(allocator, config_path, &diag) catch |err| {
            if (err == error.FileNotFound) {
                const cfg = try config_mod.Config.init(allocator);
                var app: App = .{
                    .allocator = allocator,
                    .args = args,
                    .config_path = config_path,
                    .config = cfg,
                    .theme = Theme.resolve(cfg.theme, cfg.background_color, cfg.blur, cfg.opacity),
                    .buffers = std.array_list.Managed(buffer_mod.Buffer).init(allocator),
                    .command_buffer = std.array_list.Managed(u8).init(allocator),
                    .search_buffer = std.array_list.Managed(u8).init(allocator),
                    .normal_sequence = std.array_list.Managed(u8).init(allocator),
                    .status = std.array_list.Managed(u8).init(allocator),
                    .builtins = builtins_mod.Registry.init(allocator),
                    .plugin_catalog = plugin_catalog_mod.Catalog.init(allocator),
                    .scheduler = scheduler_mod.Scheduler.init(allocator),
                    .diagnostics = diagnostics_mod.Store.init(allocator),
                    .lsp = lsp_mod.Session.init(allocator),
                    .lsp_server = null,
                    .syntax = syntax_mod.Service.init(allocator),
                    .diagnostics_list = listpane_mod.ListPane.init(allocator),
                    .picker = picker_mod.Picker.init(allocator),
                    .plugins_list = listpane_mod.ListPane.init(allocator),
                    .plugin_detail_rows = std.array_list.Managed(PluginDetailRow).init(allocator),
                    .panes = pane_mod.Manager.init(allocator),
                    .diagnostics_pane_id = null,
                    .picker_pane_id = null,
                    .plugins_pane_id = null,
                    .plugin_details_pane_id = null,
                    .plugin_detail_selected = 0,
                    .plugin_detail_context = null,
                    .plugin_activity = std.array_list.Managed(u8).init(allocator),
                    .picker_source_key = null,
                    .picker_source_spec = null,
                    .search = search,
                    .workspace = workspace,
                    .file_to_open = file_to_open,
                    .jump_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
                    .change_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
                    .quickfix_list = listpane_mod.ListPane.init(allocator),
                    .registers = RegisterStore.init(allocator),
                };
                var host = app.builtinHost();
                app.builtins.clearExtensionRegistrations();
                try app.plugin_catalog.rebuild(&host, app.config.builtins.enabled.items, app.config.plugins.root, app.config.plugins.enabled.items);
                try app.builtins.rebuild(&host, app.config.builtins.api_version, app.plugin_catalog.manifests());
                app.startConfiguredLsp();
                _ = try app.panes.open(.editor, "editor");
                return app;
            }
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ config_path, diag.line, diag.column, diag.message });
            return err;
        };

        var app: App = .{
            .allocator = allocator,
            .args = args,
            .config_path = config_path,
            .config = config,
            .theme = Theme.resolve(config.theme, config.background_color, config.blur, config.opacity),
            .buffers = std.array_list.Managed(buffer_mod.Buffer).init(allocator),
            .command_buffer = std.array_list.Managed(u8).init(allocator),
            .search_buffer = std.array_list.Managed(u8).init(allocator),
            .normal_sequence = std.array_list.Managed(u8).init(allocator),
            .status = std.array_list.Managed(u8).init(allocator),
            .builtins = builtins_mod.Registry.init(allocator),
            .plugin_catalog = plugin_catalog_mod.Catalog.init(allocator),
            .scheduler = scheduler_mod.Scheduler.init(allocator),
            .diagnostics = diagnostics_mod.Store.init(allocator),
            .lsp = lsp_mod.Session.init(allocator),
            .lsp_server = null,
            .syntax = syntax_mod.Service.init(allocator),
            .diagnostics_list = listpane_mod.ListPane.init(allocator),
            .picker = picker_mod.Picker.init(allocator),
            .plugins_list = listpane_mod.ListPane.init(allocator),
            .plugin_detail_rows = std.array_list.Managed(PluginDetailRow).init(allocator),
            .panes = pane_mod.Manager.init(allocator),
            .diagnostics_pane_id = null,
            .picker_pane_id = null,
            .plugins_pane_id = null,
            .plugin_details_pane_id = null,
            .plugin_detail_selected = 0,
            .plugin_detail_context = null,
            .plugin_activity = std.array_list.Managed(u8).init(allocator),
            .picker_source_key = null,
            .picker_source_spec = null,
            .picker_job_id = null,
            .search = search,
            .workspace = workspace,
            .file_to_open = file_to_open,
            .jump_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
            .change_history = std.array_list.Managed(buffer_mod.Position).init(allocator),
            .quickfix_list = listpane_mod.ListPane.init(allocator),
            .registers = RegisterStore.init(allocator),
        };
        var host = app.builtinHost();
        try app.plugin_catalog.rebuild(&host, app.config.builtins.enabled.items, app.config.plugins.root, app.config.plugins.enabled.items);
        try app.builtins.rebuild(&host, app.config.builtins.api_version, app.plugin_catalog.manifests());
        app.startConfiguredLsp();
        _ = try app.panes.open(.editor, "editor");
        return app;
    }

    pub fn deinit(self: *App) void {
        self.shutdownConfiguredLsp();
        self.exitTerminal() catch {};
        self.syncWorkspaceSession() catch {};
        for (self.buffers.items) |*buf| buf.deinit();
        self.buffers.deinit();
        self.command_buffer.deinit();
        self.search_buffer.deinit();
        self.normal_sequence.deinit();
        self.status.deinit();
        self.plugin_catalog.deinit();
        self.builtins.deinit();
        self.scheduler.deinit();
        self.diagnostics.deinit();
        if (self.lsp_server) |*server| {
            server.deinit();
            self.lsp_server = null;
        }
        self.lsp.deinit();
        self.syntax.deinit();
        self.diagnostics_list.deinit();
        self.picker.deinit();
        self.plugins_list.deinit();
        self.clearPluginDetailRows();
        self.plugin_detail_rows.deinit();
        self.panes.deinit();
        self.plugin_details_pane_id = null;
        if (self.plugin_detail_context) |text| self.allocator.free(text);
        self.plugin_detail_context = null;
        self.plugin_activity.deinit();
        self.search.deinit();
        self.picker_source_key = null;
        self.picker_source_spec = null;
        self.plugins_pane_id = null;
        if (self.picker_job_id) |job_id| {
            _ = self.scheduler.cancel(job_id);
            self.picker_job_id = null;
        }
        if (self.picker_source_pattern) |pattern| self.allocator.free(pattern);
        if (self.picker_source_pathspec) |pathspec| self.allocator.free(pathspec);
        self.workspace.deinit();
        if (self.search_highlight) |needle| self.allocator.free(needle);
        if (self.search_preview_highlight) |needle| self.allocator.free(needle);
        if (self.last_interactive_command) |cmd| self.allocator.free(cmd);
        if (self.clipboard_contents) |text| self.allocator.free(text);
        if (self.visual_block_insert) |*block| {
            block.text.deinit();
            self.visual_block_insert = null;
        }
        for (self.macros, 0..) |item, idx| {
            if (item) |value| self.allocator.free(value);
            self.macros[idx] = null;
        }
        self.jump_history.deinit();
        self.change_history.deinit();
        self.clearQuickfix();
        self.quickfix_list.deinit();
        self.registers.deinit();
        self.config.deinit();
        self.allocator.free(self.config_path);
        if (self.file_to_open) |f| self.allocator.free(f);
    }

    fn startConfiguredLsp(self: *App) void {
        if (!self.config.lsp.enabled) return;
        if (self.config.lsp.command.len == 0) {
            self.setStatus("lsp not configured") catch {};
            return;
        }
        if (self.lsp_server != null) return;
        const argv_len = 1 + self.config.lsp.args.items.len;
        const argv = self.allocator.alloc([]const u8, argv_len) catch {
            self.setStatus("lsp unavailable") catch {};
            return;
        };
        defer self.allocator.free(argv);
        argv[0] = self.config.lsp.command;
        for (self.config.lsp.args.items, 0..) |arg, idx| {
            argv[idx + 1] = arg;
        }
        var server = lsp_mod.ProcessServer.start(self.allocator, argv) catch |err| {
            self.setStatus(lspSpawnErrorMessage(err)) catch {};
            return;
        };
        server.startReaderThread() catch |err| {
            server.deinit();
            self.setStatus(lspReaderErrorMessage(err)) catch {};
            return;
        };
        self.lsp.attachTransport(server.transportHandle());
        const initialize_payload = self.buildInitializePayload() catch {
            server.deinit();
            self.lsp.detachTransport();
            return;
        };
        defer self.allocator.free(initialize_payload);
        _ = self.lsp.initialize(initialize_payload) catch |err| {
            self.setStatus(lspInitializeErrorMessage(err)) catch {};
            self.lsp.detachTransport();
            server.deinit();
            return;
        };
        self.lsp_server = server;
    }

    fn serviceLsp(self: *App) void {
        if (self.lsp_server) |*server| {
            while (server.pollMessage()) |raw_message| {
                var message = raw_message;
                defer message.deinit(self.allocator);
                self.lsp.handleMessage(message) catch |err| {
                    if (err == error.InvalidJsonRpcMessage) {
                        self.setStatus("lsp malformed JSON-RPC") catch {};
                    } else {
                        self.setStatus("lsp message error") catch {};
                    }
                };
            }
            if (server.takeMalformedJsonRpc()) {
                self.setStatus("lsp malformed JSON-RPC") catch {};
            }
        }
    }

    fn shutdownConfiguredLsp(self: *App) void {
        if (self.lsp_server) |*server| {
            defer self.lsp.detachTransport();
            self.serviceLsp();
            if (self.lsp.initialized) {
                _ = self.lsp.shutdown() catch {};
                var attempts: usize = 0;
                while (!self.lsp.shutdown_acknowledged and attempts < 100) : (attempts += 1) {
                    self.serviceLsp();
                    if (!self.lsp.shutdown_acknowledged) std.Thread.sleep(10 * std.time.ns_per_ms);
                }
                self.serviceLsp();
            }
            self.lsp.clear();
            server.deinit();
            self.lsp_server = null;
        }
    }

    fn buildInitializePayload(self: *App) ![]u8 {
        return try std.fmt.allocPrint(self.allocator,
            "{{\"processId\":null,\"rootUri\":\"file://{s}\",\"workspaceFolders\":[{{\"uri\":\"file://{s}\",\"name\":\"Beam\"}}],\"clientInfo\":{{\"name\":\"Beam\",\"version\":\"1\"}},\"capabilities\":{{\"workspace\":{{\"workspaceFolders\":true,\"configuration\":true,\"applyEdit\":true}},\"textDocument\":{{\"publishDiagnostics\":{{\"relatedInformation\":true}},\"synchronization\":{{\"dynamicRegistration\":false,\"willSave\":false,\"willSaveWaitUntil\":false,\"didSave\":true}}}},\"window\":{{\"workDoneProgress\":true}},\"general\":{{\"positionEncodings\":[\"utf-8\"]}}}}}}",
            .{ self.workspace.root_path, self.workspace.root_path },
        );
    }

    fn lspSpawnErrorMessage(err: anyerror) []const u8 {
        return switch (err) {
            error.FileNotFound => "lsp executable not found",
            error.AccessDenied => "lsp spawn denied",
            error.PermissionDenied => "lsp spawn denied",
            else => "lsp spawn failed",
        };
    }

    fn lspReaderErrorMessage(_: anyerror) []const u8 {
        return "lsp reader failed";
    }

    fn lspInitializeErrorMessage(_: anyerror) []const u8 {
        return "lsp initialize failed";
    }

    pub fn run(self: *App) !void {
        try self.initTerminal();
        defer self.exitTerminal() catch {};

        try self.loadInitialBuffers();
        self.serviceLsp();
        try self.setStatus("ready");
        try self.eventLoop();
    }

    fn loadInitialBuffers(self: *App) !void {
        if (self.file_to_open == null and self.workspace.session.open_buffers.items.len > 0) {
            for (self.workspace.session.open_buffers.items) |path| {
                try self.openPath(path);
            }
            self.active_index = @min(self.workspace.session.active_index, self.buffers.items.len - 1);
            self.split_index = if (self.workspace.session.split_index) |idx| if (idx < self.buffers.items.len) idx else null else null;
            self.split_focus = if (self.workspace.session.split_focus_right) .right else .left;
            self.syncActiveSyntax();
            return;
        }
        if (self.file_to_open) |path| {
            try self.buffers.append(buffer_mod.Buffer.loadFile(self.allocator, path) catch |err| switch (err) {
                error.FileNotFound => blk: {
                    var buf = try buffer_mod.Buffer.initEmpty(self.allocator);
                    try buf.replacePath(path);
                    break :blk buf;
                },
                else => return err,
            });
            try self.workspace.recordOpenBuffer(path);
            try self.lsp.didOpenPath(path);
            self.syncActiveSyntax();
        } else {
            try self.buffers.append(try buffer_mod.Buffer.initEmpty(self.allocator));
            self.syncActiveSyntax();
        }
        self.emitBuiltinEvent("buffer_open", "{}");
    }

    fn initTerminal(self: *App) !void {
        const stdin_file = std.fs.File.stdin();
        self.raw_mode = try terminal_mod.RawMode.enable(stdin_file);
        const stdout_file = std.fs.File.stdout();
        var out_buf: [4096]u8 = undefined;
        var out_writer = stdout_file.writer(&out_buf);
        const out = &out_writer.interface;
        try terminal_mod.enterAltScreen(out);
        try terminal_mod.showCursor(out);
        try terminal_mod.setCursorShape(out, true);
        try out.flush();
    }

    fn exitTerminal(self: *App) !void {
        const stdout_file = std.fs.File.stdout();
        var out_buf: [4096]u8 = undefined;
        var out_writer = stdout_file.writer(&out_buf);
        const out = &out_writer.interface;
        try terminal_mod.showCursor(out);
        try terminal_mod.setCursorShape(out, true);
        try terminal_mod.leaveAltScreen(out);
        try out.flush();
        if (self.raw_mode) |*mode| mode.disable();
        self.raw_mode = null;
    }

    fn eventLoop(self: *App) !void {
        const stdin_file = std.fs.File.stdin();
        var input_buf: [1]u8 = undefined;
        while (!self.should_quit) {
            self.serviceLsp();
            try self.render();
            const n = stdin_file.read(&input_buf) catch break;
            if (n == 0) break;
            try self.handleByte(input_buf[0], stdin_file);
            self.syncActiveSyntax();
            self.serviceLsp();
        }
    }

    fn handleByte(self: *App, byte: u8, stdin_file: std.fs.File) !void {
        _ = stdin_file;
        const start_buffer = self.activeBuffer();
        const start_cursor = start_buffer.cursor;
        defer self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        switch (self.mode) {
            .insert => switch (byte) {
                0x1b => {
                    if (self.visual_block_insert) |*block| {
                        try self.commitVisualBlockInsert(block);
                    }
                    self.mode = .normal;
                },
                0x12 => {
                    self.insert_register_prefix = true;
                },
                0x17 => {
                    if (self.visual_block_insert) |*block| {
                        while (block.text.items.len > 0 and std.ascii.isWhitespace(block.text.items[block.text.items.len - 1])) {
                            _ = block.text.pop();
                        }
                        while (block.text.items.len > 0 and !std.ascii.isWhitespace(block.text.items[block.text.items.len - 1])) {
                            _ = block.text.pop();
                        }
                    } else {
                        try self.deleteInsertPreviousWord();
                    }
                },
                0x7f => {
                    if (self.visual_block_insert) |*block| {
                        if (block.text.items.len > 0) _ = block.text.pop();
                    } else {
                        try self.activeBuffer().backspace();
                    }
                },
                '\r', '\n' => {
                    if (self.visual_block_insert) |*block| {
                        try block.text.append('\n');
                    } else {
                        try self.activeBuffer().insertByte('\n');
                    }
                },
                else => try self.handleInsertByte(byte),
            },
            .replace => switch (byte) {
                0x1b, 0x03 => self.mode = .normal,
                0x12 => self.insert_register_prefix = true,
                0x17 => try self.deleteInsertPreviousWord(),
                0x7f => try self.activeBuffer().backspace(),
                '\r', '\n' => try self.activeBuffer().insertByte('\n'),
                else => try self.handleReplaceByte(byte),
            },
            .command => switch (byte) {
                0x1b => self.clearPrompt(.command),
                0x7f => {
                    if (self.command_buffer.items.len > 0) _ = self.command_buffer.pop();
                },
                '\r', '\n' => try self.executeCommand(),
                else => try self.command_buffer.append(byte),
            },
            .search => switch (byte) {
                0x1b => {
                    self.clearPrompt(.search);
                    self.clearSearchPreview();
                },
                0x7f => {
                    if (self.search_buffer.items.len > 0) _ = self.search_buffer.pop();
                    try self.updateSearchPreview(self.search_buffer.items);
                },
                '\r', '\n' => try self.executeSearch(),
                else => {
                    try self.search_buffer.append(byte);
                    try self.updateSearchPreview(self.search_buffer.items);
                },
            },
            .visual => try self.handleVisualByte(byte),
            .select => try self.handleVisualByte(byte),
            .normal => try self.handleNormalByte(byte),
        }
    }

    fn handleInsertByte(self: *App, byte: u8) !void {
        const start_buffer = self.activeBuffer();
        const start_cursor = start_buffer.cursor;
        defer self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        if (self.visual_block_insert) |*block| {
            if (self.insert_register_prefix) {
                self.insert_register_prefix = false;
                const value = self.registers.get(byte) orelse "";
                try block.text.appendSlice(value);
                return;
            }
            try block.text.append(byte);
            return;
        }
        if (self.insert_register_prefix) {
            self.insert_register_prefix = false;
            const value = self.registers.get(byte) orelse "";
            try self.activeBuffer().insertTextAtCursor(value);
            return;
        }
        try self.activeBuffer().insertByte(byte);
    }

    fn handleReplaceByte(self: *App, byte: u8) !void {
        const start_buffer = self.activeBuffer();
        const start_cursor = start_buffer.cursor;
        defer self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        if (self.visual_block_insert) |*block| {
            if (self.insert_register_prefix) {
                self.insert_register_prefix = false;
                const value = self.registers.get(byte) orelse "";
                try block.text.appendSlice(value);
                return;
            }
            try block.text.append(byte);
            return;
        }

        if (self.insert_register_prefix) {
            self.insert_register_prefix = false;
            const value = self.registers.get(byte) orelse "";
            try self.activeBuffer().insertTextAtCursor(value);
            return;
        }

        const buf = self.activeBuffer();
        const line = buf.lines.items[buf.cursor.row];
        if (buf.cursor.col < line.len) {
            try buf.replaceCurrentCharacter(byte);
            buf.moveRight();
        } else {
            try buf.insertByte(byte);
        }
    }

    fn clearPrompt(self: *App, mode: Mode) void {
        if (mode == .command) self.command_buffer.clearRetainingCapacity();
        if (mode == .search) self.search_buffer.clearRetainingCapacity();
        self.mode = .normal;
    }

    fn clearSearchPreview(self: *App) void {
        if (self.search_preview_highlight) |needle| self.allocator.free(needle);
        self.search_preview_highlight = null;
    }

    fn updateSearchHighlight(self: *App, slot: *?[]u8, needle: []const u8) !void {
        if (slot.*) |existing| {
            self.allocator.free(existing);
            slot.* = null;
        }
        if (needle.len == 0) return;
        slot.* = try self.allocator.dupe(u8, needle);
    }

    fn updateSearchPreview(self: *App, needle: []const u8) !void {
        try self.updateSearchHighlight(&self.search_preview_highlight, needle);
    }

    fn executeCommand(self: *App) !void {
        const raw = std.mem.trim(u8, self.command_buffer.items, " \t\r\n");
        self.mode = .normal;
        if (raw.len == 0) return;

        const command = if (raw[0] == ':') raw[1..] else raw;
        const command_no_range = stripVisualRangePrefix(command);
        const has_visual_range = command_no_range.len != command.len;
        if (has_visual_range and command_no_range.len > 0 and (command_no_range[0] == '!' or command_no_range[0] == '=')) {
            const filter = std.mem.trim(u8, command_no_range[1..], " \t");
            if (filter.len == 0) {
                try self.setStatus("visual filter requires a command");
                return;
            }
            try self.runVisualFilter(filter);
            return;
        }
        const arg_split = std.mem.indexOfScalar(u8, command_no_range, ' ');
        const head = if (arg_split) |idx| command_no_range[0..idx] else command_no_range;
        const tail = if (arg_split) |idx| std.mem.trim(u8, command_no_range[idx + 1 ..], " \t") else "";

        if (try self.tryExecuteSubstitute(command_no_range, has_visual_range)) {
            return;
        }

        if (matchesCommand(head, &.{ "h", "help" }, self.config.keymap.help)) {
            if (tail.len == 0) {
                try self.showReferenceHelp();
            } else {
                try self.helpForKeyword(tail);
            }
            return;
        }
        if (matchesCommand(head, &.{ "sav", "saveas" }, self.config.keymap.save_as)) {
            _ = self.commandSaveAs(if (tail.len > 0) tail else null);
            return;
        }
        if (matchesCommand(head, &.{ "clo", "close" }, self.config.keymap.close)) {
            try self.closeCurrentPane();
            return;
        }
        if (matchesCommand(head, &.{ "ter", "terminal" }, self.config.keymap.terminal)) {
            try self.performNormalAction(.terminal, 1);
            return;
        }
        if (matchesCommand(head, &.{ "reg", "registers" }, self.config.keymap.registers)) {
            try self.showRegisters();
            return;
        }
        if (std.mem.eql(u8, head, "plugins")) {
            try self.showPlugins();
            return;
        }
        if (matchesCommand(head, &.{ "ma", "marks" }, "marks")) {
            try self.showMarks();
            return;
        }
        if (std.mem.eql(u8, head, "delmarks!") or std.mem.eql(u8, head, "delmarks")) {
            for (0..self.marks.len) |idx| {
                self.marks[idx] = null;
            }
            try self.setStatus("marks deleted");
            return;
        }
        if (matchesCommand(head, &.{ "ju", "jumps" }, "jumps")) {
            try self.showJumps();
            return;
        }
        if (matchesCommand(head, &.{ "vimgrep", "vimgrep" }, "vimgrep")) {
            try self.runQuickfixSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"grep"}, "grep")) {
            try self.runProjectSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"pickgrep"}, "pickgrep")) {
            try self.runPickerSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"files"}, "files")) {
            try self.runFilePickerSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"symbols"}, "symbols")) {
            try self.runSymbolPickerSearch(tail);
            return;
        }
        if (matchesCommand(head, &.{"lsp"}, "lsp")) {
            try self.runLspCommand(tail);
            return;
        }
        if (matchesCommand(head, &.{"diagnostics"}, "diagnostics")) {
            try self.showDiagnosticsPane();
            return;
        }
        if (matchesCommand(head, &.{"dnext"}, "dnext")) {
            try self.diagnosticsNext();
            return;
        }
        if (matchesCommand(head, &.{"dprev"}, "dprev")) {
            try self.diagnosticsPrev();
            return;
        }
        if (matchesCommand(head, &.{"dopen"}, "dopen")) {
            try self.openDiagnosticSelection();
            return;
        }
        if (matchesCommand(head, &.{"pnext"}, "pnext")) {
            try self.navigatePluginOrPicker(1);
            return;
        }
        if (matchesCommand(head, &.{"pprev"}, "pprev")) {
            try self.navigatePluginOrPicker(-1);
            return;
        }
        if (matchesCommand(head, &.{"popen"}, "popen")) {
            try self.openSelection();
            return;
        }
        if (matchesCommand(head, &.{"sort"}, "sort")) {
            try self.sortCurrentBuffer(tail);
            return;
        }
        if (matchesCommand(head, &.{ "cn", "cnext" }, "cnext")) {
            try self.quickfixNext();
            return;
        }
        if (matchesCommand(head, &.{ "cp", "cprevious" }, "cprevious")) {
            try self.quickfixPrev();
            return;
        }
        if (matchesCommand(head, &.{ "cope", "copen" }, "cope")) {
            try self.showQuickfix();
            return;
        }
        if (matchesCommand(head, &.{ "ccl", "cclose" }, "cclose")) {
            self.clearQuickfix();
            try self.setStatus("quickfix cleared");
            return;
        }
        if (matchesCommand(head, &.{"diffthis"}, "diffthis")) {
            try self.enableDiffMode();
            return;
        }
        if (matchesCommand(head, &.{ "diffoff", "diffo" }, "diffoff")) {
            self.disableDiffMode();
            try self.setStatus("diff off");
            return;
        }
        if (matchesCommand(head, &.{ "diffupdate", "diffu" }, "diffupdate")) {
            try self.updateDiffSummary();
            return;
        }
        if (matchesCommand(head, &.{"diffget"}, "diffget")) {
            try self.diffGet();
            return;
        }
        if (matchesCommand(head, &.{"diffput"}, "diffput")) {
            try self.diffPut();
            return;
        }
        if (matchesCommand(head, &.{"changes"}, "changes")) {
            try self.showChanges();
            return;
        }
        if (matchesCommand(head, &.{"open"}, self.config.keymap.open)) {
            if (tail.len == 0) return self.setStatus("open requires a path");
            try self.openPath(tail);
            return;
        }
        if (matchesCommand(head, &.{ "e", "edit" }, "edit")) {
            if (tail.len == 0) return self.setStatus("edit requires a path");
            try self.openPath(tail);
            return;
        }
        if (matchesCommand(head, &.{ "bn", "bnext" }, "bnext")) {
            try self.switchFocusedBuffer(true, 1);
            return;
        }
        if (matchesCommand(head, &.{ "bp", "bprevious" }, "bprevious")) {
            try self.switchFocusedBuffer(false, 1);
            return;
        }
        if (matchesCommand(head, &.{ "bd", "bdelete" }, "bdelete")) {
            try self.closeCurrentPane();
            return;
        }
        if (matchesCommand(head, &.{ "buffer", "b" }, "buffer")) {
            if (tail.len == 0) {
                try self.setStatus("buffer requires an index or path");
            } else {
                try self.selectBufferByArgument(tail);
            }
            return;
        }
        if (matchesCommand(head, &.{ "buffers", "ls" }, "buffers")) {
            try self.showBuffers();
            return;
        }
        if (matchesCommand(head, &.{"tabnew"}, "tabnew")) {
            try self.openNewTab(if (tail.len > 0) tail else null);
            return;
        }
        if (matchesCommand(head, &.{ "tabc", "tabclose" }, "tabclose")) {
            try self.tabCloseCurrent();
            return;
        }
        if (matchesCommand(head, &.{ "tabo", "tabonly" }, "tabonly")) {
            try self.tabOnlyCurrent();
            return;
        }
        if (matchesCommand(head, &.{"tabmove"}, "tabmove")) {
            if (tail.len == 0) {
                try self.setStatus("tabmove requires a number");
            } else {
                try self.tabMoveCurrent(tail);
            }
            return;
        }
        if (matchesCommand(head, &.{"split"}, self.config.keymap.split)) {
            try self.openSplitOrClone(tail);
            return;
        }
        if (matchesCommand(head, &.{ "sp", "split" }, "split")) {
            try self.openSplitOrClone(tail);
            return;
        }
        if (matchesCommand(head, &.{ "vs", "vsplit" }, "vsplit")) {
            try self.openSplitOrClone(tail);
            return;
        }
        if (matchesCommand(head, &.{"builtin"}, "builtin") or matchesCommand(head, &.{"plugin"}, "plugin")) {
            if (tail.len == 0) return self.setStatus("builtin requires a command name");
            if (!try self.invokeBuiltinCommand(tail, &.{})) {
                try self.setStatus("unknown builtin command");
            }
            return;
        }
        if (matchesCommand(head, &.{"reload-config"}, self.config.keymap.reload)) {
            try self.reloadConfig();
            return;
        }
        if (matchesCommand(head, &.{"refresh-sources"}, "refresh-sources") or matchesCommand(head, &.{"refresh"}, "refresh")) {
            try self.refreshDerivedSources();
            return;
        }
        if (matchesCommand(head, &.{"w"}, self.config.keymap.save)) {
            _ = self.saveActiveBuffer();
            return;
        }
        if (matchesCommand(head, &.{ "wq", "x" }, "wq")) {
            if (self.saveActiveBuffer()) self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"wqa"}, "wqa")) {
            for (self.buffers.items) |*buf| {
                if (buf.dirty) try buf.save();
            }
            self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"q!"}, self.config.keymap.force_quit)) {
            self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{ "q", "quit" }, self.config.keymap.quit)) {
            try self.requestQuit(false);
            return;
        }
        if (std.mem.eql(u8, head, "!")) {
            try self.runBangCommand(tail);
            return;
        }
        if (matchesCommand(head, &.{"ZZ"}, "ZZ")) {
            if (self.saveActiveBuffer()) self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"ZQ"}, "ZQ")) {
            self.should_quit = true;
            return;
        }
        if (matchesCommand(head, &.{"help"}, self.config.keymap.help)) {
            try self.showReferenceHelp();
            return;
        }

        if (std.mem.startsWith(u8, command, "saveas ")) {
            _ = self.commandSaveAs(std.mem.trim(u8, command[7..], " \t"));
            return;
        }

        try self.setStatus("unknown command");
    }

    fn handleNormalByte(self: *App, byte: u8) anyerror!void {
        const start_buffer = self.activeBuffer();
        const start_cursor = start_buffer.cursor;
        defer self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        if (self.close_confirm) |target| {
            switch (byte) {
                'y', 'Y' => {
                    self.close_confirm = null;
                    try self.executeCloseConfirm(target);
                },
                'n', 'N', 0x1b, 0x03 => {
                    self.close_confirm = null;
                    try self.setStatus("close cancelled");
                },
                else => {
                    self.close_confirm = null;
                    try self.setStatus("close cancelled");
                },
            }
            return;
        }
        if (self.pending_prefix != .none) {
            try self.handlePendingPrefix(byte);
            return;
        }

        if (byte == 0x1b or byte == 0x03) {
            self.resetNormalInput();
            self.visual_mode = .none;
            self.visual_anchor = null;
            return;
        }

        if (self.normal_sequence.items.len > 0) {
            try self.normal_sequence.append(byte);
            try self.resolveNormalSequence();
            return;
        }

        if (self.macro_recording != null and !self.macro_playing and byte != 'q' and byte != '@') {
            try self.appendMacroByte(byte);
        }

        switch (byte) {
            ':' => {
                self.resetNormalInput();
                self.mode = .command;
                self.command_buffer.clearRetainingCapacity();
                return;
            },
            '/' => {
                self.resetNormalInput();
                self.mode = .search;
                self.search_forward = true;
                self.search_buffer.clearRetainingCapacity();
                return;
            },
            '?' => {
                self.resetNormalInput();
                self.mode = .search;
                self.search_forward = false;
                self.search_buffer.clearRetainingCapacity();
                return;
            },
            '"' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .register;
                return;
            },
            'q' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .macro_record;
                return;
            },
            '@' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .macro_run;
                return;
            },
            'm' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .mark_set;
                return;
            },
            '\'' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .mark_jump;
                return;
            },
            '`' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .mark_jump_exact;
                return;
            },
            'f' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_forward;
                return;
            },
            'F' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_backward;
                return;
            },
            't' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_forward_before;
                return;
            },
            'T' => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .find_backward_before;
                return;
            },
            0x12 => {
                try self.performNormalAction(.redo, 1);
                return;
            },
            '\t' => {
                try self.performNormalAction(.jump_history_forward, 1);
                return;
            },
            0x15 => {
                try self.performNormalAction(.scroll_up, 1);
                return;
            },
            0x04 => {
                try self.performNormalAction(.scroll_down, 1);
                return;
            },
            0x0f => {
                try self.performNormalAction(.jump_history_backward, 1);
                return;
            },
            0x1e => {
                try self.performNormalAction(.switch_previous_buffer, 1);
                return;
            },
            '0' => {
                if (self.normal_sequence.items.len == 0) {
                    if (self.count_active) {
                        self.count_prefix *= 10;
                        return;
                    }
                    try self.performNormalAction(.move_line_start, 1);
                    return;
                }
            },
            '1'...'9' => {
                if (self.normal_sequence.items.len == 0) {
                    self.count_active = true;
                    self.count_prefix = self.count_prefix * 10 + @as(usize, byte - '0');
                    return;
                }
            },
            else => {},
        }

        try self.normal_sequence.append(byte);
        try self.resolveNormalSequence();
    }

    fn handleVisualByte(self: *App, byte: u8) !void {
        const start_buffer = self.activeBuffer();
        const start_cursor = start_buffer.cursor;
        defer self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        if (self.visual_pending) |pending| {
            self.visual_pending = null;
            switch (pending) {
                .ctrl_backslash => switch (byte) {
                    'n', 'g' => {
                        self.exitVisual();
                        return;
                    },
                    else => return,
                },
                .textobject_outer => {
                    try self.selectVisualTextObject(byte, false);
                    return;
                },
                .textobject_inner => {
                    try self.selectVisualTextObject(byte, true);
                    return;
                },
                .g_prefix => switch (byte) {
                    'v' => {
                        try self.restoreLastVisual();
                        return;
                    },
                    'g' => {
                        self.activeBuffer().moveToDocumentStart();
                        return;
                    },
                    '0' => {
                        self.activeBuffer().moveLineStart();
                        return;
                    },
                    '^' => {
                        self.activeBuffer().moveToFirstNonBlank();
                        return;
                    },
                    '$' => {
                        self.activeBuffer().moveLineEnd();
                        return;
                    },
                    '_' => {
                        self.activeBuffer().moveToLastNonBlank();
                        return;
                    },
                    'J' => {
                        try self.visualJoin(false);
                        return;
                    },
                    'q' => {
                        try self.visualFormat();
                        return;
                    },
                    '\x01' => {
                        try self.visualAdjustNumber(true, 1);
                        return;
                    },
                    '\x18' => {
                        try self.visualAdjustNumber(false, 1);
                        return;
                    },
                    else => {
                        try self.setStatus("visual command not implemented");
                        return;
                    },
                },
                .replace_char => {
                    if (byte == 0x1b or byte == 0x03) return;
                    try self.visualReplaceChar(byte);
                    return;
                },
            }
        }

        switch (byte) {
            0x1b, 0x03 => self.exitVisual(),
            0x1c => self.visual_pending = .ctrl_backslash,
            0x07 => {
                if (self.mode == .select) {
                    self.mode = .visual;
                    self.visual_select_mode = false;
                } else {
                    self.mode = .select;
                    self.visual_select_mode = true;
                }
                self.visual_select_restore = false;
                try self.setStatus(if (self.mode == .select) "select mode" else "visual mode");
            },
            0x0f => {
                if (self.mode == .select) {
                    self.mode = .visual;
                    self.visual_select_mode = false;
                    self.visual_select_restore = true;
                    try self.setStatus("visual mode");
                    return;
                }
            },
            0x08, 0x7f => {
                try self.visualDelete();
                self.exitVisual();
            },
            0x16 => {
                if (self.visual_mode == .block) {
                    self.exitVisual();
                } else {
                    self.visual_mode = .block;
                    if (self.mode == .visual) self.visual_select_mode = false;
                }
            },
            'v' => {
                if (self.visual_mode == .character and self.mode == .visual) {
                    self.exitVisual();
                } else {
                    self.visual_mode = .character;
                    if (self.mode == .visual) self.visual_select_mode = false;
                }
            },
            'V' => {
                if (self.visual_mode == .line and self.mode == .visual) {
                    self.exitVisual();
                } else {
                    self.visual_mode = .line;
                    if (self.mode == .visual) self.visual_select_mode = false;
                }
            },
            'g' => self.visual_pending = .g_prefix,
            'a' => self.visual_pending = .textobject_outer,
            'i' => self.visual_pending = .textobject_inner,
            'h' => self.activeBuffer().moveLeft(),
            'j' => self.activeBuffer().moveDown(),
            'k' => self.activeBuffer().moveUp(),
            'l' => self.activeBuffer().moveRight(),
            '0' => self.activeBuffer().moveLineStart(),
            '^' => self.activeBuffer().moveToFirstNonBlank(),
            '$' => self.activeBuffer().moveLineEnd(),
            'w' => self.activeBuffer().moveWordForward(false),
            'W' => self.activeBuffer().moveWordForward(true),
            'b' => self.activeBuffer().moveWordBackward(false),
            'B' => self.activeBuffer().moveWordBackward(true),
            'e' => self.activeBuffer().moveWordEnd(false),
            'E' => self.activeBuffer().moveWordEnd(true),
            'G' => self.activeBuffer().moveToDocumentEnd(),
            'H' => self.activeBuffer().moveToDocumentStart(),
            'M' => {
                const middle = if (self.activeBuffer().lineCount() > 0) (self.activeBuffer().lineCount() - 1) / 2 else 0;
                self.activeBuffer().moveToLine(middle);
            },
            'L' => self.activeBuffer().moveToDocumentEnd(),
            'o', 'O' => self.swapVisualCorners(),
            'y' => {
                try self.visualYank();
                self.exitVisual();
            },
            'Y' => {
                try self.visualYank();
                self.exitVisual();
            },
            'p' => try self.visualPaste(),
            'P' => try self.visualPaste(),
            'd', 'D', 'x', 'X' => {
                try self.visualDelete();
                self.exitVisual();
            },
            'c', 'C', 's', 'S', 'R' => try self.visualChange(),
            'u' => try self.visualCase(.lower),
            'U' => try self.visualCase(.upper),
            '~' => try self.visualCase(.toggle),
            '>' => try self.visualIndent(true),
            '<' => try self.visualIndent(false),
            'J' => try self.visualJoin(true),
            'A' => try self.visualBlockInsert(true),
            'I' => try self.visualBlockInsert(false),
            'K' => try self.visualVisualHelp(),
            0x1d => try self.visualJumpTag(),
            'r' => self.visual_pending = .replace_char,
            '!' => {
                self.mode = .command;
                self.command_buffer.clearRetainingCapacity();
                try self.command_buffer.appendSlice("'<,'>!");
            },
            '=' => try self.visualEqualPrg(),
            ':' => {
                self.mode = .command;
                self.command_buffer.clearRetainingCapacity();
                try self.command_buffer.appendSlice("'<,'>");
            },
            0x01 => try self.visualAdjustNumber(true, 1),
            0x18 => try self.visualAdjustNumber(false, 1),
            else => {
                if (self.mode == .select and byte >= 0x20 and byte != 0x7f) {
                    try self.selectReplaceByte(byte);
                } else {
                    try self.setStatus("visual command not implemented");
                }
            },
        }
        if (self.visual_select_restore and self.mode == .visual and self.visual_pending == null) {
            self.visual_select_restore = false;
            self.mode = .select;
            self.visual_select_mode = true;
            try self.setStatus("select mode");
        }
    }

    fn handlePendingPrefix(self: *App, byte: u8) anyerror!void {
        switch (self.pending_prefix) {
            .register => {
                self.pending_prefix = .none;
                self.pending_register = byte;
                const msg = try std.fmt.allocPrint(self.allocator, "register \"{c}", .{byte});
                defer self.allocator.free(msg);
                try self.setStatus(msg);
            },
            .replace_char => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.activeBuffer().replaceCurrentCharacter(byte);
            },
            .find_forward, .find_forward_before, .find_backward, .find_backward_before => {
                const count = self.consumeCount();
                const forward = self.pending_prefix == .find_forward or self.pending_prefix == .find_forward_before;
                const before = self.pending_prefix == .find_forward_before or self.pending_prefix == .find_backward_before;
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                self.last_find = .{ .char = byte, .forward = forward, .before = before };
                try self.performFind(byte, forward, before, count);
            },
            .macro_record => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                if (self.macro_recording) |current| {
                    if (current == byte) {
                        self.macro_recording = null;
                        try self.setStatus("macro stopped");
                        return;
                    }
                }
                try self.startMacroRecording(byte);
            },
            .macro_run => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.runMacro(byte);
            },
            .mark_set => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.setMark(byte);
            },
            .mark_jump => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.jumpMark(byte, false);
            },
            .mark_jump_exact => {
                self.pending_prefix = .none;
                if (byte == 0x1b or byte == 0x03) return;
                try self.jumpMark(byte, true);
            },
            else => unreachable,
        }
    }

    fn resolveNormalSequence(self: *App) !void {
        const sequence = self.normal_sequence.items;
        if (sequence.len == 0) return;

        if (normalActionFor(sequence, self.config.keymap.leader, self.config.keymap.leader_bindings.items)) |action| {
            if (normalActionHasPrefix(sequence, self.config.keymap.leader, self.config.keymap.leader_bindings.items)) return;
            const count = self.consumeCount();
            self.normal_sequence.clearRetainingCapacity();
            try self.performNormalAction(action, count);
            return;
        }

        if (try self.executeCompoundEditIfReady(sequence)) return;

        if (self.compoundEditHasPrefix(sequence)) return;

        if (normalActionHasPrefix(sequence, self.config.keymap.leader, self.config.keymap.leader_bindings.items)) {
            return;
        }

        self.normal_sequence.clearRetainingCapacity();
        self.count_active = false;
        self.count_prefix = 0;
        try self.setStatus("unknown command");
    }

    fn resetNormalInput(self: *App) void {
        self.normal_sequence.clearRetainingCapacity();
        self.pending_prefix = .none;
        self.pending_register = null;
        self.count_prefix = 0;
        self.count_active = false;
    }

    fn consumeCount(self: *App) usize {
        const count = if (self.count_active and self.count_prefix > 0) self.count_prefix else 1;
        self.count_prefix = 0;
        self.count_active = false;
        return count;
    }

    fn performNormalAction(self: *App, action: NormalAction, count: usize) !void {
        const buf = self.activeBuffer();
        const start_buffer = buf;
        const start_cursor = self.activeBuffer().cursor;
        var text_changed = false;
        var record_jump = true;
        switch (action) {
            .move_left => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveLeft();
            },
            .move_down => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveDown();
            },
            .move_up => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveUp();
            },
            .move_right => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveRight();
            },
            .move_line_start => buf.moveLineStart(),
            .move_line_nonblank => buf.moveToFirstNonBlank(),
            .move_line_last_nonblank => buf.moveToLastNonBlank(),
            .move_line_end => buf.moveLineEnd(),
            .move_doc_start => {
                if (count > 1) {
                    buf.moveToLine(@min(count - 1, buf.lineCount() - 1));
                } else {
                    buf.moveToDocumentStart();
                }
                self.setViewport(.top);
            },
            .move_doc_middle => {
                const middle = if (buf.lineCount() > 0) (buf.lineCount() - 1) / 2 else 0;
                buf.moveToLine(middle);
            },
            .move_doc_end => {
                if (count > 1) {
                    buf.moveToLine(@min(count - 1, buf.lineCount() - 1));
                } else {
                    buf.moveToDocumentEnd();
                }
                self.setViewport(.bottom);
            },
            .tab_next => try self.switchFocusedBuffer(true, count),
            .tab_prev => try self.switchFocusedBuffer(false, count),
            .window_split_horizontal, .window_split_vertical => try self.openSplitFromCurrentBuffer(),
            .window_new => try self.openNewWindow(),
            .window_switch => self.toggleSplitFocus(),
            .window_close => try self.closeCurrentPane(),
            .window_exchange => try self.exchangeFocusedBuffers(),
            .window_resize_increase, .window_resize_wider => try self.resizeSplitBy(10),
            .window_resize_decrease, .window_resize_narrower => try self.resizeSplitBy(-10),
            .window_maximize_width, .window_maximize_height => try self.maximizeSplit(),
            .window_to_tab => try self.splitToTab(),
            .window_left, .window_up => self.focusWindow(.left),
            .window_right, .window_down => self.focusWindow(.right),
            .window_far_left => self.focusWindow(.left),
            .window_far_right => self.focusWindow(.right),
            .window_far_bottom => self.focusWindow(.right),
            .window_far_top => self.focusWindow(.left),
            .window_equalize => try self.equalizeWindows(),
            .fold_create => try self.createFoldAtCursor(),
            .fold_delete => self.deleteFoldAtCursor(),
            .fold_toggle => self.toggleFoldAtCursor(),
            .fold_open => self.openFoldAtCursor(),
            .fold_close => self.closeFoldAtCursor(),
            .fold_open_all => self.activeBuffer().openAllFolds(),
            .fold_close_all => self.activeBuffer().closeAllFolds(),
            .fold_toggle_enabled => self.activeBuffer().toggleFolding(),
            .fold_delete_all => {
                self.activeBuffer().clearFolds();
                try self.setStatus("all folds deleted");
            },
            .diff_get => try self.diffGet(),
            .diff_put => try self.diffPut(),
            .diff_this => try self.enableDiffMode(),
            .diff_off => self.disableDiffMode(),
            .diff_update => try self.updateDiffSummary(),
            .diff_next_change => try self.jumpChangeHistory(true),
            .diff_prev_change => try self.jumpChangeHistory(false),
            .move_word_forward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordForward(false);
            },
            .move_word_forward_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordForward(true);
            },
            .move_word_backward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordBackward(false);
            },
            .move_word_backward_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordBackward(true);
            },
            .move_word_end => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEnd(false);
            },
            .move_word_end_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEnd(true);
            },
            .move_word_end_backward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEndBackward(false);
            },
            .move_word_end_backward_big => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveWordEndBackward(true);
            },
            .move_paragraph_forward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveParagraphForward();
            },
            .move_paragraph_backward => {
                var i: usize = 0;
                while (i < count) : (i += 1) buf.moveParagraphBackward();
            },
            .move_sentence_forward => try self.moveSentence(true, count),
            .move_sentence_backward => try self.moveSentence(false, count),
            .scroll_up => try self.scrollViewport(false, count),
            .scroll_down => try self.scrollViewport(true, count),
            .jump_history_forward => try self.jumpHistory(true, count),
            .jump_history_backward => try self.jumpHistory(false, count),
            .switch_previous_buffer => self.togglePreviousBuffer(),
            .find_forward, .find_backward, .find_forward_before, .find_backward_before => unreachable,
            .repeat_find_forward => {
                if (self.last_find) |find| try self.performFind(find.char, find.forward, find.before, count);
            },
            .repeat_find_backward => {
                if (self.last_find) |find| try self.performFind(find.char, !find.forward, find.before, count);
            },
            .delete_char => {
                try buf.deleteForward();
                try self.setStatus("deleted");
            },
            .replace_char => {
                self.normal_sequence.clearRetainingCapacity();
                self.pending_prefix = .replace_char;
                try self.setStatus("replace a single character");
            },
            .replace_mode => {
                self.mode = .replace;
                self.visual_select_mode = false;
            },
            .substitute_char => {
                try buf.deleteForward();
                self.mode = .insert;
            },
            .substitute_line => {
                const removed = try buf.deleteLine(1);
                defer self.allocator.free(removed);
                self.mode = .insert;
            },
            .insert_before => self.mode = .insert,
            .insert_at_bol => {
                buf.moveToFirstNonBlank();
                self.mode = .insert;
            },
            .append_after => {
                buf.moveRight();
                self.mode = .insert;
            },
            .append_eol => {
                buf.moveLineEnd();
                self.mode = .insert;
            },
            .open_below => {
                try self.insertIndentedBlankLine(false);
                self.mode = .insert;
            },
            .open_above => {
                try self.insertIndentedBlankLine(true);
                self.mode = .insert;
            },
            .insert_line_below => {
                var i: usize = 0;
                while (i < count) : (i += 1) try self.insertIndentedBlankLine(false);
            },
            .insert_line_above => {
                var i: usize = 0;
                while (i < count) : (i += 1) try self.insertIndentedBlankLine(true);
            },
            .delete_line => {
                const removed = try buf.deleteLine(count);
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, true);
                try self.setStatus("deleted line");
            },
            .delete_to_bol => {
                const removed = try buf.deleteToLineStart();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, false);
                try self.setStatus("deleted line start");
            },
            .yank_line => {
                const yanked = try buf.yankLine(count);
                defer self.allocator.free(yanked);
                try self.storeRegisterForYank(yanked, true);
                try self.setStatus("yanked line");
            },
            .paste_after => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(false, key);
                self.pending_register = null;
            },
            .paste_before => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(true, key);
                self.pending_register = null;
            },
            .paste_after_keep_cursor => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(false, key);
                self.pending_register = null;
            },
            .paste_before_keep_cursor => {
                const key = self.pending_register orelse '"';
                var i: usize = 0;
                while (i < count) : (i += 1) try self.pasteRegisterKey(true, key);
                self.pending_register = null;
            },
            .undo => {
                var i: usize = 0;
                while (i < count) : (i += 1) try buf.undo();
            },
            .redo => {
                var i: usize = 0;
                while (i < count) : (i += 1) try buf.redo();
            },
            .delete_word => {
                const removed = try buf.deleteCurrentWord();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, false);
            },
            .change_word => {
                const removed = try buf.deleteCurrentWord();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, false);
                self.mode = .insert;
            },
            .change_line => {
                const removed = try buf.deleteLine(count);
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, true);
                self.mode = .insert;
            },
            .change_to_eol => {
                const removed = try buf.deleteToLineEnd();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, false);
                self.mode = .insert;
            },
            .yank_word => {
                const word = buf.currentWord();
                try self.storeRegisterForYank(word, false);
            },
            .yank_to_eol => {
                const line = buf.currentLine();
                const start_col = @min(buf.cursor.col, line.len);
                const yanked = try self.allocator.dupe(u8, line[start_col..]);
                defer self.allocator.free(yanked);
                try self.storeRegisterForYank(yanked, false);
            },
            .delete_to_eol => {
                const removed = try buf.deleteToLineEnd();
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, false);
            },
            .indent_line => {
                try self.shiftCurrentLine(true, count);
                text_changed = true;
            },
            .dedent_line => {
                try self.shiftCurrentLine(false, count);
                text_changed = true;
            },
            .toggle_case_char => {
                try self.toggleCurrentCharacter();
                text_changed = true;
            },
            .toggle_case_word => {
                try self.transformCurrentWord(.toggle);
                text_changed = true;
            },
            .lowercase_word => {
                try self.transformCurrentWord(.lower);
                text_changed = true;
            },
            .uppercase_word => {
                try self.transformCurrentWord(.upper);
                text_changed = true;
            },
            .viewport_top => self.setViewport(.top),
            .viewport_middle => self.setViewport(.middle),
            .viewport_bottom => self.setViewport(.bottom),
            .join_line_space => try self.joinCurrentLine(true),
            .join_line_nospace => try self.joinCurrentLine(false),
            .save => {
                _ = self.saveActiveBuffer();
            },
            .save_as => {
                _ = self.commandSaveAs(null);
            },
            .close => try self.closeCurrentPane(),
            .terminal => try self.openTerminalShell(),
            .help => try self.openManPageForCurrentWord(),
            .jump_local_declaration => try self.jumpToDeclaration(false),
            .jump_global_declaration => try self.jumpToDeclaration(true),
            .jump_matching_character => try self.jumpToMatchingCharacter(),
            .search_next => try self.repeatSearch(true),
            .search_prev => try self.repeatSearch(false),
            .search_word_forward => try self.searchWordUnderCursor(true),
            .search_word_backward => try self.searchWordUnderCursor(false),
            .registers => try self.showRegisters(),
            .open => try self.setStatus("use :open PATH"),
            .open_file_under_cursor => try self.openCursorPath(false),
            .open_link_under_cursor => try self.openCursorPath(true),
            .split => try self.setStatus("use :split PATH"),
            .set_mark => try self.setStatus("use m{mark}"),
            .jump_mark => try self.setStatus("use '{mark}"),
            .jump_mark_exact => try self.setStatus("use `{mark}"),
            .repeat_last_command => try self.repeatLastCommand(),
            .reload_config => try self.reloadConfig(),
            .quit => try self.requestQuit(false),
            .force_quit => try self.requestQuit(true),
            .close_prompt => try self.requestCloseConfirm(),
            .visual_char => self.startVisual(.character),
            .visual_line => self.startVisual(.line),
            .visual_block => {
                self.startVisual(.block);
                try self.setStatus("visual block mode is partial");
            },
            .exit_visual => self.exitVisual(),
            .visual_yank => try self.visualYank(),
            .visual_delete => try self.visualDelete(),
            .visual_restore => try self.restoreLastVisual(),
            .not_implemented => try self.setStatus("not implemented"),
            .macro_record => try self.setStatus("use q<reg> in normal mode"),
            .macro_run => try self.setStatus("use @<reg> in normal mode"),
            .tab_new => try self.openNewTab(null),
            .tab_close => try self.tabCloseCurrent(),
            .tab_only => try self.tabOnlyCurrent(),
            .tab_move => try self.setStatus("use :tabmove N"),
        }
        self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        if (text_changed or actionIsEditing(action)) try self.recordChange(start_cursor);
        if (action == .scroll_up or action == .scroll_down or action == .jump_history_forward or action == .jump_history_backward or action == .switch_previous_buffer or action == .repeat_last_command) {
            record_jump = false;
        }
        const end_cursor = self.activeBuffer().cursor;
        if (record_jump and (end_cursor.row != start_cursor.row or end_cursor.col != start_cursor.col)) try self.recordJump(start_cursor);
        self.pending_register = null;
        if (actionIsRepeatableChange(action)) {
            self.last_repeatable_edit = .{ .action = .{ .action = action, .count = count } };
        }
    }

    const CompoundParseStatus = enum { complete, prefix, invalid };
    const ParsedMotion = struct {
        motion: MotionSpec,
        count: usize = 1,
    };

    const CompoundParseResult = struct {
        status: CompoundParseStatus,
        recipe: ?OperatorRecipe = null,
    };

    fn executeCompoundEditIfReady(self: *App, sequence: []const u8) !bool {
        const parsed = try self.parseCompoundEdit(sequence);
        switch (parsed.status) {
            .complete => {
                const count = self.consumeCount();
                self.normal_sequence.clearRetainingCapacity();
                var recipe = parsed.recipe.?;
                recipe.operator_count *= count;
                try self.performOperatorRecipe(recipe);
                return true;
            },
            .prefix => return false,
            .invalid => return false,
        }
    }

    fn compoundEditHasPrefix(self: *App, sequence: []const u8) bool {
        const parsed = self.parseCompoundEdit(sequence) catch return false;
        return parsed.status == .prefix;
    }

    fn parseCompoundEdit(self: *App, sequence: []const u8) !CompoundParseResult {
        if (sequence.len == 0) return .{ .status = .prefix };
        const operator = switch (sequence[0]) {
            'd' => OperatorKind.delete,
            'c' => OperatorKind.change,
            'y' => OperatorKind.yank,
            else => return .{ .status = .invalid },
        };
        if (sequence.len == 1) return .{ .status = .prefix };
        const motion = try self.parseMotionSequence(sequence[1..]);
        return switch (motion.status) {
            .complete => .{
                .status = .complete,
                .recipe = .{
                    .kind = operator,
                    .motion_count = motion.motion.?.count,
                    .motion = motion.motion.?.motion,
                },
            },
            .prefix => .{ .status = .prefix },
            .invalid => .{ .status = .invalid },
        };
    }

    fn parseMotionSequence(self: *App, sequence: []const u8) !struct { status: CompoundParseStatus, motion: ?ParsedMotion = null } {
        if (sequence.len == 0) return .{ .status = .prefix };

        if (sequence[0] >= '1' and sequence[0] <= '9') {
            var idx: usize = 0;
            var count: usize = 0;
            while (idx < sequence.len and std.ascii.isDigit(sequence[idx])) : (idx += 1) {
                count = count * 10 + @as(usize, sequence[idx] - '0');
            }
            if (idx == sequence.len) return .{ .status = .prefix };
            const tail = try self.parseMotionSequence(sequence[idx..]);
            return switch (tail.status) {
                .complete => .{
                    .status = .complete,
                    .motion = .{
                        .motion = tail.motion.?.motion,
                        .count = @max(@as(usize, 1), count) * tail.motion.?.count,
                    },
                },
                .prefix => .{ .status = .prefix },
                .invalid => .{ .status = .invalid },
            };
        }

        return switch (sequence[0]) {
            'h' => .{ .status = .complete, .motion = .{ .motion = .left } },
            'j' => .{ .status = .complete, .motion = .{ .motion = .down } },
            'k' => .{ .status = .complete, .motion = .{ .motion = .up } },
            'l' => .{ .status = .complete, .motion = .{ .motion = .right } },
            '0' => .{ .status = .complete, .motion = .{ .motion = .line_start } },
            '^' => .{ .status = .complete, .motion = .{ .motion = .line_nonblank } },
            '$' => .{ .status = .complete, .motion = .{ .motion = .line_end } },
            'w' => .{ .status = .complete, .motion = .{ .motion = .{ .word_forward = false } } },
            'W' => .{ .status = .complete, .motion = .{ .motion = .{ .word_forward = true } } },
            'b' => .{ .status = .complete, .motion = .{ .motion = .{ .word_backward = false } } },
            'B' => .{ .status = .complete, .motion = .{ .motion = .{ .word_backward = true } } },
            'e' => .{ .status = .complete, .motion = .{ .motion = .{ .word_end_forward = false } } },
            'E' => .{ .status = .complete, .motion = .{ .motion = .{ .word_end_forward = true } } },
            'g' => {
                if (sequence.len < 2) return .{ .status = .prefix };
                return switch (sequence[1]) {
                    'g' => .{ .status = .complete, .motion = .{ .motion = .doc_start } },
                    '_' => .{ .status = .complete, .motion = .{ .motion = .line_last_nonblank } },
                    '0' => .{ .status = .complete, .motion = .{ .motion = .line_start } },
                    '^' => .{ .status = .complete, .motion = .{ .motion = .line_nonblank } },
                    '$' => .{ .status = .complete, .motion = .{ .motion = .line_end } },
                    'e' => .{ .status = .complete, .motion = .{ .motion = .{ .word_end_backward = false } } },
                    'E' => .{ .status = .complete, .motion = .{ .motion = .{ .word_end_backward = true } } },
                    else => .{ .status = .invalid },
                };
            },
            'G' => .{ .status = .complete, .motion = .{ .motion = .doc_end } },
            'H' => .{ .status = .complete, .motion = .{ .motion = .doc_start } },
            'M' => .{ .status = .complete, .motion = .{ .motion = .doc_middle } },
            'L' => .{ .status = .complete, .motion = .{ .motion = .doc_end } },
            '}' => .{ .status = .complete, .motion = .{ .motion = .paragraph_forward } },
            '{' => .{ .status = .complete, .motion = .{ .motion = .paragraph_backward } },
            ')' => .{ .status = .complete, .motion = .{ .motion = .sentence_forward } },
            '(' => .{ .status = .complete, .motion = .{ .motion = .sentence_backward } },
            '%' => .{ .status = .complete, .motion = .{ .motion = .matching_character } },
            'f' => if (sequence.len < 2) .{ .status = .prefix } else .{ .status = .complete, .motion = .{ .motion = .{ .find_forward = .{ .needle = sequence[1], .before = false } } } },
            't' => if (sequence.len < 2) .{ .status = .prefix } else .{ .status = .complete, .motion = .{ .motion = .{ .find_forward = .{ .needle = sequence[1], .before = true } } } },
            'F' => if (sequence.len < 2) .{ .status = .prefix } else .{ .status = .complete, .motion = .{ .motion = .{ .find_backward = .{ .needle = sequence[1], .before = false } } } },
            'T' => if (sequence.len < 2) .{ .status = .prefix } else .{ .status = .complete, .motion = .{ .motion = .{ .find_backward = .{ .needle = sequence[1], .before = true } } } },
            'a' => if (sequence.len < 2) .{ .status = .prefix } else .{ .status = .complete, .motion = .{ .motion = .{ .text_object = .{ .byte = sequence[1], .inner = false } } } },
            'i' => if (sequence.len < 2) .{ .status = .prefix } else .{ .status = .complete, .motion = .{ .motion = .{ .text_object = .{ .byte = sequence[1], .inner = true } } } },
            'd', 'c', 'y' => .{ .status = .complete, .motion = .{ .motion = .current_line } },
            else => .{ .status = .invalid },
        };
    }

    fn performOperatorRecipe(self: *App, recipe: OperatorRecipe) !void {
        const buf = self.activeBuffer();
        const start_buffer = buf;
        const start_cursor = buf.cursor;
        const total_count = recipe.operator_count * recipe.motion_count;
        const range = try self.motionRange(recipe.motion, total_count);
        defer self.syncViewportIfCursorMoved(start_buffer, start_cursor);
        if (range == null) {
            try self.setStatus("motion not found");
            return;
        }

        var changed = false;
        switch (recipe.kind) {
            .delete => {
                const removed = try buf.deleteRange(range.?.start, range.?.end);
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, recipe.motion == .current_line);
                changed = true;
            },
            .change => {
                const removed = try buf.deleteRange(range.?.start, range.?.end);
                defer self.allocator.free(removed);
                try self.storeRegisterForDelete(removed, recipe.motion == .current_line);
                self.mode = .insert;
                changed = true;
            },
            .yank => {
                const yanked = try self.selectedText(range.?.start, range.?.end);
                defer self.allocator.free(yanked);
                try self.storeRegisterForYank(yanked, recipe.motion == .current_line);
            },
        }

        if (changed) try self.recordChange(start_cursor);
        if (buf.cursor.row != start_cursor.row or buf.cursor.col != start_cursor.col) try self.recordJump(start_cursor);
        self.pending_register = null;
        if (recipe.kind != .yank) {
            self.last_repeatable_edit = .{ .operator = recipe };
        }
    }

    fn motionRange(self: *App, motion: MotionSpec, count: usize) !?struct { start: buffer_mod.Position, end: buffer_mod.Position } {
        const buf = self.activeBuffer();
        const start = buf.cursor;
        switch (motion) {
            .current_line => {
                const line = buf.currentLine();
                return .{
                    .start = .{ .row = start.row, .col = 0 },
                    .end = if (start.row + 1 < buf.lineCount())
                        .{ .row = start.row + 1, .col = 0 }
                    else
                        .{ .row = start.row, .col = line.len },
                };
            },
            .text_object => |obj| {
                const range = try self.resolveVisualTextObject(obj.byte, obj.inner) orelse return null;
                return .{ .start = range.start, .end = range.end };
            },
            .line_start, .line_nonblank, .line_last_nonblank, .line_end, .doc_start, .doc_middle, .doc_end, .left, .down, .up, .right, .word_forward, .word_backward, .word_end_forward, .word_end_backward, .paragraph_forward, .paragraph_backward, .sentence_forward, .sentence_backward, .matching_character, .find_forward, .find_backward => {
                defer buf.cursor = start;
                buf.cursor = start;
                switch (motion) {
                    .line_start => buf.moveLineStart(),
                    .line_nonblank => buf.moveToFirstNonBlank(),
                    .line_last_nonblank => buf.moveToLastNonBlank(),
                    .line_end => buf.moveLineEnd(),
                    .doc_start => buf.moveToDocumentStart(),
                    .doc_middle => {
                        const middle = if (buf.lineCount() > 0) (buf.lineCount() - 1) / 2 else 0;
                        buf.moveToLine(middle);
                    },
                    .doc_end => {
                        buf.moveToDocumentEnd();
                        buf.cursor.col = buf.currentLine().len;
                    },
                    .left => {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveLeft();
                    },
                    .down => {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveDown();
                    },
                    .up => {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveUp();
                    },
                    .right => {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveRight();
                    },
                    .word_forward => |big| {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveWordForward(big);
                    },
                    .word_backward => |big| {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveWordBackward(big);
                    },
                    .word_end_forward => |big| {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveWordEnd(big);
                    },
                    .word_end_backward => |big| {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveWordEndBackward(big);
                    },
                    .paragraph_forward => {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveParagraphForward();
                    },
                    .paragraph_backward => {
                        var i: usize = 0;
                        while (i < count) : (i += 1) buf.moveParagraphBackward();
                    },
                    .sentence_forward => try self.moveSentence(true, count),
                    .sentence_backward => try self.moveSentence(false, count),
                    .matching_character => try self.jumpToMatchingCharacter(),
                    .find_forward => |find| try self.performFind(find.needle, true, find.before, count),
                    .find_backward => |find| try self.performFind(find.needle, false, find.before, count),
                    .current_line, .text_object => unreachable,
                }
                const end = buf.cursor;
                if (start.row == end.row and start.col == end.col) return null;
                return .{
                    .start = if (start.row < end.row or (start.row == end.row and start.col <= end.col)) start else end,
                    .end = if (start.row < end.row or (start.row == end.row and start.col <= end.col)) end else start,
                };
            },
        }
    }

    fn performFind(self: *App, needle: u8, forward: bool, before: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (line.len == 0) return;
        var idx = buf.cursor.col;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (forward) {
                var start = if (idx < line.len) idx + 1 else line.len;
                var found: ?usize = null;
                while (start < line.len) : (start += 1) {
                    if (line[start] == needle) {
                        found = start;
                        break;
                    }
                }
                if (found) |pos| {
                    idx = if (before and pos > 0) pos - 1 else pos;
                }
            } else {
                if (idx == 0) break;
                var start: usize = idx - 1;
                var found: ?usize = null;
                while (true) {
                    if (line[start] == needle) {
                        found = start;
                        break;
                    }
                    if (start == 0) break;
                    start -= 1;
                }
                if (found) |pos| {
                    idx = if (!before and pos + 1 < line.len) pos + 1 else pos;
                }
            }
        }
        buf.cursor.col = @min(idx, line.len);
        self.last_find = .{ .char = needle, .forward = forward, .before = before };
    }

    fn saveActiveBuffer(self: *App) bool {
        self.activeBuffer().save() catch |err| {
            self.setStatus(@errorName(err)) catch {};
            return false;
        };
        if (self.activeBuffer().path) |path| self.lsp.didSavePath(path) catch {};
        self.workspace.noteSessionChange();
        self.emitBuiltinEvent("buffer_save", "{}");
        self.setStatus("saved") catch {};
        self.refreshDerivedSources() catch {};
        return true;
    }

    fn commandSaveAs(self: *App, path: ?[]const u8) bool {
        const actual = path orelse {
            self.setStatus("saveas requires a path") catch {};
            return false;
        };
        self.activeBuffer().saveAs(actual) catch |err| {
            self.setStatus(@errorName(err)) catch {};
            return false;
        };
        self.lsp.didSavePath(actual) catch {};
        self.workspace.noteSessionChange();
        self.setStatus("saved as") catch {};
        self.refreshDerivedSources() catch {};
        return true;
    }

    fn requestQuit(self: *App, force: bool) !void {
        if (!force and self.anyDirty()) {
            try self.setStatus("buffer modified, use :q! or :wq");
            return;
        }
        self.should_quit = true;
    }

    fn anyDirty(self: *const App) bool {
        for (self.buffers.items) |buf| {
            if (buf.dirty) return true;
        }
        return false;
    }

    fn startVisual(self: *App, mode: VisualMode) void {
        self.last_visual_state = null;
        self.mode = .visual;
        self.visual_mode = mode;
        self.visual_select_mode = false;
        self.visual_select_restore = false;
        self.visual_pending = null;
        self.visual_anchor = self.activeBuffer().cursor;
    }

    fn exitVisual(self: *App) void {
        if (self.visual_anchor) |anchor| {
            self.last_visual_state = .{
                .mode = self.visual_mode,
                .anchor = anchor,
                .cursor = self.activeBuffer().cursor,
                .select_mode = self.mode == .select,
                .select_restore = self.visual_select_restore,
            };
        }
        self.visual_mode = .none;
        self.visual_anchor = null;
        self.visual_select_mode = false;
        self.visual_select_restore = false;
        self.visual_pending = null;
        self.mode = .normal;
    }

    const VisualSelection = struct {
        start: buffer_mod.Position,
        end: buffer_mod.Position,
    };

    fn visualSelection(self: *App) ?VisualSelection {
        const anchor = self.visual_anchor orelse return null;
        const cursor = self.activeBuffer().cursor;
        const ordered: VisualSelection = if (anchor.row < cursor.row or (anchor.row == cursor.row and anchor.col <= cursor.col))
            .{ .start = anchor, .end = cursor }
        else
            .{ .start = cursor, .end = anchor };
        return switch (self.visual_mode) {
            .line => .{
                .start = .{ .row = ordered.start.row, .col = 0 },
                .end = .{ .row = ordered.end.row, .col = self.activeBuffer().lines.items[ordered.end.row].len },
            },
            else => ordered,
        };
    }

    const VisualBlockBounds = struct {
        start_row: usize,
        end_row: usize,
        start_col: usize,
        end_col: usize,
    };

    fn visualBlockBounds(self: *App) ?VisualBlockBounds {
        if (self.visual_mode != .block) return null;
        const anchor = self.visual_anchor orelse return null;
        const cursor = self.activeBuffer().cursor;
        return .{
            .start_row = @min(anchor.row, cursor.row),
            .end_row = @max(anchor.row, cursor.row),
            .start_col = @min(anchor.col, cursor.col),
            .end_col = @max(anchor.col, cursor.col),
        };
    }

    fn swapVisualCorners(self: *App) void {
        if (self.visual_anchor) |anchor| {
            const current = self.activeBuffer().cursor;
            self.activeBuffer().cursor = anchor;
            self.visual_anchor = current;
        }
    }

    fn restoreLastVisual(self: *App) !void {
        const saved = self.last_visual_state orelse {
            try self.setStatus("no previous visual area");
            return;
        };
        self.mode = if (saved.select_mode) .select else .visual;
        self.visual_mode = saved.mode;
        self.visual_anchor = saved.anchor;
        self.activeBuffer().cursor = saved.cursor;
        self.visual_select_mode = saved.select_mode;
        self.visual_select_restore = saved.select_restore;
    }

    fn commitVisualBlockInsert(self: *App, block: *VisualBlockInsert) !void {
        const inserted = try block.text.toOwnedSlice();
        defer self.allocator.free(inserted);
        var row = block.start_row;
        while (row <= block.end_row) : (row += 1) {
            const pos = buffer_mod.Position{ .row = row, .col = block.column };
            try self.activeBuffer().replaceRangeWithText(pos, pos, inserted);
        }
        block.text.clearRetainingCapacity();
        self.visual_block_insert = null;
        self.exitVisual();
    }

    fn visualYank(self: *App) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockYank();
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(text);
        try self.storeRegisterForYank(text, self.visual_mode == .line);
    }

    fn visualDelete(self: *App) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockDelete();
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed, self.visual_mode == .line);
    }

    fn visualReplaceChar(self: *App, byte: u8) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockReplaceChar(byte);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        if (start >= end) return;
        const replacement = try self.allocator.alloc(u8, end - start);
        defer self.allocator.free(replacement);
        @memset(replacement, byte);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, replacement);
        self.exitVisual();
    }

    fn visualPaste(self: *App) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockPaste();
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const key = self.pending_register orelse '"';
        const value = self.registers.get(key) orelse {
            try self.setStatus("register empty");
            return;
        };
        const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed, self.visual_mode == .line);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.start, value);
        self.exitVisual();
    }

    fn visualBlockPaste(self: *App) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        const key = self.pending_register orelse '"';
        const value = self.registers.get(key) orelse {
            try self.setStatus("register empty");
            return;
        };
        var removed = std.array_list.Managed(u8).init(self.allocator);
        errdefer removed.deinit();
        var row = bounds.start_row;
        var line_index: usize = 0;
        while (row <= bounds.end_row) : (row += 1) {
            const segment = splitRegisterLine(value, line_index);
            const line = self.activeBuffer().lines.items[row];
            const removed_piece = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(removed_piece);
            if (row > bounds.start_row) try removed.append('\n');
            try removed.appendSlice(removed_piece);
            try self.replaceBlockRowSlice(row, bounds, segment);
            line_index += 1;
        }
        const removed_text = try removed.toOwnedSlice();
        defer self.allocator.free(removed_text);
        try self.storeRegisterForDelete(removed_text, false);
        self.exitVisual();
    }

    fn visualChange(self: *App) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed, self.visual_mode == .line);
        self.exitVisual();
        self.mode = .insert;
    }

    fn selectReplaceByte(self: *App, byte: u8) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const removed = try self.activeBuffer().deleteRange(selection.start, selection.end);
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed, self.visual_mode == .line);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.start, &[_]u8{byte});
        self.exitVisual();
        self.mode = .insert;
    }

    fn visualCase(self: *App, mode: CaseMode) !void {
        if (self.visual_mode == .block) {
            try self.visualBlockCase(mode);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        if (start >= end) return;
        const piece = try self.allocator.dupe(u8, text[start..end]);
        defer self.allocator.free(piece);
        for (piece) |*ch| {
            ch.* = switch (mode) {
                .toggle => toggleAsciiCase(ch.*),
                .lower => std.ascii.toLower(ch.*),
                .upper => std.ascii.toUpper(ch.*),
            };
        }
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, piece);
        self.exitVisual();
    }

    fn visualIndent(self: *App, right: bool) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        if (selection.start.row != selection.end.row) {
            const start_row = selection.start.row;
            const end_row = selection.end.row;
            var row: usize = start_row;
            while (row <= end_row) : (row += 1) {
                try self.shiftCurrentLineSelection(row, right, 1);
            }
            self.exitVisual();
            return;
        }
        try self.applyVisualIndent(right);
    }

    fn shiftCurrentLineSelection(self: *App, row: usize, right: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const line = buf.lines.items[row];
        const start = buffer_mod.Position{ .row = row, .col = 0 };
        const end = buffer_mod.Position{ .row = row, .col = line.len };
        const width = self.config.tab_width * count;
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        if (right) {
            try out.appendNTimes(' ', width);
            try out.appendSlice(line);
        } else {
            var trim = line;
            var removed: usize = 0;
            while (removed < width and trim.len > 0 and trim[0] == ' ') : (removed += 1) {
                trim = trim[1..];
            }
            try out.appendSlice(trim);
        }
        try buf.replaceRangeWithText(start, end, try out.toOwnedSlice());
    }

    fn visualJoin(self: *App, with_space: bool) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        if (selection.start.row == selection.end.row) return;
        const buf = self.activeBuffer();
        var line = selection.start.row;
        const end_row = selection.end.row;
        var combined = std.array_list.Managed(u8).init(self.allocator);
        defer combined.deinit();
        while (line <= end_row) : (line += 1) {
            if (line > selection.start.row) {
                if (with_space) try combined.append(' ');
            }
            try combined.appendSlice(buf.lines.items[line]);
        }
        try buf.replaceRangeWithText(.{ .row = selection.start.row, .col = 0 }, .{ .row = selection.end.row, .col = buf.lines.items[selection.end.row].len }, try combined.toOwnedSlice());
        self.exitVisual();
    }

    fn runVisualFilter(self: *App, command: []const u8) !void {
        if (self.visual_mode == .block) {
            try self.runVisualBlockFilter(command);
            return;
        }
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const input = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(input);
        const output = try self.runCommandWithInput(command, input);
        defer self.allocator.free(output);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, output);
        self.exitVisual();
    }

    fn runVisualBlockFilter(self: *App, command: []const u8) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            const line = self.activeBuffer().lines.items[row];
            const input = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(input);
            const output = try self.runCommandWithInput(command, input);
            defer self.allocator.free(output);
            const normalized = trimTrailingNewline(output);
            try self.replaceBlockRowSlice(row, bounds, normalized);
        }
        self.exitVisual();
    }

    fn runCommandWithInput(self: *App, command: []const u8, input: []const u8) ![]u8 {
        const argv = if (builtin.os.tag == .windows) blk: {
            const shell = try self.defaultShell();
            defer if (shell.owned) self.allocator.free(shell.path);
            break :blk &[_][]const u8{ shell.path, "/C", command };
        } else &[_][]const u8{ "sh", "-c", command };

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();
        if (child.stdin) |*stdin_file| {
            try stdin_file.writeAll(input);
            stdin_file.close();
            child.stdin = null;
        }

        const output = if (child.stdout) |*stdout_file| blk: {
            const text = try stdout_file.readToEndAlloc(self.allocator, 1 << 20);
            stdout_file.close();
            child.stdout = null;
            break :blk text;
        } else try self.allocator.dupe(u8, "");
        errdefer self.allocator.free(output);
        _ = try child.wait();
        return output;
    }

    fn trimTrailingNewline(bytes: []const u8) []const u8 {
        return if (bytes.len > 0 and bytes[bytes.len - 1] == '\n') bytes[0 .. bytes.len - 1] else bytes;
    }

    fn splitRegisterLine(text: []const u8, index: usize) []const u8 {
        var start: usize = 0;
        var line_index: usize = 0;
        while (start <= text.len) {
            const rel_end = std.mem.indexOfScalar(u8, text[start..], '\n');
            const end = if (rel_end) |idx| start + idx else text.len;
            if (line_index == index) return text[start..end];
            if (end >= text.len) return text[start..end];
            start = end + 1;
            line_index += 1;
        }
        return text;
    }

    fn blockSliceForLine(self: *App, line: []const u8, bounds: VisualBlockBounds) ![]u8 {
        const width = bounds.end_col - bounds.start_col;
        var out = try self.allocator.alloc(u8, width);
        @memset(out, ' ');
        const src_start = @min(bounds.start_col, line.len);
        const src_end = @min(bounds.end_col, line.len);
        if (src_start < src_end) {
            @memcpy(out[src_start - bounds.start_col .. src_end - bounds.start_col], line[src_start..src_end]);
        }
        return out;
    }

    fn replaceBlockRowSlice(self: *App, row: usize, bounds: VisualBlockBounds, replacement: []const u8) !void {
        const buf = self.activeBuffer();
        const line = buf.lines.items[row];
        const start_col = @min(bounds.start_col, line.len);
        const end_col = @min(bounds.end_col, line.len);
        const start = buffer_mod.Position{ .row = row, .col = start_col };
        const end = buffer_mod.Position{ .row = row, .col = end_col };
        try buf.replaceRangeWithText(start, end, replacement);
    }

    fn visualBlockYank(self: *App) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            if (row > bounds.start_row) try out.append('\n');
            const line = self.activeBuffer().lines.items[row];
            const slice = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(slice);
            try out.appendSlice(slice);
        }
        const text = try out.toOwnedSlice();
        defer self.allocator.free(text);
        try self.storeRegisterForYank(text, false);
    }

    fn visualBlockDelete(self: *App) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            if (row > bounds.start_row) try out.append('\n');
            const line = self.activeBuffer().lines.items[row];
            const slice = try self.blockSliceForLine(line, bounds);
            defer self.allocator.free(slice);
            try out.appendSlice(slice);
            try self.replaceBlockRowSlice(row, bounds, "");
        }
        const removed = try out.toOwnedSlice();
        defer self.allocator.free(removed);
        try self.storeRegisterForDelete(removed, false);
    }

    fn visualBlockReplaceChar(self: *App, byte: u8) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            const line = self.activeBuffer().lines.items[row];
            const start_col = @min(bounds.start_col, line.len);
            const end_col = @min(bounds.end_col, line.len);
            if (start_col >= end_col) continue;
            const width = end_col - start_col;
            const replacement = try self.allocator.alloc(u8, width);
            defer self.allocator.free(replacement);
            @memset(replacement, byte);
            try self.replaceBlockRowSlice(row, bounds, replacement);
        }
        self.exitVisual();
    }

    fn visualBlockCase(self: *App, mode: CaseMode) !void {
        const bounds = self.visualBlockBounds() orelse return self.setStatus("no selection");
        var row = bounds.start_row;
        while (row <= bounds.end_row) : (row += 1) {
            const line = self.activeBuffer().lines.items[row];
            const start_col = @min(bounds.start_col, line.len);
            const end_col = @min(bounds.end_col, line.len);
            if (start_col >= end_col) continue;
            const selection = line[start_col..end_col];
            const replacement = try self.allocator.dupe(u8, selection);
            defer self.allocator.free(replacement);
            for (replacement) |*ch| {
                ch.* = switch (mode) {
                    .toggle => toggleAsciiCase(ch.*),
                    .lower => std.ascii.toLower(ch.*),
                    .upper => std.ascii.toUpper(ch.*),
                };
            }
            try self.replaceBlockRowSlice(row, bounds, replacement);
        }
        self.exitVisual();
    }

    fn visualBlockInsert(self: *App, before: bool) !void {
        if (self.visual_mode != .block) {
            try self.setStatus("block insert only works in block mode");
            return;
        }
        const bounds = self.visualBlockBounds() orelse {
            try self.setStatus("no selection");
            return;
        };
        if (self.visual_block_insert) |*block| {
            block.text.clearRetainingCapacity();
            block.start_row = bounds.start_row;
            block.end_row = bounds.end_row;
            block.column = if (before) bounds.start_col else bounds.end_col;
            block.before = before;
        } else {
            var text = std.array_list.Managed(u8).init(self.allocator);
            errdefer text.deinit();
            self.visual_block_insert = .{
                .start_row = bounds.start_row,
                .end_row = bounds.end_row,
                .column = if (before) bounds.start_col else bounds.end_col,
                .before = before,
                .text = text,
            };
        }
        self.exitVisual();
        self.mode = .insert;
        try self.setStatus("block insert");
    }

    fn visualFormat(self: *App) !void {
        try self.visualJoin(true);
    }

    fn visualEqualPrg(self: *App) !void {
        try self.runVisualFilter(self.config.equalprg);
    }

    fn visualVisualHelp(self: *App) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(text);
        if (text.len == 0) {
            try self.setStatus("no selection");
            return;
        }
        if (!self.runInteractiveCommand(&.{ "man", text })) {
            try self.setStatus("man page not available");
        } else {
            try self.setStatus("returned from man");
        }
    }

    fn visualJumpTag(self: *App) !void {
        const selection = self.visualSelection() orelse {
            try self.setStatus("no selection");
            return;
        };
        const selected = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(selected);
        var token_it = std.mem.tokenizeAny(u8, selected, " \t\r\n");
        const tag = token_it.next() orelse {
            try self.setStatus("no tag under cursor");
            return;
        };
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const found = findWordOccurrence(text, tag, cursor_offset, true) orelse {
            try self.setStatus("tag not found");
            return;
        };
        buf.cursor = self.offsetToPosition(text, found);
        self.exitVisual();
    }

    fn selectVisualTextObject(self: *App, byte: u8, inner: bool) !void {
        const range = try self.resolveVisualTextObject(byte, inner) orelse {
            try self.setStatus("text object not found");
            return;
        };
        self.setVisualRange(range);
    }

    const VisualTextRange = struct {
        start: buffer_mod.Position,
        end: buffer_mod.Position,
    };

    fn resolveVisualTextObject(self: *App, byte: u8, inner: bool) !?VisualTextRange {
        return switch (byte) {
            'w' => self.wordObjectRange(false, inner),
            'W' => self.wordObjectRange(true, inner),
            '(', ')', 'b', '[', ']', '{', '}', 'B', '<', '>' => self.syntaxAwareBlockObjectRange(inner) orelse switch (byte) {
                '(', ')', 'b' => self.pairedObjectRange('(', ')', inner),
                '[', ']' => self.pairedObjectRange('[', ']', inner),
                '{', '}', 'B' => self.pairedObjectRange('{', '}', inner),
                '<', '>' => self.angleObjectRange(inner),
                else => null,
            },
            '"' => self.quoteObjectRange('"', inner),
            '\'' => self.quoteObjectRange('\'', inner),
            '`' => self.quoteObjectRange('`', inner),
            'p' => self.paragraphObjectRange(inner),
            's' => self.sentenceObjectRange(inner),
            't' => self.tagObjectRange(inner),
            else => null,
        };
    }

    fn setVisualRange(self: *App, range: VisualTextRange) void {
        self.mode = .visual;
        self.visual_mode = .character;
        self.visual_select_mode = false;
        self.visual_pending = null;
        self.visual_anchor = range.start;
        self.activeBuffer().cursor = range.end;
    }

    fn wordObjectRange(self: *App, big: bool, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (line.len == 0) return null;
        const cursor = @min(buf.cursor.col, line.len);
        var start = cursor;
        if (start == line.len and start > 0) start -= 1;
        while (start > 0 and isObjectWordChar(line[start - 1], big)) : (start -= 1) {}
        var end = cursor;
        while (end < line.len and isObjectWordChar(line[end], big)) : (end += 1) {}
        if (!inner) {
            while (end < line.len and std.ascii.isWhitespace(line[end])) : (end += 1) {}
        }
        if (start == end) return null;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn pairedObjectRange(self: *App, open: u8, close: u8, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const text = buf.serialize() catch return null;
        defer self.allocator.free(text);
        const cursor = self.positionToOffset(buf.cursor, text);
        const left = findPairBoundary(text, cursor, open, close, true) orelse return null;
        const right = findPairBoundary(text, cursor, open, close, false) orelse return null;
        const start = if (inner and left + 1 <= right) left + 1 else left;
        const end = if (inner and right > start) right else right + 1;
        return .{
            .start = self.offsetToPosition(text, start),
            .end = self.offsetToPosition(text, end),
        };
    }

    fn quoteObjectRange(self: *App, quote: u8, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const cursor = @min(buf.cursor.col, line.len);
        var left: ?usize = null;
        if (line.len > 0) {
            var idx: usize = @min(cursor, line.len - 1);
            while (true) {
                if (line[idx] == quote) {
                    left = idx;
                    break;
                }
                if (idx == 0) break;
                idx -= 1;
            }
        }
        var right: ?usize = null;
        var idx: usize = cursor;
        while (idx < line.len) : (idx += 1) {
            if (line[idx] == quote) {
                right = idx;
                break;
            }
        }
        const l = left orelse return null;
        const r = right orelse return null;
        const start = if (inner) l + 1 else l;
        const end = if (inner) r else r + 1;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn angleObjectRange(self: *App, inner: bool) ?VisualTextRange {
        return self.pairedObjectRange('<', '>', inner);
    }

    fn syntaxAwareBlockObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        if (!std.mem.eql(u8, buf.filetypeText(), "zig")) return null;
        if (!self.syntax.hasParsedTree(buf.id)) return null;
        const snapshot = buf.readSnapshot(null) catch return null;
        defer buf.freeReadSnapshot(snapshot);
        const range = self.syntax.textObjectRange(snapshot, inner) orelse return null;
        return .{ .start = range.start, .end = range.end };
    }

    fn insertIndentedBlankLine(self: *App, above: bool) !void {
        const buf = self.activeBuffer();
        const indent_row = if (above or buf.cursor.row + 1 >= buf.lines.items.len) buf.cursor.row else buf.cursor.row + 1;
        const indent = self.syntaxIndentForRowFromActiveBuffer(indent_row);
        if (above) {
            try buf.insertBlankLineAboveIndented(indent);
        } else {
            try buf.insertBlankLineBelowIndented(indent);
        }
    }

    fn syntaxIndentForRowFromActiveBuffer(self: *App, row: usize) usize {
        const buf = self.activeBuffer();
        const snapshot = buf.readSnapshot(null) catch return self.lineIndentForRow(row);
        defer buf.freeReadSnapshot(snapshot);
        return self.syntax.indentForRow(snapshot, row);
    }

    fn lineIndentForRow(self: *App, row: usize) usize {
        const buf = self.activeBuffer();
        if (row >= buf.lines.items.len) return 0;
        const line = buf.lines.items[row];
        var indent: usize = 0;
        while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
        return indent;
    }

    fn paragraphObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        if (buf.lineCount() == 0) return null;
        var start_row = buf.cursor.row;
        while (start_row > 0 and buf.lines.items[start_row - 1].len != 0) : (start_row -= 1) {}
        var end_row = buf.cursor.row;
        while (end_row + 1 < buf.lineCount() and buf.lines.items[end_row + 1].len != 0) : (end_row += 1) {}
        if (inner) {
            while (start_row < end_row and buf.lines.items[start_row].len == 0) : (start_row += 1) {}
            while (end_row > start_row and buf.lines.items[end_row].len == 0) : (end_row -= 1) {}
        }
        return .{
            .start = .{ .row = start_row, .col = 0 },
            .end = .{ .row = end_row, .col = buf.lines.items[end_row].len },
        };
    }

    fn sentenceObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (line.len == 0) return null;
        const cursor = @min(buf.cursor.col, line.len);
        var start: usize = 0;
        var i: usize = cursor;
        while (i > 0) : (i -= 1) {
            if (line[i - 1] == '.' or line[i - 1] == '!' or line[i - 1] == '?') {
                start = i;
                break;
            }
        }
        while (start < line.len and std.ascii.isWhitespace(line[start])) : (start += 1) {}
        var end: usize = line.len;
        i = cursor;
        while (i < line.len) : (i += 1) {
            if (line[i] == '.' or line[i] == '!' or line[i] == '?') {
                end = i + 1;
                break;
            }
        }
        if (inner) {
            while (end > start and std.ascii.isWhitespace(line[end - 1])) : (end -= 1) {}
        }
        if (start >= end) return null;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn tagObjectRange(self: *App, inner: bool) ?VisualTextRange {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const cursor = @min(buf.cursor.col, line.len);
        var left: ?usize = null;
        var right: ?usize = null;
        if (line.len > 0) {
            var i: usize = @min(cursor, line.len - 1);
            while (true) {
                if (line[i] == '<') {
                    left = i;
                    break;
                }
                if (i == 0) break;
                i -= 1;
            }
        }
        var i: usize = cursor;
        while (i < line.len) : (i += 1) {
            if (line[i] == '>') {
                right = i;
                break;
            }
        }
        const l = left orelse return null;
        const r = right orelse return null;
        const start = if (inner) l + 1 else l;
        const end = if (inner) r else r + 1;
        return .{ .start = .{ .row = buf.cursor.row, .col = start }, .end = .{ .row = buf.cursor.row, .col = end } };
    }

    fn isObjectWordChar(byte: u8, big: bool) bool {
        return if (big) !std.ascii.isWhitespace(byte) else isWordChar(byte);
    }

    fn findPairBoundary(text: []const u8, cursor: usize, open: u8, close: u8, left: bool) ?usize {
        if (left) {
            var depth: usize = 0;
            if (text.len == 0) return null;
            var idx = @min(cursor, text.len - 1);
            while (true) {
                const ch = text[idx];
                if (ch == open) {
                    if (depth == 0) return idx;
                    depth -= 1;
                } else if (ch == close) {
                    depth += 1;
                }
                if (idx == 0) break;
                idx -= 1;
            }
            return null;
        }
        var depth: usize = 0;
        var idx: usize = cursor;
        while (idx < text.len) : (idx += 1) {
            const ch = text[idx];
            if (ch == close) {
                if (depth == 0) return idx;
                depth -= 1;
            } else if (ch == open) {
                depth += 1;
            }
        }
        return null;
    }

    fn visualAdjustNumber(self: *App, add: bool, amount: usize) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        if (start >= end) return;
        var piece = try self.allocator.dupe(u8, text[start..end]);
        defer self.allocator.free(piece);
        var i: usize = 0;
        while (i < piece.len and !std.ascii.isDigit(piece[i]) and piece[i] != '-') : (i += 1) {}
        if (i >= piece.len) {
            try self.setStatus("no number in selection");
            return;
        }
        const num_start = i;
        if (piece[i] == '-') i += 1;
        while (i < piece.len and std.ascii.isDigit(piece[i])) : (i += 1) {}
        const value = std.fmt.parseInt(i64, piece[num_start..i], 10) catch {
            try self.setStatus("invalid number");
            return;
        };
        const delta: i64 = @intCast(amount);
        const next = if (add) value + delta else value - delta;
        const number = try std.fmt.allocPrint(self.allocator, "{d}", .{next});
        defer self.allocator.free(number);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        try out.appendSlice(piece[0..num_start]);
        try out.appendSlice(number);
        try out.appendSlice(piece[i..]);
        const replacement = try out.toOwnedSlice();
        defer self.allocator.free(replacement);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, replacement);
        self.exitVisual();
    }

    fn selectedText(self: *App, start: buffer_mod.Position, end: buffer_mod.Position) ![]u8 {
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start_index = self.positionToOffset(start, text);
        const end_index = self.positionToOffset(end, text);
        return try self.allocator.dupe(u8, text[start_index..end_index]);
    }

    fn positionToOffset(self: *App, pos: buffer_mod.Position, text: []const u8) usize {
        _ = self;
        var row: usize = 0;
        var offset: usize = 0;
        var start: usize = 0;
        while (start <= text.len) {
            const rel_end = std.mem.indexOfScalar(u8, text[start..], '\n');
            const end = if (rel_end) |idx| start + idx else text.len;
            if (row == pos.row) {
                return offset + @min(pos.col, end - start);
            }
            offset += end - start;
            if (end < text.len) offset += 1;
            if (end >= text.len) break;
            start = end + 1;
            row += 1;
        }
        return text.len;
    }

    fn normalizedLinewiseRegister(self: *App, bytes: []const u8) []const u8 {
        _ = self;
        return if (bytes.len > 0 and bytes[bytes.len - 1] == '\n') bytes[0 .. bytes.len - 1] else bytes;
    }

    fn clipboardRegisterKey(key: u8) bool {
        return key == '+' or key == '*';
    }

    fn readSystemClipboard(self: *App) !?[]u8 {
        if (self.clipboard_get_hook) |hook| {
            if (hook(self)) |text| return try self.allocator.dupe(u8, text);
            return null;
        }

        const command = switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos => "pbpaste",
            .windows => "powershell -NoProfile -Command Get-Clipboard",
            else => "wl-paste --no-newline 2>/dev/null || xclip -selection clipboard -o 2>/dev/null || xsel --clipboard --output 2>/dev/null",
        };
        return try self.runCommandWithInput(command, "");
    }

    fn writeSystemClipboard(self: *App, text: []const u8) !void {
        if (self.clipboard_set_hook) |hook| {
            if (hook(self, text)) return;
            return error.SystemClipboardUnavailable;
        }

        const command = switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos => "pbcopy",
            .windows => "clip",
            else => "wl-copy 2>/dev/null || xclip -selection clipboard 2>/dev/null || xsel --clipboard --input 2>/dev/null",
        };
        _ = try self.runCommandWithInput(command, text);
    }

    fn storeRegisterForYank(self: *App, bytes: []const u8, linewise: bool) !void {
        const value = if (linewise) self.normalizedLinewiseRegister(bytes) else bytes;
        try self.registers.setWithKind('"', value, linewise);
        try self.registers.setWithKind('0', value, linewise);
        if (self.pending_register) |reg| try self.registers.setWithKind(reg, value, linewise);
        if (self.pending_register) |reg| {
            if (clipboardRegisterKey(reg)) self.writeSystemClipboard(value) catch {
                try self.setStatus("clipboard unavailable");
            };
        }
    }

    fn storeRegisterForDelete(self: *App, bytes: []const u8, linewise: bool) !void {
        const value = if (linewise) self.normalizedLinewiseRegister(bytes) else bytes;
        try self.registers.setWithKind('"', value, linewise);
        if (self.pending_register) |reg| try self.registers.setWithKind(reg, value, linewise);
        if (self.pending_register) |reg| {
            if (clipboardRegisterKey(reg)) self.writeSystemClipboard(value) catch {
                try self.setStatus("clipboard unavailable");
            };
        }
    }

    fn pasteRegister(self: *App, before: bool) !void {
        try self.pasteRegisterKey(before, self.pending_register orelse '"');
        self.pending_register = null;
    }

    fn pasteRegisterKey(self: *App, before: bool, key: u8) !void {
        var clipboard_text: ?[]u8 = null;
        defer if (clipboard_text) |text| self.allocator.free(text);
        const value = if (self.registers.get(key)) |existing| existing else blk: {
            if (!clipboardRegisterKey(key)) {
                try self.setStatus("register empty");
                return;
            }
            const fetched = self.readSystemClipboard() catch {
                try self.setStatus("clipboard unavailable");
                return;
            };
            clipboard_text = fetched orelse {
                try self.setStatus("clipboard empty");
                return;
            };
            try self.registers.setWithKind(key, clipboard_text.?, false);
            break :blk clipboard_text.?;
        };
        if (self.registers.isLinewise(key)) {
            try self.activeBuffer().insertLinewiseText(before, value);
        } else {
            if (before) {
                try self.activeBuffer().insertTextAtCursor(value);
            } else {
                self.activeBuffer().moveRight();
                try self.activeBuffer().insertTextAtCursor(value);
            }
        }
    }

    fn joinCurrentLine(self: *App, with_space: bool) !void {
        const buf = self.activeBuffer();
        if (buf.cursor.row + 1 >= buf.lineCount()) return;
        const current = buf.lines.items[buf.cursor.row];
        const next = buf.lines.items[buf.cursor.row + 1];
        const sep = if (with_space and current.len > 0 and next.len > 0) " " else "";
        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ current, sep, next });
        self.allocator.free(buf.lines.items[buf.cursor.row]);
        self.allocator.free(buf.lines.items[buf.cursor.row + 1]);
        buf.lines.items[buf.cursor.row] = combined;
        _ = buf.lines.orderedRemove(buf.cursor.row + 1);
        buf.dirty = true;
    }

    fn showRegisters(self: *App) !void {
        const summary = try self.registers.formatSummary(self.allocator);
        defer self.allocator.free(summary);
        try self.setStatus(summary);
    }

    fn showPlugins(self: *App) !void {
        try self.ensurePluginsPane();
        try self.syncPluginPane();
        try self.setStatus("plugin catalog opened");
    }

    fn showReferenceHelp(self: *App) !void {
        try self.setStatus("help: :help keyword | :w | :wq | :q | :q! | :saveas PATH | :close | :terminal | :edit PATH | :open PATH | :bd | :bn | :bp | :buffer N|PATH | :buffers | :split PATH | :sp PATH | :vs PATH | :tabnew | :tabclose | :tabonly | :tabmove N | :refresh-sources | :lsp ACTION | :plugins | :vimgrep /pat/ [path] | :grep PAT [path] | :sort [u] | :!cmd | :cn | :cp | :cope | :ccl | :marks | :delmarks! | :zf | :za | :zo | :zc | :zE | :zr | :zm | :zi | :diffthis | :diffoff | :diffupdate | :diffget | :diffput | ]c/[c | syntax-aware a{/i{/a(/i( in Zig | n/N | * / # | m/'/` | Ctrl+u/d/i/o/^ | Ctrl+w s/v/n/q/x/+/-/</>/\\/|/_/=/T | leader x | :registers");
    }

    fn showHelpForCurrentWord(self: *App) !void {
        const word = self.activeBuffer().currentWord();
        if (word.len == 0) {
            try self.setStatus("no word under cursor");
            return;
        }
        if (!self.runInteractiveCommand(&.{ "man", word })) {
            try self.setStatus("man page not available");
        } else {
            try self.setStatus("returned from man");
        }
    }

    fn showMarks(self: *App) !void {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var any = false;
        for (self.marks, 0..) |mark, idx| {
            if (mark) |pos| {
                any = true;
                if (out.items.len > 0) try out.appendSlice(" | ");
                const piece = try std.fmt.allocPrint(self.allocator, "{c}:{d},{d}", .{ @as(u8, @intCast('a' + idx)), pos.row + 1, pos.col + 1 });
                defer self.allocator.free(piece);
                try out.appendSlice(piece);
            }
        }
        if (!any) try out.appendSlice("marks empty");
        const summary = try out.toOwnedSlice();
        defer self.allocator.free(summary);
        try self.setStatus(summary);
    }

    fn showJumps(self: *App) !void {
        try self.setStatus(try self.formatPositionList(&self.jump_history, "jumps empty"));
    }

    fn showChanges(self: *App) !void {
        try self.setStatus(try self.formatPositionList(&self.change_history, "changes empty"));
    }

    fn formatPositionList(self: *App, positions: *const std.array_list.Managed(buffer_mod.Position), empty_text: []const u8) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        if (positions.items.len == 0) {
            try out.appendSlice(empty_text);
            return try out.toOwnedSlice();
        }
        var count: usize = 0;
        var idx: usize = positions.items.len;
        while (idx > 0 and count < 8) : (count += 1) {
            idx -= 1;
            const pos = positions.items[idx];
            if (out.items.len > 0) try out.appendSlice(" | ");
            const piece = try std.fmt.allocPrint(self.allocator, "{d}:{d}", .{ pos.row + 1, pos.col + 1 });
            defer self.allocator.free(piece);
            try out.appendSlice(piece);
        }
        return try out.toOwnedSlice();
    }

    fn recordJump(self: *App, pos: buffer_mod.Position) !void {
        try self.jump_history.append(pos);
        self.jump_history_index = null;
    }

    fn recordChange(self: *App, pos: buffer_mod.Position) !void {
        try self.change_history.append(pos);
        self.change_jump_index = null;
        self.syncActiveSyntax();
        if (self.activeBuffer().path) |path| self.lsp.didChangePath(path) catch {};
    }

    fn actionIsEditing(action: NormalAction) bool {
        return switch (action) {
            .delete_char, .replace_char, .replace_mode, .substitute_char, .substitute_line, .insert_before, .insert_at_bol, .append_after, .append_eol, .open_below, .open_above, .insert_line_below, .insert_line_above, .delete_line, .yank_line, .yank_to_eol, .paste_after, .paste_before, .paste_after_keep_cursor, .paste_before_keep_cursor, .delete_word, .yank_word, .delete_to_eol, .change_word, .change_line, .change_to_eol, .join_line_space, .join_line_nospace, .indent_line, .dedent_line, .toggle_case_char, .toggle_case_word, .lowercase_word, .uppercase_word, .diff_get, .diff_put, .visual_yank, .visual_delete => true,
            else => false,
        };
    }

    fn actionIsRepeatableChange(action: NormalAction) bool {
        return switch (action) {
            .delete_char, .replace_char, .replace_mode, .substitute_char, .substitute_line, .insert_before, .insert_at_bol, .append_after, .append_eol, .open_below, .open_above, .insert_line_below, .insert_line_above, .delete_line, .paste_after, .paste_before, .paste_after_keep_cursor, .paste_before_keep_cursor, .delete_word, .delete_to_eol, .change_word, .change_line, .change_to_eol, .join_line_space, .join_line_nospace, .indent_line, .dedent_line, .toggle_case_char, .toggle_case_word, .lowercase_word, .uppercase_word, .diff_get, .diff_put, .visual_delete => true,
            else => false,
        };
    }

    fn syncViewportIfCursorMoved(self: *App, start_buffer: *buffer_mod.Buffer, start_cursor: buffer_mod.Position) void {
        const current_buffer = self.activeBuffer();
        if (current_buffer != start_buffer or current_buffer.cursor.row != start_cursor.row or current_buffer.cursor.col != start_cursor.col) {
            self.ensureCursorVisible();
        }
    }

    fn ensureCursorVisible(self: *App) void {
        const buf = self.activeBuffer();
        const line_count = buf.lineCount();
        if (line_count == 0) {
            buf.scroll_row = 0;
            return;
        }
        const height = self.last_render_height;
        if (height == 0 or height >= line_count) {
            buf.scroll_row = 0;
            return;
        }
        if (buf.cursor.row < buf.scroll_row) {
            buf.scroll_row = buf.cursor.row;
        } else if (buf.cursor.row >= buf.scroll_row + height) {
            buf.scroll_row = buf.cursor.row + 1 - height;
        }
        const max_scroll = line_count - height;
        if (buf.scroll_row > max_scroll) buf.scroll_row = max_scroll;
    }

    fn setViewport(self: *App, mode: enum { top, middle, bottom }) void {
        const buf = self.activeBuffer();
        const height = self.last_render_height;
        const line_count = buf.lineCount();
        const cursor_row = buf.cursor.row;
        const target = switch (mode) {
            .top => cursor_row,
            .middle => if (height > 0) cursor_row -| (height / 2) else cursor_row,
            .bottom => if (height > 0) cursor_row -| (height - 1) else cursor_row,
        };
        if (line_count == 0 or height == 0) {
            buf.scroll_row = 0;
            return;
        }
        const max_scroll = if (line_count > height) line_count - height else 0;
        buf.scroll_row = @min(target, max_scroll);
    }

    fn startMacroRecording(self: *App, key: u8) !void {
        const idx = macroIndex(key) orelse {
            try self.setStatus("macro register must be a-z");
            return;
        };
        if (self.macros[idx]) |existing| {
            self.allocator.free(existing);
            self.macros[idx] = null;
        }
        self.macro_recording = key;
        self.macro_ignore_next = true;
        try self.setStatus("macro recording");
        self.macros[idx] = try self.allocator.dupe(u8, "");
    }

    fn appendMacroByte(self: *App, byte: u8) !void {
        const key = self.macro_recording orelse return;
        const idx = macroIndex(key) orelse return;
        const current = self.macros[idx] orelse return;
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        try out.appendSlice(current);
        try out.append(byte);
        self.allocator.free(current);
        self.macros[idx] = try out.toOwnedSlice();
    }

    fn runMacro(self: *App, key: u8) anyerror!void {
        const idx = macroIndex(key) orelse {
            try self.setStatus("macro register must be a-z");
            return;
        };
        const seq = self.macros[idx] orelse {
            try self.setStatus("macro empty");
            return;
        };
        self.macro_playing = true;
        defer self.macro_playing = false;
        var i: usize = 0;
        while (i < seq.len) : (i += 1) {
            try self.handleNormalByte(seq[i]);
        }
    }

    fn macroIndex(key: u8) ?usize {
        if (key >= 'a' and key <= 'z') return key - 'a';
        if (key >= 'A' and key <= 'Z') return key - 'A';
        return null;
    }

    fn shiftCurrentLine(self: *App, right: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const start = buffer_mod.Position{ .row = buf.cursor.row, .col = 0 };
        const end = buffer_mod.Position{ .row = buf.cursor.row, .col = line.len };
        const width = self.config.tab_width * count;
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        if (right) {
            try out.appendNTimes(' ', width);
            try out.appendSlice(line);
        } else {
            var trim = line;
            var removed: usize = 0;
            while (removed < width and trim.len > 0 and trim[0] == ' ') : (removed += 1) {
                trim = trim[1..];
            }
            try out.appendSlice(trim);
        }
        try buf.replaceRangeWithText(start, end, try out.toOwnedSlice());
    }

    const CaseMode = enum { toggle, lower, upper };

    fn transformCurrentWord(self: *App, mode: CaseMode) !void {
        const buf = self.activeBuffer();
        const bounds = buf.wordBounds() orelse return;
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const word = try self.allocator.dupe(u8, text[self.positionToOffset(bounds.start, text)..self.positionToOffset(bounds.end, text)]);
        defer self.allocator.free(word);
        for (word) |*ch| {
            ch.* = switch (mode) {
                .toggle => toggleAsciiCase(ch.*),
                .lower => std.ascii.toLower(ch.*),
                .upper => std.ascii.toUpper(ch.*),
            };
        }
        try buf.replaceRangeWithText(bounds.start, bounds.end, word);
    }

    fn toggleCurrentCharacter(self: *App) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        if (buf.cursor.col >= line.len) return;
        var ch = line[buf.cursor.col];
        ch = toggleAsciiCase(ch);
        try buf.replaceCurrentCharacter(ch);
    }

    fn applyVisualIndent(self: *App, right: bool) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        const slice = text[start..end];
        const transformed = try self.indentBlock(slice, right);
        defer self.allocator.free(transformed);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, transformed);
        self.exitVisual();
    }

    fn applyVisualCase(self: *App, mode: CaseMode) !void {
        const selection = self.visualSelection() orelse return self.setStatus("no selection");
        const text = try self.activeBuffer().serialize();
        defer self.allocator.free(text);
        const start = self.positionToOffset(selection.start, text);
        const end = self.positionToOffset(selection.end, text);
        const piece = try self.allocator.dupe(u8, text[start..end]);
        defer self.allocator.free(piece);
        for (piece) |*ch| {
            ch.* = switch (mode) {
                .toggle => toggleAsciiCase(ch.*),
                .lower => std.ascii.toLower(ch.*),
                .upper => std.ascii.toUpper(ch.*),
            };
        }
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, piece);
        self.exitVisual();
    }

    fn indentBlock(self: *App, slice: []const u8, right: bool) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var lines = std.mem.splitScalar(u8, slice, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (!first) try out.append('\n');
            first = false;
            if (right) {
                try out.appendNTimes(' ', self.config.tab_width);
                try out.appendSlice(line);
            } else {
                var trimmed = line;
                var removed: usize = 0;
                while (removed < self.config.tab_width and trimmed.len > 0 and trimmed[0] == ' ') : (removed += 1) {
                    trimmed = trimmed[1..];
                }
                try out.appendSlice(trimmed);
            }
        }
        return try out.toOwnedSlice();
    }

    fn toggleAsciiCase(byte: u8) u8 {
        if (std.ascii.isUpper(byte)) return std.ascii.toLower(byte);
        if (std.ascii.isLower(byte)) return std.ascii.toUpper(byte);
        return byte;
    }

    fn closeCurrentPane(self: *App) !void {
        if (self.activeBuffer().dirty) {
            try self.setStatus("buffer modified, save first or use :q!");
            return;
        }
        self.disableDiffMode();
        var closed_path: ?[]const u8 = self.activeBuffer().path;
        var closed_buffer_id: u64 = self.activeBuffer().id;
        if (self.split_index) |idx| {
            if (self.split_focus == .right) {
                closed_path = self.buffers.items[idx].path;
                closed_buffer_id = self.buffers.items[idx].id;
                self.buffers.items[idx].deinit();
                _ = self.buffers.orderedRemove(idx);
            } else {
                closed_path = self.buffers.items[self.active_index].path;
                closed_buffer_id = self.buffers.items[self.active_index].id;
                self.buffers.items[self.active_index].deinit();
                _ = self.buffers.orderedRemove(self.active_index);
            }
            self.split_index = null;
            self.split_focus = .left;
            if (closed_path) |path| {
                self.lsp.didClosePath(path) catch {};
                self.lsp.clearPath(path);
            }
            self.syntax.clearBuffer(closed_buffer_id);
            if (self.buffers.items.len == 0) {
                try self.buffers.append(try buffer_mod.Buffer.initEmpty(self.allocator));
            }
            self.active_index = 0;
            self.workspace.noteSessionChange();
            try self.refreshDerivedSources();
            try self.setStatus("pane closed");
            return;
        }
        if (self.buffers.items.len > 1) {
            self.buffers.items[self.active_index].deinit();
            _ = self.buffers.orderedRemove(self.active_index);
        } else {
            self.buffers.items[0].deinit();
            self.buffers.items[0] = try buffer_mod.Buffer.initEmpty(self.allocator);
        }
        if (closed_path) |path| self.lsp.didClosePath(path) catch {};
        if (closed_path) |path| self.lsp.clearPath(path);
        self.syntax.clearBuffer(closed_buffer_id);
        self.active_index = 0;
        self.workspace.noteSessionChange();
        try self.refreshDerivedSources();
        try self.setStatus("buffer closed");
    }

    fn requestCloseConfirm(self: *App) !void {
        const target = self.closeConfirmTarget();
        self.close_confirm = target;
        try self.setStatus(self.closeConfirmPrompt(target));
    }

    fn executeCloseConfirm(self: *App, target: CloseTarget) !void {
        switch (target) {
            .split => try self.closeCurrentPane(),
            .tab => try self.tabCloseCurrent(),
            .buffer => try self.closeCurrentPane(),
        }
    }

    fn closeConfirmTarget(self: *const App) CloseTarget {
        if (self.split_index != null) return .split;
        if (self.buffers.items.len > 1) return .tab;
        return .buffer;
    }

    fn closeConfirmPrompt(self: *const App, target: CloseTarget) []const u8 {
        _ = self;
        return switch (target) {
            .split => "close split? [y/N]",
            .tab => "close tab? [y/N]",
            .buffer => "close buffer? [y/N]",
        };
    }

    fn focusedBufferIndex(self: *const App) usize {
        if (self.split_index) |idx| {
            return switch (self.split_focus) {
                .left => self.active_index,
                .right => idx,
            };
        }
        return self.active_index;
    }

    fn focusBufferIndex(self: *App, index: usize) void {
        const current = self.focusedBufferIndex();
        if (current != index) self.previous_active_index = current;
        if (self.split_index != null and self.split_focus == .right) {
            self.split_index = index;
        } else {
            self.active_index = index;
        }
    }

    fn switchFocusedBuffer(self: *App, forward: bool, count: usize) !void {
        if (self.buffers.items.len <= 1) return;
        var index = self.focusedBufferIndex();
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            index = if (forward)
                (index + 1) % self.buffers.items.len
            else
                (index + self.buffers.items.len - 1) % self.buffers.items.len;
        }
        self.focusBufferIndex(index);
    }

    fn openNewTab(self: *App, path: ?[]const u8) !void {
        if (path) |actual| {
            try self.openPath(actual);
            return;
        }
        self.disableDiffMode();
        const buf = try buffer_mod.Buffer.initEmpty(self.allocator);
        try self.buffers.append(buf);
        self.focusBufferIndex(self.buffers.items.len - 1);
        self.emitBuiltinEvent("buffer_open", "{}");
    }

    fn cloneActiveBuffer(self: *App) !buffer_mod.Buffer {
        const src = self.activeBuffer();
        var clone = try buffer_mod.Buffer.initEmpty(self.allocator);
        errdefer clone.deinit();
        const text = try src.serialize();
        defer self.allocator.free(text);
        try clone.setText(text);
        if (src.path) |path| try clone.replacePath(path);
        clone.cursor = src.cursor;
        clone.scroll_row = src.scroll_row;
        clone.dirty = src.dirty;
        clone.fold_enabled = src.fold_enabled;
        for (src.folds.items) |fold| {
            try clone.folds.append(fold);
        }
        return clone;
    }

    fn openSplitFromCurrentBuffer(self: *App) !void {
        self.disableDiffMode();
        const clone = try self.cloneActiveBuffer();
        if (self.split_index) |idx| {
            self.buffers.items[idx].deinit();
            self.buffers.items[idx] = clone;
        } else {
            try self.buffers.append(clone);
            self.split_index = self.buffers.items.len - 1;
        }
        self.split_focus = .right;
        self.emitBuiltinEvent("buffer_open", "{}");
    }

    fn openNewWindow(self: *App) !void {
        self.disableDiffMode();
        const buf = try buffer_mod.Buffer.initEmpty(self.allocator);
        if (self.split_index) |idx| {
            self.buffers.items[idx].deinit();
            self.buffers.items[idx] = buf;
        } else {
            try self.buffers.append(buf);
            self.split_index = self.buffers.items.len - 1;
        }
        self.split_focus = .right;
        self.emitBuiltinEvent("buffer_open", "{}");
        try self.setStatus("new window");
    }

    fn splitToTab(self: *App) !void {
        if (self.split_index == null) {
            try self.setStatus("no split to move");
            return;
        }
        self.disableDiffMode();
        const clone = try self.cloneActiveBuffer();
        try self.buffers.append(clone);
        self.split_index = null;
        self.split_focus = .left;
        self.active_index = self.buffers.items.len - 1;
        self.emitBuiltinEvent("buffer_open", "{}");
        try self.setStatus("split moved to tab");
    }

    fn openSplitOrClone(self: *App, path: []const u8) !void {
        if (path.len == 0) {
            try self.openSplitFromCurrentBuffer();
        } else {
            try self.openSplit(path);
        }
    }

    fn focusWindow(self: *App, side: SplitFocus) void {
        if (self.split_index == null) return;
        self.split_focus = side;
    }

    fn exchangeFocusedBuffers(self: *App) !void {
        const other_index = self.split_index orelse {
            try self.setStatus("no other window");
            return;
        };
        self.disableDiffMode();
        const current_index = self.focusedBufferIndex();
        if (current_index == other_index) return;
        std.mem.swap(buffer_mod.Buffer, &self.buffers.items[current_index], &self.buffers.items[other_index]);
        if (self.active_index == current_index) {
            self.active_index = other_index;
        } else if (self.active_index == other_index) {
            self.active_index = current_index;
        }
        if (self.split_index) |*idx| {
            if (idx.* == current_index) {
                idx.* = other_index;
            } else if (idx.* == other_index) {
                idx.* = current_index;
            }
        }
        try self.setStatus("windows exchanged");
    }

    fn selectBufferByArgument(self: *App, arg: []const u8) !void {
        const parsed = std.fmt.parseInt(usize, arg, 10) catch null;
        if (parsed) |num| {
            if (num == 0 or num > self.buffers.items.len) {
                try self.setStatus("buffer index out of range");
                return;
            }
            self.focusBufferIndex(num - 1);
            return;
        }
        for (self.buffers.items, 0..) |buf, idx| {
            if (buf.path) |path| {
                if (std.mem.eql(u8, path, arg)) {
                    self.focusBufferIndex(idx);
                    return;
                }
            }
        }
        try self.setStatus("buffer not found");
    }

    fn showBuffers(self: *App) !void {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        for (self.buffers.items, 0..) |buf, idx| {
            if (idx > 0) try out.appendSlice(" | ");
            if (idx == self.active_index or (self.split_index != null and self.split_index.? == idx and self.split_focus == .right)) {
                try out.appendSlice("*");
            } else {
                try out.appendSlice(" ");
            }
            const name = buf.path orelse "[No Name]";
            const piece = try std.fmt.allocPrint(self.allocator, "{d}:{s}", .{ idx + 1, name });
            defer self.allocator.free(piece);
            try out.appendSlice(piece);
        }
        if (self.buffers.items.len == 0) try out.appendSlice("buffers empty");
        const summary = try out.toOwnedSlice();
        defer self.allocator.free(summary);
        try self.setStatus(summary);
    }

    fn enableDiffMode(self: *App) !void {
        if (self.buffers.items.len <= 1) {
            try self.setStatus("no diff peer available");
            return;
        }
        const current = self.focusedBufferIndex();
        const fallback: usize = if (current == 0) 1 else 0;
        const peer: usize = if (self.split_index) |idx| if (idx != current) idx else fallback else fallback;
        if (peer >= self.buffers.items.len or peer == current) {
            try self.setStatus("no diff peer available");
            return;
        }
        self.diff_mode = true;
        self.diff_peer_index = peer;
        try self.updateDiffSummary();
    }

    fn disableDiffMode(self: *App) void {
        self.diff_mode = false;
        self.diff_peer_index = null;
    }

    fn diffPeerBuffer(self: *App) ?*buffer_mod.Buffer {
        const idx = self.diff_peer_index orelse return null;
        if (idx >= self.buffers.items.len) return null;
        return &self.buffers.items[idx];
    }

    fn updateDiffSummary(self: *App) !void {
        const peer = self.diffPeerBuffer() orelse {
            try self.setStatus("diff off");
            return;
        };
        const active = self.activeBuffer();
        const msg = try std.fmt.allocPrint(self.allocator, "diff on with {d} vs {d} lines", .{ active.lineCount(), peer.lineCount() });
        defer self.allocator.free(msg);
        try self.setStatus(msg);
    }

    fn diffGet(self: *App) !void {
        const peer = self.diffPeerBuffer() orelse {
            try self.setStatus("no diff peer");
            return;
        };
        const row = self.activeBuffer().cursor.row;
        if (row >= peer.lineCount()) {
            try self.setStatus("no corresponding line");
            return;
        }
        const text = peer.lines.items[row];
        try self.activeBuffer().replaceLine(row, text);
        try self.setStatus("diff got");
    }

    fn diffPut(self: *App) !void {
        const peer = self.diffPeerBuffer() orelse {
            try self.setStatus("no diff peer");
            return;
        };
        const row = self.activeBuffer().cursor.row;
        if (row >= peer.lineCount()) {
            try self.setStatus("no corresponding line");
            return;
        }
        const text = self.activeBuffer().lines.items[row];
        try peer.replaceLine(row, text);
        try self.setStatus("diff put");
    }

    fn jumpChangeHistory(self: *App, forward: bool) !void {
        if (self.change_history.items.len == 0) {
            try self.setStatus("changes empty");
            return;
        }
        const len = self.change_history.items.len;
        var index = self.change_jump_index orelse if (forward) len - 1 else 0;
        if (forward) {
            index = (index + 1) % len;
        } else if (index == 0) {
            index = len - 1;
        } else {
            index -= 1;
        }
        self.change_jump_index = index;
        const pos = self.change_history.items[index];
        self.activeBuffer().cursor = pos;
    }

    fn jumpHistory(self: *App, forward: bool, count: usize) !void {
        if (self.jump_history.items.len == 0) {
            try self.setStatus("jumps empty");
            return;
        }
        const len = self.jump_history.items.len;
        var index = self.jump_history_index orelse if (forward) len - 1 else 0;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (forward) {
                index = @min(index + 1, len - 1);
            } else if (index == 0) {
                index = 0;
            } else {
                index -= 1;
            }
        }
        self.jump_history_index = index;
        self.activeBuffer().cursor = self.jump_history.items[index];
    }

    fn togglePreviousBuffer(self: *App) void {
        const prev = self.previous_active_index orelse return;
        const current = self.focusedBufferIndex();
        if (prev >= self.buffers.items.len or prev == current) return;
        self.focusBufferIndex(prev);
        self.previous_active_index = current;
    }

    fn moveSentence(self: *App, forward: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        var offset = self.positionToOffset(buf.cursor, text);
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            offset = self.nextSentenceOffset(text, offset, forward) orelse if (forward) text.len else 0;
        }
        buf.cursor = self.offsetToPosition(text, offset);
    }

    fn nextSentenceOffset(self: *App, text: []const u8, offset: usize, forward: bool) ?usize {
        _ = self;
        if (text.len == 0) return null;
        if (forward) {
            var idx = @min(offset + 1, text.len);
            while (idx < text.len) : (idx += 1) {
                if (text[idx] == '.' or text[idx] == '!' or text[idx] == '?') {
                    var next = idx + 1;
                    while (next < text.len and std.ascii.isWhitespace(text[next])) : (next += 1) {}
                    return next;
                }
            }
            return null;
        }
        if (offset == 0) return 0;
        var idx = offset - 1;
        while (true) {
            if (text[idx] == '.' or text[idx] == '!' or text[idx] == '?') {
                var start = idx;
                while (start > 0 and std.ascii.isWhitespace(text[start - 1])) : (start -= 1) {}
                while (start > 0 and text[start - 1] != '.' and text[start - 1] != '!' and text[start - 1] != '?') : (start -= 1) {}
                while (start < text.len and std.ascii.isWhitespace(text[start])) : (start += 1) {}
                return start;
            }
            if (idx == 0) break;
            idx -= 1;
        }
        return null;
    }

    fn scrollViewport(self: *App, down: bool, count: usize) !void {
        const buf = self.activeBuffer();
        const step = @max(@as(usize, 1), self.last_render_height / 2);
        const amount = step * count;
        const height = self.last_render_height;
        const max_scroll = if (buf.lineCount() > height) buf.lineCount() - height else 0;
        if (down) {
            buf.scroll_row = @min(buf.scroll_row +| amount, max_scroll);
        } else {
            buf.scroll_row = buf.scroll_row -| amount;
        }
    }

    fn setMark(self: *App, mark: u8) !void {
        const idx = markIndex(mark) orelse {
            try self.setStatus("mark must be a-z or A-Z");
            return;
        };
        self.marks[idx] = self.activeBuffer().cursor;
        try self.setStatus("mark set");
    }

    fn jumpMark(self: *App, mark: u8, exact: bool) !void {
        const idx = markIndex(mark) orelse {
            try self.setStatus("mark must be a-z or A-Z");
            return;
        };
        const pos = self.marks[idx] orelse {
            try self.setStatus("mark not set");
            return;
        };
        self.activeBuffer().cursor = if (exact) pos else .{ .row = pos.row, .col = 0 };
    }

    fn markIndex(mark: u8) ?usize {
        if (mark >= 'a' and mark <= 'z') return mark - 'a';
        if (mark >= 'A' and mark <= 'Z') return mark - 'A';
        return null;
    }

    fn searchWordUnderCursor(self: *App, forward: bool) !void {
        const buf = self.activeBuffer();
        const bounds = buf.wordBounds() orelse {
            try self.setStatus("no word under cursor");
            return;
        };
        const word = try self.selectedText(bounds.start, bounds.end);
        defer self.allocator.free(word);
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = if (forward)
            self.positionToOffset(bounds.end, text)
        else
            self.positionToOffset(bounds.start, text);
        const found = if (forward)
            findWordOccurrence(text, word, cursor_offset, true)
        else
            findWordOccurrence(text, word, cursor_offset, false);
        if (found) |offset| {
            self.search_forward = forward;
            try self.updateSearchHighlight(&self.search_highlight, word);
            buf.cursor = self.offsetToPosition(text, offset);
        } else {
            try self.setStatus("word not found");
        }
    }

    fn repeatSearch(self: *App, forward: bool) !void {
        const needle = self.activeSearchHighlight(true) orelse {
            try self.setStatus("no search term");
            return;
        };
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const actual_forward = if (forward) self.search_forward else !self.search_forward;
        const found = findSubstringOccurrence(text, needle, cursor_offset, actual_forward);
        if (found) |offset| {
            buf.cursor = self.offsetToPosition(text, offset);
        } else {
            try self.setStatus("not found");
        }
        self.search_forward = actual_forward;
    }

    fn openCursorPath(self: *App, link: bool) !void {
        const token = self.pathTokenUnderCursor(link);
        if (token.len == 0) {
            try self.setStatus("no path under cursor");
            return;
        }
        if (link and (std.mem.startsWith(u8, token, "http://") or std.mem.startsWith(u8, token, "https://"))) {
            if (!self.openExternalLink(token)) {
                try self.setStatus("link opener unavailable");
            } else {
                try self.setStatus("opened link");
            }
            return;
        }
        try self.openPath(token);
    }

    fn pathTokenUnderCursor(self: *App, allow_url: bool) []const u8 {
        const line = self.activeBuffer().currentLine();
        if (line.len == 0) return line;
        const cursor = @min(self.activeBuffer().cursor.col, line.len);
        const is_path_char = struct {
            fn f(byte: u8, url: bool) bool {
                return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == '.' or byte == '/' or byte == '~' or byte == ':' or byte == '?' or byte == '#' or byte == '=' or byte == '&' or byte == '%' or byte == '+' or byte == '@' or (url and byte == ':');
            }
        }.f;
        var start = cursor;
        if (start == line.len and start > 0) start -= 1;
        while (start > 0 and is_path_char(line[start - 1], allow_url)) : (start -= 1) {}
        var end = cursor;
        while (end < line.len and is_path_char(line[end], allow_url)) : (end += 1) {}
        return line[start..end];
    }

    fn openExternalLink(self: *App, url: []const u8) bool {
        const argv = switch (builtin.os.tag) {
            .windows => &[_][]const u8{ "cmd.exe", "/C", "start", "", url },
            .macos => &[_][]const u8{ "open", url },
            else => &[_][]const u8{ "xdg-open", url },
        };
        return self.runInteractiveCommand(argv);
    }

    const SubstituteSpec = struct {
        pattern: []u8,
        replacement: []u8,
        global: bool,

        fn deinit(self: *const SubstituteSpec, allocator: std.mem.Allocator) void {
            allocator.free(self.pattern);
            allocator.free(self.replacement);
        }
    };

    fn tryExecuteSubstitute(self: *App, command: []const u8, has_visual_range: bool) !bool {
        const spec = if (command.len > 0 and command[0] == '%')
            self.parseSubstituteSpec(command[1..]) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return false,
            }
        else if (command.len > 0 and command[0] == 's')
            self.parseSubstituteSpec(command) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return false,
            }
        else
            return false;

        if (spec == null) return false;
        defer spec.?.deinit(self.allocator);

        if (spec.?.pattern.len == 0) {
            try self.setStatus("substitute requires a pattern");
            return true;
        }

        if (command[0] == '%') {
            try self.substituteWholeDocument(spec.?);
        } else if (has_visual_range) {
            try self.substituteVisualSelection(spec.?);
        } else {
            try self.substituteCurrentLine(spec.?);
        }
        return true;
    }

    fn parseSubstituteSpec(self: *App, command: []const u8) !?SubstituteSpec {
        if (command.len < 3 or command[0] != 's') return null;
        const delim = command[1];
        const pattern_end = self.findSubstituteSegmentEnd(command, 2, delim) orelse return null;
        const replacement_start = pattern_end + 1;
        const replacement_end = self.findSubstituteSegmentEnd(command, replacement_start, delim) orelse return null;
        const flags = if (replacement_end + 1 < command.len) command[replacement_end + 1 ..] else "";
        return .{
            .pattern = try self.unescapeSubstituteSegment(command[2..pattern_end], delim),
            .replacement = try self.unescapeSubstituteSegment(command[replacement_start..replacement_end], delim),
            .global = std.mem.indexOfScalar(u8, flags, 'g') != null,
        };
    }

    fn findSubstituteSegmentEnd(self: *App, command: []const u8, start: usize, delim: u8) ?usize {
        _ = self;
        var idx = start;
        while (idx < command.len) : (idx += 1) {
            if (command[idx] == delim and (idx == start or command[idx - 1] != '\\')) return idx;
        }
        return null;
    }

    fn unescapeSubstituteSegment(self: *App, segment: []const u8, delim: u8) ![]u8 {
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var idx: usize = 0;
        while (idx < segment.len) {
            if (segment[idx] == '\\' and idx + 1 < segment.len and (segment[idx + 1] == delim or segment[idx + 1] == '\\')) {
                try out.append(segment[idx + 1]);
                idx += 2;
                continue;
            }
            try out.append(segment[idx]);
            idx += 1;
        }
        return try out.toOwnedSlice();
    }

    fn substituteWholeDocument(self: *App, spec: SubstituteSpec) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const replaced = try self.substituteText(text, spec);
        defer self.allocator.free(replaced);
        const end_row = buf.lines.items.len - 1;
        try buf.replaceRangeWithText(.{ .row = 0, .col = 0 }, .{ .row = end_row, .col = buf.lines.items[end_row].len }, replaced);
        try self.setStatus("substituted");
    }

    fn substituteCurrentLine(self: *App, spec: SubstituteSpec) !void {
        const buf = self.activeBuffer();
        const line = buf.currentLine();
        const replaced = try self.substituteText(line, spec);
        defer self.allocator.free(replaced);
        const row = buf.cursor.row;
        try buf.replaceRangeWithText(.{ .row = row, .col = 0 }, .{ .row = row, .col = line.len }, replaced);
        try self.setStatus("substituted");
    }

    fn substituteVisualSelection(self: *App, spec: SubstituteSpec) !void {
        const selection = self.visualSelection() orelse {
            try self.setStatus("no selection");
            return;
        };
        const input = try self.selectedText(selection.start, selection.end);
        defer self.allocator.free(input);
        const replaced = try self.substituteText(input, spec);
        defer self.allocator.free(replaced);
        try self.activeBuffer().replaceRangeWithText(selection.start, selection.end, replaced);
        self.exitVisual();
        try self.setStatus("substituted");
    }

    fn substituteText(self: *App, input: []const u8, spec: SubstituteSpec) ![]u8 {
        if (spec.pattern.len == 0) return try self.allocator.dupe(u8, input);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var changed: usize = 0;
        var lines = std.mem.splitScalar(u8, input, '\n');
        var first_line = true;
        while (lines.next()) |line| {
            if (!first_line) try out.append('\n');
            first_line = false;
            const replaced = try self.replaceLiteralInLine(line, spec.pattern, spec.replacement, spec.global, &changed);
            defer self.allocator.free(replaced);
            try out.appendSlice(replaced);
        }
        if (changed == 0) return try self.allocator.dupe(u8, input);
        return try out.toOwnedSlice();
    }

    fn replaceLiteralInLine(self: *App, line: []const u8, needle: []const u8, replacement: []const u8, global: bool, changed: *usize) ![]u8 {
        if (needle.len == 0) return try self.allocator.dupe(u8, line);
        var out = std.array_list.Managed(u8).init(self.allocator);
        errdefer out.deinit();
        var idx: usize = 0;
        var replaced_once = false;
        while (idx <= line.len) {
            const hit = std.mem.indexOfPos(u8, line, idx, needle) orelse break;
            try out.appendSlice(line[idx..hit]);
            try out.appendSlice(replacement);
            changed.* += 1;
            idx = hit + needle.len;
            replaced_once = true;
            if (!global) break;
        }
        if (!replaced_once) return try self.allocator.dupe(u8, line);
        try out.appendSlice(line[idx..]);
        return try out.toOwnedSlice();
    }

    fn deleteInsertPreviousWord(self: *App) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const end = self.positionToOffset(buf.cursor, text);
        var start = end;
        while (start > 0 and std.ascii.isWhitespace(text[start - 1])) : (start -= 1) {}
        while (start > 0 and !std.ascii.isWhitespace(text[start - 1])) : (start -= 1) {}
        if (start == end) return;
        const start_pos = self.offsetToPosition(text, start);
        try buf.replaceRangeWithText(start_pos, buf.cursor, "");
    }

    fn findSubstringOccurrence(text: []const u8, needle: []const u8, start_offset: usize, forward: bool) ?usize {
        if (needle.len == 0 or text.len < needle.len) return null;
        if (forward) {
            var idx = @min(start_offset + 1, text.len);
            while (idx + needle.len <= text.len) : (idx += 1) {
                if (std.mem.eql(u8, text[idx .. idx + needle.len], needle)) return idx;
            }
            return null;
        }
        var idx = @min(start_offset, text.len);
        while (idx > 0) : (idx -= 1) {
            if (idx >= needle.len and std.mem.eql(u8, text[idx - needle.len .. idx], needle)) return idx - needle.len;
        }
        return null;
    }

    fn repeatLastCommand(self: *App) anyerror!void {
        const repeatable = self.last_repeatable_edit orelse {
            try self.setStatus("no repeatable command");
            return;
        };
        switch (repeatable) {
            .action => |entry| try self.performNormalAction(entry.action, entry.count),
            .operator => |recipe| try self.performOperatorRecipe(recipe),
        }
    }

    fn createFoldAtCursor(self: *App) !void {
        const buf = self.activeBuffer();
        const snapshot = buf.readSnapshot(null) catch {
            try buf.createParagraphFold();
            try self.setStatus("fold created");
            return;
        };
        defer buf.freeReadSnapshot(snapshot);
        if (self.syntax.foldRangeForSnapshot(snapshot)) |range| {
            try buf.createFoldRange(range.start_row, range.end_row);
        } else {
            try buf.createParagraphFold();
        }
        self.syntax.updateSnapshot(snapshot) catch {};
        try self.setStatus("fold created");
    }

    fn deleteFoldAtCursor(self: *App) void {
        if (self.activeBuffer().deleteFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold deleted") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn toggleFoldAtCursor(self: *App) void {
        if (self.activeBuffer().toggleFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold toggled") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn openFoldAtCursor(self: *App) void {
        if (self.activeBuffer().openFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold opened") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn closeFoldAtCursor(self: *App) void {
        if (self.activeBuffer().closeFoldAtRow(self.activeBuffer().cursor.row)) {
            self.setStatus("fold closed") catch {};
        } else {
            self.setStatus("no fold") catch {};
        }
    }

    fn clearQuickfix(self: *App) void {
        self.quickfix_list.clear();
    }

    fn showQuickfix(self: *App) !void {
        if (self.quickfix_list.items.items.len == 0) {
            try self.setStatus("quickfix empty");
            return;
        }
        const entry = self.quickfix_list.selectedItem() orelse return;
        const msg = try std.fmt.allocPrint(self.allocator, "{d}/{d} {s}:{d}:{d} {s}", .{
            @min(self.quickfix_list.selected + 1, self.quickfix_list.items.items.len),
            self.quickfix_list.items.items.len,
            entry.path orelse "[missing]",
            entry.row + 1,
            entry.col + 1,
            entry.detail orelse "",
        });
        defer self.allocator.free(msg);
        try self.setStatus(msg);
    }

    fn quickfixNext(self: *App) !void {
        if (self.quickfix_list.items.items.len == 0) {
            try self.setStatus("quickfix empty");
            return;
        }
        self.quickfix_list.moveSelection(1);
        try self.openQuickfixEntry(self.quickfix_list.selectedItem() orelse return);
    }

    fn quickfixPrev(self: *App) !void {
        if (self.quickfix_list.items.items.len == 0) {
            try self.setStatus("quickfix empty");
            return;
        }
        self.quickfix_list.moveSelection(-1);
        try self.openQuickfixEntry(self.quickfix_list.selectedItem() orelse return);
    }

    fn openQuickfixEntry(self: *App, entry: listpane_mod.Item) !void {
        const path = entry.path orelse return;
        try self.openOrFocusPath(path);
        const buf = self.activeBuffer();
        buf.cursor = .{ .row = entry.row, .col = entry.col };
        try self.setStatus("quickfix jump");
    }

    fn openOrFocusPath(self: *App, path: []const u8) !void {
        for (self.buffers.items, 0..) |buf, idx| {
            if (buf.path) |current| {
                if (std.mem.eql(u8, current, path)) {
                    self.focusBufferIndex(idx);
                    return;
                }
            }
        }
        try self.openPath(path);
    }

    fn runQuickfixSearch(self: *App, tail: []const u8) !void {
        const spec = std.mem.trim(u8, tail, " \t");
        const parsed = parseQuickfixSpec(spec) orelse {
            try self.setStatus("use :vimgrep /pattern/ [path]");
            return;
        };
        self.clearQuickfix();
        const source_spec = listsource_mod.specForCommand("vimgrep").?;
        try self.runPickerSource(source_spec, parsed.pattern, parsed.pathspec);
        if (self.quickfix_list.items.items.len == 0) {
            try self.setStatus("no matches");
            return;
        }
        self.quickfix_list.selected = 0;
        try self.showQuickfix();
    }

    fn runProjectSearch(self: *App, tail: []const u8) !void {
        const spec = std.mem.trim(u8, tail, " \t");
        if (spec.len == 0) {
            try self.setStatus("grep requires a pattern");
            return;
        }
        const split = std.mem.indexOfScalar(u8, spec, ' ');
        const pattern = if (split) |idx| spec[0..idx] else spec;
        const pathspec = if (split) |idx| std.mem.trim(u8, spec[idx + 1 ..], " \t") else "";
        self.clearQuickfix();
        const source_spec = listsource_mod.specForCommand("grep").?;
        try self.runPickerSource(source_spec, pattern, pathspec);
        if (self.quickfix_list.items.items.len == 0) {
            try self.setStatus("no matches");
            return;
        }
        self.quickfix_list.selected = 0;
        try self.showQuickfix();
    }

    fn runPickerSearch(self: *App, tail: []const u8) !void {
        const spec = std.mem.trim(u8, tail, " \t");
        if (spec.len == 0) {
            try self.setStatus("pickgrep requires a pattern");
            return;
        }
        const split = std.mem.indexOfScalar(u8, spec, ' ');
        const pattern = if (split) |idx| spec[0..idx] else spec;
        const pathspec = if (split) |idx| std.mem.trim(u8, spec[idx + 1 ..], " \t") else "";
        try self.runPickerSource(.{ .command = "pickgrep", .kind = .search, .title = "picker", .emit_quickfix = true }, pattern, pathspec);
    }

    fn sortCurrentBuffer(self: *App, tail: []const u8) !void {
        const unique = std.mem.containsAtLeast(u8, tail, 1, "u");
        const buf = self.activeBuffer();
        if (buf.lines.items.len == 0) return;
        var lines = std.array_list.Managed([]u8).init(self.allocator);
        defer lines.deinit();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            try lines.append(try self.allocator.dupe(u8, line));
        }
        const Cmp = struct {
            fn lessThan(_: void, a: []u8, b: []u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        };
        std.mem.sort([]u8, lines.items, {}, Cmp.lessThan);
        if (unique and lines.items.len > 1) {
            var write_idx: usize = 1;
            var read_idx: usize = 1;
            while (read_idx < lines.items.len) : (read_idx += 1) {
                if (!std.mem.eql(u8, lines.items[read_idx], lines.items[write_idx - 1])) {
                    lines.items[write_idx] = lines.items[read_idx];
                    write_idx += 1;
                } else {
                    self.allocator.free(lines.items[read_idx]);
                }
            }
            lines.items.len = write_idx;
        }
        defer {
            for (lines.items) |line| self.allocator.free(line);
        }
        var out = std.array_list.Managed(u8).init(self.allocator);
        defer out.deinit();
        for (lines.items, 0..) |line, idx| {
            if (idx > 0) try out.append('\n');
            try out.appendSlice(line);
        }
        const sorted = try out.toOwnedSlice();
        defer self.allocator.free(sorted);
        try buf.setText(sorted);
        try self.setStatus("sorted");
    }

    fn runBangCommand(self: *App, tail: []const u8) !void {
        const cmd = std.mem.trim(u8, tail, " \t");
        if (cmd.len == 0) {
            try self.setStatus("bang command requires a shell command");
            return;
        }
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const path = buf.path orelse "";
        var command = std.array_list.Managed(u8).init(self.allocator);
        defer command.deinit();
        var idx: usize = 0;
        while (idx < cmd.len) {
            if (cmd[idx] == '%' and idx + 1 <= cmd.len) {
                try command.appendSlice(path);
                idx += 1;
                continue;
            }
            try command.append(cmd[idx]);
            idx += 1;
        }
        const output = try self.runCommandWithInput(command.items, text);
        defer self.allocator.free(output);
        const summary = trimTrailingNewline(output);
        if (summary.len == 0) {
            try self.setStatus("command complete");
        } else {
            try self.setStatus(summary);
        }
    }

    const QuickfixSpec = struct {
        pattern: []const u8,
        pathspec: []const u8,
    };

    const SearchCollector = struct {
        app: *App,
        source: listsource_mod.AsyncListSource,
        emit_quickfix: bool,
        request_key: listsource_mod.SourceKey = .{},

        fn init(app: *App, kind: listsource_mod.SourceKind, emit_quickfix: bool) SearchCollector {
            return .{
                .app = app,
                .source = listsource_mod.AsyncListSource.init(app.allocator, kind),
                .emit_quickfix = emit_quickfix,
            };
        }

        fn deinit(self: *SearchCollector) void {
            self.source.deinit();
        }

        fn emit(ctx: *anyopaque, result: search_mod.SearchResult) anyerror!void {
            const self: *SearchCollector = @ptrCast(@alignCast(ctx));
            defer result.deinit(self.app.allocator);
            if (self.emit_quickfix and result.kind == .match) {
                try self.app.appendQuickfixMatch(result.path, result.row, result.col, result.line);
            }
            try self.emitListItem(.{
                .id = self.source.items.items.len + 1,
                .path = try self.app.allocator.dupe(u8, result.path),
                .row = result.row,
                .col = result.col,
                .label = try std.fmt.allocPrint(self.app.allocator, "{s}:{d}:{d}", .{ result.path, result.row + 1, result.col + 1 }),
                .detail = try self.app.allocator.dupe(u8, result.line),
                .score = @intCast(result.line.len),
            });
        }

        fn emitListItem(self: *SearchCollector, item: listpane_mod.Item) !void {
            self.source.append(self.request_key, item) catch |err| switch (err) {
                error.StaleSource, error.Canceled => return,
                else => return err,
            };
        }

        fn emitListItemOpaque(ctx: *anyopaque, item: listpane_mod.Item) anyerror!void {
            const self: *SearchCollector = @ptrCast(@alignCast(ctx));
            try self.emitListItem(item);
        }
    };

    fn parseQuickfixSpec(spec: []const u8) ?QuickfixSpec {
        if (spec.len == 0 or spec[0] != '/') return null;
        const end = std.mem.indexOfScalarPos(u8, spec, 1, '/') orelse return null;
        const pattern = spec[1..end];
        const pathspec = std.mem.trim(u8, spec[end + 1 ..], " \t");
        return .{ .pattern = pattern, .pathspec = pathspec };
    }

    fn runFilePickerSearch(self: *App, tail: []const u8) !void {
        const pathspec = std.mem.trim(u8, tail, " \t");
        try self.runPickerSource(.{ .command = "files", .kind = .files, .title = "files" }, "", pathspec);
    }

    fn runSymbolPickerSearch(self: *App, tail: []const u8) !void {
        const pattern = std.mem.trim(u8, tail, " \t");
        if (pattern.len == 0) {
            try self.setStatus("symbols requires a pattern");
            return;
        }
        try self.runPickerSource(.{ .command = "symbols", .kind = .symbols, .title = "symbols" }, pattern, "");
    }

    fn runLspCommand(self: *App, tail: []const u8) !void {
        const arg_split = std.mem.indexOfScalar(u8, tail, ' ');
        const head = if (arg_split) |idx| tail[0..idx] else tail;
        const rest = if (arg_split) |idx| std.mem.trim(u8, tail[idx + 1 ..], " \t") else "";
        if (head.len == 0) {
            try self.setStatus("lsp commands: definition|references|hover|completion|rename NAME|code-action|semantic-tokens");
            return;
        }
        if (std.mem.eql(u8, head, "definition")) {
            try self.requestLspAction("definition", null);
            return;
        }
        if (std.mem.eql(u8, head, "references")) {
            try self.requestLspAction("references", null);
            return;
        }
        if (std.mem.eql(u8, head, "hover")) {
            try self.requestLspAction("hover", null);
            return;
        }
        if (std.mem.eql(u8, head, "completion")) {
            try self.requestLspAction("completion", null);
            return;
        }
        if (std.mem.eql(u8, head, "code-action")) {
            try self.requestLspAction("code-action", null);
            return;
        }
        if (std.mem.eql(u8, head, "semantic-tokens")) {
            try self.requestLspAction("semantic-tokens", null);
            return;
        }
        if (std.mem.eql(u8, head, "rename")) {
            if (rest.len == 0) {
                try self.setStatus("lsp rename requires a new name");
                return;
            }
            try self.requestLspAction("rename", rest);
            return;
        }
        try self.setStatus("unknown lsp command");
    }

    fn requestLspAction(self: *App, action: []const u8, tail: ?[]const u8) !void {
        const buf = self.activeBuffer();
        const path = buf.path orelse {
            try self.setStatus("current buffer has no path");
            return;
        };
        const payload = try self.lspPositionPayload(path, tail);
        defer self.allocator.free(payload);
        if (std.mem.eql(u8, action, "definition")) {
            _ = try self.lsp.requestDefinition(payload);
        } else if (std.mem.eql(u8, action, "references")) {
            _ = try self.lsp.requestReferences(payload);
        } else if (std.mem.eql(u8, action, "rename")) {
            _ = try self.lsp.requestRename(payload);
        } else if (std.mem.eql(u8, action, "completion")) {
            _ = try self.lsp.requestCompletion(payload);
        } else if (std.mem.eql(u8, action, "hover")) {
            _ = try self.lsp.requestHover(payload);
        } else if (std.mem.eql(u8, action, "code-action")) {
            _ = try self.lsp.requestCodeActions(payload);
        } else if (std.mem.eql(u8, action, "semantic-tokens")) {
            _ = try self.lsp.requestSemanticTokens(payload);
        } else {
            _ = try self.lsp.request(action, payload);
        }
        try self.setStatus("lsp request sent");
    }

    fn lspPositionPayload(self: *App, path: []const u8, tail: ?[]const u8) ![]u8 {
        const buf = self.activeBuffer();
        const row = buf.cursor.row;
        const col = buf.cursor.col;
        if (tail) |text| {
            return try std.fmt.allocPrint(self.allocator,
                "{{\"textDocument\":{{\"uri\":\"file://{s}\"}},\"position\":{{\"line\":{d},\"character\":{d}}},\"newName\":{s}}}",
                .{ path, row, col, try jsonStringLiteral(self.allocator, text) },
            );
        }
        return try std.fmt.allocPrint(self.allocator,
            "{{\"textDocument\":{{\"uri\":\"file://{s}\"}},\"position\":{{\"line\":{d},\"character\":{d}}}}}",
            .{ path, row, col },
        );
    }

    fn runPickerSource(self: *App, spec: listsource_mod.SourceSpec, pattern: []const u8, pathspec: []const u8) !void {
        self.cancelActivePickerSource();
        var collector = SearchCollector.init(self, spec.kind, spec.emit_quickfix);
        defer collector.deinit();
        const restored_picker_selection = self.workspace.session.selected_picker_index;
        const job_kind: scheduler_mod.JobKind = switch (spec.kind) {
            .search => .grep,
            .files => .search,
            .symbols => .symbols,
            .diagnostics => .custom,
            .custom => .custom,
        };
        const job_id = try self.scheduler.spawn(job_kind, self.workspace.session_generation, self.workspace.session_generation);
        self.picker_job_id = job_id;
        const key = listsource_mod.SourceKey{
            .request_id = job_id,
            .workspace_generation = self.workspace.session_generation,
        };
        collector.request_key = key;
        collector.source.begin(key);
        self.picker_source_key = key;
        self.picker_source_spec = spec;
        self.picker_source_pattern = try self.allocator.dupe(u8, pattern);
        self.picker_source_pathspec = try self.allocator.dupe(u8, pathspec);

        self.picker.clear();
        try self.picker.setQuery(if (pattern.len > 0) pattern else pathspec);
        self.picker.setState(.loading);
        try self.ensurePickerPane();
        try self.syncPickerPaneTitle(spec.title);

        const sink = search_mod.ResultSink{ .ctx = &collector, .emit = SearchCollector.emit };
        const search_result = switch (spec.kind) {
            .search => self.search.grep(pattern, pathspec, sink, std.math.maxInt(usize)),
            .files => self.search.searchFiles(pathspec, sink, std.math.maxInt(usize)),
            .symbols => blk: {
                const lsp_sink = lsp_mod.ResultSink{ .ctx = &collector, .emit = SearchCollector.emitListItemOpaque };
                const lsp_count = self.lsp.querySymbols(pattern, lsp_sink, std.math.maxInt(usize)) catch |err| switch (err) {
                    error.StaleSource, error.Canceled => 0,
                    else => return err,
                };
                if (lsp_count > 0) break :blk lsp_count;
                break :blk self.search.symbols(pattern, sink, std.math.maxInt(usize));
            },
            else => error.Unsupported,
        };
        _ = search_result catch |err| {
            try self.picker.setError(@errorName(err));
            _ = self.scheduler.complete(job_id, @errorName(err), false) catch {};
            if (self.picker_job_id == job_id) self.picker_job_id = null;
            try self.setStatus(spec.failure_message);
            return err;
        };

        collector.source.complete(key);
        _ = self.scheduler.complete(job_id, "picker completed", true) catch {};
        if (self.picker_job_id == job_id) self.picker_job_id = null;
        try self.picker.setItems(collector.source.items.items);
        self.picker.selected = if (self.picker.items.items.len == 0) 0 else @min(restored_picker_selection, self.picker.items.items.len - 1);
        self.picker.setState(.ready);
        try self.syncPickerPreview(spec);
        if (collector.source.items.items.len == 0) {
            try self.setStatus(spec.empty_message);
            self.picker.clearPreview();
        }
        try self.syncPickerPaneTitle(spec.title);
    }

    fn cancelActivePickerSource(self: *App) void {
        if (self.picker_source_key) |_| {
            self.picker_source_key = null;
            self.picker_source_spec = null;
        }
        if (self.picker_source_pattern) |pattern| self.allocator.free(pattern);
        if (self.picker_source_pathspec) |pathspec| self.allocator.free(pathspec);
        self.picker_source_pattern = null;
        self.picker_source_pathspec = null;
        self.picker.clearError();
        self.picker.clearPreview();
        self.picker.setState(.idle);
    }

    fn openPluginPicker(self: *App, title: []const u8, query: []const u8) !void {
        self.cancelActivePickerSource();
        self.picker.clear();
        try self.picker.setQuery(query);
        self.picker.setState(.loading);
        try self.ensurePickerPane();
        try self.syncPickerPaneTitle(title);
    }

    fn setPluginPickerItems(self: *App, items: []const listpane_mod.Item) !void {
        try self.ensurePickerPane();
        try self.picker.setItems(items);
        self.picker.setState(.ready);
        if (self.picker.selectedItem()) |item| {
            try self.syncPluginPickerPreviewForSelection(item);
        } else {
            self.picker.clearPreview();
        }
        if (self.picker.items.items.len == 0) {
            try self.setStatus("picker empty");
        }
    }

    fn appendPluginPickerItem(self: *App, item: listpane_mod.Item) !void {
        try self.ensurePickerPane();
        try self.picker.appendItem(item);
        self.picker.setState(.ready);
    }

    fn setPluginPickerPreview(self: *App, preview: ?[]const u8) !void {
        try self.picker.setPreview(preview);
    }

    fn cancelPluginPicker(self: *App) void {
        self.picker.clear();
    }

    fn syncPluginPickerPreviewForSelection(self: *App, item: listpane_mod.Item) !void {
        if (item.detail) |detail| {
            try self.picker.setPreview(detail);
        } else {
            self.picker.clearPreview();
        }
    }

    fn refreshDerivedSources(self: *App) !void {
        _ = self.lsp.refreshDiagnostics() catch {};
        _ = self.lsp.refreshSymbols() catch {};
        if (self.picker_source_spec) |spec| {
            const pattern = self.picker_source_pattern orelse "";
            const pathspec = self.picker_source_pathspec orelse "";
            const pattern_copy = try self.allocator.dupe(u8, pattern);
            defer self.allocator.free(pattern_copy);
            const pathspec_copy = try self.allocator.dupe(u8, pathspec);
            defer self.allocator.free(pathspec_copy);
            try self.runPickerSource(spec, pattern_copy, pathspec_copy);
        }
        if (self.diagnostics_pane_id != null) {
            try self.syncDiagnosticsPane();
        }
        if (self.plugins_pane_id != null) {
            try self.syncPluginPane();
        }
        if (self.plugin_details_pane_id != null) {
            try self.syncPluginDetailPane();
        }
    }

    fn appendQuickfixMatch(self: *App, path: []const u8, row: usize, col: usize, line: []const u8) !void {
        try self.quickfix_list.appendOwnedItem(.{
            .id = @intCast(self.quickfix_list.items.items.len + 1),
            .path = try self.allocator.dupe(u8, path),
            .row = row,
            .col = col,
            .label = try std.fmt.allocPrint(self.allocator, "{s}:{d}:{d}", .{ path, row + 1, col + 1 }),
            .detail = try self.allocator.dupe(u8, line),
            .score = @intCast(line.len),
        });
    }

    fn showPickerSelection(self: *App) !void {
        if (self.picker.items.items.len == 0) {
            try self.setStatus("picker empty");
            self.picker.clearPreview();
            return;
        }
        const item = self.picker.items.items[@min(self.picker.selected, self.picker.items.items.len - 1)];
        const msg = try std.fmt.allocPrint(self.allocator, "{d}/{d} {s}", .{
            @min(self.picker.selected + 1, self.picker.items.items.len),
            self.picker.items.items.len,
            item.label,
        });
        defer self.allocator.free(msg);
        try self.setStatus(msg);
        try self.syncPickerPreviewForSelection(item);
        try self.syncPickerPaneTitle(self.picker.query.items);
    }

    fn showDiagnosticsPane(self: *App) !void {
        try self.ensureDiagnosticsPane();
        try self.syncDiagnosticsPane();
        try self.setStatus("diagnostics pane");
    }

    fn selectedDiagnostic(self: *const App) ?listpane_mod.Item {
        return self.diagnostics_list.selectedItem();
    }

    fn diagnosticsNext(self: *App) !void {
        if (self.diagnostics_list.items.items.len == 0) {
            try self.setStatus("diagnostics empty");
            return;
        }
        self.diagnostics_list.moveSelection(1);
        try self.showDiagnosticsSelection();
    }

    fn diagnosticsPrev(self: *App) !void {
        if (self.diagnostics_list.items.items.len == 0) {
            try self.setStatus("diagnostics empty");
            return;
        }
        self.diagnostics_list.moveSelection(-1);
        try self.showDiagnosticsSelection();
    }

    fn showDiagnosticsSelection(self: *App) !void {
        const diag = self.selectedDiagnostic() orelse {
            try self.setStatus("diagnostics empty");
            return;
        };
        const msg = try std.fmt.allocPrint(self.allocator, "{d}/{d} {s}", .{
            @min(self.diagnostics_list.selected + 1, self.diagnostics_list.items.items.len),
            self.diagnostics_list.items.items.len,
            diag.label,
        });
        defer self.allocator.free(msg);
        try self.setStatus(msg);
        try self.syncDiagnosticsPane();
    }

    fn openDiagnosticSelection(self: *App) !void {
        const diag = self.selectedDiagnostic() orelse {
            try self.setStatus("diagnostics empty");
            return;
        };
        const path = diag.path orelse {
            try self.setStatus("diagnostic missing path");
            return;
        };
        try self.openOrFocusPath(path);
        const buf = self.activeBuffer();
        buf.cursor = .{ .row = diag.row, .col = diag.col };
        try self.setStatus("diagnostic jump");
    }

    fn pickerNext(self: *App) !void {
        if (self.picker.items.items.len == 0) {
            try self.setStatus("picker empty");
            return;
        }
        self.picker.moveSelection(1);
        try self.showPickerSelection();
    }

    fn pickerPrev(self: *App) !void {
        if (self.picker.items.items.len == 0) {
            try self.setStatus("picker empty");
            return;
        }
        self.picker.moveSelection(-1);
        try self.showPickerSelection();
    }

    fn openPickerSelection(self: *App) !void {
        const item = self.picker.selectedItem() orelse {
            try self.setStatus("picker empty");
            return;
        };
        const path = item.path orelse {
            try self.setStatus("picker item missing path");
            return;
        };
        try self.openOrFocusPath(path);
        const buf = self.activeBuffer();
        buf.cursor = .{ .row = item.row, .col = item.col };
        try self.setStatus("picker jump");
    }

    fn openSelection(self: *App) !void {
        if (self.panes.focusedPaneKind()) |focused_kind| {
            if (focused_kind == .custom or focused_kind == .plugin_details) {
                try self.openPluginSelection();
                return;
            }
        }
        try self.openPickerSelection();
    }

    fn navigatePluginOrPicker(self: *App, delta: isize) !void {
        if (self.panes.focusedPaneKind()) |focused_kind| {
            if (focused_kind == .custom or focused_kind == .plugin_details) {
                try self.pluginNextPrev(delta);
                return;
            }
        }
        if (self.picker.items.items.len == 0) {
            try self.setStatus("picker empty");
            return;
        }
        if (delta > 0) {
            try self.pickerNext();
        } else {
            try self.pickerPrev();
        }
    }

    fn ensurePickerPane(self: *App) !void {
        if (self.picker_pane_id) |id| {
            _ = self.panes.focus(id);
            return;
        }
        if (self.panes.findByKind(.picker)) |id| {
            self.picker_pane_id = id;
            _ = self.panes.focus(id);
            return;
        }
        const id = try self.panes.open(.picker, "picker");
        self.picker_pane_id = id;
        _ = self.panes.focus(id);
    }

    fn ensureDiagnosticsPane(self: *App) !void {
        if (self.diagnostics_pane_id) |id| {
            _ = self.panes.focus(id);
            return;
        }
        if (self.panes.findByKind(.diagnostics)) |id| {
            self.diagnostics_pane_id = id;
            _ = self.panes.focus(id);
            return;
        }
        const id = try self.panes.open(.diagnostics, "diagnostics");
        self.diagnostics_pane_id = id;
        _ = self.panes.focus(id);
    }

    fn ensurePluginsPane(self: *App) !void {
        if (self.plugins_pane_id) |id| {
            _ = self.panes.focus(id);
            return;
        }
        if (self.panes.findByKind(.custom)) |id| {
            self.plugins_pane_id = id;
            _ = self.panes.focus(id);
            return;
        }
        const id = try self.panes.open(.custom, "plugins");
        self.plugins_pane_id = id;
        _ = self.panes.focus(id);
    }

    fn ensurePluginDetailsPane(self: *App) !void {
        if (self.plugin_details_pane_id) |id| {
            _ = self.panes.focus(id);
            return;
        }
        if (self.panes.findByKind(.plugin_details)) |id| {
            self.plugin_details_pane_id = id;
            _ = self.panes.focus(id);
            return;
        }
        const id = try self.panes.open(.plugin_details, "plugin details");
        self.plugin_details_pane_id = id;
        _ = self.panes.focus(id);
    }

    fn syncPickerPaneTitle(self: *App, title_suffix: []const u8) !void {
        const id = self.picker_pane_id orelse return;
        const title = if (title_suffix.len == 0) "picker" else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "picker: {s}", .{title_suffix});
        };
        defer if (title_suffix.len > 0) self.allocator.free(title);
        _ = try self.panes.updateTitle(id, title);
    }

    fn syncPickerPreview(self: *App, spec: listsource_mod.SourceSpec) !void {
        if (spec.preview == .none) {
            self.picker.clearPreview();
            return;
        }
        if (self.picker.selectedItem()) |item| {
            try self.syncPickerPreviewForSelection(item);
        } else {
            self.picker.clearPreview();
        }
    }

    fn syncPickerPreviewForSelection(self: *App, item: listpane_mod.Item) !void {
        if (self.picker_source_spec) |spec| {
            switch (spec.preview) {
                .none => self.picker.clearPreview(),
                .detail => if (item.detail) |detail| try self.picker.setPreview(detail) else self.picker.clearPreview(),
            }
            return;
        }
        if (item.detail) |detail| {
            try self.picker.setPreview(detail);
        } else {
            self.picker.clearPreview();
        }
    }

    fn syncDiagnosticsPane(self: *App) !void {
        const id = self.diagnostics_pane_id orelse return;
        self.diagnostics.clearDecorations();
        const errors = self.diagnostics.count(.err);
        const warnings = self.diagnostics.count(.warning);
        const infos = self.diagnostics.count(.info);
        const lsp_errors = self.lsp.diagnosticsCount(.err);
        const lsp_warnings = self.lsp.diagnosticsCount(.warning);
        const lsp_infos = self.lsp.diagnosticsCount(.info);
        const restored_diagnostics_selection = self.workspace.session.selected_diagnostics_index;
        var source = listsource_mod.AsyncListSource.init(self.allocator, .diagnostics);
        defer source.deinit();
        const key = listsource_mod.SourceKey{
            .request_id = 1,
            .workspace_generation = self.workspace.session_generation,
        };
        source.begin(key);
        for (self.diagnostics.diagnostics.items) |diag| {
            const severity = switch (diag.severity) {
                .err => "error",
                .warning => "warning",
                .info => "info",
            };
            const path = diag.path orelse "[buffer]";
            const label = try std.fmt.allocPrint(self.allocator, "{s}:{d}:{d}", .{
                path,
                diag.row + 1,
                diag.col + 1,
            });
            const detail = try std.fmt.allocPrint(self.allocator, "[{s}] {s}", .{ severity, diag.message });
            self.diagnostics.addDiagnosticDecoration(diag) catch {};
            try source.append(key, .{
                .id = source.items.items.len + 1,
                .path = if (diag.path) |p| try self.allocator.dupe(u8, p) else null,
                .row = diag.row,
                .col = diag.col,
                .label = label,
                .detail = detail,
                .score = @intCast(diag.message.len),
            });
        }
        for (self.lsp.diagnostics.items) |diag| {
            const severity = switch (diag.severity) {
                .err => "error",
                .warning => "warning",
                .info => "info",
            };
            const path = diag.path orelse "[buffer]";
            const label = try std.fmt.allocPrint(self.allocator, "{s}:{d}:{d}", .{
                path,
                diag.row + 1,
                diag.col + 1,
            });
            const detail = try std.fmt.allocPrint(self.allocator, "[lsp {s}] {s}", .{ severity, diag.message });
            try source.append(key, .{
                .id = source.items.items.len + 1,
                .path = if (diag.path) |p| try self.allocator.dupe(u8, p) else null,
                .row = diag.row,
                .col = diag.col,
                .label = label,
                .detail = detail,
                .score = @intCast(diag.message.len),
            });
        }
        source.complete(key);
        try self.diagnostics_list.setItems(source.items.items);
        self.diagnostics_list.selected = if (self.diagnostics_list.items.items.len == 0) 0 else @min(restored_diagnostics_selection, self.diagnostics_list.items.items.len - 1);
        const total = self.diagnostics_list.items.items.len;
        const selected = if (total == 0) 0 else @min(self.diagnostics_list.selected + 1, total);
        const title = try std.fmt.allocPrint(self.allocator, "diagnostics: E{d} W{d} I{d} | LSP E{d} W{d} I{d} {d}/{d}", .{ errors, warnings, infos, lsp_errors, lsp_warnings, lsp_infos, selected, total });
        defer self.allocator.free(title);
        try self.syncListPaneOverlay(id, title, &self.diagnostics_list, "no diagnostics");
    }

    fn syncPluginPane(self: *App) !void {
        const id = self.plugins_pane_id orelse return;
        try self.plugin_catalog.fillListPane(self.allocator, &self.plugins_list);
        if (self.plugin_activity.items.len > 0) {
            const label = try self.allocator.dupe(u8, "activity");
            errdefer self.allocator.free(label);
            const detail = try self.allocator.dupe(u8, self.plugin_activity.items);
            errdefer self.allocator.free(detail);
            try self.plugins_list.appendOwnedItem(.{
                .id = 0,
                .label = label,
                .detail = detail,
                .score = 100,
            });
        }
        for (self.builtins.extensionCommands()) |command| {
            const label = try std.fmt.allocPrint(self.allocator, "cmd {s}", .{command.name});
            errdefer self.allocator.free(label);
            const detail = try std.fmt.allocPrint(self.allocator, "{s}", .{command.description});
            errdefer self.allocator.free(detail);
            try self.plugins_list.appendOwnedItem(.{
                .id = @intCast(self.plugins_list.items.items.len + 1),
                .label = label,
                .detail = detail,
                .score = 80,
            });
        }
        const title = try self.plugin_catalog.statusText(self.allocator);
        defer self.allocator.free(title);
        try self.syncListPaneOverlay(id, title, &self.plugins_list, "no plugins");
        try self.syncPluginDetailPane();
    }

    fn pluginNextPrev(self: *App, delta: isize) !void {
        const focused_kind = self.panes.focusedPaneKind();
        if (focused_kind == .plugin_details) {
            try self.movePluginDetailSelection(delta);
            return;
        }
        if (self.plugins_list.items.items.len == 0) {
            try self.setStatus("plugin pane empty");
            return;
        }
        self.plugins_list.moveSelection(delta);
        try self.syncPluginDetailPane();
    }

    fn movePluginDetailSelection(self: *App, delta: isize) !void {
        if (self.plugin_detail_rows.items.len == 0) {
            try self.setStatus("plugin detail pane empty");
            return;
        }
        const current: isize = @intCast(self.plugin_detail_selected);
        const max_index: isize = @intCast(self.plugin_detail_rows.items.len - 1);
        const next = std.math.clamp(current + delta, 0, max_index);
        self.plugin_detail_selected = @intCast(next);
        try self.syncPluginDetailPane();
    }

    fn openPluginSelection(self: *App) !void {
        if (self.panes.focusedPaneKind() == .plugin_details) {
            try self.openSelectedPluginDetailRow();
            return;
        }
        const item = self.plugins_list.selectedItem() orelse {
            try self.setStatus("plugin pane empty");
            return;
        };
        if (std.mem.eql(u8, item.label, "activity")) {
            try self.showPluginDetail(item, "activity selected");
            try self.setStatus(item.detail orelse "plugin activity");
            return;
        }
        if (std.mem.startsWith(u8, item.label, "cmd ")) {
            const command_name = item.label["cmd ".len..];
            try self.showPluginDetail(item, "running command");
            if (!try self.invokeBuiltinCommand(command_name, &.{})) {
                try self.setStatus("unknown plugin command");
            }
            return;
        }
        try self.showPluginDetail(item, "plugin selected");
        try self.setStatus(item.detail orelse "plugin item selected");
    }

    fn showPluginDetail(self: *App, item: listpane_mod.Item, action: []const u8) !void {
        try self.ensurePluginDetailsPane();
        const id = self.plugin_details_pane_id orelse return;
        try self.rebuildPluginDetailRows(item);
        _ = self.panes.clearStreaming(id);
        const title = try self.pluginDetailTitle(action);
        defer self.allocator.free(title);
        _ = try self.panes.updateTitle(id, title);
        try self.renderPluginDetailPane(id);
    }

    fn syncPluginDetailPane(self: *App) !void {
        const id = self.plugin_details_pane_id orelse return;
        const item = self.plugins_list.selectedItem() orelse {
            self.clearPluginDetailRows();
            _ = self.panes.clearStreaming(id);
            _ = try self.panes.updateTitle(id, "plugin details");
            _ = try self.panes.appendStreaming(id, "select a plugin row\n");
            return;
        };
        try self.showPluginDetail(item, "preview");
    }

    fn openSelectedPluginDetailRow(self: *App) !void {
        const row = self.selectedPluginDetailRow() orelse {
            try self.setStatus("plugin detail pane empty");
            return;
        };
        switch (row.action) {
            .run_command => {
                const command_name = row.command_name orelse {
                    try self.setStatus("plugin command missing name");
                    return;
                };
                try self.setStatus(row.detail orelse "running plugin command");
                if (!try self.invokeBuiltinCommand(command_name, &.{})) {
                    try self.setStatus("unknown plugin command");
                }
                try self.syncPluginDetailPane();
            },
            .none => {
                try self.setStatus(row.detail orelse row.label);
            },
        }
    }

    fn rebuildPluginDetailRows(self: *App, item: listpane_mod.Item) !void {
        const is_same_context = if (self.plugin_detail_context) |context| std.mem.eql(u8, context, item.label) else false;
        const preserved_selection = self.plugin_detail_selected;
        if (!is_same_context) {
            if (self.plugin_detail_context) |text| self.allocator.free(text);
            self.plugin_detail_context = try self.allocator.dupe(u8, item.label);
        }
        self.clearPluginDetailRows();
        var default_selected: usize = 0;
        try self.appendPluginDetailRow(item.label, item.detail, .none, null);
        if (std.mem.eql(u8, item.label, "activity")) {
            try self.appendPluginDetailRow("activity", if (self.plugin_activity.items.len > 0) self.plugin_activity.items else "none", .none, null);
            try self.appendPluginDetailRow("source", "plugin activity", .none, null);
            try self.appendPluginDetailRow("action", "preview", .none, null);
        } else if (std.mem.startsWith(u8, item.label, "cmd ")) {
            const command_name = item.label["cmd ".len..];
            try self.appendPluginDetailRow("command", null, .none, null);
            try self.appendPluginDetailRow("name", command_name, .none, null);
            try self.appendPluginDetailRow("scope", "extension", .none, null);
            default_selected = self.plugin_detail_rows.items.len;
            try self.appendPluginDetailRow("action", "runnable", .run_command, command_name);
            try self.appendPluginDetailRow("activity", if (self.plugin_activity.items.len > 0) self.plugin_activity.items else "none", .none, null);
        } else if (item.label.len > 0) {
            const manifest_name = pluginManifestNameForLabel(item.label);
            if (manifest_name) |name| {
                if (self.plugin_catalog.findEntry(name)) |entry| {
                    try self.appendPluginDetailRow("manifest", null, .none, null);
                    try self.appendPluginDetailRow("version", entry.manifest.version, .none, null);
                    try self.appendPluginDetailRow("source", @tagName(entry.source), .none, null);
                    try self.appendPluginDetailRow("state", @tagName(entry.state), .none, null);
                    try self.appendPluginDetailRow("capabilities", null, .none, null);
                    try self.appendPluginCapabilityRows(entry.manifest.capabilities);
                }
            }
        }
        if (!is_same_context) {
            self.plugin_detail_selected = default_selected;
        } else {
            self.plugin_detail_selected = preserved_selection;
        }
        self.clampPluginDetailSelection();
    }

    fn appendPluginDetailRow(self: *App, label: []const u8, detail: ?[]const u8, action: PluginDetailAction, command_name: ?[]const u8) !void {
        try self.plugin_detail_rows.append(.{
            .label = try self.allocator.dupe(u8, label),
            .detail = if (detail) |text| try self.allocator.dupe(u8, text) else null,
            .action = action,
            .command_name = if (command_name) |text| try self.allocator.dupe(u8, text) else null,
        });
    }

    fn appendPluginCapabilityRows(self: *App, caps: builtins_mod.Capabilities) !void {
        const capabilities = [_]struct { name: []const u8, enabled: bool }{
            .{ .name = "command", .enabled = caps.command },
            .{ .name = "event", .enabled = caps.event },
            .{ .name = "status", .enabled = caps.status },
            .{ .name = "buffer_read", .enabled = caps.buffer_read },
            .{ .name = "buffer_edit", .enabled = caps.buffer_edit },
            .{ .name = "jobs", .enabled = caps.jobs },
            .{ .name = "workspace", .enabled = caps.workspace },
            .{ .name = "diagnostics", .enabled = caps.diagnostics },
            .{ .name = "picker", .enabled = caps.picker },
            .{ .name = "pane", .enabled = caps.pane },
            .{ .name = "fs_read", .enabled = caps.fs_read },
            .{ .name = "tree_query", .enabled = caps.tree_query },
            .{ .name = "decoration", .enabled = caps.decoration },
            .{ .name = "lsp", .enabled = caps.lsp },
        };
        var any = false;
        for (capabilities) |cap| {
            if (!cap.enabled) continue;
            any = true;
            try self.appendPluginDetailRow(cap.name, "enabled", .none, null);
        }
        if (!any) {
            try self.appendPluginDetailRow("none", null, .none, null);
        }
    }

    fn selectedPluginDetailRow(self: *const App) ?PluginDetailRow {
        if (self.plugin_detail_rows.items.len == 0) return null;
        return self.plugin_detail_rows.items[self.plugin_detail_selected];
    }

    fn clampPluginDetailSelection(self: *App) void {
        if (self.plugin_detail_rows.items.len == 0) {
            self.plugin_detail_selected = 0;
            return;
        }
        if (self.plugin_detail_selected >= self.plugin_detail_rows.items.len) {
            self.plugin_detail_selected = self.plugin_detail_rows.items.len - 1;
        }
    }

    fn clearPluginDetailRows(self: *App) void {
        for (self.plugin_detail_rows.items) |row| {
            self.allocator.free(row.label);
            if (row.detail) |detail| self.allocator.free(detail);
            if (row.command_name) |name| self.allocator.free(name);
        }
        self.plugin_detail_rows.clearRetainingCapacity();
        self.plugin_detail_selected = 0;
    }

    fn pluginManifestNameForLabel(label: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, label, "activity")) return null;
        if (std.mem.startsWith(u8, label, "cmd ")) return null;
        const end = std.mem.indexOfScalar(u8, label, ' ') orelse label.len;
        return label[0..end];
    }

    fn pluginDetailTitle(self: *const App, action: []const u8) ![]u8 {
        const total = self.plugin_detail_rows.items.len;
        const selected = if (total == 0) 0 else @min(self.plugin_detail_selected + 1, total);
        if (action.len == 0 or std.mem.eql(u8, action, "preview")) {
            return try std.fmt.allocPrint(self.allocator, "plugin details [{d}/{d}]", .{ selected, total });
        }
        return try std.fmt.allocPrint(self.allocator, "plugin details [{d}/{d}] {s}", .{ selected, total, action });
    }

    fn renderPluginDetailPane(self: *App, id: u64) !void {
        _ = self.panes.clearStreaming(id);
        const total = self.plugin_detail_rows.items.len;
        if (total == 0) {
            _ = try self.panes.appendStreaming(id, "no plugin details\n");
            return;
        }
        for (self.plugin_detail_rows.items, 0..) |row, idx| {
            const prefix = if (idx == self.plugin_detail_selected) "> " else "  ";
            if (row.detail) |detail| {
                const line = try std.fmt.allocPrint(self.allocator, "{s}{s}: {s}", .{ prefix, row.label, detail });
                defer self.allocator.free(line);
                _ = try self.panes.appendStreaming(id, line);
            } else {
                const line = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, row.label });
                defer self.allocator.free(line);
                _ = try self.panes.appendStreaming(id, line);
            }
            _ = try self.panes.appendStreaming(id, "\n");
        }
    }

    fn syncListPaneOverlay(self: *App, id: u64, title: []const u8, list: *const listpane_mod.ListPane, empty_message: []const u8) !void {
        _ = try self.panes.updateTitle(id, title);
        _ = self.panes.clearStreaming(id);
        if (list.items.items.len == 0) {
            _ = try self.panes.appendStreaming(id, empty_message);
            _ = try self.panes.appendStreaming(id, "\n");
            return;
        }
        for (list.items.items, 0..) |item, idx| {
            const prefix = if (idx == list.selected) "> " else "  ";
            const line = try std.fmt.allocPrint(self.allocator, "{s}{s} {s}\n", .{ prefix, item.label, item.detail orelse "" });
            defer self.allocator.free(line);
            _ = try self.panes.appendStreaming(id, line);
        }
    }

    fn tabCloseCurrent(self: *App) !void {
        const had_split = self.split_index != null;
        const had_multiple_tabs = self.buffers.items.len > 1;
        const was_dirty = self.activeBuffer().dirty;
        try self.closeCurrentPane();
        if (!was_dirty and !had_split and had_multiple_tabs) {
            self.workspace.noteSessionChange();
            try self.refreshDerivedSources();
            try self.setStatus("tab closed");
        }
    }

    fn tabOnlyCurrent(self: *App) !void {
        if (self.activeBuffer().dirty) {
            try self.setStatus("buffer modified, save first or use :q!");
            return;
        }
        self.disableDiffMode();
        const keep_index = self.focusedBufferIndex();
        var idx = self.buffers.items.len;
        while (idx > 0) : (idx -= 1) {
            const remove_index = idx - 1;
            if (remove_index == keep_index) continue;
            self.buffers.items[remove_index].deinit();
            _ = self.buffers.orderedRemove(remove_index);
        }
        self.split_index = null;
        self.split_focus = .left;
        self.active_index = 0;
        self.workspace.noteSessionChange();
        try self.refreshDerivedSources();
        try self.setStatus("tab only");
    }

    fn tabMoveCurrent(self: *App, target_text: []const u8) !void {
        const parsed = std.fmt.parseInt(usize, target_text, 10) catch {
            try self.setStatus("tabmove requires a number");
            return;
        };
        if (self.buffers.items.len <= 1) return;
        self.disableDiffMode();
        const current = self.focusedBufferIndex();
        const target = @min(parsed, self.buffers.items.len - 1);
        if (current == target) {
            try self.setStatus("tab moved");
            return;
        }
        const item = self.buffers.items[current];
        if (current < target) {
            std.mem.copyForwards(buffer_mod.Buffer, self.buffers.items[current..target], self.buffers.items[current + 1 .. target + 1]);
        } else {
            std.mem.copyBackwards(buffer_mod.Buffer, self.buffers.items[target + 1 .. current + 1], self.buffers.items[target..current]);
        }
        self.buffers.items[target] = item;

        if (self.active_index == current) self.active_index = target;
        if (self.split_index) |*idx| {
            if (idx.* == current) {
                idx.* = target;
            } else if (current < target and idx.* > current and idx.* <= target) {
                idx.* -= 1;
            } else if (current > target and idx.* >= target and idx.* < current) {
                idx.* += 1;
            }
        }
        self.workspace.noteSessionChange();
        try self.refreshDerivedSources();
        try self.setStatus("tab moved");
    }

    fn helpForKeyword(self: *App, keyword: []const u8) !void {
        const stripped = if (keyword.len > 0 and keyword[0] == ':') keyword[1..] else keyword;
        if (stripped.len == 0) {
            try self.setStatus("help: use :help keyword");
            return;
        }
        if (std.mem.eql(u8, stripped, "leader")) {
            try self.setStatus("leader mappings live under [keymap.leader]; leader x confirms close of a split, tab, or buffer");
            return;
        }
        if (normalActionHelp(stripped, self.config.keymap.leader, self.config.keymap.leader_bindings.items)) |doc| {
            try self.setStatus(doc);
            return;
        }
        if (std.mem.eql(u8, stripped, "w") or std.mem.eql(u8, stripped, "save")) {
            try self.setStatus("write the current buffer");
            return;
        }
        if (std.mem.eql(u8, stripped, "saveas") or std.mem.eql(u8, stripped, "sav")) {
            try self.setStatus("save the current buffer under a new path");
            return;
        }
        if (std.mem.eql(u8, stripped, "close") or std.mem.eql(u8, stripped, "clo")) {
            try self.setStatus("close the current pane");
            return;
        }
        if (std.mem.eql(u8, stripped, "terminal") or std.mem.eql(u8, stripped, "ter")) {
            try self.setStatus("open a terminal pane");
            return;
        }
        if (std.mem.eql(u8, stripped, "registers") or std.mem.eql(u8, stripped, "reg")) {
            try self.setStatus("show register contents");
            return;
        }
        if (std.mem.eql(u8, stripped, "open")) {
            try self.setStatus("open a path in a new buffer");
            return;
        }
        if (std.mem.eql(u8, stripped, "split")) {
            try self.setStatus("open a path in a split pane");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabnew")) {
            try self.setStatus("open a path in a new tab");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabclose") or std.mem.eql(u8, stripped, "tabc")) {
            try self.setStatus("close the current tab");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabonly") or std.mem.eql(u8, stripped, "tabo")) {
            try self.setStatus("keep only the current tab");
            return;
        }
        if (std.mem.eql(u8, stripped, "tabmove")) {
            try self.setStatus("move the current tab to a new index");
            return;
        }
        if (std.mem.eql(u8, stripped, "refresh-sources") or std.mem.eql(u8, stripped, "refresh")) {
            try self.setStatus("refresh picker and diagnostics sources");
            return;
        }
        if (std.mem.eql(u8, stripped, "marks")) {
            try self.setStatus("list marks");
            return;
        }
        if (std.mem.eql(u8, stripped, "jumps")) {
            try self.setStatus("list jumps");
            return;
        }
        if (std.mem.eql(u8, stripped, "changes")) {
            try self.setStatus("list changes");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffthis")) {
            try self.setStatus("enable diff mode for this window");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffoff")) {
            try self.setStatus("disable diff mode");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffupdate")) {
            try self.setStatus("update diff summary");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffget") or std.mem.eql(u8, stripped, "do")) {
            try self.setStatus("get the line from the diff peer");
            return;
        }
        if (std.mem.eql(u8, stripped, "diffput") or std.mem.eql(u8, stripped, "dp")) {
            try self.setStatus("put the current line into the diff peer");
            return;
        }
        if (std.mem.eql(u8, stripped, "q") or std.mem.eql(u8, stripped, "quit")) {
            try self.setStatus("quit the editor");
            return;
        }
        try self.setStatus("no help found");
    }

    fn openManPageForCurrentWord(self: *App) !void {
        const word = self.activeBuffer().currentWord();
        if (word.len == 0) {
            try self.setStatus("no word under cursor");
            return;
        }
        if (!self.runInteractiveCommand(&.{ "man", word })) {
            try self.setStatus("man page not available");
        } else {
            try self.setStatus("returned from man");
        }
    }

    fn openTerminalShell(self: *App) !void {
        const shell = try self.defaultShell();
        defer if (shell.owned) self.allocator.free(shell.path);
        if (!self.runInteractiveCommand(&.{shell.path})) {
            try self.setStatus("terminal unavailable");
        } else {
            try self.setStatus("returned from terminal");
        }
    }

    const ShellRef = struct {
        path: []const u8,
        owned: bool,
    };

    fn defaultShell(self: *App) !ShellRef {
        if (builtin.os.tag == .windows) {
            return .{ .path = "cmd.exe", .owned = false };
        }
        const owned = std.process.getEnvVarOwned(self.allocator, "SHELL") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return .{ .path = "sh", .owned = false },
            else => return err,
        };
        return .{ .path = owned, .owned = true };
    }

    fn runInteractiveCommand(self: *App, argv: []const []const u8) bool {
        if (self.interactive_command_hook) |hook| {
            return hook(self, argv);
        }
        const had_raw = self.raw_mode != null;
        if (had_raw) self.exitTerminal() catch return false;
        defer if (had_raw) self.initTerminal() catch {};

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        child.spawn() catch return false;
        _ = child.wait() catch return false;
        return true;
    }

    fn jumpToMatchingCharacter(self: *App) !void {
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const candidate = if (cursor_offset < text.len and isMatchPair(text[cursor_offset])) text[cursor_offset] else if (cursor_offset > 0 and isMatchPair(text[cursor_offset - 1])) text[cursor_offset - 1] else 0;
        if (candidate == 0) {
            try self.setStatus("no matching character under cursor");
            return;
        }
        const jump_offset = findMatchingPairOffset(text, cursor_offset, candidate) orelse {
            try self.setStatus("matching character not found");
            return;
        };
        buf.cursor = self.offsetToPosition(text, jump_offset);
    }

    fn jumpToDeclaration(self: *App, global: bool) !void {
        const buf = self.activeBuffer();
        const word = buf.currentWord();
        if (word.len == 0) {
            try self.setStatus("no word under cursor");
            return;
        }
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const found = if (global)
            findWordOccurrence(text, word, 0, true)
        else
            findWordOccurrence(text, word, cursor_offset, false);
        if (found) |offset| {
            buf.cursor = self.offsetToPosition(text, offset);
        } else {
            try self.setStatus("declaration not found");
        }
    }

    fn findMatchingPairOffset(text: []const u8, cursor_offset: usize, ch: u8) ?usize {
        const pair = matchingPair(ch) orelse return null;
        const open = pair[0];
        const close = pair[1];
        if (ch == open) {
            var depth: usize = 0;
            var idx = @min(cursor_offset + 1, text.len);
            while (idx < text.len) : (idx += 1) {
                const byte = text[idx];
                if (byte == open) depth += 1;
                if (byte == close) {
                    if (depth == 0) return idx;
                    depth -= 1;
                }
            }
            return null;
        }

        var depth: usize = 0;
        var idx = if (cursor_offset > 0) cursor_offset - 1 else return null;
        while (true) {
            const byte = text[idx];
            if (byte == close) {
                depth += 1;
            } else if (byte == open) {
                if (depth == 0) return idx;
                depth -= 1;
            }
            if (idx == 0) break;
            idx -= 1;
        }
        return null;
    }

    fn findWordOccurrence(text: []const u8, word: []const u8, start_offset: usize, forward: bool) ?usize {
        if (word.len == 0 or text.len < word.len) return null;
        if (forward) {
            var idx = start_offset;
            while (idx + word.len <= text.len) : (idx += 1) {
                if (std.mem.eql(u8, text[idx .. idx + word.len], word) and isWordBoundary(text, idx, word.len)) return idx;
            }
            return null;
        }
        var idx = @min(start_offset, text.len);
        while (idx > 0) : (idx -= 1) {
            if (idx >= word.len and std.mem.eql(u8, text[idx - word.len .. idx], word) and isWordBoundary(text, idx - word.len, word.len)) return idx - word.len;
        }
        return null;
    }

    fn isWordBoundary(text: []const u8, start: usize, len: usize) bool {
        const before_ok = start == 0 or !isWordChar(text[start - 1]);
        const after_index = start + len;
        const after_ok = after_index >= text.len or !isWordChar(text[after_index]);
        return before_ok and after_ok;
    }

    fn offsetToPosition(self: *App, text: []const u8, offset: usize) buffer_mod.Position {
        _ = self;
        var row: usize = 0;
        var col: usize = 0;
        var idx: usize = 0;
        while (idx < text.len and idx < offset) : (idx += 1) {
            if (text[idx] == '\n') {
                row += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return .{ .row = row, .col = col };
    }

    fn matchingPair(ch: u8) ?[2]u8 {
        return switch (ch) {
            '(' => .{ '(', ')' },
            ')' => .{ '(', ')' },
            '[' => .{ '[', ']' },
            ']' => .{ '[', ']' },
            '{' => .{ '{', '}' },
            '}' => .{ '{', '}' },
            else => null,
        };
    }

    fn isMatchPair(ch: u8) bool {
        return matchingPair(ch) != null;
    }

    fn isWordChar(byte: u8) bool {
        return std.ascii.isAlphanumeric(byte) or byte == '_';
    }

    fn executeSearch(self: *App) !void {
        const needle = self.search_buffer.items;
        self.mode = .normal;
        self.clearSearchPreview();
        if (needle.len == 0) return;
        try self.updateSearchHighlight(&self.search_highlight, needle);
        const buf = self.activeBuffer();
        const text = try buf.serialize();
        defer self.allocator.free(text);
        const cursor_offset = self.positionToOffset(buf.cursor, text);
        const found = findSubstringOccurrence(text, needle, cursor_offset, self.search_forward);
        if (found) |offset| {
            buf.cursor = self.offsetToPosition(text, offset);
            try self.setStatus("match found");
        } else {
            try self.setStatus("not found");
        }
    }

    fn reloadConfig(self: *App) !void {
        var diag = config_mod.Diagnostics{};
        const new_config = config_mod.load(self.allocator, self.config_path, &diag) catch {
            const msg = try std.fmt.allocPrint(self.allocator, "config error {d}:{d} {s}", .{ diag.line, diag.column, diag.message });
            defer self.allocator.free(msg);
            try self.setStatus(msg);
            return;
        };
        self.config.deinit();
        self.config = new_config;
        var host = self.builtinHost();
        self.builtins.clearExtensionRegistrations();
        try self.plugin_catalog.rebuild(&host, self.config.builtins.enabled.items, self.config.plugins.root, self.config.plugins.enabled.items);
        try self.builtins.rebuild(&host, self.config.builtins.api_version, self.plugin_catalog.manifests());
        self.shutdownConfiguredLsp();
        try self.setStatus("config reloaded");
        self.startConfiguredLsp();
    }

    fn openPath(self: *App, path: []const u8) !void {
        self.disableDiffMode();
        const buf = buffer_mod.Buffer.loadFile(self.allocator, path) catch |err| switch (err) {
            error.FileNotFound => blk: {
                var empty = try buffer_mod.Buffer.initEmpty(self.allocator);
                try empty.replacePath(path);
                break :blk empty;
            },
            else => return err,
        };
        try self.buffers.append(buf);
        self.focusBufferIndex(self.buffers.items.len - 1);
        try self.workspace.recordOpenBuffer(path);
        try self.lsp.didOpenPath(path);
        self.syncActiveSyntax();
        self.emitBuiltinEvent("buffer_open", "{}");
    }

    fn openSplit(self: *App, path: []const u8) !void {
        self.disableDiffMode();
        const buf = buffer_mod.Buffer.loadFile(self.allocator, path) catch |err| switch (err) {
            error.FileNotFound => blk: {
                var empty = try buffer_mod.Buffer.initEmpty(self.allocator);
                try empty.replacePath(path);
                break :blk empty;
            },
            else => return err,
        };
        if (self.split_index) |idx| {
            self.buffers.items[idx].deinit();
            self.buffers.items[idx] = buf;
        } else {
            try self.buffers.append(buf);
            self.split_index = self.buffers.items.len - 1;
        }
        self.split_focus = .right;
        try self.workspace.recordOpenBuffer(path);
        try self.lsp.didOpenPath(path);
        self.syncActiveSyntax();
        self.emitBuiltinEvent("buffer_open", "{}");
    }

    fn render(self: *App) !void {
        const stdout_file = std.fs.File.stdout();
        const size = terminal_mod.size(stdout_file);
        var out_buf: [4096]u8 = undefined;
        var out_writer = stdout_file.writer(&out_buf);
        const writer = &out_writer.interface;
        try terminal_mod.clear(writer);
        try terminal_mod.showCursor(writer);
        try terminal_mod.setCursorShape(writer, self.mode == .normal);

        const show_bottom_bar = self.config.status_bar or self.mode == .command or self.mode == .search;
        const render_height = if (show_bottom_bar and size.rows > 0) size.rows - 1 else size.rows;
        var diagnostics_rows: usize = 0;
        if (self.diagnostics_pane_id != null and self.diagnostics.diagnostics.items.len > 0) {
            diagnostics_rows = @min(8, @max(3, self.diagnostics.diagnostics.items.len + 1));
        }
        var picker_rows: usize = 0;
        if (self.picker_pane_id != null and self.picker.items.items.len > 0) {
            const available_rows = render_height;
            if (available_rows > 3) {
                picker_rows = @min(8, @max(3, available_rows / 3));
            }
        }
        var plugins_rows: usize = 0;
        if (self.plugins_pane_id != null) {
            const available_rows = render_height;
            if (available_rows > 3) {
                const item_rows = if (self.plugins_list.items.items.len == 0) 1 else self.plugins_list.items.items.len + 1;
                plugins_rows = @min(8, @max(3, @min(available_rows / 3, item_rows)));
            } else {
                plugins_rows = available_rows;
            }
        }
        var plugin_details_rows: usize = 0;
        if (self.plugin_details_pane_id != null) {
            const available_rows = render_height;
            if (available_rows > 3) {
                const detail_lines: usize = if (self.plugin_detail_rows.items.len == 0) 3 else self.plugin_detail_rows.items.len + 1;
                plugin_details_rows = @min(8, @max(3, @min(available_rows / 3, detail_lines)));
            } else {
                plugin_details_rows = available_rows;
            }
        }
        const overlay_rows = plugins_rows + plugin_details_rows + diagnostics_rows + picker_rows;
        const content_height = if (render_height > overlay_rows) render_height - overlay_rows else 0;
        self.last_render_height = content_height;
        const has_split = self.split_index != null and size.cols > 1;
        const separator_width: usize = if (has_split) 1 else 0;
        const available_width = if (size.cols > separator_width) size.cols - separator_width else size.cols;
        var left_width: usize = available_width;
        var right_width: usize = 0;
        var right_x: usize = 0;
        const split_width = if (self.config.split_ratio > 0 and self.config.split_ratio < 100)
            (available_width * self.config.split_ratio) / 100
        else
            available_width / 2;
        if (has_split and available_width > 1) {
            left_width = @min(available_width - 1, @max(20, split_width));
            if (left_width + separator_width < available_width) {
                right_width = available_width - left_width - separator_width;
                right_x = left_width + separator_width;
            }
        }
        if (right_width == 0) {
            left_width = available_width;
        }

        try self.renderPane(writer, self.activeBuffer(), 0, left_width, content_height, self.split_focus == .left);
        if (has_split and right_width > 0) {
            try self.renderPaneSeparator(writer, left_width, content_height);
            if (self.split_index) |idx| {
                try self.renderPane(writer, &self.buffers.items[idx], right_x, right_width, content_height, self.split_focus == .right);
            }
        }

        if (plugins_rows > 0) {
            if (self.plugins_pane_id) |id| {
                if (self.findPaneById(id)) |pane| {
                    try self.renderTextOverlayPane(writer, size.cols, content_height + 1, plugins_rows, pane.title, pane.streaming.items);
                }
            }
        }
        if (plugin_details_rows > 0) {
            if (self.plugin_details_pane_id) |id| {
                if (self.findPaneById(id)) |pane| {
                    try self.renderTextOverlayPane(writer, size.cols, content_height + 1 + plugins_rows, plugin_details_rows, pane.title, pane.streaming.items);
                }
            }
        }
        if (diagnostics_rows > 0) {
            if (self.diagnostics_pane_id) |id| {
                if (self.findPaneById(id)) |pane| {
                    try self.renderTextOverlayPane(writer, size.cols, content_height + 1 + plugins_rows + plugin_details_rows, diagnostics_rows, pane.title, pane.streaming.items);
                }
            }
        }
        if (picker_rows > 0) {
            const picker_row = content_height + plugins_rows + plugin_details_rows + diagnostics_rows + 1;
            try self.renderPickerPane(writer, size.cols, picker_row, picker_rows);
        }

        if (show_bottom_bar and size.rows > 0) {
            if (self.mode == .command or self.mode == .search) {
                try self.renderPromptBar(writer, size.cols, size.rows);
            } else if (self.config.status_bar) {
                try self.renderStatusBar(writer, size.cols, size.rows);
            }
        }

        switch (self.mode) {
            .command, .search => {},
            else => {},
        }

        const buf = self.activeBuffer();
        const gutter_width: usize = if (self.config.show_line_numbers) 7 else 0;
        const cursor_row: usize = if (render_height > 0) blk: {
            const visible_row = buf.cursor.row -| buf.scroll_row;
            break :blk @min(visible_row + 1, render_height);
        }
        else if (size.rows > 0)
            1
        else
            0;
        const cursor_col = @min(buf.cursor.col + 1 + gutter_width, if (self.split_index != null and self.split_focus == .right and right_width > 0) right_width else left_width);
        const base_col = if (self.split_index != null and self.split_focus == .right and right_width > 0) right_x + 1 else 1;
        if (cursor_row > 0 and cursor_col > 0) {
            try writer.print("\x1b[{d};{d}H", .{ cursor_row, base_col + cursor_col - 1 });
        }
        try writer.flush();
    }

    fn renderStatusBar(self: *App, writer: anytype, cols: usize, row: usize) !void {
        const section_gap: usize = 2;
        const render_safety: usize = 2;
        const right_budget_floor: usize = 12;
        const mode_pill_width = displayWidth(modeIconText(self, self.mode)) + displayWidth(modeLabel(self.mode)) + 5;
        const available = if (cols > mode_pill_width + section_gap * 2 + render_safety)
            cols - mode_pill_width - section_gap * 2 - render_safety
        else
            0;
        const right_budget = if (available == 0) 0 else @min(available, @max(right_budget_floor, available / 3));
        const right_text = try self.statusBarRightText(self.allocator, right_budget);
        defer self.allocator.free(right_text);
        const mode_style = self.theme.modeStyle(self.mode);
        const mode_icon = modeIconText(self, self.mode);
        const right_width = displayWidth(right_text);
        const left_budget = if (available > right_width) available - right_width else 0;
        const left_text = try self.statusBarLeftText(self.allocator, left_budget);
        defer self.allocator.free(left_text);

        try writer.print("\x1b[{d};1H", .{row});
        try writeStyle(writer, self.theme.statusStyle());
        try writer.writeByte(' ');
        try writeStyledText(writer, mode_style, " ");
        try writeStyledText(writer, mode_style, mode_icon);
        try writer.writeByte(' ');
        try writeStyledText(writer, mode_style, modeLabel(self.mode));
        try writeStyledText(writer, mode_style, " ");
        try writeStyle(writer, self.theme.statusStyle());
        try writer.writeByte(' ');
        try writeStyledText(writer, self.theme.statusStyle(), left_text);

        var used: usize = mode_pill_width + section_gap + displayWidth(left_text);
        if (right_width > 0 and used + right_width < cols) {
            while (used + section_gap + right_width < cols) : (used += 1) {
                try writer.writeByte(' ');
            }
        }
        if (right_width > 0) {
            try writeStyledText(writer, self.theme.statusStyle(), right_text);
            used += right_width;
        }
        while (used < cols) : (used += 1) {
            try writer.writeByte(' ');
        }
        try writer.writeAll("\x1b[0m");
    }

    fn renderPromptBar(self: *App, writer: anytype, cols: usize, row: usize) !void {
        const detail = try self.promptBarText(self.allocator);
        defer self.allocator.free(detail);

        try writer.print("\x1b[{d};1H", .{row});
        try writeStyle(writer, self.theme.promptStyle());
        try writer.writeByte(' ');
        try writeStyledText(writer, self.theme.modeStyle(self.mode), modeLabel(self.mode));
        try writer.writeByte(' ');
        try writeStyledText(writer, .{ .fg = self.theme.border, .bg = self.theme.prompt_bg }, "|");
        try writer.writeByte(' ');
        try writeStyledText(writer, self.theme.promptStyle(), detail);
        var used: usize = 2 + modeLabel(self.mode).len + 3 + detail.len;
        while (used < cols) : (used += 1) {
            try writer.writeByte(' ');
        }
        try writer.writeAll("\x1b[0m");
    }

    fn renderPaneSeparator(self: *App, writer: anytype, x: usize, height: usize) !void {
        var row: usize = 0;
        while (row < height) : (row += 1) {
            try writer.print("\x1b[{d};{d}H", .{ row + 1, x + 1 });
            try writeStyledText(writer, self.theme.separatorStyle(), "|");
        }
    }

    fn renderPane(self: *App, writer: anytype, buffer: *buffer_mod.Buffer, x: usize, width: usize, height: usize, active: bool) !void {
        const max_scroll = if (buffer.lines.items.len > height) buffer.lines.items.len - height else 0;
        const start_row = if (buffer.lines.items.len == 0) 0 else @min(buffer.scroll_row, max_scroll);
        const active_search = self.activeSearchHighlight(active);
            const active_visual = if (active and (self.mode == .visual or self.mode == .select)) self.visualSelection() else null;
        var screen_row: usize = 0;
        var row = start_row;
        while (screen_row < height and row < buffer.lines.items.len) {
            if (buffer.foldAtRow(row)) |fold| {
                if (buffer.fold_enabled and fold.closed) {
                    if (row > fold.start_row) {
                        row = fold.end_row + 1;
                        continue;
                    }
                    try writer.print("\x1b[{d};{d}H", .{ screen_row + 1, x + 1 });
                    if (self.config.show_line_numbers) {
                        try writeStyle(writer, self.theme.lineNumberStyle(active));
                        try writer.print("{d: >4}", .{row + 1});
                        try writeStyle(writer, self.theme.separatorStyle());
                        try writer.writeAll(" | ");
                    }
                    const line = buffer.lines.items[row];
                    const gutter_width: usize = if (self.config.show_line_numbers) 7 else 0;
                    const available = if (width > gutter_width) width - gutter_width else 0;
                    try writeStyle(writer, self.theme.textStyle(active));
                    const suffix = "  [+fold]";
                    const room = if (available > suffix.len) available - suffix.len else 0;
                    try self.renderHighlightedLine(writer, line[0..@min(line.len, room)], row, available, active_search, active_visual, self.rowDecorationForBuffer(buffer, row), active);
                    try writeStyle(writer, self.theme.separatorStyle());
                    try writer.writeAll(suffix);
                    try writer.writeAll("\x1b[0m");
                    screen_row += 1;
                    row = fold.end_row + 1;
                    continue;
                }
            }
            try writer.print("\x1b[{d};{d}H", .{ screen_row + 1, x + 1 });
            if (self.config.show_line_numbers) {
                try writeStyle(writer, self.theme.lineNumberStyle(active));
                try writer.print("{d: >4}", .{row + 1});
                try writeStyle(writer, self.theme.separatorStyle());
                try writer.writeAll(" | ");
            }
            const line = buffer.lines.items[row];
            const gutter_width: usize = if (self.config.show_line_numbers) 7 else 0;
            const available = if (width > gutter_width) width - gutter_width else 0;
            try self.renderHighlightedLine(writer, line, row, available, active_search, active_visual, self.rowDecorationForBuffer(buffer, row), active);
            screen_row += 1;
            row += 1;
        }
    }

    fn renderPickerPane(self: *App, writer: anytype, cols: usize, row: usize, height: usize) !void {
        if (height == 0) return;
        const pane_style = self.theme.statusStyle();
        const title = if (self.picker.state == .loading)
            "picker loading"
        else if (self.picker.state == .failed)
            self.picker.error_message orelse "picker"
        else
            "picker";
        try writer.print("\x1b[{d};1H", .{row});
        try writeStyle(writer, pane_style);
        try writer.writeByte(' ');
        try writer.writeAll("󰌑 ");
        try writeStyledText(writer, pane_style, title);
        while (displayWidth(title) + 3 < cols) {
            try writer.writeByte(' ');
            if (displayWidth("picker") + 3 >= cols) break;
        }
        try writer.writeAll("\x1b[0m");

        if (height < 2) return;
        const visible_rows = height - 1;
        const total_items = self.picker.items.items.len;
        const selected = if (total_items == 0) 0 else @min(self.picker.selected, total_items - 1);
        const scroll = if (selected >= visible_rows and visible_rows > 0) selected - visible_rows + 1 else 0;
        var idx: usize = 0;
        while (idx < visible_rows) : (idx += 1) {
            const item_index = scroll + idx;
            const current_row = row + idx + 1;
            try writer.print("\x1b[{d};1H", .{current_row});
            if (item_index >= total_items) {
                try writeStyle(writer, pane_style);
                while (idx < visible_rows) : (idx += 1) {
                    try writer.print("\x1b[{d};1H", .{row + idx + 1});
                    try writeStyle(writer, pane_style);
                    try writer.writeByte(' ');
                    while (displayWidth("") + 1 < cols) {
                        try writer.writeByte(' ');
                        if (cols <= 1) break;
                        break;
                    }
                    try writer.writeAll("\x1b[0m");
                }
                break;
            }
            const item = self.picker.items.items[item_index];
            const active = item_index == selected;
            const prefix = if (active) ">" else " ";
            const prefix_style = if (active) self.theme.visualStyle() else pane_style;
            try writeStyle(writer, prefix_style);
            try writer.writeByte(' ');
            try writer.writeAll(prefix);
            try writer.writeByte(' ');
            const label_budget = if (cols > 4) cols - 4 else 0;
            const label = clipText(item.label, label_budget);
            try writeStyledText(writer, prefix_style, label);
            if (item.detail) |detail| {
                const room = if (cols > displayWidth(label) + 7) cols - displayWidth(label) - 7 else 0;
                if (room > 0) {
                    try writeStyledText(writer, pane_style, " │ ");
                    try writeStyledText(writer, pane_style, clipText(detail, room));
                }
            }
            while (displayWidth(label) + 4 < cols) {
                try writer.writeByte(' ');
                if (displayWidth(label) + 4 >= cols) break;
            }
            try writer.writeAll("\x1b[0m");
        }
    }

    fn renderTextOverlayPane(self: *App, writer: anytype, cols: usize, row: usize, height: usize, title: []const u8, text: []const u8) !void {
        if (height == 0) return;
        const pane_style = self.theme.statusStyle();
        try writer.print("\x1b[{d};1H", .{row});
        try writeStyle(writer, pane_style);
        try writer.writeByte(' ');
        try writer.writeAll(title);
        while (displayWidth(title) + 1 < cols) {
            try writer.writeByte(' ');
            if (cols <= displayWidth(title) + 1) break;
        }
        try writer.writeAll("\x1b[0m");

        if (height < 2) return;
        var lines = std.mem.splitScalar(u8, text, '\n');
        var current_row: usize = row + 1;
        while (current_row < row + height) : (current_row += 1) {
            try writer.print("\x1b[{d};1H", .{current_row});
            try writeStyle(writer, pane_style);
            if (lines.next()) |line| {
                try writer.writeByte(' ');
                try writer.writeAll(clipText(line, if (cols > 1) cols - 1 else 0));
            } else {
                try writer.writeByte(' ');
            }
            while (displayWidth("") + 1 < cols) {
                try writer.writeByte(' ');
                if (cols <= 1) break;
                break;
            }
            try writer.writeAll("\x1b[0m");
        }
    }

    fn findPaneById(self: *App, id: u64) ?*pane_mod.Pane {
        for (self.panes.panes.items) |*pane| {
            if (pane.id == id) return pane;
        }
        return null;
    }

    const HighlightKind = enum { base, search, visual, hint };
    const TextRange = struct { start: usize, end: usize };

    fn renderHighlightedLine(
        self: *App,
        writer: anytype,
        line: []const u8,
        row: usize,
        available: usize,
        search: ?[]const u8,
        visual: ?VisualSelection,
        decoration: ?[]const u8,
        active: bool,
    ) !void {
        const limit = @min(line.len, available);
        const visual_range = if (visual) |selection| self.visualRangeForRow(selection, row, line.len) else null;
        const search_needle = search orelse "";
        var search_range = if (search) |needle| self.nextSearchRange(line, needle, 0) else null;
        var col: usize = 0;
        const base_style = self.theme.textStyle(active);
        var current: HighlightKind = .base;
        try writeStyle(writer, base_style);
        while (col < limit) : (col += 1) {
            while (search_range) |range| {
                if (col < range.start) break;
                if (col >= range.end) {
                    search_range = self.nextSearchRange(line, search_needle, range.end);
                    continue;
                }
                break;
            }

            const in_visual = if (visual_range) |range| col >= range.start and col < range.end else false;
            const in_search = if (search_range) |span| col >= span.start and col < span.end else false;
            const kind: HighlightKind = if (in_visual) .visual else if (in_search) .search else .base;

            if (kind != current) {
                switch (kind) {
                    .base => try writeStyle(writer, base_style),
                    .search => try writeStyle(writer, self.theme.searchStyle()),
                    .visual => try writeStyle(writer, self.theme.visualStyle()),
                    .hint => try writeStyle(writer, self.theme.separatorStyle()),
                }
                current = kind;
            }
            try writer.writeByte(line[col]);
        }
        if (decoration) |hint| {
            if (limit < available and hint.len > 0) {
                const remaining = available - limit;
                if (remaining > 3) {
                    try writeStyle(writer, self.theme.separatorStyle());
                    try writer.writeAll(" │ ");
                    try writeStyledText(writer, self.theme.separatorStyle(), clipText(hint, remaining - 3));
                }
            }
        }
        try writer.writeAll("\x1b[0m");
    }

    fn nextSearchRange(self: *App, line: []const u8, needle: []const u8, start: usize) ?TextRange {
        _ = self;
        if (needle.len == 0 or start > line.len) return null;
        const hit = std.mem.indexOfPos(u8, line, start, needle) orelse return null;
        return .{ .start = hit, .end = hit + needle.len };
    }

    fn rowDecorationForBuffer(self: *App, buffer: *buffer_mod.Buffer, row: usize) ?[]const u8 {
        for (self.diagnostics.diagnostics.items) |diagnostic| {
            if (diagnostic.buffer_id == buffer.id and diagnostic.row == row) {
                return diagnostic.message;
            }
        }
        const path = buffer.path orelse return null;
        for (self.lsp.diagnostics.items) |diagnostic| {
            if (diagnostic.row == row) {
                if (diagnostic.path) |diag_path| {
                    if (std.mem.eql(u8, diag_path, path)) return diagnostic.message;
                }
            }
        }
        if (self.diagnostics.bestDecorationForRow(buffer.id, row)) |decoration| {
            if (decoration.text) |text| return text;
        }
        return null;
    }

    fn visualRangeForRow(self: *App, selection: VisualSelection, row: usize, line_len: usize) ?TextRange {
        return switch (self.visual_mode) {
            .block => if (self.visualBlockBounds()) |bounds| blk: {
                if (row < bounds.start_row or row > bounds.end_row) break :blk null;
                break :blk .{ .start = @min(bounds.start_col, line_len), .end = @min(bounds.end_col, line_len) };
            } else null,
            .line => if (row < selection.start.row or row > selection.end.row)
                null
            else
                .{ .start = 0, .end = line_len },
            else => if (row < selection.start.row or row > selection.end.row)
                null
            else if (selection.start.row == selection.end.row)
                .{ .start = @min(selection.start.col, line_len), .end = @min(selection.end.col, line_len) }
            else if (row == selection.start.row)
                .{ .start = @min(selection.start.col, line_len), .end = line_len }
            else if (row == selection.end.row)
                .{ .start = 0, .end = @min(selection.end.col, line_len) }
            else
                .{ .start = 0, .end = line_len },
        };
    }

    fn activeBuffer(self: *App) *buffer_mod.Buffer {
        if (self.split_index) |idx| {
            return switch (self.split_focus) {
                .left => &self.buffers.items[self.active_index],
                .right => &self.buffers.items[idx],
            };
        }
        return &self.buffers.items[self.active_index];
    }

    fn bufferById(self: *App, buffer_id: u64) ?*buffer_mod.Buffer {
        for (self.buffers.items) |*buffer| {
            if (buffer.id == buffer_id) return buffer;
        }
        return null;
    }

    fn selectionForBuffer(self: *App, buffer_id: u64) ?buffer_mod.Selection {
        const buffer = self.bufferById(buffer_id) orelse return null;
        if (self.buffers.items.len == 0) return null;
        if (buffer.id != self.activeBuffer().id) return null;
        const visual = self.visualSelection() orelse return null;
        return .{ .start = visual.start, .end = visual.end };
    }

    fn readBufferSnapshot(self: *App, buffer_id: u64) !buffer_mod.ReadSnapshot {
        const buffer = self.bufferById(buffer_id) orelse return error.BufferNotFound;
        return try buffer.readSnapshot(self.selectionForBuffer(buffer_id));
    }

    fn freeBufferSnapshot(self: *App, snapshot: buffer_mod.ReadSnapshot) void {
        self.allocator.free(snapshot.text);
    }

    fn beginBufferEdit(self: *App, buffer_id: u64) !buffer_mod.EditTransaction {
        const buffer = self.bufferById(buffer_id) orelse return error.BufferNotFound;
        return try buffer.beginTransaction();
    }

    fn workspaceInfo(self: *App) !plugin_mod.WorkspaceInfo {
        return .{
            .root_path = try self.allocator.dupe(u8, self.workspace.root_path),
            .session_generation = self.workspace.session_generation,
            .open_buffer_count = self.workspace.session.open_buffers.items.len,
        };
    }

    fn freeWorkspaceInfo(self: *App, info: plugin_mod.WorkspaceInfo) void {
        self.allocator.free(info.root_path);
    }

    fn freeBytes(self: *App, bytes: []u8) void {
        self.allocator.free(bytes);
    }

    fn syntaxNodeAtCursor(self: *App, buffer_id: u64) !?syntax_mod.Node {
        const snapshot = try self.readBufferSnapshot(buffer_id);
        defer self.freeBufferSnapshot(snapshot);
        return self.syntax.nodeAtCursor(snapshot);
    }

    fn syntaxFoldRange(self: *App, buffer_id: u64) !?syntax_mod.FoldRange {
        const snapshot = try self.readBufferSnapshot(buffer_id);
        defer self.freeBufferSnapshot(snapshot);
        return self.syntax.foldRangeForSnapshot(snapshot);
    }

    fn syntaxEnclosingScope(self: *App, buffer_id: u64) !?syntax_mod.FoldRange {
        const snapshot = try self.readBufferSnapshot(buffer_id);
        defer self.freeBufferSnapshot(snapshot);
        return self.syntax.enclosingScope(snapshot);
    }

    fn syntaxIndentForBufferRow(self: *App, buffer_id: u64, row: usize) !usize {
        const snapshot = try self.readBufferSnapshot(buffer_id);
        defer self.freeBufferSnapshot(snapshot);
        return self.syntax.indentForRow(snapshot, row);
    }

    fn syntaxTextObjectRange(self: *App, buffer_id: u64, inner: bool) !?syntax_mod.TextRange {
        const snapshot = try self.readBufferSnapshot(buffer_id);
        defer self.freeBufferSnapshot(snapshot);
        return self.syntax.textObjectRange(snapshot, inner);
    }

    fn lspRequestDefinition(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestDefinition(payload);
    }

    fn lspRequestReferences(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestReferences(payload);
    }

    fn lspRequestRename(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestRename(payload);
    }

    fn lspRequestCompletion(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestCompletion(payload);
    }

    fn lspRequestHover(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestHover(payload);
    }

    fn lspRequestCodeAction(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestCodeActions(payload);
    }

    fn lspRequestSemanticTokens(self: *App, payload: []const u8) !u64 {
        return try self.lsp.requestSemanticTokens(payload);
    }

    fn activeSearchHighlight(self: *App, active: bool) ?[]const u8 {
        if (!active) return null;
        if (self.mode == .search) return self.search_preview_highlight orelse self.search_highlight;
        return self.search_highlight;
    }

    fn statusBarText(self: *App, allocator: std.mem.Allocator) ![]u8 {
        const left = try self.statusBarLeftText(allocator, std.math.maxInt(usize));
        defer allocator.free(left);
        const right = try self.statusBarRightText(allocator, std.math.maxInt(usize));
        defer allocator.free(right);
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        try out.appendSlice(modeIconText(self, self.mode));
        try out.appendByte(' ');
        try out.appendSlice(modeLabel(self.mode));
        try out.appendSlice(" | ");
        try out.appendSlice(left);
        if (right.len > 0) {
            try out.appendSlice(" | ");
            try out.appendSlice(right);
        }
        return try out.toOwnedSlice();
    }

    fn statusBarLeftText(self: *App, allocator: std.mem.Allocator, max_width: usize) ![]u8 {
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        if (max_width == 0) return try out.toOwnedSlice();

        const name = self.activeBuffer().path orelse "[No Name]";
        const file_prefix = "󰈙 ";
        const file_prefix_width = displayWidth(file_prefix);
        if (file_prefix_width > max_width) return try out.toOwnedSlice();
        const file_budget = if (max_width > file_prefix_width) max_width - file_prefix_width else 0;
        const clipped_name = clipText(name, file_budget);
        try out.appendSlice(file_prefix);
        try out.appendSlice(clipped_name);

        var used: usize = file_prefix_width + displayWidth(clipped_name);
        const split_text = if (self.split_index != null) if (self.split_focus == .left) " [L]" else " [R]" else "";
        const dirty_text = if (self.activeBuffer().dirty) " │ ● modified" else "";
        const diff_text = if (self.diff_mode) " │ diff" else "";
        const extras = [_][]const u8{ split_text, dirty_text, diff_text };
        for (extras) |extra| {
            const extra_width = displayWidth(extra);
            if (extra_width == 0) continue;
            if (used + extra_width > max_width) break;
            try out.appendSlice(extra);
            used += extra_width;
        }
        return try out.toOwnedSlice();
    }

    fn statusBarRightText(self: *App, allocator: std.mem.Allocator, max_width: usize) ![]u8 {
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        if (max_width == 0) return try out.toOwnedSlice();

        const buf = self.activeBuffer();
        const line_count = buf.lineCount();
        const row = if (line_count == 0) 0 else @min(buf.cursor.row, line_count - 1);
        const col = if (line_count == 0) 0 else @min(buf.cursor.col, buf.lines.items[row].len);
        const percent = if (line_count <= 1) 100 else @min(100, ((row + 1) * 100) / line_count);

        const location = try std.fmt.allocPrint(allocator, "L/N {d}:{d}", .{ row + 1, col + 1 });
        defer allocator.free(location);
        const progress = try std.fmt.allocPrint(allocator, "{d}%", .{percent});
        defer allocator.free(progress);

        const app_status = self.status.items;
        const builtin_status = self.builtins.statusText();
        const plugin_status_local = try self.plugin_catalog.statusText(self.allocator);
        defer self.allocator.free(plugin_status_local);
        const git_branch = try self.workspace.gitBranchName(self.allocator);
        defer self.allocator.free(git_branch);
        const git_status = if (git_branch.len == 0) try self.allocator.dupe(u8, "") else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "git {s}", .{git_branch});
        };
        defer self.allocator.free(git_status);
        const builtin_status_combined = if (builtin_status.len == 0) plugin_status_local else if (plugin_status_local.len == 0) builtin_status else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{s} | {s}", .{ builtin_status, plugin_status_local });
        };
        defer if (builtin_status_combined.len > 0 and builtin_status_combined.ptr != builtin_status.ptr and builtin_status_combined.ptr != plugin_status_local.ptr) self.allocator.free(builtin_status_combined);
        const diagnostics_status_local = try self.diagnostics.statusText(self.allocator);
        defer self.allocator.free(diagnostics_status_local);
        const lsp_diagnostics_status = try self.lsp.statusText(self.allocator);
        defer self.allocator.free(lsp_diagnostics_status);
        const diagnostics_status = if (diagnostics_status_local.len == 0) lsp_diagnostics_status else if (lsp_diagnostics_status.len == 0) diagnostics_status_local else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{s} | LSP {s}", .{ diagnostics_status_local, lsp_diagnostics_status });
        };
        defer if (diagnostics_status.len > 0 and diagnostics_status.ptr != diagnostics_status_local.ptr and diagnostics_status.ptr != lsp_diagnostics_status.ptr) self.allocator.free(diagnostics_status);
        const pane_status = if (self.panes.panes.items.len > 1) try self.panes.statusText(self.allocator) else try self.allocator.dupe(u8, "");
        defer self.allocator.free(pane_status);
        const picker_status = if (self.picker.query.items.len > 0 or self.picker.items.items.len > 0) try self.picker.statusText(self.allocator, "picker") else try self.allocator.dupe(u8, "");
        defer self.allocator.free(picker_status);
        const quickfix_status = if (self.quickfix_list.query.items.len > 0 or self.quickfix_list.items.items.len > 0) try self.quickfix_list.statusText(self.allocator, "quickfix") else try self.allocator.dupe(u8, "");
        defer self.allocator.free(quickfix_status);
        const syntax_status = try self.syntax.statusText(self.allocator, buf.id, buf.filetypeText());
        defer self.allocator.free(syntax_status);
        const file_status = try std.fmt.allocPrint(self.allocator, "{s} {s} {s}", .{ buf.filetypeText(), buf.encodingText(), buf.lineEndingText() });
        defer self.allocator.free(file_status);
        const macro_status = if (self.macro_recording) |reg| blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "recording @{c}", .{reg});
        } else try self.allocator.dupe(u8, "");
        defer self.allocator.free(macro_status);
        const app_prefix = "󰞋 ";
        const builtin_prefix = "󰒓 ";
        const diagnostics_prefix = "󰧑 ";
        const pane_prefix = "󰓩 ";
        const picker_prefix = "󰌑 ";
        const quickfix_prefix = "󰜴 ";
        const git_prefix = "󰓒 ";
        const syntax_prefix = "󰚛 ";
        const file_prefix = "󰏫 ";
        const macro_prefix = "󰘥 ";
        const app_width = if (app_status.len > 0) displayWidth(app_prefix) + displayWidth(app_status) else 0;
        const builtin_width = if (builtin_status_combined.len > 0) displayWidth(builtin_prefix) + displayWidth(builtin_status_combined) else 0;
        const diagnostics_width = if (diagnostics_status.len > 0) displayWidth(diagnostics_prefix) + displayWidth(diagnostics_status) else 0;
        const pane_width = if (pane_status.len > 0) displayWidth(pane_prefix) + displayWidth(pane_status) else 0;
        const picker_width = if (picker_status.len > 0) displayWidth(picker_prefix) + displayWidth(picker_status) else 0;
        const quickfix_width = if (quickfix_status.len > 0) displayWidth(quickfix_prefix) + displayWidth(quickfix_status) else 0;
        const git_width = if (git_status.len > 0) displayWidth(git_prefix) + displayWidth(git_status) else 0;
        const syntax_width = if (syntax_status.len > 0) displayWidth(syntax_prefix) + displayWidth(syntax_status) else 0;
        const file_width = if (file_status.len > 0) displayWidth(file_prefix) + displayWidth(file_status) else 0;
        const macro_width = if (macro_status.len > 0) displayWidth(macro_prefix) + displayWidth(macro_status) else 0;
        const location_width = displayWidth(location);
        const progress_width = displayWidth(progress);
        const sep_width: usize = displayWidth(" │ ");

        var include_app = app_width > 0 and max_width >= app_width + builtin_width + diagnostics_width + pane_width + picker_width + quickfix_width + git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        var include_builtin = builtin_width > 0 and max_width >= builtin_width + diagnostics_width + pane_width + picker_width + quickfix_width + git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        var include_diagnostics = diagnostics_width > 0 and max_width >= diagnostics_width + pane_width + picker_width + quickfix_width + git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        var include_pane = pane_width > 0 and max_width >= pane_width + picker_width + quickfix_width + git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        var include_picker = picker_width > 0 and max_width >= picker_width + quickfix_width + git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        var include_quickfix = quickfix_width > 0 and max_width >= quickfix_width + git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        var include_git = git_width > 0 and max_width >= git_width + syntax_width + file_width + macro_width + location_width + progress_width;
        const include_syntax = syntax_width > 0 and max_width >= syntax_width + file_width + macro_width + location_width + progress_width;
        var include_file = file_width > 0 and max_width >= file_width + macro_width + location_width + progress_width;
        var include_macro = macro_width > 0 and max_width >= macro_width + location_width + progress_width;

        const mandatory_width = location_width + progress_width + (if (location_width > 0 and progress_width > 0) sep_width else 0);
        if (mandatory_width > max_width) {
            const progress_budget = if (max_width > location_width + sep_width) max_width - location_width - sep_width else 0;
            const clipped_location = clipText(location, if (max_width > progress_width + sep_width) max_width - progress_width - sep_width else 0);
            try out.appendSlice(clipped_location);
            if (clipped_location.len > 0 and progress_budget > 0) {
                try out.appendSlice(" │ ");
            }
            try out.appendSlice(clipText(progress, progress_budget));
            const clipped_width = displayWidth(out.items);
            if (clipped_width <= max_width) return try out.toOwnedSlice();
            const clipped = clipText(out.items, max_width);
            var clipped_out = std.array_list.Managed(u8).init(allocator);
            errdefer clipped_out.deinit();
            try clipped_out.appendSlice(clipped);
            return try clipped_out.toOwnedSlice();
        }

        if (include_app) {
            try out.appendSlice(app_prefix);
            try out.appendSlice(app_status);
        }
        if (include_builtin) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(builtin_prefix);
            try out.appendSlice(builtin_status_combined);
        }
        if (include_diagnostics) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(diagnostics_prefix);
            try out.appendSlice(diagnostics_status);
        }
        if (include_pane) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(pane_prefix);
            try out.appendSlice(pane_status);
        }
        if (include_picker) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(picker_prefix);
            try out.appendSlice(picker_status);
        }
        if (include_quickfix) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(quickfix_prefix);
            try out.appendSlice(quickfix_status);
        }
        if (include_git) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(git_prefix);
            try out.appendSlice(git_status);
        }
        if (include_syntax) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(syntax_prefix);
            try out.appendSlice(syntax_status);
        }
        if (include_file) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(file_prefix);
            try out.appendSlice(file_status);
        }
        if (include_macro) {
            if (out.items.len > 0) try out.appendSlice(" │ ");
            try out.appendSlice(macro_prefix);
            try out.appendSlice(macro_status);
        }
        if (out.items.len > 0) try out.appendSlice(" │ ");
        try out.appendSlice(location);
        if (progress.len > 0) {
            try out.appendSlice(" │ ");
            try out.appendSlice(progress);
        }

        const final_width = displayWidth(out.items);
        if (final_width <= max_width) return try out.toOwnedSlice();

        // Drop low-priority activity fields if the right side still overflows.
        out.clearRetainingCapacity();
        include_app = false;
        include_builtin = builtin_width > 0 and max_width >= builtin_width + location_width + progress_width + sep_width * 2;
        include_diagnostics = false;
        include_pane = false;
        include_picker = false;
        include_quickfix = false;
        include_git = false;
        include_file = false;
        include_macro = false;
        if (include_builtin) {
            try out.appendSlice(builtin_prefix);
            try out.appendSlice(builtin_status_combined);
            try out.appendSlice(" │ ");
        }
        try out.appendSlice(location);
        try out.appendSlice(" │ ");
        try out.appendSlice(progress);
        if (displayWidth(out.items) <= max_width) return try out.toOwnedSlice();
        const clipped = clipText(out.items, max_width);
        var clipped_out = std.array_list.Managed(u8).init(allocator);
        errdefer clipped_out.deinit();
        try clipped_out.appendSlice(clipped);
        return try clipped_out.toOwnedSlice();
    }

    fn promptBarText(self: *App, allocator: std.mem.Allocator) ![]u8 {
        const prompt = if (self.mode == .command) self.command_buffer.items else self.search_buffer.items;
        const prefix: []const u8 = if (self.mode == .command) ":" else if (self.search_forward) "/" else "?";
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, prompt });
    }

    fn jsonStringLiteral(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
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
        return try out.toOwnedSlice();
    }

    fn toggleSplitFocus(self: *App) void {
        if (self.split_index != null) {
            self.split_focus = switch (self.split_focus) {
                .left => .right,
                .right => .left,
            };
        }
    }

    fn equalizeWindows(self: *App) !void {
        if (self.split_index == null) {
            try self.setStatus("no other window");
            return;
        }
        self.config.split_ratio = 50;
        try self.setStatus("windows equalized");
    }

    fn resizeSplitBy(self: *App, delta: isize) !void {
        if (self.split_index == null) {
            try self.setStatus("no split");
            return;
        }
        const focus_delta: isize = if (self.split_focus == .left) delta else -delta;
        const current: isize = @intCast(self.config.split_ratio);
        const next = std.math.clamp(current + focus_delta, 5, 95);
        self.config.split_ratio = @intCast(next);
        try self.setStatus("window resized");
    }

    fn maximizeSplit(self: *App) !void {
        if (self.split_index == null) {
            try self.setStatus("no split");
            return;
        }
        self.config.split_ratio = if (self.split_focus == .left) 100 else 0;
        try self.setStatus("window maximized");
    }

    fn setStatus(self: *App, text: []const u8) !void {
        self.status.clearRetainingCapacity();
        try self.status.appendSlice(text);
    }

    fn syncWorkspaceSession(self: *App) !void {
        for (self.workspace.session.open_buffers.items) |path| {
            self.allocator.free(path);
        }
        self.workspace.session.open_buffers.clearRetainingCapacity();
        for (self.buffers.items) |buf| {
            if (buf.path) |path| {
                try self.workspace.session.open_buffers.append(try self.allocator.dupe(u8, path));
            }
        }
        self.workspace.session.active_index = @min(self.active_index, if (self.buffers.items.len == 0) 0 else self.buffers.items.len - 1);
        self.workspace.session.split_index = if (self.split_index) |idx| idx else null;
        self.workspace.session.split_focus_right = self.split_focus == .right;
        self.workspace.session.split_ratio = self.config.split_ratio;
        self.workspace.session.selected_picker_index = if (self.picker.items.items.len == 0) 0 else @min(self.picker.selected, self.picker.items.items.len - 1);
        self.workspace.session.selected_diagnostics_index = if (self.diagnostics_list.items.items.len == 0) 0 else @min(self.diagnostics_list.selected, self.diagnostics_list.items.items.len - 1);
    }

    fn syncActiveSyntax(self: *App) void {
        const buf = self.activeBuffer();
        if (self.syntax.snapshotGeneration(buf.id)) |generation| {
            if (generation == buf.generation) return;
        }
        const snapshot = buf.readSnapshot(null) catch return;
        defer buf.freeReadSnapshot(snapshot);
        self.syntax.updateSnapshot(snapshot) catch {};
        self.syntax.applyDecorations(&self.diagnostics, snapshot) catch {};
    }

    fn builtinHost(self: *App) builtins_mod.Host {
        return .{
            .ctx = self,
            .caps = .{
                .command = true,
                .event = true,
                .status = true,
                .buffer_read = true,
                .buffer_edit = true,
                .jobs = true,
                .workspace = true,
                .diagnostics = true,
                .picker = true,
                .pane = true,
                .fs_read = true,
                .tree_query = true,
                .decoration = true,
                .lsp = true,
            },
            .set_status = builtinSetStatus,
            .set_extension_status = builtinSetExtensionStatus,
            .set_plugin_activity = builtinSetPluginActivity,
            .register_command = builtinRegisterCommand,
            .register_event = builtinRegisterEvent,
            .spawn_job = builtinSpawnJob,
            .add_decoration = builtinAddDecoration,
            .set_pane_text = builtinSetPaneText,
            .create_pane = builtinCreatePane,
            .focus_pane = builtinFocusPane,
            .open_picker = builtinOpenPicker,
            .set_picker_items = builtinSetPickerItems,
            .append_picker_item = builtinAppendPickerItem,
            .set_picker_preview = builtinSetPickerPreview,
            .cancel_picker = builtinCancelPicker,
            .read_buffer_snapshot = builtinReadBufferSnapshot,
            .free_buffer_snapshot = builtinFreeBufferSnapshot,
            .begin_buffer_edit = builtinBeginBufferEdit,
            .read_buffer_selection = builtinReadBufferSelection,
            .workspace_info = builtinWorkspaceInfo,
            .read_file = builtinReadFile,
            .free_bytes = builtinFreeBytes,
            .syntax_node_at_cursor = builtinSyntaxNodeAtCursor,
            .syntax_fold_range = builtinSyntaxFoldRange,
            .syntax_enclosing_scope = builtinSyntaxEnclosingScope,
            .syntax_indent_for_row = builtinSyntaxIndentForRow,
            .syntax_text_object_range = builtinSyntaxTextObjectRange,
            .request_definition = builtinRequestDefinition,
            .request_references = builtinRequestReferences,
            .request_rename = builtinRequestRename,
            .request_completion = builtinRequestCompletion,
            .request_hover = builtinRequestHover,
            .request_code_action = builtinRequestCodeAction,
            .request_semantic_tokens = builtinRequestSemanticTokens,
        };
    }

    fn emitBuiltinEvent(self: *App, event: []const u8, payload: []const u8) void {
        var host = self.builtinHost();
        self.builtins.emit(&host, event, payload);
    }

    fn invokeBuiltinCommand(self: *App, name: []const u8, args: []const []const u8) !bool {
        var host = self.builtinHost();
        return try self.builtins.invokeCommand(&host, name, args);
    }

    fn printHelp() !void {
        std.debug.print(
            \\Beam editor
            \\  beam [--config path] [file]
            \\Commands:
            \\  :help keyword  open help for a keyword
            \\  :w             save buffer
            \\  :wq            save and quit
            \\  :q             quit
            \\  :q!            force quit
            \\  :saveas PATH   save buffer as a new file
            \\  :close         close current pane
            \\  :terminal      open a terminal pane
            \\  :edit PATH     open path in a buffer
            \\  :open PATH     open path in a new buffer
            \\  :bd            delete the current buffer
            \\  :bn / :bp      move to next / previous buffer
            \\  :buffer N|PATH switch to a buffer by index or path
            \\  :buffers       list open buffers
            \\  :split PATH    open path in split view
            \\  :sp PATH      split and open a path
            \\  :vs PATH      vertical split and open a path
            \\  :tabnew PATH   open path in a new tab
            \\  :tabclose      close current tab
            \\  :tabonly       keep only the current tab
            \\  :tabmove N     move current tab to index N
            \\  :refresh-sources refresh picker and diagnostics sources
            \\  :lsp ACTION      issue an LSP request (definition, hover, completion, references, rename, code-action, semantic-tokens)
            \\  :plugins        show loaded plugin manifests
            \\  :vimgrep /pat/ [path] search files for a pattern
            \\  :pickgrep /pat/ [path] search files into the picker
            \\  :files [path]   list files into the picker
            \\  :symbols PAT    list symbols into the picker
            \\  :diagnostics   open the diagnostics pane
            \\  :dnext / :dprev / :dopen diagnostics navigation and jump
            \\  :cn / :cp      next / previous quickfix item
            \\  :pnext / :pprev / :popen picker navigation and open
            \\  :cope / :ccl   show / clear quickfix results
            \\  :zf / :za / :zo / :zc / :zE / :zr / :zm / :zi fold commands
            \\  :diffthis / :diffoff / :diffupdate / :diffget / :diffput
            \\  Ctrl+w s/v/n  split window / new empty window
            \\  Ctrl+w +/-    resize window narrower / wider
            \\  Ctrl+w </>    resize window narrower / wider
            \\  Ctrl+w \\ |   maximize window width
            \\  Ctrl+w _      maximize window height
            \\  Ctrl+w =      equalize window sizes
            \\  Ctrl+w w      switch windows
            \\  Ctrl+w q      quit a window
            \\  Ctrl+w T      move split into its own tab
            \\  Normal mode   motions compose with operators and text objects; Zig block objects prefer Tree-sitter
            \\                examples: dw, ciw, d$, y$, VG
            \\  Normal mode   line anchors: 0 ^ $ and g0 g^ g$
            \\  Normal mode   local find motions: f/F/t/T with ; and ,
            \\  [keymap.leader] leader-prefixed normal-mode mappings
            \\  ]<leader> / [<leader> add a blank line below / above without entering insert mode
            \\  <leader>x     confirm close of the current split, tab, or buffer
            \\  :reload-config reload TOML config
            \\  :registers     list register contents
            \\  :builtin NAME   invoke a registered native built-in command
            \\
        , .{});
    }
};

fn builtinSetStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    try app.setStatus(text);
}

fn builtinSetExtensionStatus(ctx: *anyopaque, text: []const u8) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    try app.builtins.setStatus(text);
}

fn builtinSetPluginActivity(ctx: *anyopaque, text: []const u8) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.plugin_activity.clearRetainingCapacity();
    try app.plugin_activity.appendSlice(text);
    try app.syncPluginPane();
}

fn builtinRegisterCommand(ctx: *anyopaque, name: []const u8, description: []const u8, handler: builtins_mod.CommandHandler) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    try app.builtins.registerExtensionCommand(name, description, handler);
}

fn builtinRegisterEvent(ctx: *anyopaque, event: []const u8, handler: builtins_mod.EventHandler) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    try app.builtins.registerExtensionEvent(event, handler);
}

fn builtinSpawnJob(ctx: *anyopaque, kind: scheduler_mod.JobKind, request_generation: u64, workspace_generation: u64) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.scheduler.spawn(kind, request_generation, workspace_generation);
}

fn builtinAddDecoration(ctx: *anyopaque, decoration: diagnostics_mod.Decoration) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    try app.diagnostics.addDecoration(decoration);
}

fn builtinSetPaneText(ctx: *anyopaque, pane_id: u64, title: []const u8, text: []const u8) anyerror!void {
    const app: *App = @ptrCast(@alignCast(ctx));
    if (!try app.panes.updateTitle(pane_id, title)) return;
    _ = app.panes.clearStreaming(pane_id);
    _ = try app.panes.appendStreaming(pane_id, text);
}

fn builtinCreatePane(ctx: *anyopaque, kind: plugin_mod.PaneKind, title: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    const id = try app.panes.open(kind, title);
    _ = app.panes.focus(id);
    return id;
}

fn builtinFocusPane(ctx: *anyopaque, pane_id: u64) bool {
    const app: *App = @ptrCast(@alignCast(ctx));
    return app.panes.focus(pane_id);
}

    fn builtinOpenPicker(ctx: *anyopaque, title: []const u8, query: []const u8) anyerror!void {
        const app: *App = @ptrCast(@alignCast(ctx));
        try app.openPluginPicker(title, query);
    }

    fn builtinSetPickerItems(ctx: *anyopaque, items: []const listpane_mod.Item) anyerror!void {
        const app: *App = @ptrCast(@alignCast(ctx));
        try app.setPluginPickerItems(items);
    }

    fn builtinAppendPickerItem(ctx: *anyopaque, item: listpane_mod.Item) anyerror!void {
        const app: *App = @ptrCast(@alignCast(ctx));
        try app.appendPluginPickerItem(item);
    }

    fn builtinSetPickerPreview(ctx: *anyopaque, preview: ?[]const u8) anyerror!void {
        const app: *App = @ptrCast(@alignCast(ctx));
        try app.setPluginPickerPreview(preview);
    }

    fn builtinCancelPicker(ctx: *anyopaque) void {
        const app: *App = @ptrCast(@alignCast(ctx));
        app.cancelPluginPicker();
    }

    fn builtinReadBufferSnapshot(ctx: *anyopaque, buffer_id: u64) anyerror!buffer_mod.ReadSnapshot {
        const app: *App = @ptrCast(@alignCast(ctx));
        return try app.readBufferSnapshot(buffer_id);
    }

fn builtinFreeBufferSnapshot(ctx: *anyopaque, snapshot: buffer_mod.ReadSnapshot) void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.freeBufferSnapshot(snapshot);
}

fn builtinBeginBufferEdit(ctx: *anyopaque, buffer_id: u64) anyerror!buffer_mod.EditTransaction {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.beginBufferEdit(buffer_id);
}

fn builtinReadBufferSelection(ctx: *anyopaque, buffer_id: u64) anyerror!?buffer_mod.Selection {
    const app: *App = @ptrCast(@alignCast(ctx));
    return app.selectionForBuffer(buffer_id);
}

fn builtinWorkspaceInfo(ctx: *anyopaque) anyerror!plugin_mod.WorkspaceInfo {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.workspaceInfo();
}

fn builtinReadFile(ctx: *anyopaque, path: []const u8) anyerror![]u8 {
    const app: *App = @ptrCast(@alignCast(ctx));
    const resolved = try std.fs.path.resolve(app.allocator, &[_][]const u8{ app.workspace.root_path, path });
    defer app.allocator.free(resolved);
    if (!std.mem.eql(u8, resolved, app.workspace.root_path)) {
        if (resolved.len <= app.workspace.root_path.len) return error.AccessDenied;
        if (!std.mem.eql(u8, resolved[0..app.workspace.root_path.len], app.workspace.root_path)) return error.AccessDenied;
        if (resolved[app.workspace.root_path.len] != std.fs.path.sep) return error.AccessDenied;
    }
    return try std.fs.cwd().readFileAlloc(app.allocator, resolved, 1 << 26);
}

fn builtinFreeBytes(ctx: *anyopaque, bytes: []u8) void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.freeBytes(bytes);
}

fn builtinSyntaxNodeAtCursor(ctx: *anyopaque, buffer_id: u64) anyerror!?syntax_mod.Node {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.syntaxNodeAtCursor(buffer_id);
}

fn builtinSyntaxFoldRange(ctx: *anyopaque, buffer_id: u64) anyerror!?syntax_mod.FoldRange {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.syntaxFoldRange(buffer_id);
}

fn builtinSyntaxEnclosingScope(ctx: *anyopaque, buffer_id: u64) anyerror!?syntax_mod.FoldRange {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.syntaxEnclosingScope(buffer_id);
}

fn builtinSyntaxIndentForRow(ctx: *anyopaque, buffer_id: u64, row: usize) anyerror!usize {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.syntaxIndentForBufferRow(buffer_id, row);
}

fn builtinSyntaxTextObjectRange(ctx: *anyopaque, buffer_id: u64, inner: bool) anyerror!?syntax_mod.TextRange {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.syntaxTextObjectRange(buffer_id, inner);
}

fn builtinRequestDefinition(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestDefinition(payload);
}

fn builtinRequestReferences(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestReferences(payload);
}

fn builtinRequestRename(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestRename(payload);
}

fn builtinRequestCompletion(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestCompletion(payload);
}

fn builtinRequestHover(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestHover(payload);
}

fn builtinRequestCodeAction(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestCodeAction(payload);
}

fn builtinRequestSemanticTokens(ctx: *anyopaque, payload: []const u8) anyerror!u64 {
    const app: *App = @ptrCast(@alignCast(ctx));
    return try app.lspRequestSemanticTokens(payload);
}

fn testInteractiveCommandHook(app: *App, argv: []const []const u8) bool {
    if (app.last_interactive_command) |cmd| app.allocator.free(cmd);
    app.last_interactive_command = std.mem.join(app.allocator, "\t", argv) catch return false;
    return true;
}

fn testClipboardGetHook(app: *App) ?[]const u8 {
    return app.clipboard_contents;
}

fn testClipboardSetHook(app: *App, text: []const u8) bool {
    if (app.clipboard_contents) |existing| app.allocator.free(existing);
    app.clipboard_contents = app.allocator.dupe(u8, text) catch return false;
    return true;
}

fn makeTestApp(allocator: std.mem.Allocator, text: []const u8) !App {
    const args = [_][:0]const u8{"beam"};
    var app = try App.init(allocator, args[0..]);
    errdefer app.deinit();
    var buf = try buffer_mod.Buffer.initEmpty(allocator);
    errdefer buf.deinit();
    try buf.setText(text);
    try app.buffers.append(buf);
    app.active_index = 0;
    return app;
}

fn makeTestAppWithFiletype(allocator: std.mem.Allocator, text: []const u8, filetype: []const u8) !App {
    var app = try makeTestApp(allocator, text);
    errdefer app.deinit();
    var buf = app.activeBuffer();
    buf.allocator.free(buf.filetype);
    buf.filetype = try buf.allocator.dupe(u8, filetype);
    app.syncActiveSyntax();
    return app;
}

fn pressNormalKeys(app: *App, keys: []const u8) !void {
    for (keys) |key| {
        try app.handleNormalByte(key);
    }
}

fn setCursor(app: *App, row: usize, col: usize) void {
    app.activeBuffer().cursor = .{ .row = row, .col = col };
}

const LeaderBindingSeed = struct {
    sequence: []const u8,
    action: []const u8,
};

const exampleLeaderBindings = [_]LeaderBindingSeed{
    .{ .sequence = "w", .action = "save" },
    .{ .sequence = "q", .action = "quit" },
    .{ .sequence = "Q", .action = "force_quit" },
    .{ .sequence = "s", .action = "window_split_horizontal" },
    .{ .sequence = "v", .action = "window_split_vertical" },
    .{ .sequence = "h", .action = "window_left" },
    .{ .sequence = "j", .action = "window_down" },
    .{ .sequence = "k", .action = "window_up" },
    .{ .sequence = "l", .action = "window_right" },
    .{ .sequence = "t", .action = "tab_next" },
    .{ .sequence = "T", .action = "tab_prev" },
    .{ .sequence = "x", .action = "close_prompt" },
};

fn configureLeader(app: *App, leader: []const u8, bindings: []const LeaderBindingSeed) !void {
    app.config.allocator.free(app.config.keymap.leader);
    app.config.keymap.leader = try app.config.allocator.dupe(u8, leader);
    for (app.config.keymap.leader_bindings.items) |binding| {
        app.config.allocator.free(binding.sequence);
        app.config.allocator.free(binding.action);
    }
    app.config.keymap.leader_bindings.clearRetainingCapacity();
    for (bindings) |binding| {
        try app.config.keymap.leader_bindings.append(.{
            .sequence = try app.config.allocator.dupe(u8, binding.sequence),
            .action = try app.config.allocator.dupe(u8, binding.action),
        });
    }
}

const VisualBindingStatus = enum { verified, todo };

const visual_binding_checklist = [_]struct {
    tag: []const u8,
    sequence: []const u8,
    status: VisualBindingStatus,
    note: []const u8,
}{
    .{ .tag = "v_CTRL-_CTRL-N", .sequence = "CTRL-\\ CTRL-N", .status = .verified, .note = "stop Visual mode" },
    .{ .tag = "v_CTRL-_CTRL-G", .sequence = "CTRL-\\ CTRL-G", .status = .verified, .note = "go to Normal mode" },
    .{ .tag = "v_CTRL-A", .sequence = "CTRL-A", .status = .verified, .note = "add N to number in highlighted text" },
    .{ .tag = "v_CTRL-C", .sequence = "CTRL-C", .status = .verified, .note = "stop Visual mode" },
    .{ .tag = "v_CTRL-G", .sequence = "CTRL-G", .status = .verified, .note = "toggle between Visual mode and Select mode" },
    .{ .tag = "v_<BS>", .sequence = "<BS>", .status = .verified, .note = "Select mode: delete highlighted area" },
    .{ .tag = "v_CTRL-H", .sequence = "CTRL-H", .status = .verified, .note = "same as <BS>" },
    .{ .tag = "v_CTRL-O", .sequence = "CTRL-O", .status = .verified, .note = "switch from Select to Visual mode for one command" },
    .{ .tag = "v_CTRL-V", .sequence = "CTRL-V", .status = .verified, .note = "make Visual mode blockwise or stop Visual mode" },
    .{ .tag = "v_CTRL-X", .sequence = "CTRL-X", .status = .verified, .note = "subtract N from number in highlighted text" },
    .{ .tag = "v_<Esc>", .sequence = "<Esc>", .status = .verified, .note = "stop Visual mode" },
    .{ .tag = "v_CTRL-]", .sequence = "CTRL-]", .status = .verified, .note = "jump to highlighted tag" },
    .{ .tag = "v_!", .sequence = "!{filter}", .status = .verified, .note = "filter the highlighted lines through {filter}" },
    .{ .tag = "v_:", .sequence = ":", .status = .verified, .note = "start a command-line with the highlighted lines as a range" },
    .{ .tag = "v_<", .sequence = "<", .status = .verified, .note = "shift the highlighted lines one shiftwidth left" },
    .{ .tag = "v_=", .sequence = "=", .status = .verified, .note = "filter the highlighted lines through equalprg" },
    .{ .tag = "v_>", .sequence = ">", .status = .verified, .note = "shift the highlighted lines one shiftwidth right" },
    .{ .tag = "v_b_A", .sequence = "A", .status = .verified, .note = "block mode append after the highlighted area" },
    .{ .tag = "v_C", .sequence = "C", .status = .verified, .note = "delete the highlighted lines and start insert" },
    .{ .tag = "v_D", .sequence = "D", .status = .verified, .note = "delete the highlighted lines" },
    .{ .tag = "v_b_I", .sequence = "I", .status = .verified, .note = "block mode insert before the highlighted area" },
    .{ .tag = "v_J", .sequence = "J", .status = .verified, .note = "join the highlighted lines" },
    .{ .tag = "v_K", .sequence = "K", .status = .verified, .note = "run keywordprg on the highlighted area" },
    .{ .tag = "v_O", .sequence = "O", .status = .verified, .note = "move horizontally to the other corner of the area" },
    .{ .tag = "v_P", .sequence = "P", .status = .verified, .note = "replace highlighted area with register contents" },
    .{ .tag = "v_R", .sequence = "R", .status = .verified, .note = "delete the highlighted lines and start insert" },
    .{ .tag = "v_S", .sequence = "S", .status = .verified, .note = "delete the highlighted lines and start insert" },
    .{ .tag = "v_U", .sequence = "U", .status = .verified, .note = "make highlighted area uppercase" },
    .{ .tag = "v_V", .sequence = "V", .status = .verified, .note = "make Visual mode linewise or stop Visual mode" },
    .{ .tag = "v_X", .sequence = "X", .status = .verified, .note = "delete the highlighted lines" },
    .{ .tag = "v_Y", .sequence = "Y", .status = .verified, .note = "yank the highlighted lines" },
    .{ .tag = "v_aquote", .sequence = "a\"", .status = .verified, .note = "extend highlighted area with a double quoted string" },
    .{ .tag = "v_a'", .sequence = "a'", .status = .verified, .note = "extend highlighted area with a single quoted string" },
    .{ .tag = "v_a(", .sequence = "a(", .status = .verified, .note = "same as ab" },
    .{ .tag = "v_a)", .sequence = "a)", .status = .verified, .note = "same as ab" },
    .{ .tag = "v_a<", .sequence = "a<", .status = .verified, .note = "extend highlighted area with a <> block" },
    .{ .tag = "v_a>", .sequence = "a>", .status = .verified, .note = "same as a<" },
    .{ .tag = "v_aB", .sequence = "aB", .status = .verified, .note = "extend highlighted area with a {} block" },
    .{ .tag = "v_aW", .sequence = "aW", .status = .verified, .note = "extend highlighted area with a WORD" },
    .{ .tag = "v_a[", .sequence = "a[", .status = .verified, .note = "extend highlighted area with a [] block" },
    .{ .tag = "v_a]", .sequence = "a]", .status = .verified, .note = "same as a[" },
    .{ .tag = "v_a", .sequence = "a", .status = .verified, .note = "extend highlighted area with a backtick quoted string" },
    .{ .tag = "v_ab", .sequence = "ab", .status = .verified, .note = "extend highlighted area with a () block" },
    .{ .tag = "v_ap", .sequence = "ap", .status = .verified, .note = "extend highlighted area with a paragraph" },
    .{ .tag = "v_as", .sequence = "as", .status = .verified, .note = "extend highlighted area with a sentence" },
    .{ .tag = "v_at", .sequence = "at", .status = .verified, .note = "extend highlighted area with a tag block" },
    .{ .tag = "v_aw", .sequence = "aw", .status = .verified, .note = "extend highlighted area with a word" },
    .{ .tag = "v_a{", .sequence = "a{", .status = .verified, .note = "same as aB" },
    .{ .tag = "v_a}", .sequence = "a}", .status = .verified, .note = "same as aB" },
    .{ .tag = "v_c", .sequence = "c", .status = .verified, .note = "delete highlighted area and start insert" },
    .{ .tag = "v_d", .sequence = "d", .status = .verified, .note = "delete highlighted area" },
    .{ .tag = "v_g_CTRL-A", .sequence = "g CTRL-A", .status = .verified, .note = "add N to number in highlighted text" },
    .{ .tag = "v_g_CTRL-X", .sequence = "g CTRL-X", .status = .verified, .note = "subtract N from number in highlighted text" },
    .{ .tag = "v_gJ", .sequence = "gJ", .status = .verified, .note = "join the highlighted lines without spaces" },
    .{ .tag = "v_gq", .sequence = "gq", .status = .verified, .note = "format the highlighted lines" },
    .{ .tag = "v_gv", .sequence = "gv", .status = .verified, .note = "exchange current and previous highlighted area" },
    .{ .tag = "v_iquote", .sequence = "i\"", .status = .verified, .note = "extend highlighted area with a double quoted string without quotes" },
    .{ .tag = "v_i'", .sequence = "i'", .status = .verified, .note = "extend highlighted area with a single quoted string without quotes" },
    .{ .tag = "v_i(", .sequence = "i(", .status = .verified, .note = "same as ib" },
    .{ .tag = "v_i)", .sequence = "i)", .status = .verified, .note = "same as ib" },
    .{ .tag = "v_i<", .sequence = "i<", .status = .verified, .note = "extend highlighted area with inner <> block" },
    .{ .tag = "v_i>", .sequence = "i>", .status = .verified, .note = "same as i<" },
    .{ .tag = "v_iB", .sequence = "iB", .status = .verified, .note = "extend highlighted area with inner {} block" },
    .{ .tag = "v_iW", .sequence = "iW", .status = .verified, .note = "extend highlighted area with inner WORD" },
    .{ .tag = "v_i[", .sequence = "i[", .status = .verified, .note = "extend highlighted area with inner [] block" },
    .{ .tag = "v_i]", .sequence = "i]", .status = .verified, .note = "same as i[" },
    .{ .tag = "v_i", .sequence = "i", .status = .verified, .note = "extend highlighted area with a backtick quoted string without the backticks" },
    .{ .tag = "v_ib", .sequence = "ib", .status = .verified, .note = "extend highlighted area with inner () block" },
    .{ .tag = "v_ip", .sequence = "ip", .status = .verified, .note = "extend highlighted area with inner paragraph" },
    .{ .tag = "v_is", .sequence = "is", .status = .verified, .note = "extend highlighted area with inner sentence" },
    .{ .tag = "v_it", .sequence = "it", .status = .verified, .note = "extend highlighted area with inner tag block" },
    .{ .tag = "v_iw", .sequence = "iw", .status = .verified, .note = "extend highlighted area with inner word" },
    .{ .tag = "v_i{", .sequence = "i{", .status = .verified, .note = "same as iB" },
    .{ .tag = "v_i}", .sequence = "i}", .status = .verified, .note = "same as iB" },
    .{ .tag = "v_o", .sequence = "o", .status = .verified, .note = "move cursor to the other corner of the area" },
    .{ .tag = "v_p", .sequence = "p", .status = .verified, .note = "replace highlighted area with register contents" },
    .{ .tag = "v_r", .sequence = "r", .status = .verified, .note = "replace highlighted area with a character" },
    .{ .tag = "v_s", .sequence = "s", .status = .verified, .note = "delete highlighted area and start insert" },
    .{ .tag = "v_u", .sequence = "u", .status = .verified, .note = "make highlighted area lowercase" },
    .{ .tag = "v_v", .sequence = "v", .status = .verified, .note = "make Visual mode charwise or stop Visual mode" },
    .{ .tag = "v_x", .sequence = "x", .status = .verified, .note = "delete the highlighted area" },
    .{ .tag = "v_y", .sequence = "y", .status = .verified, .note = "yank the highlighted area" },
    .{ .tag = "v_~", .sequence = "~", .status = .verified, .note = "swap case for the highlighted area" },
};

fn runVisualBytes(app: *App, bytes: []const u8) !void {
    for (bytes) |byte| {
        try app.handleVisualByte(byte);
    }
}

fn expectVisualExit(app: *App, bytes: []const u8) !void {
    try app.handleNormalByte('v');
    try runVisualBytes(app, bytes);
    try std.testing.expectEqual(Mode.normal, app.mode);
}

fn expectVisualMode(app: *App, initial: App.VisualMode, bytes: []const u8, app_mode: Mode, mode: App.VisualMode, select_mode: bool) !void {
    try app.handleNormalByte(switch (initial) {
        .character => 'v',
        .line => 'V',
        .block => 0x16,
        .none => 'v',
    });
    try runVisualBytes(app, bytes);
    try std.testing.expectEqual(app_mode, app.mode);
    if (app_mode == .visual) {
        try std.testing.expectEqual(mode, app.visual_mode);
        try std.testing.expectEqual(select_mode, app.visual_select_mode);
    }
}

fn pluginCommandSmoke(ctx: *anyopaque, args: []const []const u8) !void {
    _ = args;
    const app: *App = @ptrCast(@alignCast(ctx));
    app.plugin_activity.clearRetainingCapacity();
    try app.plugin_activity.appendSlice("plugin command invoked");
    try app.syncPluginPane();
}

test "command help dispatches to the documented help text" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    try app.setStatus("stale");
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":help saveas");
    try app.executeCommand();
    try std.testing.expectEqualStrings("save the current buffer under a new path", app.status.items);
}

test "plugin command dispatches through the user facing command path" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    try app.builtins.registerExtensionCommand("hello-plugin", "announce that the hello plugin is loaded", pluginCommandSmoke);
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":plugins");
    try app.executeCommand();

    var command_index: ?usize = null;
    for (app.plugins_list.items.items, 0..) |item, idx| {
        if (std.mem.eql(u8, item.label, "cmd hello-plugin")) {
            command_index = idx;
            break;
        }
    }
    try std.testing.expect(command_index != null);
    app.plugins_list.selected = command_index.?;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();

    try std.testing.expect(app.plugin_activity.items.len > 0);
    try std.testing.expectEqualStrings("plugin command invoked", app.plugin_activity.items);
    try std.testing.expect(app.plugin_details_pane_id != null);
    const detail_pane_id = app.plugin_details_pane_id.?;
    var found_detail = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != detail_pane_id) continue;
        try std.testing.expectEqualStrings("plugin details", pane.title);
        found_detail = std.mem.indexOf(u8, pane.streaming.items, "hello-plugin") != null;
        break;
    }
    try std.testing.expect(found_detail);
    var found = false;
    for (app.plugins_list.items.items) |item| {
        if (item.detail) |detail| {
            if (std.mem.eql(u8, detail, "plugin command invoked")) {
                found = true;
                break;
            }
        }
    }
    try std.testing.expect(found);
}

test "plugin pane navigation updates the detail pane" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    try app.builtins.registerExtensionCommand("hello-plugin", "announce that the hello plugin is loaded", pluginCommandSmoke);
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":plugins");
    try app.executeCommand();

    try std.testing.expect(app.plugins_list.items.items.len >= 2);
    const before = app.plugins_list.selected;
    try std.testing.expect(app.plugin_details_pane_id != null);
    const detail_pane_id = app.plugin_details_pane_id.?;
    var before_streaming: []const u8 = "";
    for (app.panes.panes.items) |pane| {
        if (pane.id != detail_pane_id) continue;
        before_streaming = pane.streaming.items;
        break;
    }
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":pnext");
    try app.executeCommand();
    try std.testing.expectEqual(before, app.plugins_list.selected);
    var saw_selected_label = false;
    var saw_runnable_marker = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != detail_pane_id) continue;
        saw_selected_label = std.mem.indexOf(u8, pane.streaming.items, "> manifest:") != null;
        saw_runnable_marker = std.mem.indexOf(u8, before_streaming, "> manifest:") == null and std.mem.indexOf(u8, pane.streaming.items, "> manifest:") != null;
        break;
    }
    try std.testing.expect(saw_selected_label);
    try std.testing.expect(saw_runnable_marker);
}

test "plugin detail pane shows manifest metadata" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":plugins");
    try app.executeCommand();

    var manifest_index: ?usize = null;
    for (app.plugins_list.items.items, 0..) |item, idx| {
        if (std.mem.eql(u8, item.label, "hello [filesystem]")) {
            manifest_index = idx;
            break;
        }
    }
    try std.testing.expect(manifest_index != null);
    app.plugins_list.selected = manifest_index.?;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();

    try std.testing.expect(app.plugin_details_pane_id != null);
    const detail_pane_id = app.plugin_details_pane_id.?;
    var saw_version = false;
    var saw_source = false;
    var saw_state = false;
    var saw_caps = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != detail_pane_id) continue;
        saw_version = std.mem.indexOf(u8, pane.streaming.items, "version: 0.1.0") != null;
        saw_source = std.mem.indexOf(u8, pane.streaming.items, "source: filesystem") != null;
        saw_state = std.mem.indexOf(u8, pane.streaming.items, "state: loaded") != null;
        saw_caps = std.mem.indexOf(u8, pane.streaming.items, "capabilities:") != null;
        break;
    }
    try std.testing.expect(saw_version);
    try std.testing.expect(saw_source);
    try std.testing.expect(saw_state);
    try std.testing.expect(saw_caps);
}

test "plugin detail pane popen reruns the selected plugin command" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    try app.builtins.registerExtensionCommand("hello-plugin", "announce that the hello plugin is loaded", pluginCommandSmoke);
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":plugins");
    try app.executeCommand();

    var command_index: ?usize = null;
    for (app.plugins_list.items.items, 0..) |item, idx| {
        if (std.mem.eql(u8, item.label, "cmd hello-plugin")) {
            command_index = idx;
            break;
        }
    }
    try std.testing.expect(command_index != null);
    app.plugins_list.selected = command_index.?;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();
    try std.testing.expectEqualStrings("plugin command invoked", app.plugin_activity.items);

    var saw_runnable_marker = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != app.plugin_details_pane_id.?) continue;
        saw_runnable_marker = std.mem.indexOf(u8, pane.streaming.items, "> action: runnable") != null;
        break;
    }
    try std.testing.expect(saw_runnable_marker);

    app.plugin_activity.clearRetainingCapacity();
    try app.plugin_activity.appendSlice("stale");
    try app.syncPluginPane();
    try std.testing.expect(app.plugin_details_pane_id != null);
    if (app.panes.focusedPaneId()) |focused_id| {
        try std.testing.expectEqual(app.plugin_details_pane_id.?, focused_id);
    }

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();
    try std.testing.expectEqualStrings("plugin command invoked", app.plugin_activity.items);
    var found = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != app.plugin_details_pane_id.?) continue;
        found = std.mem.indexOf(u8, pane.streaming.items, "plugin command invoked") != null;
        break;
    }
    try std.testing.expect(found);
}

test "plugin detail pane refresh resets stale row selection" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    try app.builtins.registerExtensionCommand("hello-plugin", "announce that the hello plugin is loaded", pluginCommandSmoke);
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":plugins");
    try app.executeCommand();

    var command_index: ?usize = null;
    var manifest_index: ?usize = null;
    for (app.plugins_list.items.items, 0..) |item, idx| {
        if (std.mem.eql(u8, item.label, "cmd hello-plugin")) command_index = idx;
        if (std.mem.eql(u8, item.label, "hello [filesystem]")) manifest_index = idx;
    }
    try std.testing.expect(command_index != null);
    try std.testing.expect(manifest_index != null);

    app.plugins_list.selected = command_index.?;
    try app.syncPluginPane();
    try std.testing.expect(app.plugin_details_pane_id != null);
    const detail_pane_id = app.plugin_details_pane_id.?;
    var saw_runnable = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != detail_pane_id) continue;
        saw_runnable = std.mem.indexOf(u8, pane.streaming.items, "> action: runnable") != null;
        break;
    }
    try std.testing.expect(saw_runnable);

    app.plugins_list.selected = manifest_index.?;
    try app.syncPluginPane();

    var saw_manifest = false;
    var saw_stale_runnable = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != detail_pane_id) continue;
        saw_manifest = std.mem.indexOf(u8, pane.streaming.items, "> manifest:") != null;
        saw_stale_runnable = std.mem.indexOf(u8, pane.streaming.items, "> action: runnable") != null;
        break;
    }
    try std.testing.expect(saw_manifest);
    try std.testing.expect(!saw_stale_runnable);
}

test "command saveas writes the buffer and updates the path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.activeBuffer().replacePath("saved.txt");

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":saveas saved.txt");
    try app.executeCommand();

    try std.testing.expectEqualStrings("saved as", app.status.items);
    try std.testing.expectEqualStrings("saved.txt", app.activeBuffer().path.?);
    _ = try tmp.dir.openFile("saved.txt", .{});
}

test "command sort unique sorts the buffer lines" {
    var app = try makeTestApp(std.testing.allocator, "b\na\na");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":sort u");
    try app.executeCommand();

    try std.testing.expectEqualStrings("sorted", app.status.items);
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("a\nb", text);
}

test "command substitute replaces whole documents and visual selections" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta\nalpha");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":%s/alpha/omega/g");
    try app.executeCommand();
    const whole = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(whole);
    try std.testing.expectEqualStrings("omega beta\nomega", whole);
    try std.testing.expectEqualStrings("substituted", app.status.items);

    var app2 = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app2.deinit();
    try app2.handleNormalByte('v');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    app2.command_buffer.clearRetainingCapacity();
    try app2.command_buffer.appendSlice(":'<,'>s/alpha/omega/");
    try app2.executeCommand();
    const selected = try app2.activeBuffer().serialize();
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqualStrings("omega beta", selected);
    try std.testing.expectEqual(Mode.normal, app2.mode);
}

test "normal close command closes a pane when the buffer is clean" {
    var app = try makeTestApp(std.testing.allocator, "one");
    defer app.deinit();
    var extra = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
    errdefer extra.deinit();
    try extra.setText("two");
    try app.buffers.append(extra);
    app.split_index = 1;
    app.split_focus = .right;
    app.active_index = 0;

    try app.performNormalAction(.close, 1);
    try std.testing.expectEqual(@as(usize, 1), app.buffers.items.len);
    try std.testing.expectEqualStrings("pane closed", app.status.items);
}

test "normal help key launches man for the word under cursor" {
    var app = try makeTestApp(std.testing.allocator, "zig build");
    defer app.deinit();
    app.interactive_command_hook = testInteractiveCommandHook;

    try app.activeBuffer().moveToLine(0);
    try app.performNormalAction(.help, 1);
    try std.testing.expectEqualStrings("man\tzig", app.last_interactive_command.?);
    try std.testing.expectEqualStrings("returned from man", app.status.items);
}

test "normal terminal key launches the configured shell" {
    var app = try makeTestApp(std.testing.allocator, "shell");
    defer app.deinit();
    app.interactive_command_hook = testInteractiveCommandHook;

    const shell = try app.defaultShell();
    defer if (shell.owned) app.allocator.free(shell.path);

    try app.performNormalAction(.terminal, 1);
    try std.testing.expectEqualStrings(shell.path, app.last_interactive_command.?);
    try std.testing.expectEqualStrings("returned from terminal", app.status.items);
}

test "command terminal dispatches to the same shell launcher" {
    var app = try makeTestApp(std.testing.allocator, "shell");
    defer app.deinit();
    app.interactive_command_hook = testInteractiveCommandHook;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":terminal");
    try app.executeCommand();

    const shell = try app.defaultShell();
    defer if (shell.owned) app.allocator.free(shell.path);
    try std.testing.expectEqualStrings(shell.path, app.last_interactive_command.?);
    try std.testing.expectEqualStrings("returned from terminal", app.status.items);
}

test "matching character jump moves across parentheses" {
    var app = try makeTestApp(std.testing.allocator, "(abc)");
    defer app.deinit();
    app.activeBuffer().cursor = .{ .row = 0, .col = 0 };

    try app.performNormalAction(.jump_matching_character, 1);
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.col);
}

test "declaration jumps search current word in the buffer" {
    var app = try makeTestApp(std.testing.allocator, "foo\nbar foo");
    defer app.deinit();
    app.activeBuffer().cursor = .{ .row = 1, .col = 4 };

    try app.performNormalAction(.jump_global_declaration, 1);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
}

test "normal binding table exposes the implemented prefixes" {
    var cfg = try config_mod.Config.init(std.testing.allocator);
    defer cfg.deinit();

    try std.testing.expect(normalActionHasPrefix("g", cfg.keymap.leader, cfg.keymap.leader_bindings.items));
    try std.testing.expect(normalActionHasPrefix("z", cfg.keymap.leader, cfg.keymap.leader_bindings.items));
    try std.testing.expect(normalActionFor("gd", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("gf", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("gx", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("d0", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("g0", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("g^", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("g$", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("y$", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("(", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor(")", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("n", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("N", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
    try std.testing.expect(normalActionFor("K", cfg.keymap.leader, cfg.keymap.leader_bindings.items) != null);
}

test "exact multi-key bindings execute once their sequence is complete" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo");
    defer app.deinit();

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "gg");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "dd");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().lineCount());
    try std.testing.expectEqualStrings("two", app.activeBuffer().currentLine());
}

test "cursor motion keys move within the buffer" {
    var app = try makeTestApp(std.testing.allocator, "  alpha\nbeta  \n  omega");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "l");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "h");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "j");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "k");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    setCursor(&app, 0, 4);
    try pressNormalKeys(&app, "0");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "^");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "$");
    try std.testing.expectEqual(@as(usize, 7), app.activeBuffer().cursor.col);

    setCursor(&app, 1, 1);
    try pressNormalKeys(&app, "g_");
    try std.testing.expectEqual(@as(usize, 3), app.activeBuffer().cursor.col);
    setCursor(&app, 1, 4);
    try pressNormalKeys(&app, "g0");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    setCursor(&app, 1, 4);
    try pressNormalKeys(&app, "g^");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    setCursor(&app, 1, 4);
    try pressNormalKeys(&app, "g$");
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);

    setCursor(&app, 2, 5);
    try pressNormalKeys(&app, "gg");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "G");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "M");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
}

test "visual line mode can extend to the end of the file" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree");
    defer app.deinit();

    setCursor(&app, 1, 1);
    try app.handleNormalByte('V');
    try app.handleVisualByte('G');
    const selection = app.visualSelection().?;
    try std.testing.expectEqual(@as(usize, 1), selection.start.row);
    try std.testing.expectEqual(@as(usize, 0), selection.start.col);
    try std.testing.expectEqual(@as(usize, 2), selection.end.row);
    try std.testing.expectEqual(@as(usize, 5), selection.end.col);
}

test "sentence motions marks and bol delete are wired" {
    var app = try makeTestApp(std.testing.allocator, "one. two. three\nalpha beta");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, ")");
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, "(");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);

    setCursor(&app, 1, 5);
    try pressNormalKeys(&app, "ma");
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "`a");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "'a");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);

    setCursor(&app, 1, 5);
    try pressNormalKeys(&app, "d0");
    try std.testing.expectEqualStrings(" beta", app.activeBuffer().currentLine());
}

test "history and previous buffer navigation keys work" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "j");
    try pressNormalKeys(&app, "k");
    try pressNormalKeys(&app, "\x0f");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try pressNormalKeys(&app, "\x0f");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    var extra = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
    errdefer extra.deinit();
    try extra.setText("other");
    try app.buffers.append(extra);
    app.active_index = 1;
    app.previous_active_index = 0;
    try pressNormalKeys(&app, "\x1e");
    try std.testing.expectEqual(@as(usize, 0), app.active_index);
}

test "word motion keys follow word boundaries" {
    var app = try makeTestApp(std.testing.allocator, "foo,bar baz");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "w");
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "W");
    try std.testing.expectEqual(@as(usize, 8), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "e");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "E");
    try std.testing.expectEqual(@as(usize, 6), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 8);
    try pressNormalKeys(&app, "b");
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.col);
    setCursor(&app, 0, 8);
    try pressNormalKeys(&app, "B");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
}

test "find keys repeat forward and backward" {
    var app = try makeTestApp(std.testing.allocator, "abcabc");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "fc");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, ";");
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
    try pressNormalKeys(&app, ",");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
}

test "compound operator motions and dot repeat work" {
    var app = try makeTestApp(std.testing.allocator, "one two three four five six");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "d3w");
    try std.testing.expectEqualStrings("four five six", app.activeBuffer().currentLine());

    try pressNormalKeys(&app, ".");
    try std.testing.expectEqualStrings("", app.activeBuffer().currentLine());
}

test "yank paste and registers work together" {
    var app = try makeTestApp(std.testing.allocator, "alpha\nbeta");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "yw");
    try std.testing.expectEqualStrings("alpha", app.registers.get('"').?);
    try std.testing.expectEqualStrings("alpha", app.registers.get('0').?);

    setCursor(&app, 1, 4);
    try pressNormalKeys(&app, "p");
    try std.testing.expectEqualStrings("betaalpha", app.activeBuffer().currentLine());
}

test "linewise paste inserts whole lines above and below" {
    var app = try makeTestApp(std.testing.allocator, "alpha\nbeta\nomega");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "yy");
    try std.testing.expectEqualStrings("alpha", app.registers.get('"').?);

    setCursor(&app, 1, 2);
    try pressNormalKeys(&app, "p");
    const after_below = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(after_below);
    try std.testing.expectEqualStrings("alpha\nbeta\nalpha\nomega", after_below);

    var app2 = try makeTestApp(std.testing.allocator, "alpha\nbeta\nomega");
    defer app2.deinit();

    setCursor(&app2, 0, 0);
    try pressNormalKeys(&app2, "yy");
    setCursor(&app2, 1, 2);
    try pressNormalKeys(&app2, "P");
    const after_above = try app2.activeBuffer().serialize();
    defer std.testing.allocator.free(after_above);
    try std.testing.expectEqualStrings("alpha\nalpha\nbeta\nomega", after_above);
}

test "clipboard registers copy and paste through the system clipboard hooks" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();
    app.clipboard_get_hook = testClipboardGetHook;
    app.clipboard_set_hook = testClipboardSetHook;

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "\"+yw");
    try std.testing.expectEqualStrings("alpha", app.clipboard_contents.?);
    try std.testing.expectEqualStrings("alpha", app.registers.get('+').?);

    var app2 = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app2.deinit();
    app2.clipboard_get_hook = testClipboardGetHook;
    app2.clipboard_contents = try app2.allocator.dupe(u8, "clip");

    setCursor(&app2, 0, 0);
    try pressNormalKeys(&app2, "\"+p");
    try std.testing.expectEqualStrings("acliplpha beta", app2.activeBuffer().currentLine());
}

test "yank to end of line and yank whole line use the right motions" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta gamma");
    defer app.deinit();

    setCursor(&app, 0, 6);
    try pressNormalKeys(&app, "y$");
    try std.testing.expectEqualStrings("beta gamma", app.registers.get('\"').?);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "Y");
    try std.testing.expectEqualStrings("alpha beta gamma", app.registers.get('\"').?);
}

test "delete and undo redo keys restore text" {
    var app = try makeTestApp(std.testing.allocator, "abc");
    defer app.deinit();

    setCursor(&app, 0, 1);
    try pressNormalKeys(&app, "x");
    try std.testing.expectEqualStrings("ac", app.activeBuffer().currentLine());
    try pressNormalKeys(&app, "u");
    try std.testing.expectEqualStrings("abc", app.activeBuffer().currentLine());
    try pressNormalKeys(&app, "\x12");
    try std.testing.expectEqualStrings("ac", app.activeBuffer().currentLine());
}

test "open split and quit commands update editor state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("one.txt", .{});
        defer f.close();
        try f.writeAll("one");
    }
    {
        var f = try tmp.dir.createFile("two.txt", .{});
        defer f.close();
        try f.writeAll("two");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":open one.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":split two.txt");
    try app.executeCommand();
    try std.testing.expect(app.split_index != null);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "x");

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":q");
    try app.executeCommand();
    try std.testing.expectEqual(false, app.should_quit);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":q!");
    try app.executeCommand();
    try std.testing.expect(app.should_quit);
}

test "tab navigation keys cycle through buffers" {
    var app = try makeTestApp(std.testing.allocator, "one");
    defer app.deinit();

    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("two");
        try app.buffers.append(buf);
    }
    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("three");
        try app.buffers.append(buf);
    }

    app.active_index = 0;
    try pressNormalKeys(&app, "gt");
    try std.testing.expectEqual(@as(usize, 1), app.active_index);
    try pressNormalKeys(&app, "gt");
    try std.testing.expectEqual(@as(usize, 2), app.active_index);
    try pressNormalKeys(&app, "gT");
    try std.testing.expectEqual(@as(usize, 1), app.active_index);
}

test "tab commands create, move, and keep only the current buffer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("one.txt", .{});
        defer f.close();
        try f.writeAll("one");
    }
    {
        var f = try tmp.dir.createFile("two.txt", .{});
        defer f.close();
        try f.writeAll("two");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabnew one.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabnew two.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 3), app.buffers.items.len);
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabmove 0");
    try app.executeCommand();
    try std.testing.expectEqualStrings("two.txt", app.buffers.items[0].path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":tabonly");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.buffers.items.len);
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);
}

test "window split keys create and cycle a split" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    try std.testing.expect(app.split_index != null);
    try std.testing.expectEqual(.right, app.split_focus);
    try std.testing.expectEqualStrings("left", app.activeBuffer().currentLine());

    try pressNormalKeys(&app, "\x17w");
    try std.testing.expectEqual(.left, app.split_focus);

    try pressNormalKeys(&app, "\x17w");
    try std.testing.expectEqual(.right, app.split_focus);

    try pressNormalKeys(&app, "\x17h");
    try std.testing.expectEqual(.left, app.split_focus);
    try pressNormalKeys(&app, "\x17l");
    try std.testing.expectEqual(.right, app.split_focus);
    try pressNormalKeys(&app, "\x17k");
    try std.testing.expectEqual(.left, app.split_focus);
    try pressNormalKeys(&app, "\x17j");
    try std.testing.expectEqual(.right, app.split_focus);
}

test "Ctrl+wN opens a new empty window" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17n");
    try std.testing.expect(app.split_index != null);
    try std.testing.expectEqual(.right, app.split_focus);
    try std.testing.expectEqualStrings("", app.activeBuffer().currentLine());
    try std.testing.expectEqualStrings("new window", app.status.items);
}

test "Ctrl+w resize keys adjust the split safely" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    app.config.split_ratio = 50;

    try pressNormalKeys(&app, "\x17>");
    try std.testing.expectEqual(@as(usize, 60), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17<");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17+");
    try std.testing.expectEqual(@as(usize, 60), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17-");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);

    try pressNormalKeys(&app, "\x17|");
    try std.testing.expectEqual(@as(usize, 100), app.config.split_ratio);
    try pressNormalKeys(&app, "\x17_");
    try std.testing.expectEqual(@as(usize, 100), app.config.split_ratio);

    try pressNormalKeys(&app, "\x17=");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);
    try std.testing.expectEqualStrings("windows equalized", app.status.items);
}

test "window exchange and close keys operate on the split" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    try app.activeBuffer().replaceRangeWithText(.{ .row = 0, .col = 0 }, .{ .row = 0, .col = 4 }, "right");

    try pressNormalKeys(&app, "\x17x");
    try std.testing.expectEqualStrings("windows exchanged", app.status.items);

    try pressNormalKeys(&app, "\x17q");
    try std.testing.expect(app.split_index == null);
    try std.testing.expectEqual(@as(usize, 1), app.buffers.items.len);
}

test "Ctrl+wT moves the split into a tab" {
    var app = try makeTestApp(std.testing.allocator, "left");
    defer app.deinit();

    try pressNormalKeys(&app, "\x17s");
    try pressNormalKeys(&app, "\x17T");
    try std.testing.expect(app.split_index == null);
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
    try std.testing.expectEqualStrings("split moved to tab", app.status.items);
}

test "buffer commands open, navigate, list, and delete buffers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("one.txt", .{});
        defer f.close();
        try f.writeAll("one");
    }
    {
        var f = try tmp.dir.createFile("two.txt", .{});
        defer f.close();
        try f.writeAll("two");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":edit one.txt");
    try app.executeCommand();
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":open two.txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 3), app.buffers.items.len);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":bn");
    try app.executeCommand();
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":bp");
    try app.executeCommand();
    try std.testing.expectEqualStrings("one.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":buffer 3");
    try app.executeCommand();
    try std.testing.expectEqualStrings("two.txt", app.activeBuffer().path.?);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":buffers");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1:") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":bd");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.buffers.items.len);
}

test "split aliases duplicate or open paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("split.txt", .{});
        defer f.close();
        try f.writeAll("split");
    }

    var app = try makeTestApp(std.testing.allocator, "base");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":sp");
    try app.executeCommand();
    try std.testing.expect(app.split_index != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":vs split.txt");
    try app.executeCommand();
    try std.testing.expect(app.split_index != null);
    try std.testing.expectEqualStrings("split.txt", app.activeBuffer().path.?);
}

test "quickfix search collects matches and navigates them" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("qf.txt", .{});
        defer f.close();
        try f.writeAll("alpha\nneedle\nbeta needle\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":vimgrep /needle/");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.quickfix_list.items.items.len);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1/2") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":cn");
    try app.executeCommand();
    try std.testing.expectEqualStrings("qf.txt", app.activeBuffer().path.?);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.row);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":cp");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 0), app.quickfix_list.selected);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":ccl");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 0), app.quickfix_list.items.items.len);
}

test "picker search populates results and opens the selected match" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("picker.txt", .{});
        defer f.close();
        try f.writeAll("alpha\nneedle\nbeta needle\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":pickgrep /needle/");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.picker.items.items.len);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1/2") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":pnext");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.picker.selected);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();
    try std.testing.expectEqualStrings("picker.txt", app.activeBuffer().path.?);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 5), app.activeBuffer().cursor.col);
}

test "file picker search lists files and opens the selected path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("alpha.txt", .{});
        defer f.close();
        try f.writeAll("alpha\n");
    }
    {
        var f = try tmp.dir.createFile("beta.md", .{});
        defer f.close();
        try f.writeAll("beta\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":files .txt");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.picker.items.items.len);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1/1") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();
    try std.testing.expectEqualStrings("alpha.txt", app.activeBuffer().path.?);
}

test "symbol picker search lists symbols and opens the selected result" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("symbols.zig", .{});
        defer f.close();
        try f.writeAll(
            \\pub fn alpha() void {}
            \\fn beta() void {}
        );
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":symbols alpha");
    try app.executeCommand();
    try std.testing.expect(app.picker.items.items.len >= 1);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1/") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":popen");
    try app.executeCommand();
    try std.testing.expectEqualStrings("symbols.zig", app.activeBuffer().path.?);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
}

test "picker selection restores from workspace session" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("picker.txt", .{});
        defer f.close();
        try f.writeAll("alpha\nneedle\nbeta needle\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();
    app.workspace.session.selected_picker_index = 1;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":pickgrep /needle/");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.picker.selected);
}

test "refresh sources reruns the active picker search" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("refresh.txt", .{});
        defer f.close();
        try f.writeAll("needle\nplain\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":pickgrep /needle/");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.picker.items.items.len);

    try std.fs.cwd().writeFile(.{ .sub_path = "refresh.txt", .data = "needle\nplain\nneedle again\n" });

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":refresh-sources");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 2), app.picker.items.items.len);
}

test "plugin picker host can open update preview and cancel" {
    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    const host = app.builtinHost();
    try host.openPicker("plugin picker", "query");
    try host.setPickerItems(&.{
        .{ .id = 1, .label = "alpha", .detail = "first item" },
        .{ .id = 2, .label = "beta", .detail = "second item" },
    });
    try host.setPickerPreview("preview text");

    try std.testing.expect(app.picker_pane_id != null);
    try std.testing.expectEqualStrings("query", app.picker.query.items);
    try std.testing.expectEqual(@as(usize, 2), app.picker.items.items.len);
    try std.testing.expect(app.picker.preview != null);
    try std.testing.expectEqualStrings("preview text", app.picker.preview.?);
    if (app.picker_pane_id) |pane_id| {
        var found_title = false;
        for (app.panes.panes.items) |pane| {
            if (pane.id == pane_id) {
                found_title = std.mem.indexOf(u8, pane.title, "plugin picker") != null;
            }
        }
        try std.testing.expect(found_title);
    }

    host.cancelPicker();
    try std.testing.expectEqual(@as(usize, 0), app.picker.items.items.len);
    try std.testing.expectEqual(listpane_mod.SourceState.idle, app.picker.state);
}

test "plugin host can create and update a custom pane" {
    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    const host = app.builtinHost();
    const pane_id = try host.createPane(.custom, "plugin pane");
    try std.testing.expect(host.focusPane(pane_id));
    try host.setPaneText(pane_id, "plugin pane", "hello pane");

    var found = false;
    for (app.panes.panes.items) |pane| {
        if (pane.id != pane_id) continue;
        found = true;
        try std.testing.expectEqualStrings("plugin pane", pane.title);
        try std.testing.expectEqualStrings("hello pane", pane.streaming.items);
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(?u64, pane_id), app.panes.focusedPaneId());
}

test "diagnostics pane opens and reflects diagnostics counts" {
    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    try app.diagnostics.add(.{
        .buffer_id = 1,
        .path = try std.testing.allocator.dupe(u8, "sample.txt"),
        .row = 0,
        .col = 1,
        .severity = .err,
        .message = try std.testing.allocator.dupe(u8, "boom"),
    });

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diagnostics");
    try app.executeCommand();

    try std.testing.expect(app.diagnostics_pane_id != null);
    if (app.diagnostics_pane_id) |id| {
        var found = false;
        for (app.panes.panes.items) |pane| {
            if (pane.id == id) {
                found = true;
                try std.testing.expect(std.mem.indexOf(u8, pane.title, "E1") != null);
                try std.testing.expect(std.mem.indexOf(u8, pane.title, "1/1") != null);
            }
        }
        try std.testing.expect(found);
    }
}

test "diagnostics selection restores from workspace session" {
    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    try app.diagnostics.add(.{
        .buffer_id = 1,
        .path = try std.testing.allocator.dupe(u8, "sample.txt"),
        .row = 0,
        .col = 1,
        .severity = .warning,
        .message = try std.testing.allocator.dupe(u8, "first"),
    });
    try app.diagnostics.add(.{
        .buffer_id = 1,
        .path = try std.testing.allocator.dupe(u8, "sample.txt"),
        .row = 1,
        .col = 2,
        .severity = .err,
        .message = try std.testing.allocator.dupe(u8, "second"),
    });
    app.workspace.session.selected_diagnostics_index = 1;

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diagnostics");
    try app.executeCommand();

    try std.testing.expectEqual(@as(usize, 1), app.diagnostics_list.selected);
}

test "diagnostics navigation opens the selected diagnostic" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("diag.txt", .{});
        defer f.close();
        try f.writeAll("alpha\nbeta\ngamma\n");
    }

    var app = try makeTestApp(std.testing.allocator, "start");
    defer app.deinit();

    try app.diagnostics.add(.{
        .buffer_id = 1,
        .path = try std.testing.allocator.dupe(u8, "diag.txt"),
        .row = 0,
        .col = 0,
        .severity = .warning,
        .message = try std.testing.allocator.dupe(u8, "first"),
    });
    try app.diagnostics.add(.{
        .buffer_id = 1,
        .path = try std.testing.allocator.dupe(u8, "diag.txt"),
        .row = 1,
        .col = 2,
        .severity = .err,
        .message = try std.testing.allocator.dupe(u8, "second"),
    });

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diagnostics");
    try app.executeCommand();
    try std.testing.expect(app.diagnostics_pane_id != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":dnext");
    try app.executeCommand();
    try std.testing.expectEqual(@as(usize, 1), app.diagnostics_list.selected);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "2/2") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":dopen");
    try app.executeCommand();
    try std.testing.expectEqualStrings("diag.txt", app.activeBuffer().path.?);
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().cursor.col);
}

test "fold commands create and manipulate paragraph folds" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\n\nthree\nfour");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "zf");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().folds.items.len);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().folds.items[0].start_row);
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().folds.items[0].end_row);
    try std.testing.expect(app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "za");
    try std.testing.expect(!app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "zc");
    try std.testing.expect(app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "zo");
    try std.testing.expect(!app.activeBuffer().folds.items[0].closed);

    try pressNormalKeys(&app, "zd");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().folds.items.len);

    setCursor(&app, 3, 0);
    try pressNormalKeys(&app, "zf");
    try pressNormalKeys(&app, "zi");
    try std.testing.expect(!app.activeBuffer().fold_enabled);
    try pressNormalKeys(&app, "zi");
    try std.testing.expect(app.activeBuffer().fold_enabled);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "zE");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().folds.items.len);
    try std.testing.expectEqualStrings("all folds deleted", app.status.items);
}

test "window equalize and insert ctrl-w behave safely" {
    var app = try makeTestApp(std.testing.allocator, "");
    defer app.deinit();

    var extra = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
    errdefer extra.deinit();
    try extra.setText("pane");
    try app.buffers.append(extra);
    app.split_index = 1;
    app.split_focus = .left;
    app.config.split_ratio = 73;

    try pressNormalKeys(&app, "\x17=");
    try std.testing.expectEqual(@as(usize, 50), app.config.split_ratio);
    try std.testing.expectEqualStrings("windows equalized", app.status.items);

    app.mode = .insert;
    try app.handleByte('a', std.fs.File.stdin());
    try app.handleByte('b', std.fs.File.stdin());
    try app.handleByte('c', std.fs.File.stdin());
    try app.handleByte(' ', std.fs.File.stdin());
    try app.handleByte('d', std.fs.File.stdin());
    try app.handleByte('e', std.fs.File.stdin());
    try app.handleByte('f', std.fs.File.stdin());
    try app.handleByte(0x17, std.fs.File.stdin());
    const line = app.activeBuffer().currentLine();
    try std.testing.expectEqualStrings("abc ", line);
}

test "diff commands copy lines and manage diff mode" {
    var app = try makeTestApp(std.testing.allocator, "left\nsame");
    defer app.deinit();

    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("right\nsame");
        try app.buffers.append(buf);
    }

    app.active_index = 0;
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diffthis");
    try app.executeCommand();
    try std.testing.expect(app.diff_mode);
    try std.testing.expect(app.diff_peer_index != null);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "do");
    try std.testing.expectEqualStrings("right", app.activeBuffer().lines.items[0]);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "dp");
    try std.testing.expectEqualStrings("right", app.buffers.items[1].lines.items[0]);

    try pressNormalKeys(&app, "]c");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    try pressNormalKeys(&app, "[c");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diffupdate");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "diff on") != null);

    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":diffoff");
    try app.executeCommand();
    try std.testing.expect(!app.diff_mode);
}

test "visual mode yank and delete use the selected region" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleNormalByte('l');
    try app.handleNormalByte('l');
    try app.handleNormalByte('y');
    try std.testing.expectEqualStrings("al", app.registers.get('"').?);
    try std.testing.expectEqual(false, app.mode == .visual);

    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleNormalByte('l');
    try app.handleNormalByte('d');
    try std.testing.expectEqualStrings("pha beta", app.activeBuffer().currentLine());
}

test "visual delete can be undone and redone" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree");
    defer app.deinit();

    try app.handleNormalByte('V');
    try app.handleVisualByte('j');
    try app.handleVisualByte('x');
    try std.testing.expectEqualStrings("three", app.activeBuffer().currentLine());

    try pressNormalKeys(&app, "u");
    const restored = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(restored);
    try std.testing.expectEqualStrings("one\ntwo\nthree", restored);

    try pressNormalKeys(&app, "\x12");
    const redone = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(redone);
    try std.testing.expectEqualStrings("three", redone);
}

test "visual block delete can be undone and redone as one edit" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('x');
    const deleted = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(deleted);
    try std.testing.expectEqualStrings("b\nd", deleted);

    try pressNormalKeys(&app, "u");
    const restored = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(restored);
    try std.testing.expectEqualStrings("ab\ncd", restored);

    try pressNormalKeys(&app, "\x12");
    const redone = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(redone);
    try std.testing.expectEqualStrings("b\nd", redone);
}

test "visual mode can switch shape and restore the previous area" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleVisualByte('V');
    try std.testing.expectEqual(Mode.visual, app.mode);
    try std.testing.expectEqual(App.VisualMode.line, app.visual_mode);

    try app.handleVisualByte('y');
    try std.testing.expectEqual(Mode.normal, app.mode);

    try pressNormalKeys(&app, "gv");
    try std.testing.expectEqual(Mode.visual, app.mode);
    try std.testing.expectEqual(App.VisualMode.line, app.visual_mode);
    try std.testing.expect(app.visual_anchor != null);
}

test "visual control keys toggle select mode and exit visual mode" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleVisualByte(0x07);
    try std.testing.expect(app.visual_select_mode);
    try app.handleVisualByte(0x0f);
    try std.testing.expect(!app.visual_select_mode);
    try std.testing.expectEqualStrings("visual mode", app.status.items);

    try app.handleVisualByte(0x1c);
    try app.handleVisualByte('n');
    try std.testing.expectEqual(Mode.normal, app.mode);

    try app.handleNormalByte('v');
    try app.handleVisualByte(0x1c);
    try app.handleVisualByte('g');
    try std.testing.expectEqual(Mode.normal, app.mode);

    try app.handleNormalByte('v');
    try app.handleVisualByte(0x07);
    try app.handleVisualByte(0x0f);
    try std.testing.expect(!app.visual_select_mode);
    try app.handleVisualByte('l');
    try std.testing.expect(app.visual_select_mode);
    try std.testing.expectEqual(Mode.visual, app.mode);
}

test "select mode typing replaces the selection and enters insert mode" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte(0x07);
    try std.testing.expectEqual(Mode.select, app.mode);
    try app.handleByte('X', std.fs.File.stdin());
    try std.testing.expectEqual(Mode.insert, app.mode);

    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Xpha", text);
}

test "select mode typing can be undone and redone" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte(0x07);
    try app.handleByte('X', std.fs.File.stdin());
    try std.testing.expectEqual(Mode.insert, app.mode);

    try pressNormalKeys(&app, "u");
    const restored = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(restored);
    try std.testing.expectEqualStrings("alpha", restored);

    try pressNormalKeys(&app, "\x12");
    const redone = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(redone);
    try std.testing.expectEqualStrings("Xpha", redone);
}

test "replace mode overwrites characters in place" {
    var app = try makeTestApp(std.testing.allocator, "abc");
    defer app.deinit();

    try app.handleNormalByte('R');
    try std.testing.expectEqual(Mode.replace, app.mode);
    try app.handleByte('X', std.fs.File.stdin());
    try app.handleByte('Y', std.fs.File.stdin());
    try std.testing.expectEqual(Mode.replace, app.mode);

    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("XYc", text);
}

test "reverse search uses ? and repeats with n and N" {
    var app = try makeTestApp(std.testing.allocator, "one two one");
    defer app.deinit();

    setCursor(&app, 0, 11);
    try app.handleNormalByte('?');
    try app.handleByte('o', std.fs.File.stdin());
    try app.handleByte('n', std.fs.File.stdin());
    try app.handleByte('e', std.fs.File.stdin());
    try app.handleByte('\n', std.fs.File.stdin());
    try std.testing.expectEqual(@as(usize, 8), app.activeBuffer().cursor.col);

    try pressNormalKeys(&app, "n");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);

    try pressNormalKeys(&app, "N");
    try std.testing.expectEqual(@as(usize, 8), app.activeBuffer().cursor.col);
}

test "visual binding checklist tracks verified and todo entries" {
    var verified: usize = 0;
    var todo: usize = 0;
    for (visual_binding_checklist) |entry| {
        switch (entry.status) {
            .verified => verified += 1,
            .todo => todo += 1,
        }
    }
    try std.testing.expectEqual(visual_binding_checklist.len, verified);
    try std.testing.expectEqual(@as(usize, 0), todo);
}

test "visual mode exits and shape toggles are table-driven" {
    const exit_cases = [_][]const u8{
        "\x1cn",
        "\x1cg",
        "\x03",
        "\x1b",
    };
    for (exit_cases) |bytes| {
        var app = try makeTestApp(std.testing.allocator, "alpha beta");
        defer app.deinit();
        try expectVisualExit(&app, bytes);
    }

    const toggle_cases = [_]struct {
        initial: App.VisualMode,
        bytes: []const u8,
        app_mode: Mode,
        expected: App.VisualMode,
        select_mode: bool,
    }{
        .{ .initial = .character, .bytes = "v", .app_mode = .normal, .expected = .none, .select_mode = false },
        .{ .initial = .character, .bytes = "V", .app_mode = .visual, .expected = .line, .select_mode = false },
        .{ .initial = .character, .bytes = "\x16", .app_mode = .visual, .expected = .block, .select_mode = false },
        .{ .initial = .line, .bytes = "v", .app_mode = .visual, .expected = .character, .select_mode = false },
        .{ .initial = .line, .bytes = "V", .app_mode = .normal, .expected = .none, .select_mode = false },
        .{ .initial = .block, .bytes = "\x16", .app_mode = .normal, .expected = .none, .select_mode = false },
        .{ .initial = .character, .bytes = "\x07", .app_mode = .visual, .expected = .character, .select_mode = true },
        .{ .initial = .character, .bytes = "\x07\x07", .app_mode = .visual, .expected = .character, .select_mode = false },
    };
    for (toggle_cases) |case| {
        var app = try makeTestApp(std.testing.allocator, "alpha beta");
        defer app.deinit();
        try expectVisualMode(&app, case.initial, case.bytes, case.app_mode, case.expected, case.select_mode);
    }
}

fn expectVisualTextObjectYank(text: []const u8, row: usize, col: usize, keys: []const u8, expected: []const u8) !void {
    var app = try makeTestApp(std.testing.allocator, text);
    defer app.deinit();
    setCursor(&app, row, col);
    try app.handleNormalByte('v');
    try runVisualBytes(&app, keys);
    try app.handleVisualByte('y');
    try std.testing.expectEqualStrings(expected, app.registers.get('"').?);
}

test "visual text objects cover words and WORDs" {
    try expectVisualTextObjectYank("hello world", 0, 0, "aw", "hello ");
    try expectVisualTextObjectYank("hello world", 0, 0, "iw", "hello");
    try expectVisualTextObjectYank("hello world", 0, 0, "aW", "hello world");
    try expectVisualTextObjectYank("hello world", 0, 0, "iW", "hello world");
}

test "visual text objects cover paired delimiters" {
    try expectVisualTextObjectYank("(abc)", 0, 0, "ab", "(abc)");
    try expectVisualTextObjectYank("(abc)", 0, 0, "ib", "abc");
    try expectVisualTextObjectYank("(abc)", 0, 0, "a(", "(abc)");
    try expectVisualTextObjectYank("(abc)", 0, 0, "i(", "abc");
    try expectVisualTextObjectYank("(abc)", 0, 0, "a)", "(abc)");
    try expectVisualTextObjectYank("(abc)", 0, 0, "i)", "abc");
    try expectVisualTextObjectYank("[abc]", 0, 0, "a[", "[abc]");
    try expectVisualTextObjectYank("[abc]", 0, 0, "i[", "abc");
    try expectVisualTextObjectYank("[abc]", 0, 0, "a]", "[abc]");
    try expectVisualTextObjectYank("[abc]", 0, 0, "i]", "abc");
    try expectVisualTextObjectYank("{abc}", 0, 0, "aB", "{abc}");
    try expectVisualTextObjectYank("{abc}", 0, 0, "iB", "abc");
    try expectVisualTextObjectYank("{abc}", 0, 0, "a{", "{abc}");
    try expectVisualTextObjectYank("{abc}", 0, 0, "i{", "abc");
    try expectVisualTextObjectYank("{abc}", 0, 0, "a}", "{abc}");
    try expectVisualTextObjectYank("{abc}", 0, 0, "i}", "abc");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "a<", "<tag>");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "i<", "tag");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "a>", "<tag>");
    try expectVisualTextObjectYank("<tag>body</tag>", 0, 0, "i>", "tag");
}

test "visual text objects prefer tree-sitter blocks in zig buffers" {
    var app = try makeTestAppWithFiletype(std.testing.allocator, "pub fn demo() void {\n    const value = 1;\n}\n", "zig");
    defer app.deinit();

    setCursor(&app, 1, 10);
        const snapshot = try app.activeBuffer().readSnapshot(app.selectionForBuffer(app.activeBuffer().id));
    defer app.activeBuffer().freeReadSnapshot(snapshot);
    const expected_range = app.syntax.textObjectRange(snapshot, true) orelse return error.TestExpected;

    try app.handleNormalByte('v');
    try app.handleVisualByte('i');
    try app.handleVisualByte('{');
    try app.handleVisualByte('y');

    const expected = try app.selectedText(expected_range.start, expected_range.end);
    defer app.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, app.registers.get('"').?);
}

test "zig open line actions use syntax-aware indentation" {
    var app = try makeTestAppWithFiletype(std.testing.allocator, "pub fn demo() void {\n}\n", "zig");
    defer app.deinit();

    const snapshot = try app.activeBuffer().readSnapshot(app.selectionForBuffer(app.activeBuffer().id));
    defer app.activeBuffer().freeReadSnapshot(snapshot);
    const expected_indent = app.syntax.indentForRow(snapshot, 1);

    setCursor(&app, 0, app.activeBuffer().lines.items[0].len);
    try app.performNormalAction(.open_below, 1);

    const blank = app.activeBuffer().lines.items[1];
    var actual_indent: usize = 0;
    while (actual_indent < blank.len and blank[actual_indent] == ' ') : (actual_indent += 1) {}

    try std.testing.expectEqual(expected_indent, actual_indent);
    try std.testing.expectEqual(.insert, app.mode);
}

test "visual text objects cover quotes and backticks" {
    try expectVisualTextObjectYank("\"abc\"", 0, 0, "a\"", "\"abc\"");
    try expectVisualTextObjectYank("\"abc\"", 0, 0, "i\"", "abc");
    try expectVisualTextObjectYank("'abc'", 0, 0, "a'", "'abc'");
    try expectVisualTextObjectYank("'abc'", 0, 0, "i'", "abc");
    try expectVisualTextObjectYank("`abc`", 0, 0, "a`", "`abc`");
    try expectVisualTextObjectYank("`abc`", 0, 0, "i`", "abc");
}

test "visual text objects cover paragraphs sentences and tags" {
    try expectVisualTextObjectYank("alpha\nbeta\n\nomega", 1, 0, "ap", "alpha\nbeta");
    try expectVisualTextObjectYank("alpha\nbeta\n\nomega", 1, 0, "ip", "alpha\nbeta");
    try expectVisualTextObjectYank("One. Two!", 0, 0, "as", "One.");
    try expectVisualTextObjectYank("One. Two!", 0, 0, "is", "One.");
    try expectVisualTextObjectYank("<p>body</p>", 0, 0, "at", "<p>");
    try expectVisualTextObjectYank("<p>body</p>", 0, 0, "it", "p");
}

test "visual paste replaces the selection for both p and P" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    try app.registers.set('"', "XYZ");
    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('p');
    try std.testing.expectEqualStrings("XYZ beta", app.activeBuffer().currentLine());

    var app2 = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app2.deinit();

    try app2.registers.set('"', "XYZ");
    setCursor(&app2, 0, 0);
    try app2.handleNormalByte('v');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('l');
    try app2.handleVisualByte('P');
    try std.testing.expectEqualStrings("XYZ beta", app2.activeBuffer().currentLine());
}

test "visual mode can adjust numbers inside the selection" {
    var app = try makeTestApp(std.testing.allocator, "value 10");
    defer app.deinit();

    setCursor(&app, 0, 6);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte(0x01);
    try std.testing.expectEqualStrings("value 11", app.activeBuffer().currentLine());
}

test "visual text objects expand to the requested word" {
    var app = try makeTestApp(std.testing.allocator, "hello world");
    defer app.deinit();

    setCursor(&app, 0, 1);
    try app.handleNormalByte('v');
    try app.handleVisualByte('i');
    try app.handleVisualByte('w');
    try app.handleVisualByte('y');
    try std.testing.expectEqualStrings("hello", app.registers.get('"').?);
}

test "visual ctrl-] uses the highlighted tag text" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta alpha");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte(0x1d);
    try std.testing.expectEqual(Mode.normal, app.mode);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 11), app.activeBuffer().cursor.col);
}

test "visual block insert prefixes every selected line" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('I');
    try app.handleByte('X', std.fs.File.stdin());
    try app.handleByte(0x1b, std.fs.File.stdin());
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Xab\nXcd", text);
}

test "visual block append applies to every selected line" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('A');
    try app.handleByte('X', std.fs.File.stdin());
    try app.handleByte(0x1b, std.fs.File.stdin());
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("aXb\ncXd", text);
}

test "visual block yank and delete operate row by row" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('y');
    try std.testing.expectEqualStrings("a\nc", app.registers.get('"').?);

    setCursor(&app, 0, 0);
    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('d');
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("b\nd", text);
}

test "visual block filter runs per line" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.runVisualFilter("tr a-z A-Z");
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Ab\nCd", text);
}

test "visual block paste inserts each register line on each row" {
    var app = try makeTestApp(std.testing.allocator, "ab\ncd");
    defer app.deinit();

    try app.registers.set('"', "X\nY");
    try app.handleNormalByte(0x16);
    try app.handleVisualByte('j');
    try app.handleVisualByte('l');
    try app.handleVisualByte('p');
    const text = try app.activeBuffer().serialize();
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Xb\nYd", text);
}

test "visual filter commands replace the highlighted text" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try app.handleNormalByte('v');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('l');
    try app.handleVisualByte('!');
    try app.handleByte('t', std.fs.File.stdin());
    try app.handleByte('r', std.fs.File.stdin());
    try app.handleByte(' ', std.fs.File.stdin());
    try app.handleByte('a', std.fs.File.stdin());
    try app.handleByte('-', std.fs.File.stdin());
    try app.handleByte('z', std.fs.File.stdin());
    try app.handleByte(' ', std.fs.File.stdin());
    try app.handleByte('A', std.fs.File.stdin());
    try app.handleByte('-', std.fs.File.stdin());
    try app.handleByte('Z', std.fs.File.stdin());
    try app.handleByte('\n', std.fs.File.stdin());
    try std.testing.expectEqualStrings("ALPHA beta", app.activeBuffer().currentLine());
}

test "search and visual highlights compute the right spans" {
    var app = try makeTestApp(std.testing.allocator, "alpha beta\ngamma");
    defer app.deinit();

    app.search_highlight = try std.testing.allocator.dupe(u8, "be");
    defer if (app.search_highlight) |needle| std.testing.allocator.free(needle);
    app.search_preview_highlight = try std.testing.allocator.dupe(u8, "ha");
    defer if (app.search_preview_highlight) |needle| std.testing.allocator.free(needle);
    const search_range = app.nextSearchRange("alpha beta", "be", 0).?;
    try std.testing.expectEqual(@as(usize, 6), search_range.start);
    try std.testing.expectEqual(@as(usize, 8), search_range.end);
    app.mode = .search;
    try std.testing.expectEqualStrings("ha", app.activeSearchHighlight(true).?);
    app.clearSearchPreview();
    app.mode = .normal;
    try std.testing.expectEqualStrings("be", app.activeSearchHighlight(true).?);

    app.visual_mode = .character;
    app.visual_anchor = .{ .row = 0, .col = 1 };
    setCursor(&app, 0, 4);
    const char_selection = app.visualSelection().?;
    const char_range = app.visualRangeForRow(char_selection, 0, 5).?;
    try std.testing.expectEqual(@as(usize, 1), char_range.start);
    try std.testing.expectEqual(@as(usize, 4), char_range.end);

    app.visual_mode = .line;
    const line_selection = app.visualSelection().?;
    const line_range = app.visualRangeForRow(line_selection, 1, 5).?;
    try std.testing.expectEqual(@as(usize, 0), line_range.start);
    try std.testing.expectEqual(@as(usize, 5), line_range.end);
}

test "status and prompt bars compose their text" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.allocator.free(app.config.status_bar_icon);
    app.config.status_bar_icon = try app.config.allocator.dupe(u8, "N");
    app.config.allocator.free(app.config.status_bar_insert_icon);
    app.config.status_bar_insert_icon = try app.config.allocator.dupe(u8, "I");
    app.config.allocator.free(app.config.status_bar_visual_icon);
    app.config.status_bar_visual_icon = try app.config.allocator.dupe(u8, "V");
    try app.setStatus("ready");
    try app.builtins.setStatus("builtins idle");
    try app.buffers.append(try buffer_mod.Buffer.initEmpty(std.testing.allocator));
    app.split_index = 1;
    app.split_focus = .left;

    const status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(status);
    try std.testing.expectEqualStrings("N NORMAL | 󰈙 alpha [L] | 󰞋 ready │ 󰒓 builtins idle │  1:1 │ 100%", status);

    app.mode = .insert;
    const insert_status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(insert_status);
    try std.testing.expect(std.mem.indexOf(u8, insert_status, "I INSERT") != null);

    app.mode = .visual;
    const visual_status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(visual_status);
    try std.testing.expect(std.mem.indexOf(u8, visual_status, "V VISUAL") != null);

    app.mode = .select;
    const select_status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(select_status);
    try std.testing.expect(std.mem.indexOf(u8, select_status, "V SELECT") != null);

    app.mode = .replace;
    const replace_status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(replace_status);
    try std.testing.expect(std.mem.indexOf(u8, replace_status, "I REPLACE") != null);

    app.mode = .command;
    try app.command_buffer.appendSlice("w");
    const command = try app.promptBarText(std.testing.allocator);
    defer std.testing.allocator.free(command);
    try std.testing.expectEqualStrings(":w", command);

    app.mode = .search;
    app.search_buffer.clearRetainingCapacity();
    try app.search_buffer.appendSlice("needle");
    app.search_forward = false;
    const search = try app.promptBarText(std.testing.allocator);
    defer std.testing.allocator.free(search);
    try std.testing.expectEqualStrings("?needle", search);
}

test "status bar right side trims to keep a single line on narrow widths" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.setStatus("ready");
    try app.builtins.setStatus("builtins idle");
    try app.buffers.append(try buffer_mod.Buffer.initEmpty(std.testing.allocator));

    const status = try app.statusBarRightText(std.testing.allocator, 16);
    defer std.testing.allocator.free(status);
    try std.testing.expectEqualStrings("L/N 1:1 │ 100%", status);
}

test "default status bar icon uses nerd font glyph" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.allocator.free(app.config.status_bar_icon);
    app.config.status_bar_icon = try app.config.allocator.dupe(u8, "default");

    const icon = modeIconText(&app, .normal);
    try std.testing.expectEqualStrings("\u{e795}", icon);

    try app.setStatus("ready");
    try app.builtins.setStatus("builtins idle");
    try app.buffers.append(try buffer_mod.Buffer.initEmpty(std.testing.allocator));
    app.split_index = 1;
    app.split_focus = .left;
    const status = try app.statusBarText(std.testing.allocator);
    defer std.testing.allocator.free(status);
    try std.testing.expect(std.mem.startsWith(u8, status, "\u{e795} NORMAL"));
}

test "shift and case commands edit the current line and word" {
    var app = try makeTestApp(std.testing.allocator, "alpha\nMiXeD");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, ">");
    try std.testing.expectEqualStrings("    alpha", app.activeBuffer().lines.items[0]);
    try pressNormalKeys(&app, "<");
    try std.testing.expectEqualStrings("alpha", app.activeBuffer().lines.items[0]);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "~");
    try std.testing.expectEqualStrings("Alpha", app.activeBuffer().lines.items[0]);

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "gu");
    try std.testing.expectEqualStrings("mixed", app.activeBuffer().lines.items[1]);

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "gU");
    try std.testing.expectEqualStrings("MIXED", app.activeBuffer().lines.items[1]);

    setCursor(&app, 1, 0);
    try pressNormalKeys(&app, "g~");
    try std.testing.expectEqualStrings("mixed", app.activeBuffer().lines.items[1]);
}

test "leader line bindings add blank lines without entering insert mode" {
    var app = try makeTestApp(std.testing.allocator, "alpha\nbeta");
    defer app.deinit();

    setCursor(&app, 0, 5);
    try configureLeader(&app, " ", &.{
        .{ .sequence = "j", .action = "insert_line_below" },
        .{ .sequence = "k", .action = "insert_line_above" },
    });
    try pressNormalKeys(&app, " j");
    try std.testing.expectEqual(Mode.normal, app.mode);
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.col);
    try std.testing.expectEqualStrings("", app.activeBuffer().lines.items[1]);

    var app2 = try makeTestApp(std.testing.allocator, "alpha\nbeta");
    defer app2.deinit();

    try configureLeader(&app2, " ", &.{});
    setCursor(&app2, 1, 0);
    try pressNormalKeys(&app2, "[ ");
    try std.testing.expectEqual(Mode.normal, app2.mode);
    try std.testing.expectEqual(@as(usize, 1), app2.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app2.activeBuffer().cursor.col);
    try std.testing.expectEqualStrings("", app2.activeBuffer().lines.items[1]);
}

test "leader prefixes stay pending until they resolve or fail" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();
    try configureLeader(&app, " ", &.{
        .{ .sequence = "w", .action = "save" },
    });

    try app.handleNormalByte(' ');
    try std.testing.expectEqual(@as(usize, 1), app.normal_sequence.items.len);
    try std.testing.expectEqual(Mode.normal, app.mode);

    try app.handleNormalByte('x');
    try std.testing.expectEqual(@as(usize, 0), app.normal_sequence.items.len);
    try std.testing.expectEqualStrings("unknown command", app.status.items);
}

test "leader x confirms close targets and rejects cancellation" {
    var split_app = try makeTestApp(std.testing.allocator, "left");
    defer split_app.deinit();
    try configureLeader(&split_app, " ", &exampleLeaderBindings);
    try pressNormalKeys(&split_app, " s");
    try std.testing.expect(split_app.split_index != null);

    try pressNormalKeys(&split_app, " x");
    try std.testing.expectEqualStrings("close split? [y/N]", split_app.status.items);
    try std.testing.expectEqual(@as(?App.CloseTarget, .split), split_app.close_confirm);
    try split_app.handleNormalByte('n');
    try std.testing.expect(split_app.split_index != null);
    try std.testing.expectEqual(@as(?App.CloseTarget, null), split_app.close_confirm);
    try std.testing.expectEqualStrings("close cancelled", split_app.status.items);

    try pressNormalKeys(&split_app, " x");
    try split_app.handleNormalByte('y');
    try std.testing.expect(split_app.split_index == null);
    try std.testing.expectEqualStrings("pane closed", split_app.status.items);

    var tab_app = try makeTestApp(std.testing.allocator, "one");
    defer tab_app.deinit();
    try configureLeader(&tab_app, " ", &exampleLeaderBindings);
    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("two");
        try tab_app.buffers.append(buf);
    }
    try pressNormalKeys(&tab_app, " x");
    try std.testing.expectEqualStrings("close tab? [y/N]", tab_app.status.items);
    try std.testing.expectEqual(@as(?App.CloseTarget, .tab), tab_app.close_confirm);
    try tab_app.handleNormalByte(0x1b);
    try std.testing.expectEqual(@as(?App.CloseTarget, null), tab_app.close_confirm);
    try std.testing.expectEqual(@as(usize, 2), tab_app.buffers.items.len);
    try std.testing.expectEqualStrings("close cancelled", tab_app.status.items);

    try pressNormalKeys(&tab_app, " x");
    try tab_app.handleNormalByte('y');
    try std.testing.expectEqual(@as(usize, 1), tab_app.buffers.items.len);
    try std.testing.expectEqualStrings("tab closed", tab_app.status.items);

    var buffer_app = try makeTestApp(std.testing.allocator, "alpha");
    defer buffer_app.deinit();
    try configureLeader(&buffer_app, " ", &exampleLeaderBindings);
    try pressNormalKeys(&buffer_app, " x");
    try std.testing.expectEqualStrings("close buffer? [y/N]", buffer_app.status.items);
    try std.testing.expectEqual(@as(?App.CloseTarget, .buffer), buffer_app.close_confirm);
    try buffer_app.handleNormalByte('y');
    try std.testing.expectEqual(@as(usize, 1), buffer_app.buffers.items.len);
    try std.testing.expectEqualStrings("", buffer_app.activeBuffer().currentLine());
    try std.testing.expectEqualStrings("buffer closed", buffer_app.status.items);
}

test "example leader bindings dispatch end to end" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    {
        var f = try tmp.dir.createFile("leader-save.txt", .{});
        defer f.close();
        try f.writeAll("alpha");
    }

    var save_app = try makeTestApp(std.testing.allocator, "alpha");
    defer save_app.deinit();
    try configureLeader(&save_app, " ", &exampleLeaderBindings);
    try save_app.activeBuffer().replacePath("leader-save.txt");
    try save_app.activeBuffer().insertByte('!');
    try pressNormalKeys(&save_app, " w");
    const saved = try std.fs.cwd().readFileAlloc(std.testing.allocator, "leader-save.txt", 1 << 20);
    defer std.testing.allocator.free(saved);
    try std.testing.expectEqualStrings("!alpha", saved);
    try std.testing.expect(!save_app.activeBuffer().dirty);

    var quit_app = try makeTestApp(std.testing.allocator, "alpha");
    defer quit_app.deinit();
    try configureLeader(&quit_app, " ", &exampleLeaderBindings);
    try pressNormalKeys(&quit_app, " q");
    try std.testing.expect(quit_app.should_quit);

    var force_quit_app = try makeTestApp(std.testing.allocator, "alpha");
    defer force_quit_app.deinit();
    try configureLeader(&force_quit_app, " ", &exampleLeaderBindings);
    try force_quit_app.activeBuffer().insertByte('!');
    try pressNormalKeys(&force_quit_app, " Q");
    try std.testing.expect(force_quit_app.should_quit);

    var split_app = try makeTestApp(std.testing.allocator, "left");
    defer split_app.deinit();
    try configureLeader(&split_app, " ", &exampleLeaderBindings);
    try pressNormalKeys(&split_app, " s");
    try std.testing.expect(split_app.split_index != null);
    try std.testing.expectEqual(.right, split_app.split_focus);
    try pressNormalKeys(&split_app, " h");
    try std.testing.expectEqual(.left, split_app.split_focus);
    try pressNormalKeys(&split_app, " l");
    try std.testing.expectEqual(.right, split_app.split_focus);
    try pressNormalKeys(&split_app, " j");
    try std.testing.expectEqual(.right, split_app.split_focus);
    try pressNormalKeys(&split_app, " k");
    try std.testing.expectEqual(.left, split_app.split_focus);

    var split_app_v = try makeTestApp(std.testing.allocator, "left");
    defer split_app_v.deinit();
    try configureLeader(&split_app_v, " ", &exampleLeaderBindings);
    try pressNormalKeys(&split_app_v, " v");
    try std.testing.expect(split_app_v.split_index != null);
    try std.testing.expectEqual(.right, split_app_v.split_focus);

    var tab_app = try makeTestApp(std.testing.allocator, "one");
    defer tab_app.deinit();
    try configureLeader(&tab_app, " ", &exampleLeaderBindings);
    {
        var buf = try buffer_mod.Buffer.initEmpty(std.testing.allocator);
        errdefer buf.deinit();
        try buf.setText("two");
        try tab_app.buffers.append(buf);
    }
    try pressNormalKeys(&tab_app, " t");
    try std.testing.expectEqual(@as(usize, 1), tab_app.active_index);
    try pressNormalKeys(&tab_app, " T");
    try std.testing.expectEqual(@as(usize, 0), tab_app.active_index);
}

test "viewport commands update scroll position" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree\nfour\nfive");
    defer app.deinit();

    app.last_render_height = 3;
    setCursor(&app, 3, 0);
    try pressNormalKeys(&app, "zt");
    try std.testing.expectEqual(@as(usize, 3), app.activeBuffer().scroll_row);
    try pressNormalKeys(&app, "zb");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().scroll_row);
    try pressNormalKeys(&app, "zz");
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().scroll_row);
}

test "viewport scroll clamps to the last full screen" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree\nfour\nfive");
    defer app.deinit();

    app.last_render_height = 3;
    setCursor(&app, 4, 0);
    try app.performNormalAction(.viewport_bottom, 1);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().scroll_row);

    try app.performNormalAction(.scroll_down, 10);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().scroll_row);
}

test "cursor motion keeps the cursor visible" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree\nfour\nfive");
    defer app.deinit();

    app.last_render_height = 3;
    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "jjjj");
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().scroll_row);
}

test "gg and G pin the viewport to the top and bottom" {
    var app = try makeTestApp(std.testing.allocator, "one\ntwo\nthree\nfour\nfive");
    defer app.deinit();

    app.last_render_height = 3;
    setCursor(&app, 2, 0);
    try pressNormalKeys(&app, "G");
    try std.testing.expectEqual(@as(usize, 4), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 2), app.activeBuffer().scroll_row);

    setCursor(&app, 4, 0);
    try pressNormalKeys(&app, "gg");
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().cursor.row);
    try std.testing.expectEqual(@as(usize, 0), app.activeBuffer().scroll_row);
}

test "macro record and playback replays recorded keys" {
    var app = try makeTestApp(std.testing.allocator, "abc");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "qalqa");
    try std.testing.expectEqual(@as(?u8, null), app.macro_recording);

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "@a");
    try std.testing.expectEqual(@as(usize, 1), app.activeBuffer().cursor.col);
}

test "jump and change commands populate their history lists" {
    var app = try makeTestApp(std.testing.allocator, "abc\ndef");
    defer app.deinit();

    setCursor(&app, 0, 0);
    try pressNormalKeys(&app, "l");
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":jumps");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1:1") != null);

    setCursor(&app, 0, 1);
    try pressNormalKeys(&app, "x");
    app.command_buffer.clearRetainingCapacity();
    try app.command_buffer.appendSlice(":changes");
    try app.executeCommand();
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "1:2") != null);
}

test "editor command aliases" {
    try std.testing.expect(matchesCommand("help", &.{ "h", "help" }, ":help"));
    try std.testing.expect(matchesCommand("wq", &.{ "wq", "x" }, ":wq"));
    try std.testing.expect(matchesCommand("q!", &.{"q!"}, ":q!"));
}

test "lsp-enabled startup path launches the configured server" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const old_cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(old_cwd);
    try tmp.dir.setAsCwd();
    defer std.process.changeCurDir(old_cwd) catch {};

    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.lsp.enabled = true;
    app.config.allocator.free(app.config.lsp.command);
    app.config.lsp.command = try app.allocator.dupe(u8, "sh");
    try app.config.lsp.args.append(try app.allocator.dupe(u8, "-c"));
    try app.config.lsp.args.append(try app.allocator.dupe(u8, "cat > lsp-init.log"));

    app.startConfiguredLsp();
    try std.testing.expect(app.lsp_server != null);
    app.shutdownConfiguredLsp();

    const capture = try tmp.dir.readFileAlloc(std.testing.allocator, "lsp-init.log", 1 << 20);
    defer std.testing.allocator.free(capture);
    try std.testing.expect(std.mem.indexOf(u8, capture, "\"method\":\"initialize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture, "\"rootUri\":\"file://") != null);
    try std.testing.expect(std.mem.indexOf(u8, capture, "\"workspaceFolders\"") != null);
}

test "buffer close clears buffered lsp state for the closed path" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    try app.activeBuffer().replacePath("sample.txt");
    try app.lsp.publishDiagnostic(.{
        .buffer_id = 0,
        .path = try app.allocator.dupe(u8, "sample.txt"),
        .row = 0,
        .col = 0,
        .severity = .warning,
        .message = try app.allocator.dupe(u8, "first"),
    });
    try app.lsp.publishSymbol(.{
        .id = 1,
        .path = try app.allocator.dupe(u8, "sample.txt"),
        .row = 0,
        .col = 0,
        .label = try app.allocator.dupe(u8, "alpha"),
        .detail = try app.allocator.dupe(u8, "fn alpha"),
        .score = 1,
    });

    try app.closeCurrentPane();
    try std.testing.expectEqual(@as(usize, 0), app.lsp.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 0), app.lsp.symbols.items.len);
    try std.testing.expectEqualStrings("buffer closed", app.status.items);
}

test "lsp startup failure falls back without quitting the editor" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.lsp.enabled = true;
    app.config.allocator.free(app.config.lsp.command);
    app.config.lsp.command = try app.allocator.dupe(u8, "definitely-not-a-real-lsp-binary");

    app.startConfiguredLsp();
    try std.testing.expect(app.lsp_server == null);
    try std.testing.expect(std.mem.indexOf(u8, app.status.items, "lsp executable not found") != null);
}

test "lsp shutdown helper clears the started server" {
    var app = try makeTestApp(std.testing.allocator, "alpha");
    defer app.deinit();

    app.config.lsp.enabled = true;
    app.config.allocator.free(app.config.lsp.command);
    app.config.lsp.command = try app.allocator.dupe(u8, "sh");
    try app.config.lsp.args.append(try app.allocator.dupe(u8, "-c"));
    try app.config.lsp.args.append(try app.allocator.dupe(u8, "cat"));

    app.startConfiguredLsp();
    try std.testing.expect(app.lsp_server != null);

    app.shutdownConfiguredLsp();
    try std.testing.expect(app.lsp_server == null);
}
