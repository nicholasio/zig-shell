const Shell = @import("shell.zig").Shell;
const InputCommand = @import("input.zig").InputCommand;

pub const BuiltInCommand = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn (shell: *const Shell, input: *const InputCommand) void,

    pub fn execute(self: BuiltInCommand, shell: *const Shell, input: *const InputCommand) !void {
        self.handler(shell, input);
    }
};
