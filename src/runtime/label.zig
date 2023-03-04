const mod = @import("../mod.zig");
const instr = @import("../instr.zig");
const util = @import("../util.zig");

pub const Label = struct {
    branch_target: u32,
    result_types: []const mod.ValueType,

    pub fn init(inst: instr.Instruction, result_types: []const mod.ValueType) !Label {
        return switch (inst) {
            .@"if" => |b| .{
                .branch_target = b.branch_target,
                .result_types = result_types,
            },
            else => return error.UnexpectedInstruction,
        };
    }
};

pub const LabelStack = util.Stack(Label);
