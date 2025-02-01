const Shell = @import("shell.zig").Shell;
const InputCommand = @import("input.zig").InputCommand;

pub const BuiltInCommand = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn (shell: *const Shell, input: *InputCommand) ?[]const u8,

    pub fn execute(self: BuiltInCommand, shell: *const Shell, input: *InputCommand) !?[]const u8 {
        return self.handler(shell, input);
    }
};
