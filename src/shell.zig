const std = @import("std");
const BuiltInCommand = @import("builtincommand.zig").BuiltInCommand;
const Input = @import("input.zig");
const InputCommand = Input.InputCommand;

pub const Shell = struct {
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

    pub fn getHomeDirectory(self: *const Shell) ![]const u8 {
        const env_vars = try std.process.getEnvMap(self.allocator);
        const home_value = env_vars.get("HOME") orelse "";
        return home_value;
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

    fn handleStdout(self: *const Shell, result: ?[]const u8, command: *InputCommand) !void {
        _ = self; // autofix
        const stdout = std.io.getStdOut().writer();
        if (result) |value| {
            if (command.nextArg()) |arg| {
                if (Input.isStdoutRedirection(arg)) {
                    const file = command.nextArg() orelse "";
                    const truncate = std.mem.eql(u8, arg, ">") or std.mem.eql(u8, arg, "1>");
                    const fileWriter = try std.fs.cwd().createFile(file, .{ .truncate = truncate });
                    if (!truncate) {
                        const stat = try fileWriter.stat();
                        try fileWriter.seekTo(stat.size);
                    }
                    const writer = fileWriter.writer();
                    try writer.print("{s}", .{value});
                } else {
                    command.rewindOneArg();
                    stdout.print("{s}", .{value}) catch {};
                }
            } else {
                stdout.print("{s}", .{value}) catch {};
            }
        }
    }

    fn handleStderr(self: *const Shell, result: ?[]const u8, command: *InputCommand) !void {
        _ = self; // autofix
        const stdout = std.io.getStdOut().writer();

        if (command.nextArg()) |arg| {
            if (Input.isStderrRedirection(arg)) {
                const file = command.nextArg() orelse "";
                const truncate = std.mem.eql(u8, arg, "2>");
                const fileWriter = try std.fs.cwd().createFile(file, .{ .truncate = truncate });
                if (!truncate) {
                    const stat = try fileWriter.stat();
                    try fileWriter.seekTo(stat.size);
                }

                if (result) |value| {
                    const writer = fileWriter.writer();
                    try writer.print("{s}", .{value});
                    return;
                }
            } else {
                command.rewindOneArg();
            }
        }

        if (result) |value| {
            stdout.print("{s}", .{value}) catch {};
        }
    }

    pub fn run(self: *const Shell, command: *InputCommand) !void {
        const stdout = std.io.getStdOut().writer();

        var found = false;
        for (self.commands) |cmd| {
            if (std.mem.eql(u8, command.name, cmd.name)) {
                found = true;
                const result = try cmd.execute(self, command);

                const b_stderr = if (result.isError) result.value else @as(?[]const u8, "");
                const b_stdout = if (!result.isError) result.value else @as(?[]const u8, "");

                try self.handleStderr(b_stderr, command);
                try self.handleStdout(b_stdout, command);

                break;
            }
        }

        if (!found) {
            const isExecutableCommand, const executablePath = self.isExecutable(command.name) catch .{ false, undefined };
            _ = executablePath; // autofix

            if (isExecutableCommand) {
                found = true;

                const argsLen: usize = if (command.hasRedirection) command.args.?.items.len - 2 + 1 else command.args.?.items.len + 1;

                var execArgs: [][]const u8 = try self.allocator.alloc([]const u8, argsLen);

                defer self.allocator.free(execArgs);

                execArgs[0] = command.name;

                var i: usize = 1;
                while (command.nextArg()) |arg| {
                    if (Input.isRedirection(arg)) {
                        command.rewindOneArg();
                        break;
                    }
                    execArgs[i] = arg;
                    i += 1;
                }

                const child = try std.process.Child.run(.{ .argv = execArgs, .allocator = self.allocator });

                try self.handleStdout(child.stdout, command);
                try self.handleStderr(child.stderr, command);
            }
        }

        if (!found) {
            // print the error message
            try stdout.print("{s}: command not found \n", .{command.name});
        }
    }
};
