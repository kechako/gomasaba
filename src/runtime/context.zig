const std = @import("std");
const ArrayList = std.ArrayList;
const mem = std.mem;
const Allocator = mem.Allocator;
const runtime = @import("../runtime.zig");
const Value = runtime.Value;
const Stack = runtime.Stack;
const Label = runtime.Label;

pub const Context = struct {
    stack: Stack,

    pub fn init(allocator: Allocator) Context {
        return .{
            .stack = Stack.init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.stack.deinit();
    }
};
