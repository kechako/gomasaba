const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const test_allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectFmt = std.testing.expectFmt;
const mod = @import("../mod.zig");

const Stack = struct {
    entries: ArrayList(Entry),

    pub fn init(allocator: Allocator) Stack {
        const entries = ArrayList(Entry).init(allocator);
        return .{ .entries = entries };
    }

    pub fn deinit(self: *Stack) void {
        self.entries.deinit();
    }

    pub fn push(self: *Stack, entry: Entry) !void {
        try self.entries.append(entry);
    }

    pub fn pop(self: *Stack) !Entry {
        if (self.entries.items.len > 0) {
            return self.entries.pop();
        }
        return error.StackUnderflow;
    }

    pub fn peek(self: Stack, depth: usize) !Entry {
        const len = self.entries.items.len;
        if (len > depth) {
            return self.entries.items[len - 1 - depth];
        }
        return error.StackUnderflow;
    }

    test "runtime.Stack" {
        var stack = Stack.init(test_allocator);
        defer stack.deinit();

        const entry1 = Entry{
            .value = Value{
                .i32 = 100,
            },
        };
        const entry2 = Entry{
            .value = Value{
                .i32 = 200,
            },
        };

        try stack.push(entry1);
        try expectEqual(@as(usize, 1), stack.entries.items.len);
        try stack.push(entry2);
        try expectEqual(@as(usize, 2), stack.entries.items.len);

        const p1 = try stack.peek(0);
        try expectEqual(entry2.value.i32, p1.value.i32);
        const p2 = try stack.peek(1);
        try expectEqual(entry1.value.i32, p2.value.i32);

        try expectError(error.StackUnderflow, stack.peek(2));

        const pp1 = try stack.pop();
        try expectEqual(entry2.value.i32, pp1.value.i32);
        const pp2 = try stack.pop();
        try expectEqual(entry1.value.i32, pp2.value.i32);

        try expectError(error.StackUnderflow, stack.pop());
    }
};

const Entry = union {
    value: Value,
    frame: Frame,
};

pub const Value = union(enum) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        comptime var base = 10;
        comptime var case: std.fmt.Case = .lower;
        if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
            base = 10;
            case = .lower;
        } else if (comptime std.mem.eql(u8, fmt, "x")) {
            base = 16;
            case = .lower;
        } else {
            invalidFormatError(fmt, self);
        }
        switch (self) {
            .i32 => |v| try std.fmt.formatInt(v, base, case, options, writer),
            .i64 => |v| try std.fmt.formatInt(v, base, case, options, writer),
            .f32 => |v| if (base == 16)
                try std.fmt.formatFloatHexadecimal(v, options, writer)
            else
                try std.fmt.formatFloatDecimal(v, options, writer),
            .f64 => |v| if (base == 16)
                try std.fmt.formatFloatHexadecimal(v, options, writer)
            else
                try std.fmt.formatFloatDecimal(v, options, writer),
        }
    }

    test "runtime.Value.format()" {
        try expectFmt("12345", "{}", .{Value{ .i32 = 12345 }});
        try expectFmt("12345", "{}", .{Value{ .i64 = 12345 }});
        try expectFmt("12345.125", "{}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("12345.125", "{}", .{Value{ .f64 = 12345.125 }});

        try expectFmt("12345", "{d}", .{Value{ .i32 = 12345 }});
        try expectFmt("12345", "{d}", .{Value{ .i64 = 12345 }});
        try expectFmt("12345.125", "{d}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("12345.125", "{d}", .{Value{ .f64 = 12345.125 }});

        try expectFmt("1234abcd", "{x}", .{Value{ .i32 = 0x1234_abcd }});
        try expectFmt("123456789abcef01", "{x}", .{Value{ .i64 = 0x1234_5678_9abc_ef01 }});
        try expectFmt("0x1.81c9p13", "{x}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("0x1.81c9p13", "{x}", .{Value{ .f64 = 12345.125 }});

        try expectFmt("    +12345", "{d: >10}", .{Value{ .i32 = 12345 }});
        try expectFmt("+12345    ", "{d: <10}", .{Value{ .i64 = 12345 }});
        try expectFmt("12345.12500", "{d:.5}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("12345.13", "{d:.2}", .{Value{ .f64 = 12345.125 }});
    }
};

fn invalidFormatError(comptime fmt: []const u8, value: anytype) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
}

pub const Frame = struct {
    locals: []Value,
    module: mod.Module,

    pub fn init(locals: []Value, module: mod.Module) Frame {
        return .{ .locals = locals, .module = module };
    }
};

test {
    _ = Stack;
    _ = Value;
}
