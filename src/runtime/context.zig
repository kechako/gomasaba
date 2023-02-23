const std = @import("std");
const ArrayList = std.ArrayList;
const mem = std.mem;
const Allocator = mem.Allocator;
const runtime = @import("../runtime.zig");
const Value = runtime.Value;

pub const Context = struct {
    allocator: Allocator,
    stack: ArrayList(StackItem),

    pub fn init(allocator: Allocator) Context {
        const stack = ArrayList(StackItem).init(allocator);
        return .{ .allocator = allocator, .stack = stack };
    }

    pub fn pushValue(self: *Context, value: Value) !void {
        self.stack.append(.{
            .value = value,
        });
    }

    pub fn popValue(self: Context) !Value {
        const item = self.stack.popOrNull();
        if (item == null) return error.StackUnderflow;

        switch (item.?) {
            .value => |v| return v,
            else => return error.InvalidStackItem,
        }
    }
};

const StackItem = union {
    value: Value,
};
