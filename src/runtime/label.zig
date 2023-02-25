const instr = @import("../instr.zig");
const util = @import("../util.zig");

pub const Label = struct {
    pub fn init() !Label {
        return .{};
    }
};

pub const LabelStack = util.Stack(Label);
