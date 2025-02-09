const std = @import("std");
const BuiltInCommand = @import("builtincommand.zig").BuiltInCommand;
const Input = @import("input.zig");
const InputCommand = Input.InputCommand;
const set = @import("ziglangSet");
const Buffer = @import("buffer.zig");

fn lessThan(_: @TypeOf(.{}), lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub const Shell = struct {
    commands: []const BuiltInCommand,
    allocator: std.mem.Allocator,
    running: bool = true,
    exitCode: u8 = 0,
    cursorPosition: usize = 0,
    buffer: Buffer,
    stdout: std.fs.File.Writer,
    stdin: std.fs.File.Reader,

    pub fn init(allocator: std.mem.Allocator, commands: []const BuiltInCommand) Shell {
        return Shell{
            .allocator = allocator,
            .commands = commands,
            .running = true,
            .cursorPosition = 0,
            .buffer = Buffer.init(),
            .stdout = std.io.getStdOut().writer(),
            .stdin = std.io.getStdIn().reader(),
        };
    }

    pub fn render(self: *Shell) !void {
        try self.stdout.print("\r\x1B[K", .{});
        try self.stdout.print("$ {s}", .{self.buffer.getSlice()});
        try self.renderCursor();
    }

    pub fn renderCursor(self: *const Shell) !void {
        try self.stdout.print("\r\x1B[{d}G", .{self.cursorPosition + 3});
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

    pub fn exit(self: *Shell, code: u8) !void {
        self.exitCode = code;
        self.running = false;
    }

    pub fn getExitCode(self: *const Shell) u8 {
        return self.exitCode;
    }

    pub fn isRunning(self: *const Shell) bool {
        return self.running;
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
                    self.stdout.print("{s}", .{value}) catch {};
                }
            } else {
                self.stdout.print("{s}", .{value}) catch {};
            }
        }
    }

    fn handleStderr(self: *const Shell, result: ?[]const u8, command: *InputCommand) !void {
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
            self.stdout.print("{s}", .{value}) catch {};
        }
    }

    pub fn handleTab(self: *Shell, command: []const u8) !std.ArrayList([]const u8) {
        var options = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
        var hashMap = std.StringHashMap(bool).init(self.allocator);

        // TODO(nicholasio): use only hashmap
        // TODO(nicholasio): improve performance
        for (self.commands) |cmd| {
            if (std.mem.startsWith(u8, cmd.name, command)) {
                try options.append(cmd.name);
                return options;
            }
        }

        const path = try self.getPath();
        var iter = std.mem.splitScalar(u8, path, ':');
        while (iter.next()) |path_segment| {
            const _dir = std.fs.cwd().openDir(path_segment, .{ .iterate = true });

            if (_dir) |dir| {
                var dirIter: ?std.fs.Dir.Walker = dir.walk(self.allocator) catch null;

                while (dirIter.?.next() catch null) |entry| {
                    const e = try self.allocator.dupe(u8, entry.basename);
                    if (std.mem.startsWith(u8, e, command) and !hashMap.contains(e)) {
                        try hashMap.put(e, true);
                        try options.append(e);
                    }
                }
            } else |_| {
                continue;
            }
        }

        std.mem.sort([]const u8, options.items, .{}, lessThan);

        return options;
    }

    pub fn prepare(self: *Shell) !void {
        try self.stdout.print("$ ", .{});
        self.buffer.reset();
        self.cursorPosition = 0;
    }

    pub fn readInput(self: *Shell) !InputCommand {
        while (true) {
            const c = try self.stdin.readByte();

            if (c == 8 or c == 127) { // BACKSPACE
                if (self.cursorPosition > 0) {
                    self.buffer.removeChar(self.cursorPosition - 1);
                    self.cursorPosition -= 1;

                    try self.render();
                }

                continue;
            }
            if (c == '\x1B') {
                var esc_buffer: [8]u8 = undefined;
                const esc_read = try self.stdin.read(&esc_buffer);

                if (std.mem.eql(u8, esc_buffer[0..esc_read], "[D")) {
                    if (self.cursorPosition > 0) {
                        self.cursorPosition -= 1;
                    }
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[C")) {
                    if (self.cursorPosition < self.buffer.len) {
                        self.cursorPosition += 1;
                    }
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[3~")) { // DEL
                    if (self.cursorPosition < self.buffer.len) {
                        self.buffer.removeChar(self.cursorPosition);

                        try self.render();
                    }
                } else {
                    std.debug.print("input: unknown escape sequence: {s}\r\n", .{esc_buffer[0..esc_read]});
                }

                try self.renderCursor();

                continue;
            }

            if (c == '\t') {
                if (self.buffer.len > 0) {
                    const options = self.handleTab(self.buffer.getSlice()) catch std.ArrayList([]const u8).init(self.allocator);

                    if (options.items.len == 1) {
                        const remainingCommand = options.items[0][self.buffer.len..options.items[0].len];
                        self.buffer.appendSlice(remainingCommand);
                        self.buffer.append(' ');
                        self.cursorPosition = self.buffer.len;
                        try self.stdout.print("{s} ", .{remainingCommand});
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

                        if (commonLen > self.buffer.len) {
                            const completion = first[self.buffer.len..commonLen];
                            self.buffer.appendSlice(completion);
                            self.cursorPosition = self.buffer.len;
                            try self.stdout.print("{s}", .{completion});
                        } else {
                            try self.stdout.writeAll("\x07");
                            try self.stdout.print("\n", .{});

                            for (options.items) |option| {
                                try self.stdout.print("{s}  ", .{option});
                            }
                            try self.stdout.print("\n$ {s}", .{self.buffer.getSlice()});
                        }
                    } else {
                        try self.stdout.writeAll("\x07");
                    }
                }
                continue;
            }

            if (c == '\n') {
                try self.stdout.print("\n", .{});
                break;
            }

            self.buffer.putChar(c, self.cursorPosition);
            self.cursorPosition += 1;

            try self.render();
        }

        return InputCommand.parse(self.allocator, self.buffer.getSlice()) catch InputCommand{ .name = "error", .args = undefined };
    }

    pub fn run(self: *Shell, command: *InputCommand) !void {
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
            try self.stdout.print("{s}: command not found \n", .{command.name});
        }
    }
};
