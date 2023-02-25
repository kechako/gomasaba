const std = @import("std");

pub const Opecode = @import("./instr/instr.zig").Opecode;
pub const Instruction = @import("./instr/instr.zig").Instruction;

pub const Code = @import("./instr/code.zig").Code;
pub const CodeParser = @import("./instr/code.zig").CodeParser;
pub const codeParser = @import("./instr/code.zig").codeParser;
pub const CodeReader = @import("./instr/code.zig").CodeReader;

test {
    std.testing.refAllDecls(@This());
}
