const std = @import("std");
const InputCommand = @import("input.zig").InputCommand;
const Shell = @import("shell.zig").Shell;
const BuiltInCommand = @import("builtincommand.zig").BuiltInCommand;

fn exitHandler(shell: *const Shell, input: *InputCommand) ?[]const u8 {
    _ = shell; // autofix
    const firstArgument = input.nextArg() orelse "0";

    const code = std.fmt.parseInt(u8, firstArgument, 10) catch 0;

    std.process.exit(code);

    return null;
}

fn echoHandler(shell: *const Shell, input: *InputCommand) ?[]const u8 {
    if (input.args.?.items.len == 0) {
        return null;
    }

    var echoed: ?[]u8 = null;
    while (input.nextArg()) |value| {
        if (std.mem.eql(u8, value, ">")) {
            input.rewindOneArg();
            break;
        }
        const toConcat = echoed orelse "";
        echoed = std.fmt.allocPrint(shell.allocator, "{s}{s} ", .{ toConcat, value }) catch "";
    }

    return echoed;
}

fn typeHandler(shell: *const Shell, input: *InputCommand) ?[]const u8 {
    const commandName = input.nextArg() orelse "";

    if (std.mem.eql(u8, commandName, "")) {
        return null;
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

    if (isExecutable) {
        out = std.fmt.allocPrint(shell.allocator, "{s} is {s}", .{ commandName, executablePath }) catch "";
    } else if (found) {
        out = std.fmt.allocPrint(shell.allocator, "{s} is a shell builtin", .{commandName}) catch "";
    } else {
        out = std.fmt.allocPrint(shell.allocator, "{s}: not found", .{commandName}) catch "";
    }

    return out;
}

fn pwdHandler(shell: *const Shell, input: *InputCommand) ?[]const u8 {
    _ = input; // autofix

    const cwd = std.fs.cwd().realpathAlloc(shell.allocator, ".") catch "";

    return cwd;
}

fn cdHandler(shell: *const Shell, input: *InputCommand) ?[]const u8 {
    var directory = input.nextArg() orelse "";

    if (std.mem.eql(u8, directory, "~")) {
        directory = shell.getHomeDirectory() catch "";
    }

    const dirObject = std.fs.cwd().openDir(directory, .{});

    if (dirObject) |dir| {
        dir.setAsCwd() catch {};
    } else |err| {
        return switch (err) {
            std.fs.Dir.OpenError.FileNotFound => std.fmt.allocPrint(shell.allocator, "cd: {s}: No such file or directory", .{directory}) catch null,
            std.fs.Dir.OpenError.NotDir => std.fmt.allocPrint(shell.allocator, "cd: {s}: Not a directory", .{directory}) catch null,
            else => std.fmt.allocPrint(shell.allocator, "cd: {s}: {s}", .{
                directory,
                "an error occurred",
            }) catch null,
        };
    }

    return null;
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
        var cmd = InputCommand.parse(allocator, command) catch InputCommand{ .name = "error", .args = undefined };

        try shell.run(&cmd);
    }
}
