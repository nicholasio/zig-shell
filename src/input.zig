const std = @import("std");
const expect = std.testing.expect;

const RedirectionType = enum {
    None,
    Input,
    Output,
    Append,
};

const InputRedirection = struct {
    type: RedirectionType,
    file: []const u8,
};

pub fn isRedirection(arg: []const u8) bool {
    return std.mem.eql(u8, arg, ">") or std.mem.eql(u8, arg, "1>") or std.mem.eql(u8, arg, ">>") or std.mem.eql(u8, arg, "<") or std.mem.eql(u8, arg, "2>") or std.mem.eql(u8, arg, "2>>");
}
pub const InputCommand = struct {
    name: []const u8,
    args: ?std.ArrayList([]const u8),
    argIndex: usize = 0,
    hasRedirection: bool = false,

    pub fn nextArg(self: *InputCommand) ?[]const u8 {
        if (self.args == null) {
            return null;
        }

        if (self.args.?.items.len == 0) {
            return null;
        }

        if (self.argIndex >= self.args.?.items.len) {
            return null;
        }

        const arg = self.args.?.items[self.argIndex];
        self.argIndex = self.argIndex + 1;
        return arg;
    }

    pub fn rewindOneArg(self: *InputCommand) void {
        if (self.argIndex > 0) {
            self.argIndex = self.argIndex - 1;
        }
    }

    pub fn peekArg(self: *InputCommand) ?[]const u8 {
        if (self.args == null) {
            return null;
        }

        if (self.args.?.items.len == 0) {
            return null;
        }

        if (self.argIndex >= self.args.?.items.len) {
            return null;
        }

        return self.args.?.items[self.argIndex];
    }

    pub fn parse(allocator: std.mem.Allocator, command: []const u8) !InputCommand {
        // split the command into name and args
        var args = try std.ArrayList([]const u8).initCapacity(allocator, 10);

        var hasCapturedCommandName = false;
        var name: []u8 = undefined;
        var in_quote = false;
        var in_double_quotes = false;
        var isEscapedChar = false;
        var hasRedirection = false;

        var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
        defer buffer.deinit();

        for (command, 0..) |c, i| {
            if (isEscapedChar) {
                try buffer.append(c);
                isEscapedChar = false;
            } else {
                const nextChar = if (i < command.len - 1) command[i + 1] else @as(u8, ' ');
                const maybeEscape = nextChar == '\\' or nextChar == '"' or nextChar == '$';

                // if there's a backslash and it's not inside quotes, we should escape the next character
                // if we're in double quotes, we should only escape depending on the next char
                if ((c == '\\' and (!in_double_quotes and !in_quote)) or (c == '\\' and in_double_quotes and maybeEscape)) {
                    isEscapedChar = true;
                    continue;
                }

                if (c == ' ' and !in_quote and !in_double_quotes) {
                    if (buffer.items.len > 0) {
                        if (!hasCapturedCommandName) {
                            hasCapturedCommandName = true;
                            name = try allocator.alloc(u8, buffer.items.len);
                            name = try buffer.toOwnedSlice();
                        } else {
                            const slice = try buffer.toOwnedSlice();
                            if (isRedirection(slice)) {
                                hasRedirection = true;
                            }
                            try args.append(slice);
                        }
                        buffer.clearRetainingCapacity();
                    }

                    continue;
                }

                if (c == '\'' and !in_double_quotes) {
                    in_quote = !in_quote;
                    continue;
                }

                if (c == '"' and !in_quote) {
                    in_double_quotes = !in_double_quotes;
                    continue;
                }

                try buffer.append(c);
            }
        }

        if (buffer.items.len > 0) {
            if (!hasCapturedCommandName) {
                hasCapturedCommandName = true;
                name = try allocator.alloc(u8, buffer.items.len);
                name = try buffer.toOwnedSlice();
            } else {
                const slice = try buffer.toOwnedSlice();
                if (isRedirection(slice)) {
                    hasRedirection = true;
                }
                try args.append(slice);
            }
        }

        return InputCommand{ .name = name, .args = args, .hasRedirection = hasRedirection };
    }
};

test "parse command name with quotes" {
    const allocator = std.heap.page_allocator;
    const command = "\"this is an exec\"";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "this is an exec"));
}

test "parse simple command" {
    const allocator = std.heap.page_allocator;
    const command = "echo hello test";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 2);
    try expect(std.mem.eql(u8, input.args.?.items[0], "hello"));
    try expect(std.mem.eql(u8, input.args.?.items[1], "test"));
}

test "parse command with single quotes" {
    const allocator = std.heap.page_allocator;
    const command = "echo 'hello world'";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 1);
    try expect(std.mem.eql(u8, input.args.?.items[0], "hello world"));
}

test "parse command with single quotes and multile args" {
    const allocator = std.heap.page_allocator;
    const command = "echo 'hello world' test 'foo bar'";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 3);
    try expect(std.mem.eql(u8, input.args.?.items[0], "hello world"));
    try expect(std.mem.eql(u8, input.args.?.items[1], "test"));
    try expect(std.mem.eql(u8, input.args.?.items[2], "foo bar"));
}

test "parse command with double quotes and multile args" {
    const allocator = std.heap.page_allocator;
    const command = "echo \"hello world\" test \"foo bar\"";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 3);
    try expect(std.mem.eql(u8, input.args.?.items[0], "hello world"));
    try expect(std.mem.eql(u8, input.args.?.items[1], "test"));
    try expect(std.mem.eql(u8, input.args.?.items[2], "foo bar"));
}

test "parse command with double quotes and multile args and with both single and double quotes" {
    const allocator = std.heap.page_allocator;
    const command = "echo \"hello world\" \"test's\" \"foo bar\" 'hello \" test'";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 4);
    try expect(std.mem.eql(u8, input.args.?.items[0], "hello world"));
    try expect(std.mem.eql(u8, input.args.?.items[1], "test's"));
    try expect(std.mem.eql(u8, input.args.?.items[2], "foo bar"));
    try expect(std.mem.eql(u8, input.args.?.items[3], "hello \" test"));
}

test "parse command with backslashes inside double quotes" {
    const allocator = std.heap.page_allocator;
    const command = "echo \"before\\    after\" \"hello'script'\\\\n'world\"";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 2);
    try expect(std.mem.eql(u8, input.args.?.items[0], "before\\    after"));
    try expect(std.mem.eql(u8, input.args.?.items[1], "hello'script'\\n'world"));
}

test "parse command with backslashes outsite quotes" {
    const allocator = std.heap.page_allocator;
    const command = "echo example\\ \\ \\ \\ \\ \\ script";

    var input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(std.mem.eql(u8, input.args.?.items[0], "example      script"));

    const catCommand = "cat \"/tmp/file\\\\name\" \"/tmp/file\\ name\"";
    input = try InputCommand.parse(allocator, catCommand);

    try expect(std.mem.eql(u8, input.name, "cat"));
    try expect(std.mem.eql(u8, input.args.?.items[0], "/tmp/file\\name"));
    try expect(std.mem.eql(u8, input.args.?.items[1], "/tmp/file\\ name"));
}

test "parse command with backslashes inside single quotes" {
    const allocator = std.heap.page_allocator;
    const command = "echo 'before\\    after'";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(std.mem.eql(u8, input.args.?.items[0], "before\\    after"));
}
