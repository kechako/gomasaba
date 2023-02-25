const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn Stack(comptime T: type) type {
    return struct {
        stack: ArrayList(T),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .stack = ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit();
        }

        pub fn push(self: *Self, v: T) !void {
            try self.stack.append(v);
        }

        pub fn pop(self: *Self) !T {
            if (self.stack.items.len > 0) {
                return self.stack.pop();
            }
            return error.StackUnderflow;
        }

        pub fn peek(self: *Self) !T {
            return try self.peekDepth(0);
        }

        pub fn peekDepth(self: *Self, depth: usize) !T {
            const len = self.stack.items.len;
            if (len > depth) {
                return self.stack.items[len - 1 - depth];
            }
            return error.StackUnderflow;
        }
    };
}

const test_allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "util.Stack" {
    const TestStack = Stack(u8);
    var stack = TestStack.init(test_allocator);
    defer stack.deinit();

    const v1: u8 = 10;
    const v2: u8 = 20;

    try stack.push(v1);
    try expectEqual(@as(usize, 1), stack.stack.items.len);
    try stack.push(v2);
    try expectEqual(@as(usize, 2), stack.stack.items.len);

    const pkd1 = try stack.peekDepth(0);
    try expectEqual(v2, pkd1);
    const pkd2 = try stack.peekDepth(1);
    try expectEqual(v1, pkd2);

    try expectError(error.StackUnderflow, stack.peekDepth(2));

    const pk1 = try stack.peek();
    try expectEqual(v2, pk1);
    const pp1 = try stack.pop();
    try expectEqual(v2, pp1);

    const pk2 = try stack.peek();
    try expectEqual(v1, pk2);
    const pp2 = try stack.pop();
    try expectEqual(v1, pp2);

    try expectError(error.StackUnderflow, stack.peek());
    try expectError(error.StackUnderflow, stack.pop());
}
