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
        shell.buffer.reset();
        shell.cursorPosition = 0;

        while (true) {
            const c = try stdin.readByte();

            if (c == 8 or c == 127) { // BACKSPACE
                if (shell.cursorPosition > 0) {
                    shell.buffer.removeChar(shell.cursorPosition - 1);
                    shell.cursorPosition -= 1;

                    try shell.render();
                }

                continue;
            }
            if (c == '\x1B') {
                var esc_buffer: [8]u8 = undefined;
                const esc_read = try stdin.read(&esc_buffer);

                if (std.mem.eql(u8, esc_buffer[0..esc_read], "[D")) {
                    if (shell.cursorPosition > 0) {
                        shell.cursorPosition -= 1;
                    }
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[C")) {
                    if (shell.cursorPosition < shell.buffer.len) {
                        shell.cursorPosition += 1;
                    }
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[3~")) { // DEL
                    if (shell.cursorPosition < shell.buffer.len) {
                        shell.buffer.removeChar(shell.cursorPosition);

                        try shell.render();
                    }
                } else {
                    std.debug.print("input: unknown escape sequence: {s}\r\n", .{esc_buffer[0..esc_read]});
                }

                try shell.renderCursor();

                continue;
            }

            if (c == '\t') {
                if (shell.buffer.len > 0) {
                    const options = shell.handleTab(shell.buffer.getSlice()) catch std.ArrayList([]const u8).init(allocator);

                    if (options.items.len == 1) {
                        const remainingCommand = options.items[0][shell.buffer.len..options.items[0].len];
                        shell.buffer.appendSlice(remainingCommand);
                        shell.buffer.append(' ');
                        shell.cursorPosition = shell.buffer.len;
                        try stdout.print("{s} ", .{remainingCommand});
                    } else if (options.items.len > 1) {
                        const first = options.items[0];
                        var commonLen = first.len;

                        for (options.items[0..]) |option| {
                            var i: usize = 0;
                            while (i < commonLen and i < option.len) : (i += 1) {
                                if (first[i] != option[i]) {
                                    commonLen = i;
                                    break;
                                }
                            }
                            commonLen = @min(commonLen, option.len);
                        }

                        if (commonLen > shell.buffer.len) {
                            const completion = first[shell.buffer.len..commonLen];
                            shell.buffer.appendSlice(completion);
                            shell.cursorPosition = shell.buffer.len;
                            try stdout.print("{s}", .{completion});
                        } else {
                            try stdout.writeAll("\x07");
                            try stdout.print("\n", .{});

                            for (options.items) |option| {
                                try stdout.print("{s}  ", .{option});
                            }
                            try stdout.print("\n$ {s}", .{shell.buffer.getSlice()});
                        }
                    } else {
                        try stdout.writeAll("\x07");
                    }
                }
                continue;
            }

            if (c == '\n') {
                try stdout.print("\n", .{});
                break;
            }

            shell.buffer.putChar(c, shell.cursorPosition);
            shell.cursorPosition += 1;

            try shell.render();
        }
        const command = shell.buffer.getSlice();
        var cmd = InputCommand.parse(allocator, command) catch InputCommand{ .name = "error", .args = undefined };

        try shell.run(&cmd);
    }

    try Input.setRawInput(false);

    std.process.exit(shell.getExitCode());
}
