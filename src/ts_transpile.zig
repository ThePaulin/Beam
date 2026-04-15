const std = @import("std");

pub fn transpile(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    var in_string: ?u8 = null;
    var in_line_comment = false;
    var in_block_comment = false;
    var brace_depth: usize = 0;

    var in_function_params = false;
    var param_paren_depth: usize = 0;
    var param_brace_depth: usize = 0;
    var param_bracket_depth: usize = 0;
    var param_angle_depth: usize = 0;
    var saw_function_keyword = false;
    var in_var_decl = false;
    var after_initializer = false;

    while (i < source.len) {
        const c = source[i];

        if (in_line_comment) {
            try out.append(c);
            i += 1;
            if (c == '\n') in_line_comment = false;
            continue;
        }

        if (in_block_comment) {
            try out.append(c);
            i += 1;
            if (c == '*' and i < source.len and source[i] == '/') {
                try out.append('/');
                i += 1;
                in_block_comment = false;
            }
            continue;
        }

        if (in_string) |quote| {
            try out.append(c);
            i += 1;
            if (c == '\\' and i < source.len) {
                try out.append(source[i]);
                i += 1;
                continue;
            }
            if (c == quote) in_string = null;
            continue;
        }

        if (isWordStart(c)) {
            const word = readWord(source, i);
            if (std.mem.eql(u8, word, "function")) {
                saw_function_keyword = true;
                try out.appendSlice(word);
                i += word.len;
                continue;
            }
            if (std.mem.eql(u8, word, "const") or std.mem.eql(u8, word, "let") or std.mem.eql(u8, word, "var")) {
                in_var_decl = true;
                after_initializer = false;
                try out.appendSlice(word);
                i += word.len;
                continue;
            }
            if (std.mem.eql(u8, word, "as")) {
                i = try skipTypeAnnotation(source, i + word.len);
                continue;
            }
            if (brace_depth == 0 and isTopLevelDeclarationStart(word, source, i)) {
                i = try skipTypeDeclaration(source, i + word.len);
                continue;
            }
            if (brace_depth == 0 and std.mem.eql(u8, word, "export")) {
                i += word.len;
                while (i < source.len and std.ascii.isWhitespace(source[i])) i += 1;
                if (matchWord(source, i, "default")) {
                    i += "default".len;
                }
                continue;
            }
            try out.appendSlice(word);
            i += word.len;
            continue;
        }

        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                try out.appendSlice("//");
                i += 2;
                in_line_comment = true;
                continue;
            }
            if (source[i + 1] == '*') {
                try out.appendSlice("/*");
                i += 2;
                in_block_comment = true;
                continue;
            }
        }

        if (c == '"' or c == '\'') {
            try out.append(c);
            in_string = c;
            i += 1;
            continue;
        }

        if ((saw_function_keyword or (in_var_decl and after_initializer)) and c == '(') {
            saw_function_keyword = false;
            in_function_params = true;
            param_paren_depth = 1;
            param_brace_depth = 0;
            param_bracket_depth = 0;
            param_angle_depth = 0;
            try out.append(c);
            i += 1;
            continue;
        }

        if (!in_function_params) {
            if (c == '{') brace_depth += 1;
            if (c == '}') {
                if (brace_depth > 0) brace_depth -= 1;
            }
        }

        if (in_var_decl and !in_function_params and param_paren_depth == 0 and param_bracket_depth == 0 and param_angle_depth == 0) {
            if (c == '=') {
                after_initializer = true;
            } else if (c == ',') {
                after_initializer = false;
            } else if (c == ';' or c == '\n') {
                in_var_decl = false;
                after_initializer = false;
            }
        }

        if (in_function_params) {
            if (c == '(') {
                param_paren_depth += 1;
            } else if (c == ')') {
                if (param_paren_depth > 0) param_paren_depth -= 1;
                if (param_paren_depth == 0) in_function_params = false;
            } else if (c == '{') {
                param_brace_depth += 1;
            } else if (c == '}') {
                if (param_brace_depth > 0) param_brace_depth -= 1;
            } else if (c == '[') {
                param_bracket_depth += 1;
            } else if (c == ']') {
                if (param_bracket_depth > 0) param_bracket_depth -= 1;
            } else if (c == '<') {
                param_angle_depth += 1;
            } else if (c == '>') {
                if (param_angle_depth > 0) param_angle_depth -= 1;
            }

            if (c == ':' and param_paren_depth == 1 and param_brace_depth == 0 and param_bracket_depth == 0 and param_angle_depth == 0) {
                i = try skipTypeAnnotation(source, i + 1);
                continue;
            }

            try out.append(c);
            i += 1;
            continue;
        }

        if (in_var_decl and !after_initializer and c == ':' and param_paren_depth == 0 and param_bracket_depth == 0 and param_angle_depth == 0) {
            i = try skipTypeAnnotation(source, i + 1);
            continue;
        }

        try out.append(c);
        i += 1;
    }

    return try out.toOwnedSlice();
}

fn isWordStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '$';
}

fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
}

fn readWord(source: []const u8, start: usize) []const u8 {
    var end = start;
    while (end < source.len and isWordChar(source[end])) : (end += 1) {}
    return source[start..end];
}

fn matchWord(source: []const u8, index: usize, word: []const u8) bool {
    if (index + word.len > source.len) return false;
    if (!std.mem.eql(u8, source[index .. index + word.len], word)) return false;
    if (index > 0 and isWordChar(source[index - 1])) return false;
    if (index + word.len < source.len and isWordChar(source[index + word.len])) return false;
    return true;
}

fn isTopLevelDeclarationStart(word: []const u8, source: []const u8, index: usize) bool {
    if (!std.mem.eql(u8, word, "type") and !std.mem.eql(u8, word, "interface")) return false;
    if (index > 0 and isWordChar(source[index - 1])) return false;
    return true;
}

fn skipTypeDeclaration(source: []const u8, start: usize) !usize {
    var i = start;
    var brace_depth: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_string: ?u8 = null;
    var in_line_comment = false;
    var in_block_comment = false;

    while (i < source.len) {
        const c = source[i];

        if (in_line_comment) {
            i += 1;
            if (c == '\n') in_line_comment = false;
            continue;
        }
        if (in_block_comment) {
            i += 1;
            if (c == '*' and i < source.len and source[i] == '/') {
                i += 1;
                in_block_comment = false;
            }
            continue;
        }
        if (in_string) |quote| {
            i += 1;
            if (c == '\\' and i < source.len) {
                i += 1;
                continue;
            }
            if (c == quote) in_string = null;
            continue;
        }
        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                in_line_comment = true;
                i += 2;
                continue;
            }
            if (source[i + 1] == '*') {
                in_block_comment = true;
                i += 2;
                continue;
            }
        }
        if (c == '"' or c == '\'') {
            in_string = c;
            i += 1;
            continue;
        }
        if (c == '{') brace_depth += 1;
        if (c == '}') {
            if (brace_depth == 0 and paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) return i + 1;
            if (brace_depth > 0) brace_depth -= 1;
        }
        if (c == '(') paren_depth += 1;
        if (c == ')') {
            if (paren_depth > 0) paren_depth -= 1;
        }
        if (c == '[') bracket_depth += 1;
        if (c == ']') {
            if (bracket_depth > 0) bracket_depth -= 1;
        }
        if (c == '<') angle_depth += 1;
        if (c == '>') {
            if (angle_depth > 0) angle_depth -= 1;
        }

        if (c == '=' and brace_depth == 0 and paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
            return try skipUntilSemicolon(source, i + 1);
        }
        if (c == '{' and brace_depth == 1) {
            return try skipBalancedBrace(source, i + 1);
        }
        i += 1;
    }
    return source.len;
}

fn skipBalancedBrace(source: []const u8, start: usize) !usize {
    var i = start;
    var depth: usize = 1;
    var in_string: ?u8 = null;
    var in_line_comment = false;
    var in_block_comment = false;

    while (i < source.len) {
        const c = source[i];
        if (in_line_comment) {
            i += 1;
            if (c == '\n') in_line_comment = false;
            continue;
        }
        if (in_block_comment) {
            i += 1;
            if (c == '*' and i < source.len and source[i] == '/') {
                i += 1;
                in_block_comment = false;
            }
            continue;
        }
        if (in_string) |quote| {
            i += 1;
            if (c == '\\' and i < source.len) {
                i += 1;
                continue;
            }
            if (c == quote) in_string = null;
            continue;
        }
        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                in_line_comment = true;
                i += 2;
                continue;
            }
            if (source[i + 1] == '*') {
                in_block_comment = true;
                i += 2;
                continue;
            }
        }
        if (c == '"' or c == '\'') {
            in_string = c;
            i += 1;
            continue;
        }
        if (c == '{') depth += 1;
        if (c == '}') {
            depth -= 1;
            if (depth == 0) {
                i += 1;
                while (i < source.len and std.ascii.isWhitespace(source[i])) i += 1;
                if (i < source.len and source[i] == ';') i += 1;
                return i;
            }
        }
        i += 1;
    }
    return source.len;
}

fn skipUntilSemicolon(source: []const u8, start: usize) !usize {
    var i = start;
    var brace_depth: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_string: ?u8 = null;
    var in_line_comment = false;
    var in_block_comment = false;

    while (i < source.len) {
        const c = source[i];
        if (in_line_comment) {
            i += 1;
            if (c == '\n') in_line_comment = false;
            continue;
        }
        if (in_block_comment) {
            i += 1;
            if (c == '*' and i < source.len and source[i] == '/') {
                i += 1;
                in_block_comment = false;
            }
            continue;
        }
        if (in_string) |quote| {
            i += 1;
            if (c == '\\' and i < source.len) {
                i += 1;
                continue;
            }
            if (c == quote) in_string = null;
            continue;
        }
        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                in_line_comment = true;
                i += 2;
                continue;
            }
            if (source[i + 1] == '*') {
                in_block_comment = true;
                i += 2;
                continue;
            }
        }
        if (c == '"' or c == '\'') {
            in_string = c;
            i += 1;
            continue;
        }
        if (c == '{') brace_depth += 1;
        if (c == '}') {
            if (brace_depth > 0) brace_depth -= 1;
        }
        if (c == '(') paren_depth += 1;
        if (c == ')') {
            if (paren_depth > 0) paren_depth -= 1;
        }
        if (c == '[') bracket_depth += 1;
        if (c == ']') {
            if (bracket_depth > 0) bracket_depth -= 1;
        }
        if (c == '<') angle_depth += 1;
        if (c == '>') {
            if (angle_depth > 0) angle_depth -= 1;
        }
        if (c == ';' and brace_depth == 0 and paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
            return i + 1;
        }
        i += 1;
    }
    return source.len;
}

fn skipTypeAnnotation(source: []const u8, start: usize) !usize {
    var i = start;
    var brace_depth: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_string: ?u8 = null;
    var in_line_comment = false;
    var in_block_comment = false;

    while (i < source.len) {
        const c = source[i];
        if (in_line_comment) {
            i += 1;
            if (c == '\n') in_line_comment = false;
            continue;
        }
        if (in_block_comment) {
            i += 1;
            if (c == '*' and i < source.len and source[i] == '/') {
                i += 1;
                in_block_comment = false;
            }
            continue;
        }
        if (in_string) |quote| {
            i += 1;
            if (c == '\\' and i < source.len) {
                i += 1;
                continue;
            }
            if (c == quote) in_string = null;
            continue;
        }
        if (c == '/' and i + 1 < source.len) {
            if (source[i + 1] == '/') {
                in_line_comment = true;
                i += 2;
                continue;
            }
            if (source[i + 1] == '*') {
                in_block_comment = true;
                i += 2;
                continue;
            }
        }
        if (c == '"' or c == '\'') {
            in_string = c;
            i += 1;
            continue;
        }
        if (c == '{') brace_depth += 1;
        if (c == '}') {
            if (brace_depth > 0) brace_depth -= 1;
        }
        if (c == '(') paren_depth += 1;
        if (c == ')') {
            if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) return i;
            if (paren_depth > 0) paren_depth -= 1;
        }
        if (c == '[') bracket_depth += 1;
        if (c == ']') {
            if (bracket_depth > 0) bracket_depth -= 1;
        }
        if (c == '<') angle_depth += 1;
        if (c == '>') {
            if (angle_depth > 0) angle_depth -= 1;
        }

        if (brace_depth == 0 and paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
            if (c == ',' or c == ')' or c == ';' or c == '}') return i;
            if (c == '=') {
                if (i + 1 < source.len and source[i + 1] == '>') {
                    i += 1;
                    continue;
                }
                return i;
            }
        }
        i += 1;
    }
    return source.len;
}

test "strip typescript subset" {
    const input =
        \\export type BeamContext = {
        \\  on(event: string, handler: (payload: unknown) => void): void;
        \\};
        \\
        \\export async function activate(beam: BeamContext) {
        \\  const label: string = "hello" as string;
        \\  const run = (name: string, count: number) => {
        \\    return name;
        \\  };
        \\  beam.registerCommand("hello.say", "Say hello", async () => {
        \\    return "hello";
        \\  });
        \\}
    ;
    const output = try transpile(std.testing.allocator, input);
    defer std.testing.allocator.free(output);
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, "BeamContext"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, "export"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, ": string"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, " as string"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "function activate(beam)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "const run = (name, count) =>"));
}
