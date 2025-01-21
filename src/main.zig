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

const BuiltInCommand = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn (shell: *const Shell, input: *const InputCommand) void,

    pub fn execute(self: BuiltInCommand, shell: *const Shell, input: *const InputCommand) !void {
        self.handler(shell, input);
    }
};

const Shell = struct {
    commands: []const BuiltInCommand,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, commands: []const BuiltInCommand) Shell {
        return Shell{
            .allocator = allocator,
            .commands = commands,
        };
    }

    pub fn getPath(self: Shell) ![]const u8 {
        const env_vars = try std.process.getEnvMap(self.allocator);
        const path_value = env_vars.get("PATH") orelse "";
        return path_value;
    }

    pub fn isExecutable(self: *const Shell, command: []const u8) !struct { bool, []const u8 } {
        const path = self.getPath() catch "";
        var iter = std.mem.splitScalar(u8, path, ':');
        while (iter.next()) |path_segment| {
            const fullPath = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path_segment, command }) catch "";
            const file = std.fs.cwd().openFile(fullPath, .{}) catch null;
            if (file != null) {
                return .{ true, fullPath };
            }
        }

        return .{ false, undefined };
    }

    // method to run the command
    pub fn run(self: *const Shell, command: *const InputCommand) !void {
        const stdout = std.io.getStdOut().writer();
        // check if the command exists
        var found = false;
        for (self.commands) |cmd| {
            if (std.mem.eql(u8, command.name, cmd.name)) {
                found = true;
                try cmd.execute(self, command);
                break;
            }
        }

        if (!found) {
            const isExecutableCommand, const executablePath = self.isExecutable(command.name) catch .{ false, undefined };
            _ = executablePath; // autofix

            if (isExecutableCommand) {
                found = true;
                var execArgs: [][]const u8 = try self.allocator.alloc([]const u8, command.args.?.items.len + 1);
                defer self.allocator.free(execArgs);

                execArgs[0] = command.name;

                for (command.args.?.items, 1..) |arg, i| {
                    execArgs[i] = arg;
                }

                var child = std.process.Child.init(execArgs, self.allocator);
                _ = try child.spawnAndWait();
            }
        }

        if (!found) {
            // print the error message
            try stdout.print("{s}: command not found \n", .{command.name});
        }
    }
};

fn exitHandler(shell: *const Shell, input: *const InputCommand) void {
    _ = shell; // autofix
    const firstArgument = if (input.args.?.items.len > 0) input.args.?.items[0] else "0";

    const code = std.fmt.parseInt(u8, firstArgument, 10) catch 0;

    std.process.exit(code);
}

fn echoHandler(shell: *const Shell, input: *const InputCommand) void {
    _ = shell; // autofix

    if (input.args.?.items.len == 0) {
        return;
    }

    const stdout = std.io.getStdOut().writer();

    for (input.args.?.items) |value| {
        stdout.print("{s} ", .{value}) catch {};
    }

    stdout.print("\n", .{}) catch {};
}

fn typeHandler(shell: *const Shell, input: *const InputCommand) void {
    if (input.args.?.items.len == 0) {
        return;
    }

    const stdout = std.io.getStdOut().writer();
    const commandName = input.args.?.items[0];

    var found = false;
    var isExecutable = false;
    var executablePath: []const u8 = undefined;

    for (shell.commands) |cmd| {
        if (std.mem.eql(u8, commandName, cmd.name)) {
            found = true;
            break;
        }
    }

    if (!found) {
        isExecutable, executablePath = shell.isExecutable(commandName) catch .{ false, undefined };
    }

    if (isExecutable) {
        stdout.print("{s} is {s} \n", .{ commandName, executablePath }) catch {};
    } else if (found) {
        stdout.print("{s} is a shell builtin \n", .{commandName}) catch {};
    } else {
        stdout.print("{s}: not found \n", .{commandName}) catch {};
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var buffer: [1024]u8 = undefined;

    const commands = [_]BuiltInCommand{
        BuiltInCommand{ .name = "exit", .description = "Exit shell", .handler = &exitHandler },
        BuiltInCommand{ .name = "echo", .description = "Echo the input", .handler = &echoHandler },
        BuiltInCommand{ .name = "type", .description = "Print the type of the input", .handler = &typeHandler },
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const shell = Shell.init(allocator, &commands);

    while (true) {
        try stdout.print("$ ", .{});
        const command = try stdin.readUntilDelimiter(&buffer, '\n');
        const cmd = InputCommand.parse(allocator, command) catch InputCommand{ .name = "error", .args = undefined };

        try shell.run(&cmd);
    }
}
