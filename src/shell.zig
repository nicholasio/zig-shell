const std = @import("std");
const BuiltInCommand = @import("builtincommand.zig").BuiltInCommand;
const InputCommand = @import("input.zig").InputCommand;

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

    // method to run the command
    pub fn run(self: *const Shell, command: *InputCommand) !void {
        const stdout = std.io.getStdOut().writer();
        // check if the command exists
        var found = false;
        for (self.commands) |cmd| {
            if (std.mem.eql(u8, command.name, cmd.name)) {
                found = true;
                const result = try cmd.execute(self, command);

                if (result) |value| {
                    if (command.nextArg()) |arg| {
                        if (std.mem.eql(u8, arg, "1>") or std.mem.eql(u8, arg, ">")) {
                            const file = command.nextArg() orelse "";
                            const fileWriter = try std.fs.cwd().createFile(file, .{ .truncate = true });
                            const writer = fileWriter.writer();
                            try writer.print("{s}\n", .{value});
                        } else if (std.mem.eql(u8, arg, "2>") or std.mem.eql(u8, arg, "2>>")) {
                            const file = command.nextArg() orelse "";
                            const fileWriter = try std.fs.cwd().openFile(file, .{ .mode = std.fs.File.OpenMode.read_write });

                            const writer = fileWriter.writer();
                            try writer.print("{s}\n", .{value});
                        } else if (std.mem.eql(u8, arg, ">>")) {
                            const file = command.nextArg() orelse "";
                            const fileWriter = try std.fs.cwd().openFile(file, .{ .mode = std.fs.File.OpenMode.read_write });

                            const writer = fileWriter.writer();
                            try writer.print("{s}\n", .{value});
                        } else {
                            stdout.print("{s}\n", .{value}) catch {};
                        }
                    } else {
                        stdout.print("{s}\n", .{value}) catch {};
                    }
                }
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
