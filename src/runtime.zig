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
        };
    }

    pub fn deinit(self: *VM) void {
        self.value_stack.deinit();
        self.frame_stack.deinit();
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
        var frame = try self.initFunction(function);

        loop: while (frame.code_reader.next()) |instruction| {
            //std.debug.print("OP: {s}\n", .{@tagName(instruction)});

            switch (instruction) {
                .block => |b| {
                    const result_types = try self.enterBlock(&frame, b.block_type);

                    const label = try Label.init(instruction, result_types);
                    try frame.pushLabel(label);
                },
                .loop => |b| {
                    const result_types = try self.enterBlock(&frame, b.block_type);

                    const label = try Label.init(instruction, result_types);
                    try frame.pushLabel(label);
                },
                .@"if" => |b| {
                    const c = try self.value_stack.pop();
                    if (c != .i32) {
                        return error.InvalidValueStack;
                    }

                    const result_types = try self.enterBlock(&frame, b.block_type);

                    const label = try Label.init(instruction, result_types);
                    try frame.pushLabel(label);

                    if (c.i32 == 0) {
                        // false
                        if (b.else_pointer > 0) {
                            try frame.code_reader.setPointer(b.else_pointer);
                        } else {
                            try frame.code_reader.setPointer(b.branch_target);
                        }
                    } else {
                        // true
                    }
                },
                .@"else" => {
                    const label = try frame.popLabel();

                    try frame.code_reader.setPointer(label.branch_target);
                },
                .end => {
                    if (frame.tryPopLabel()) |label| {
                        try self.exitBlock(label);
                    } else {
                        frame = try self.finalizeFunction() orelse break :loop;
                    }
                },
                .br => |idx| try self.executeBr(&frame, idx),
                .br_if => |idx| {
                    const c = try self.value_stack.pop();
                    if (c != .i32) {
                        return error.InvalidValueStack;
                    }

                    if (c.i32 == 0) {
                        // false
                    } else {
                        // true
                        try self.executeBr(&frame, idx);
                    }
                },
                .@"return" => {
                    frame = try self.finalizeFunction() orelse break :loop;
                },
                .call => |idx| {
                    const func = try frame.module.getFunction(idx);
                    frame = try self.initFunction(func);
                },
                .drop => _ = try self.value_stack.pop(),
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
                        .i32 = @intFromBool(c.i32 == 0),
                    });
                },
                .@"i32.eq" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @intFromBool(c1.i32 == c2.i32),
                    });
                },
                .@"i32.ne" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @intFromBool(c1.i32 != c2.i32),
                    });
                },
                .@"i32.lt_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @intFromBool(c1.i32 < c2.i32),
                    });
                },
                .@"i32.gt_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @intFromBool(c1.i32 > c2.i32),
                    });
                },
                .@"i32.le_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @intFromBool(c1.i32 <= c2.i32),
                    });
                },
                .@"i32.ge_s" => {
                    const c2 = try self.value_stack.pop();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try self.value_stack.pop();
                    if (c1 != .i32) return error.InvalidStack;

                    try self.value_stack.push(.{
                        .i32 = @intFromBool(c1.i32 >= c2.i32),
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

    fn initFunction(self: *VM, function: *FunctionInstance) !Frame {
        const paramLen = function.parameter_types.len;
        var params: []Value = try self.allocator.alloc(Value, paramLen);
        for (function.parameter_types, 0..) |typ, i| {
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

        // frame
        const frame = try Frame.init(self.allocator, params, self.module, function);
        try self.frame_stack.push(frame);

        return frame;
    }

    fn finalizeFunction(self: *VM) !?Frame {
        const frame = try self.frame_stack.peek();

        var result = try self.popResult(frame);
        defer result.deinit();

        _ = try self.frame_stack.pop();

        for (result.values) |value| {
            try self.value_stack.push(value);
        }

        return self.frame_stack.tryPeek();
    }

    fn enterBlock(self: *VM, frame: *Frame, block_type: mod.BlockType) !?[]const mod.ValueType {
        return switch (block_type) {
            .empty => null,
            .value_type => |v| {
                return &[_]mod.ValueType{v};
            },
            .type_index => |idx| {
                const typ = try frame.module.getType(@as(u32, @intCast(idx)));
                const arity = typ.parameter_types.len;
                for (typ.parameter_types, 0..) |value_type, i| {
                    const v = try self.value_stack.peekDepth(arity - i - 1);
                    const valid = switch (value_type) {
                        .i32 => v == .i32,
                        .i64 => v == .i64,
                        .f32 => v == .f32,
                        .f64 => v == .f64,
                        else => return error.UnexpectedValueType,
                    };
                    if (!valid) {
                        return error.InvalidValueStack;
                    }
                }
                return typ.result_types;
            },
        };
    }

    fn exitBlock(self: *VM, label: Label) !void {
        if (label.result_types) |result_types| {
            const arity = result_types.len;
            for (result_types, 0..) |value_type, i| {
                const v = try self.value_stack.peekDepth(arity - i - 1);
                const valid = switch (value_type) {
                    .i32 => v == .i32,
                    .i64 => v == .i64,
                    .f32 => v == .f32,
                    .f64 => v == .f64,
                    else => return error.UnexpectedValueType,
                };
                if (!valid) {
                    return error.InvalidValueStack;
                }
            }
        }
    }

    fn executeBr(self: *VM, frame: *Frame, idx: u32) !void {
        const label = frame.tryPeekLabelDepth(idx) orelse return error.InvalidLabelIndex;
        try self.exitBlock(label);
        var i: usize = 0;
        while (i < idx + 1) : (i += 1) {
            _ = try frame.popLabel();
        }

        try frame.code_reader.setPointer(label.branch_target);
    }

    fn popResult(self: *VM, frame: Frame) !Result {
        const function = frame.function;
        const types = function.result_types;

        var result = try Result.init(self.allocator, types.len);

        for (types, result.values) |typ, *value| {
            const v = try self.value_stack.pop();
            switch (typ) {
                .i32 => {
                    if (v != .i32) {
                        return error.InvalidStack;
                    }
                    value.* = v;
                },
                .i64 => {
                    if (v != .i64) {
                        return error.InvalidStack;
                    }
                    value.* = v;
                },
                .f32 => {
                    if (v != .f32) {
                        return error.InvalidStack;
                    }
                    value.* = v;
                },
                .f64 => {
                    if (v != .f64) {
                        return error.InvalidStack;
                    }
                    value.* = v;
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
