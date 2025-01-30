const std = @import("std");
const expect = std.testing.expect;

pub const InputCommand = struct {
    name: []const u8,
    args: ?std.ArrayList([]const u8),

    // method to parse the command
    pub fn parse(allocator: std.mem.Allocator, command: []const u8) !InputCommand {
        // split the command into name and args
        var parts = std.mem.splitScalar(u8, command, ' ');
        const name = parts.first();

        const argsString = parts.rest();

        var args = try std.ArrayList([]const u8).initCapacity(allocator, 10);

        var in_quote = false;
        var in_double_quotes = false;

        var buffer = try std.ArrayList(u8).initCapacity(allocator, 10);
        defer buffer.deinit();

        for (argsString) |c| {
            if (c == ' ' and !in_quote) {
                if (buffer.items.len > 0) {
                    try args.append(try buffer.toOwnedSlice());
                    buffer.clearRetainingCapacity();
                }

                continue;
            }

            if (c == '\'') {
                in_quote = !in_quote;
                continue;
            }

            if (c == '"') {
                in_double_quotes = !in_double_quotes;
                continue;
            }

            try buffer.append(c);
        }

        if (buffer.items.len > 0) {
            try args.append(try buffer.toOwnedSlice());
        }

        return InputCommand{ .name = name, .args = args };
    }
};

test "parse simple command" {
    const allocator = std.heap.page_allocator;
    const command = "echo hello";

    const input = try InputCommand.parse(allocator, command);

    try expect(std.mem.eql(u8, input.name, "echo"));
    try expect(input.args.?.items.len == 1);
    try expect(std.mem.eql(u8, input.args.?.items[0], "hello"));
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
