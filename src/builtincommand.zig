const Shell = @import("shell.zig").Shell;
const InputCommand = @import("input.zig").InputCommand;

pub const Result = struct {
    value: ?[]const u8,
    isError: bool,
};

pub const BuiltInCommand = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn (shell: *Shell, input: *InputCommand) Result,

    pub fn execute(self: BuiltInCommand, shell: *Shell, input: *InputCommand) !Result {
        return self.handler(shell, input);
    }
};
