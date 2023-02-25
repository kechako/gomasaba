const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

const mod = @import("./mod.zig");
const instr = @import("./instr.zig");
const instance = @import("./instance.zig");

pub const Value = @import("runtime/value.zig").Value;
pub const ValueStack = @import("runtime/value.zig").ValueStack;

pub const Frame = @import("runtime/frame.zig").Frame;
pub const FrameStack = @import("runtime/frame.zig").FrameStack;

pub const Label = @import("runtime/label.zig").Label;
pub const LabelStack = @import("runtime/label.zig").LabelStack;

const ModuleInstance = instance.ModuleInstance;
const FunctionInstance = instance.FunctionInstance;

pub const VM = struct {
    allocator: std.mem.Allocator,
    module: *ModuleInstance,

    value_stack: ValueStack,
    frame_stack: FrameStack,
    label_stack: LabelStack,

    pub const Result = struct {
        allocator: Allocator,
        values: []Value,

        fn init(allocator: Allocator, n: usize) !Result {
            const values = try allocator.alloc(Value, n);
            return .{
                .allocator = allocator,
                .values = values,
            };
        }

        pub fn deinit(self: *Result) void {
            self.allocator.free(self.values);
        }
    };

    pub fn init(allocator: Allocator, module: *ModuleInstance) !VM {
        return .{
            .allocator = allocator,
            .module = module,
            .value_stack = ValueStack.init(allocator),
            .frame_stack = FrameStack.init(allocator),
            .label_stack = LabelStack.init(allocator),
        };
    }

    pub fn deinit(self: *VM) void {
        self.value_stack.deinit();
        self.frame_stack.deinit();
        self.label_stack.deinit();
    }

    pub fn start(self: *VM) !Result {
        const function = try self.module.getStartFunction();
        return try self.invoke(function);
    }

    pub fn call(self: *VM, name: []const u8) !Result {
        const function = try self.module.findFunction(name);
        return try self.invoke(function);
    }

    fn invoke(self: *VM, function: *FunctionInstance) !Result {
        try self.initFunction(function);

        var label = try self.label_stack.peek();
        var frame = try self.frame_stack.peek();

        loop: while (frame.code_reader.next()) |instruction| {
            //std.debug.print("OP: {s}\n", .{@tagName(instruction)});

            switch (instruction) {
                .@"end" => {
                    try self.finalizeFunction();
                    label = self.label_stack.peek() catch |err| {
                        if (err == error.StackUnderflow) {
                            break :loop;
                        }
                        return err;
                    };
                    frame = try self.frame_stack.peek();
                },
                .@"return" => {
                    try self.finalizeFunction();
                    label = self.label_stack.peek() catch |err| {
                        if (err == error.StackUnderflow) {
                            break :loop;
                        }
                        return err;
                    };
                    frame = try self.frame_stack.peek();
                },
                .@"call" => |idx| {
                    const func = try frame.module.getFunction(idx);
                    try self.initFunction(func);
                    label = try self.label_stack.peek();
                    frame = try self.frame_stack.peek();
                },
                .@"drop" => _ = try self.value_stack.pop(),
                .@"local.get" => |idx| {
                    const value = try frame.getLocal(idx);
                    try self.value_stack.push(value);
                },
                .@"local.set" => |idx| try self.push(frame, idx),
                .@"local.tee" => |idx| {
                    const value = try self.value_stack.pop();
                    try self.value_stack.push(value);
                    try self.value_stack.push(value);

                    try self.push(frame, idx);
                },
                .@"i32.const" => |v| try self.value_stack.push(.{ .i32 = v }),
                .@"i32.eqz" => {
                    const c = try self.value_stack.pop();
                    if (c != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c.i32 == 0),
                    });
                },
                .@"i32.eq" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c1.i32 == c2.i32),
                    });
                },
                .@"i32.ne" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c1.i32 != c2.i32),
                    });
                },
                .@"i32.lt_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c1.i32 < c2.i32),
                    });
                },
                .@"i32.gt_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c1.i32 > c2.i32),
                    });
                },
                .@"i32.le_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c1.i32 <= c2.i32),
                    });
                },
                .@"i32.ge_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @boolToInt(c1.i32 >= c2.i32),
                    });
                },
                .@"i32.add" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = c1.i32 + c2.i32,
                    });
                },
                .@"i32.sub" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = c1.i32 - c2.i32,
                    });
                },
                .@"i32.mul" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = c1.i32 * c2.i32,
                    });
                },
                .@"i32.div_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    if (c2.i32 == 0) return error.IntegerDivideByZero;

                    try self.value_stack.push(.{
                        .i32 = @divTrunc(c1.i32, c2.i32),
                    });
                },
                else => {
                    _ = try std.io.getStdErr().write(@tagName(instruction));
                    return error.UnsupportedInstruction;
                },
            }
        }

        return try self.popResult(frame);
    }

    fn initFunction(self: *VM, function: *FunctionInstance) !void {
        const paramLen = function.parameter_types.len;
        var params: []Value = try self.allocator.alloc(Value, paramLen);
        for (function.parameter_types) |typ, i| {
            const value = try self.value_stack.pop();
            switch (typ) {
                .i32 => if (value != .i32) return error.InvalidStack,
                .i64 => if (value != .i64) return error.InvalidStack,
                .f32 => if (value != .f32) return error.InvalidStack,
                .f64 => if (value != .f64) return error.InvalidStack,
                else => return error.UnsupportedType,
            }
            params[paramLen - i - 1] = value;
        }

        // label
        const label = try Label.init();
        try self.label_stack.push(label);

        // frame
        const frame = try Frame.init(self.allocator, params, self.module, function);
        try self.frame_stack.push(frame);
    }

    fn finalizeFunction(self: *VM) !void {
        const frame = try self.frame_stack.peek();

        var result = try self.popResult(frame);
        defer result.deinit();

        _ = try self.frame_stack.pop();
        _ = try self.label_stack.pop();

        for (result.values) |value| {
            try self.value_stack.push(value);
        }
    }

    fn popResult(self: *VM, frame: Frame) !Result {
        const function = frame.function;
        const types = function.result_types;

        var result = try Result.init(self.allocator, types.len);

        for (types) |typ, i| {
            const value = try self.value_stack.pop();
            switch (typ) {
                .i32 => {
                    if (value != .i32) {
                        return error.InvalidStack;
                    }
                    result.values[i] = value;
                },
                .i64 => {
                    if (value != .i64) {
                        return error.InvalidStack;
                    }
                    result.values[i] = value;
                },
                .f32 => {
                    if (value != .f32) {
                        return error.InvalidStack;
                    }
                    result.values[i] = value;
                },
                .f64 => {
                    if (value != .f64) {
                        return error.InvalidStack;
                    }
                    result.values[i] = value;
                },
                else => return error.UnsupportedValueType,
            }
        }

        return result;
    }

    fn push(self: *VM, frame: Frame, idx: u32) !void {
        const value = try self.value_stack.pop();
        try frame.setLocal(idx, value);
    }
};

test {
    std.testing.refAllDecls(@This());
}
