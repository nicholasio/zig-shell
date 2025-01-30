const std = @import("std");
const InputCommand = @import("input.zig").InputCommand;
const Shell = @import("shell.zig").Shell;
const BuiltInCommand = @import("builtincommand.zig").BuiltInCommand;

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

fn pwdHandler(shell: *const Shell, input: *const InputCommand) void {
    _ = input; // autofix
    const stdout = std.io.getStdOut().writer();
    const cwd = std.fs.cwd().realpathAlloc(shell.allocator, ".") catch "";
    defer shell.allocator.free(cwd);
    stdout.print("{s}\n", .{cwd}) catch {};
}

fn cdHandler(shell: *const Shell, input: *const InputCommand) void {
    if (input.args.?.items.len == 0) {
        return;
    }

    var directory = input.args.?.items[0];

    if (std.mem.eql(u8, directory, "~")) {
        directory = shell.getHomeDirectory() catch "";
    }

    const dirObject = std.fs.cwd().openDir(directory, .{});

    if (dirObject) |dir| {
        dir.setAsCwd() catch {};
        //         defer dir.close();
    } else |err| {
        const stdout = std.io.getStdOut().writer();
        switch (err) {
            std.fs.Dir.OpenError.FileNotFound => stdout.print("cd: {s}: No such file or directory \n", .{directory}) catch {},
            std.fs.Dir.OpenError.NotDir => stdout.print("cd: {s}: Not a directory \n", .{directory}) catch {},
            else => {
                stdout.print("cd: {s}: {s} \n", .{
                    directory,
                    "an error occurred",
                }) catch {};
                return;
            },
        }
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
        BuiltInCommand{ .name = "pwd", .description = "Print the current working directory", .handler = &pwdHandler },
        BuiltInCommand{ .name = "cd", .description = "Change the current working directory", .handler = &cdHandler },
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
