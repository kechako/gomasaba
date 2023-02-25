const std = @import("std");
const expectFmt = std.testing.expectFmt;

const util = @import("../util.zig");

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
};

fn invalidFormatError(comptime fmt: []const u8, value: anytype) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
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

pub const ValueStack = util.Stack(Value);
