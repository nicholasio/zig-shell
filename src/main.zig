const std = @import("std");
const Input = @import("input.zig");
const InputCommand = Input.InputCommand;
const Shell = @import("shell.zig").Shell;
const BuiltInCommand = @import("builtincommand.zig").BuiltInCommand;
const Result = @import("builtincommand.zig").Result;

fn exitHandler(shell: *Shell, input: *InputCommand) Result {
    const firstArgument = input.nextArg() orelse "0";

    const code = std.fmt.parseInt(u8, firstArgument, 10) catch 0;

    shell.exit(code) catch {};

    return .{ .value = null, .isError = false };
}

fn echoHandler(shell: *Shell, input: *InputCommand) Result {
    if (input.args.?.items.len == 0) {
        return .{ .value = null, .isError = false };
    }

    var echoed: ?[]u8 = null;
    while (input.nextArg()) |value| {
        if (Input.isRedirection(value)) {
            input.rewindOneArg();
            break;
        }
        const toConcat = echoed orelse "";
        echoed = std.fmt.allocPrint(shell.allocator, "{s}{s} ", .{ toConcat, value }) catch "";
    }

    if (echoed) |value| {
        return .{ .value = std.fmt.allocPrint(shell.allocator, "{s}\n", .{value}) catch null, .isError = false };
    }

    return .{ .value = echoed, .isError = false };
}

fn typeHandler(shell: *Shell, input: *InputCommand) Result {
    const commandName = input.nextArg() orelse "";

    if (std.mem.eql(u8, commandName, "")) {
        return .{ .value = null, .isError = false };
    }

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

    var out: ?[]const u8 = null;
    var isError = false;

    if (isExecutable) {
        out = std.fmt.allocPrint(shell.allocator, "{s} is {s}\n", .{ commandName, executablePath }) catch "";
    } else if (found) {
        out = std.fmt.allocPrint(shell.allocator, "{s} is a shell builtin\n", .{commandName}) catch "";
    } else {
        isError = true;
        out = std.fmt.allocPrint(shell.allocator, "{s}: not found\n", .{commandName}) catch "";
    }

    return .{ .value = out, .isError = isError };
}

fn pwdHandler(shell: *Shell, input: *InputCommand) Result {
    _ = input; // autofix

    const cwd = std.fs.cwd().realpathAlloc(shell.allocator, ".") catch "";

    return .{ .value = std.fmt.allocPrint(shell.allocator, "{s}\n", .{cwd}) catch null, .isError = false };
}

fn cdHandler(shell: *Shell, input: *InputCommand) Result {
    var directory = input.nextArg() orelse "";

    if (std.mem.eql(u8, directory, "~")) {
        directory = shell.getHomeDirectory() catch "";
    }

    const dirObject = std.fs.cwd().openDir(directory, .{});

    if (dirObject) |dir| {
        dir.setAsCwd() catch {};
    } else |err| {
        return switch (err) {
            std.fs.Dir.OpenError.FileNotFound => .{ .value = std.fmt.allocPrint(shell.allocator, "cd: {s}: No such file or directory\n", .{directory}) catch null, .isError = true },
            std.fs.Dir.OpenError.NotDir => .{ .value = std.fmt.allocPrint(shell.allocator, "cd: {s}: Not a directory\n", .{directory}) catch null, .isError = true },
            else => .{ .value = std.fmt.allocPrint(shell.allocator, "cd: {s}: {s}\n", .{
                directory,
                "an error occurred",
            }) catch null, .isError = true },
        };
    }

    return .{ .value = null, .isError = false };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var buffer: [1024]u8 = undefined;

    const commands = [_]BuiltInCommand{
        BuiltInCommand{ .name = "exit", .description = "Exit shell", .handler = &exitHandler },
        BuiltInCommand{ .name = "echo", .description = "Echo the input", .handler = &echoHandler },
        BuiltInCommand{ .name = "type", .description = "Print the type of the input", .handler = &typeHandler },
        BuiltInCommand{ .name = "pwd", .description = "Print the current working directory", .handler = &pwdHandler },
        BuiltInCommand{ .name = "cd", .description = "Change the current working directory", .handler = &cdHandler },
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var shell = Shell.init(allocator, &commands);

    try Input.setRawInput(true);

    while (shell.isRunning()) {
        try stdout.print("$ ", .{});

        var buf_index: usize = 0;

        while (true) {
            const c = try stdin.readByte();

            if (c == '\t') {
                if (buf_index > 0) {
                    const len = try shell.handleTab(buffer[0..buf_index], &buffer);
                    if (len > 0) {
                        try stdout.print("{s}", .{buffer[buf_index..len]});
                        buf_index = len;
                    }
                }
                continue;
            }

            if (c == '\n') {
                try stdout.print("\n", .{});
                buffer[buf_index] = c;
                break;
            }

            try stdout.print("{c}", .{c});
            buffer[buf_index] = c;

            buf_index += 1;
        }
        const command = buffer[0..buf_index];
        var cmd = InputCommand.parse(allocator, command) catch InputCommand{ .name = "error", .args = undefined };

        try shell.run(&cmd);
    }

    try Input.setRawInput(false);

    std.process.exit(shell.getExitCode());
}
