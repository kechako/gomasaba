const std = @import("std");
const Allocator = std.mem.Allocator;

const instance = @import("../instance.zig");
const instr = @import("../instr.zig");
const runtime = @import("../runtime.zig");
const util = @import("../util.zig");

const ModuleInstance = instance.ModuleInstance;
const FunctionInstance = instance.FunctionInstance;
const Label = runtime.Label;
const LabelStack = runtime.LabelStack;
const Value = runtime.Value;
const CodeReader = instr.CodeReader;

pub const Frame = struct {
    allocator: Allocator,
    locals: []Value,
    module: *ModuleInstance,
    function: *FunctionInstance,
    code_reader: *CodeReader,

    label_stack: LabelStack,

    pub fn init(allocator: Allocator, params: []const Value, mod: *ModuleInstance, function: *FunctionInstance) !Frame {
        var reader = try allocator.create(CodeReader);
        reader.* = CodeReader.init(function.code);
        return .{
            .allocator = allocator,
            .locals = try initLocals(allocator, params, function),
            .module = mod,
            .function = function,
            .code_reader = reader,
            .label_stack = LabelStack.init(allocator),
        };
    }

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.locals);
        self.allocator.free(self.code_reader);
        self.label_stack.deinit();
    }

    fn initLocals(allocator: Allocator, params: []const Value, function: ?*FunctionInstance) ![]Value {
        var len = params.len;
        if (function) |func| {
            for (func.locals) |l| {
                len += l.count;
            }
        }

        var values = try allocator.alloc(Value, len);
        var i: usize = 0;
        for (params) |param| {
            values[i] = param;
            i += 1;
        }

        if (function) |func| {
            for (func.locals) |local| {
                var c: usize = 0;
                while (c < local.count) : (c += 1) {
                    values[i] = switch (local.value_type) {
                        .i32 => .{ .i32 = 0 },
                        .i64 => .{ .i64 = 0 },
                        .f32 => .{ .f32 = 0 },
                        .f64 => .{ .f64 = 0 },
                        else => return error.UnsupportedType,
                    };
                }
                i += 1;
            }
        }
        return values;
    }

    pub fn getLocal(self: Frame, idx: u32) !Value {
        if (idx < self.locals.len) {
            return self.locals[idx];
        } else {
            return error.OutOfRange;
        }
    }

    pub fn setLocal(self: Frame, idx: u32, value: Value) !void {
        if (idx < self.locals.len) {
            self.locals[idx] = value;
        } else {
            return error.OutOfRange;
        }
    }

    pub fn pushLabel(self: *Frame, label: Label) !void {
        try self.label_stack.push(label);
    }

    pub fn popLabel(self: *Frame) !Label {
        return try self.label_stack.pop();
    }

    pub fn tryPopLabel(self: *Frame) ?Label {
        return self.label_stack.tryPop();
    }

    pub fn peekLabel(self: *Frame) !Label {
        return try self.label_stack.peek();
    }
};

pub const FrameStack = util.Stack(Frame);
