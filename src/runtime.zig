const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const mod = @import("./mod.zig");
const expr = mod.expr;
const instr = mod.instr;

const Context = @import("runtime/context.zig").Context;
const ModuleInstance = @import("runtime/instance.zig").ModuleInstance;
const FunctionInstance = @import("runtime/instance.zig").FunctionInstance;

pub const VM = struct {
    allocator: std.mem.Allocator,
    instance: ModuleInstance,

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

    pub fn init(allocator: Allocator, module: mod.Module) !VM {
        const instance = try ModuleInstance.init(allocator, module);
        return .{ .allocator = allocator, .instance = instance };
    }

    pub fn deinit(self: *VM) void {
        self.instance.deinit();
    }

    pub fn start(self: *VM) !Result {
        if (self.instance.start) |st| {
            var instance = try self.instance.getFunctionInstance(st.function_index);

            return try self.invoke(instance);
        }

        return error.StartSectionNotFound;
    }

    pub fn call(self: *VM, name: []const u8) !Result {
        const instance = try self.instance.findFunctionInstance(name);

        return try self.invoke(instance);
    }

    fn invoke(self: *VM, instance: FunctionInstance) !Result {
        var ctx = Context.init(self.allocator);
        defer ctx.deinit();

        try self.initFunction(&ctx, instance);

        var stack = &ctx.stack;
        var label = try stack.currentLabel();
        var frame = try stack.currentFrame();
        var instructions = label.instructions;

        loop: while (try instructions.next()) |instruction| {
            //std.debug.print("OP: {s}\n", .{@tagName(instruction)});

            switch (instruction) {
                .@"end" => {
                    try self.finalizeFunction(&ctx);
                    label = stack.currentLabel() catch |err| {
                        if (err == error.LabelNotFound) {
                            break :loop;
                        }
                        return err;
                    };
                    frame = try stack.currentFrame();
                    instructions = label.instructions;
                },
                .@"return" => {
                    try self.finalizeFunction(&ctx);
                    label = stack.currentLabel() catch |err| {
                        if (err == error.LabelNotFound) {
                            break :loop;
                        }
                        return err;
                    };
                    frame = try stack.currentFrame();
                    instructions = label.instructions;
                },
                .@"call" => |idx| {
                    const funcInstance = try frame.instance.getFunctionInstance(idx);
                    try self.initFunction(&ctx, funcInstance);
                    label = try stack.currentLabel();
                    frame = try stack.currentFrame();
                    instructions = label.instructions;
                },
                .@"drop" => _ = try ctx.stack.popValue(),
                .@"local.get" => |idx| {
                    const value = try frame.getLocal(idx);
                    try stack.pushValue(value);
                },
                .@"local.set" => |idx| try self.push(&ctx, frame, idx),
                .@"local.tee" => |idx| {
                    const value = try stack.popValue();
                    try stack.pushValue(value);
                    try stack.pushValue(value);

                    try self.push(&ctx, frame, idx);
                },
                .@"i32.const" => |v| try ctx.stack.pushValue(.{ .i32 = v }),
                .@"i32.eqz" => {
                    const c = try stack.popValue();
                    if (c != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c.i32 == 0),
                    });
                },
                .@"i32.eq" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c1.i32 == c2.i32),
                    });
                },
                .@"i32.ne" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c1.i32 != c2.i32),
                    });
                },
                .@"i32.lt_s" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c1.i32 < c2.i32),
                    });
                },
                .@"i32.gt_s" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c1.i32 > c2.i32),
                    });
                },
                .@"i32.le_s" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c1.i32 <= c2.i32),
                    });
                },
                .@"i32.ge_s" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = @boolToInt(c1.i32 >= c2.i32),
                    });
                },
                .@"i32.add" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = c1.i32 + c2.i32,
                    });
                },
                .@"i32.sub" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = c1.i32 - c2.i32,
                    });
                },
                .@"i32.mul" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    try ctx.stack.pushValue(.{
                        .i32 = c1.i32 * c2.i32,
                    });
                },
                .@"i32.div_s" => {
                    const c2 = try stack.popValue();
                    if (c2 != .i32) return error.InvalidStack;
                    const c1 = try stack.popValue();
                    if (c1 != .i32) return error.InvalidStack;

                    if (c2.i32 == 0) return error.IntegerDivideByZero;

                    try ctx.stack.pushValue(.{
                        .i32 = @divTrunc(c1.i32, c2.i32),
                    });
                },
                else => {
                    _ = try std.io.getStdErr().write(@tagName(instruction));
                    return error.UnsupportedInstruction;
                },
            }
        }

        return try self.popResult(stack, frame);
    }

    fn initFunction(self: *VM, ctx: *Context, instance: FunctionInstance) !void {
        var stack = &ctx.stack;

        const paramLen = instance.function_type.parameter_types.len;
        var params: []Value = try self.allocator.alloc(Value, paramLen);
        for (instance.function_type.parameter_types) |typ, i| {
            const value = try stack.popValue();
            switch (typ) {
                .i32 => {
                    if (value != .i32) {
                        return error.InvalidStack;
                    }
                    params[paramLen - i - 1] = value;
                },
                .i64 => {
                    if (value != .i64) {
                        return error.InvalidStack;
                    }
                    params[paramLen - i - 1] = value;
                },
                .f32 => {
                    if (value != .f32) {
                        return error.InvalidStack;
                    }
                    params[paramLen - i - 1] = value;
                },
                .f64 => {
                    if (value != .f64) {
                        return error.InvalidStack;
                    }
                    params[paramLen - i - 1] = value;
                },
                else => return error.UnsupportedType,
            }
        }

        // label
        const label = try Label.init(instance.code.instructions);
        try stack.pushLabel(label);

        // frame
        const frame = try Frame.init(self.allocator, params, instance.code.locals, self.instance, instance);
        try stack.pushFrame(frame);
    }

    fn finalizeFunction(self: *VM, ctx: *Context) !void {
        var stack = &ctx.stack;
        const frame = try stack.currentFrame();

        var result = try self.popResult(stack, frame);
        defer result.deinit();

        _ = try stack.popFrame();
        _ = try stack.popLabel();

        for (result.values) |value| {
            try stack.pushValue(value);
        }
    }

    fn popResult(self: VM, stack: *Stack, frame: Frame) !Result {
        const instance = frame.functionInstance orelse return error.InvalidStack;
        const types = instance.function_type.result_types;

        var result = try Result.init(self.allocator, types.len);

        for (types) |typ, i| {
            const value = try stack.popValue();
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

    fn push(self: VM, ctx: *Context, frame: Frame, idx: u32) !void {
        _ = self;
        const value = try ctx.stack.popValue();
        try frame.setLocal(idx, value);
    }
};

pub const Value = @import("runtime/stack.zig").Value;
pub const Label = @import("runtime/stack.zig").Label;
pub const Frame = @import("runtime/stack.zig").Frame;
pub const Stack = @import("runtime/stack.zig").Stack;

const TestUnion = union(enum) {
    a: i32,
    b: i32,
};
