const std = @import("std");

pub const ModuleInstance = @import("./instance/instance.zig").ModuleInstance;
pub const FunctionInstance = @import("./instance/instance.zig").FunctionInstance;
pub const StartInstance = @import("./instance/instance.zig").StartInstance;
pub const ExportInstance = @import("./instance/instance.zig").ExportInstance;
pub const ExportValue = @import("./instance/instance.zig").ExportValue;

test {
    std.testing.refAllDecls(@This());
}
