const std = @import("std");

const InputCommand = struct {
    name: []const u8,
    args: ?std.ArrayList([]const u8),

    // method to parse the command
    pub fn parse(allocator: std.mem.Allocator, command: []const u8) !InputCommand {
        // split the command into name and args
        var parts = std.mem.splitScalar(u8, command, ' ');
        const name = parts.first();

        var args = try std.ArrayList([]const u8).initCapacity(allocator, 10);

        while (parts.next()) |part| {
            try args.append(part);
        }

        return InputCommand{ .name = name, .args = args };
    }
};

const Command = struct {
    name: []const u8,
    description: []const u8,
    // handler: fn (runner: *Runner, input: *InputCommand) i32,

    pub fn execute(self: Command, runner: *const Runner, input: *const InputCommand) void {
        if (std.mem.eql(u8, self.name, "exit")) {
            return exitHandler(runner, input);
        }
    }
};

const Runner = struct {
    commands: []const Command,

    // method to run the command
    pub fn run(self: *const Runner, command: *const InputCommand) !void {
        // check if the command exists
        var found = false;
        for (self.commands) |cmd| {
            if (std.mem.eql(u8, command.*.name, cmd.name)) {
                found = true;
                cmd.execute(self, command);
                break;
            }
        }

        // print the error message
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}: command not found \n", .{command.*.name});
    }
};

fn exitHandler(runner: *const Runner, input: *const InputCommand) void {
    _ = runner; // autofix
    const firstArgument = input.*.args.?.items[0];

    const code = std.fmt.parseInt(u8, firstArgument, 10) catch 0;

    std.process.exit(code);
}

const exitCommand = Command{
    .name = "exit",
    .description = "Exit the shell",
    .handler = exitHandler,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const stdin = std.io.getStdIn().reader();
    var buffer: [1024]u8 = undefined;

    const commands = [_]Command{
        Command{ .name = "exit", .description = "Exit shell" },
    };

    const runner = Runner{ .commands = &commands };
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    while (true) {
        try stdout.print("$ ", .{});
        const command = try stdin.readUntilDelimiter(&buffer, '\n');
        const cmd = InputCommand.parse(allocator, command) catch InputCommand{ .name = "error", .args = undefined };

        try runner.run(&cmd);
    }
}
