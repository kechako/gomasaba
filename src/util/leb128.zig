const std = @import("std");
const Log2Int = std.math.Log2Int;
const Log2IntCeil = std.math.Log2IntCeil;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const test_allocator = std.testing.allocator;

pub fn readUnsigned(comptime T: type, reader: anytype, value: *T) !usize {
    const bitCount = comptime getBitCount(T, .unsigned);
    const maxBytes = comptime getMaxBytes(bitCount);

    var shift: Log2Int(T) = 0;
    var i: usize = 0;
    value.* = 0;
    while (i < maxBytes) : (i += 1) {
        const b = try reader.readByte();
        value.* |= @as(T, @intCast(b & 0x7f)) << shift;
        if (b & 0x80 == 0) {
            return i + 1;
        }
        shift += 7;
    }

    return error.ReadMaxBytes;
}

pub fn writeUnsigned(comptime T: type, writer: anytype, value: T) !usize {
    const bitCount = comptime getBitCount(T, .unsigned);
    const maxBytes = comptime getMaxBytes(bitCount);

    var v = value;
    var buf: [maxBytes]u8 = undefined;

    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @as(u8, @truncate(v & 0x7f));
        v >>= 7;
        if (v == 0) {
            const size = i + 1;
            try writer.writeAll(buf[0..size]);
            return size;
        }
        buf[i] |= 0x80;
    }

    return error.OutOfMemory;
}

const unsignedTests = [_]struct {
    v: u32,
    n: usize,
    b: []const u8,
}{
    .{ .v = 0, .n = 1, .b = @as([]const u8, &[_]u8{0}) },
    .{ .v = 1, .n = 1, .b = @as([]const u8, &[_]u8{1}) },
    .{ .v = 0x7F, .n = 1, .b = @as([]const u8, &[_]u8{0x7F}) },
    .{ .v = 0x80, .n = 2, .b = @as([]const u8, &[_]u8{ 0x80, 1 }) },
    .{ .v = 0x81, .n = 2, .b = @as([]const u8, &[_]u8{ 0x81, 1 }) },
    .{ .v = 0xFF, .n = 2, .b = @as([]const u8, &[_]u8{ 0xFF, 1 }) },
    .{ .v = 0x4000, .n = 3, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 1 }) },
    .{ .v = 0x4001, .n = 3, .b = @as([]const u8, &[_]u8{ 0x81, 0x80, 1 }) },
    .{ .v = 0x4081, .n = 3, .b = @as([]const u8, &[_]u8{ 0x81, 0x81, 1 }) },
    .{ .v = 0x0FFFFFFF, .n = 4, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xFF, 0x7F }) },
    .{ .v = 0xFFFFFFFF, .n = 5, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xF }) },
};

test "util.leb128.readUnsigned()" {
    for (unsignedTests) |tt| {
        var fbs = std.io.fixedBufferStream(tt.b);
        var v: u32 = undefined;
        const n = try readUnsigned(u32, fbs.reader(), &v);
        try expectEqual(tt.n, n);
        try expectEqual(tt.v, v);
    }
}

test "util.leb128.writeUnsigned()" {
    for (unsignedTests) |tt| {
        var buf = std.ArrayList(u8).init(test_allocator);
        defer buf.deinit();

        const n = try writeUnsigned(u32, buf.writer(), tt.v);
        try expectEqual(tt.n, n);
        try expectEqualSlices(u8, tt.b, buf.items);
    }
}

pub fn readSigned(comptime T: type, reader: anytype, value: *T) !usize {
    const bitCount = comptime getBitCount(T, .signed);
    const maxBytes = comptime getMaxBytes(bitCount);

    var shift: Log2Int(T) = 0;
    var i: usize = 0;
    value.* = 0;
    while (i < maxBytes) : (i += 1) {
        const b = try reader.readByte();
        value.* |= @as(T, @intCast(b & 0x7f)) << shift;
        if (b & 0x80 == 0) {
            const size = i + 1;
            if (shift < bitCount - 7 and (b & 0x40) != 0) {
                value.* |= @as(T, -1) << (shift + 7);
                return size;
            }
            return size;
        }
        shift += 7;
    }

    return error.ReadMaxBytes;
}

pub fn writeSigned(comptime T: type, writer: anytype, value: T) !usize {
    const bitCount = comptime getBitCount(T, .signed);
    const maxBytes = comptime getMaxBytes(bitCount);

    var v = value;
    var buf: [maxBytes]u8 = undefined;

    const negative = v < 0;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        const b = @as(u8, @intCast(v & 0x7f));
        v >>= 7;
        if (negative) {
            v |= @as(T, @truncate(@as(i128, -1) << (bitCount - 7)));
        }
        if (v == 0 and (b & 0x40) == 0 or
            (v == -1 and (b & 0x40) != 0))
        {
            buf[i] = b;
            const size = i + 1;
            try writer.writeAll(buf[0..size]);
            return size;
        }
        buf[i] = b | 0x80;
    }

    return error.OutOfMemory;
}

const signedTests = [_]struct {
    v: i32,
    n: usize,
    b: []const u8,
}{
    .{ .v = 0, .n = 1, .b = @as([]const u8, &[_]u8{0}) },
    .{ .v = 1, .n = 1, .b = @as([]const u8, &[_]u8{1}) },
    .{ .v = 0x3F, .n = 1, .b = @as([]const u8, &[_]u8{0x3F}) },
    .{ .v = 0x40, .n = 2, .b = @as([]const u8, &[_]u8{ 0xC0, 0 }) },
    .{ .v = 0x41, .n = 2, .b = @as([]const u8, &[_]u8{ 0xC1, 0 }) },
    .{ .v = 0x80, .n = 2, .b = @as([]const u8, &[_]u8{ 0x80, 1 }) },
    .{ .v = 0xFF, .n = 2, .b = @as([]const u8, &[_]u8{ 0xFF, 1 }) },
    .{ .v = 0x1FFF, .n = 2, .b = @as([]const u8, &[_]u8{ 0xFF, 0x3F }) },
    .{ .v = 0x2000, .n = 3, .b = @as([]const u8, &[_]u8{ 0x80, 0xC0, 0 }) },
    .{ .v = 0x2001, .n = 3, .b = @as([]const u8, &[_]u8{ 0x81, 0xC0, 0 }) },
    .{ .v = 0x2081, .n = 3, .b = @as([]const u8, &[_]u8{ 0x81, 0xC1, 0 }) },
    .{ .v = 0x4000, .n = 3, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 1 }) },
    .{ .v = 0x0FFFFF, .n = 3, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0x3F }) },
    .{ .v = 0x100000, .n = 4, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0xC0, 0 }) },
    .{ .v = 0x100001, .n = 4, .b = @as([]const u8, &[_]u8{ 0x81, 0x80, 0xC0, 0 }) },
    .{ .v = 0x100081, .n = 4, .b = @as([]const u8, &[_]u8{ 0x81, 0x81, 0xC0, 0 }) },
    .{ .v = 0x104081, .n = 4, .b = @as([]const u8, &[_]u8{ 0x81, 0x81, 0xC1, 0 }) },
    .{ .v = 0x200000, .n = 4, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x80, 1 }) },
    .{ .v = 0x7FFFFFF, .n = 4, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xFF, 0x3F }) },
    .{ .v = 0x8000000, .n = 5, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x80, 0xC0, 0 }) },
    .{ .v = 0x8000001, .n = 5, .b = @as([]const u8, &[_]u8{ 0x81, 0x80, 0x80, 0xC0, 0 }) },
    .{ .v = 0x8000081, .n = 5, .b = @as([]const u8, &[_]u8{ 0x81, 0x81, 0x80, 0xC0, 0 }) },
    .{ .v = 0x8004081, .n = 5, .b = @as([]const u8, &[_]u8{ 0x81, 0x81, 0x81, 0xC0, 0 }) },
    .{ .v = 0x8204081, .n = 5, .b = @as([]const u8, &[_]u8{ 0x81, 0x81, 0x81, 0xC1, 0 }) },
    .{ .v = 0x0FFFFFFF, .n = 5, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0 }) },
    .{ .v = 0x10000000, .n = 5, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x80, 0x80, 1 }) },
    .{ .v = 0x7FFFFFFF, .n = 5, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x7 }) },
    .{ .v = -1, .n = 1, .b = @as([]const u8, &[_]u8{0x7F}) },
    .{ .v = -2, .n = 1, .b = @as([]const u8, &[_]u8{0x7E}) },
    .{ .v = -0x3F, .n = 1, .b = @as([]const u8, &[_]u8{0x41}) },
    .{ .v = -0x40, .n = 1, .b = @as([]const u8, &[_]u8{0x40}) },
    .{ .v = -0x41, .n = 2, .b = @as([]const u8, &[_]u8{ 0xBF, 0x7F }) },
    .{ .v = -0x80, .n = 2, .b = @as([]const u8, &[_]u8{ 0x80, 0x7F }) },
    .{ .v = -0x81, .n = 2, .b = @as([]const u8, &[_]u8{ 0xFF, 0x7E }) },
    .{ .v = -0x00002000, .n = 2, .b = @as([]const u8, &[_]u8{ 0x80, 0x40 }) },
    .{ .v = -0x00002001, .n = 3, .b = @as([]const u8, &[_]u8{ 0xFF, 0xBF, 0x7F }) },
    .{ .v = -0x00100000, .n = 3, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x40 }) },
    .{ .v = -0x00100001, .n = 4, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xBF, 0x7F }) },
    .{ .v = -0x08000000, .n = 4, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x80, 0x40 }) },
    .{ .v = -0x08000001, .n = 5, .b = @as([]const u8, &[_]u8{ 0xFF, 0xFF, 0xFF, 0xBF, 0x7F }) },
    .{ .v = -0x20000000, .n = 5, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x7E }) },
    .{ .v = @as(i32, @bitCast(@as(u32, 0x80000000))), .n = 5, .b = @as([]const u8, &[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x78 }) },
};

test "util.leb128.readSigned()" {
    for (signedTests) |tt| {
        var fbs = std.io.fixedBufferStream(tt.b);
        var v: i32 = undefined;
        const n = try readSigned(i32, fbs.reader(), &v);
        try expectEqual(tt.n, n);
        try expectEqual(tt.v, v);
    }
}

test "util.leb128.writeSigned()" {
    for (signedTests) |tt| {
        var buf = std.ArrayList(u8).init(test_allocator);
        defer buf.deinit();

        const n = try writeSigned(i32, buf.writer(), tt.v);
        try expectEqual(tt.n, n);
        try expectEqualSlices(u8, tt.b, buf.items);
    }
}

fn getBitCount(comptime T: type, comptime signedness: std.builtin.Signedness) Log2IntCeil(T) {
    return switch (@typeInfo(T)) {
        .Int => |info| if (info.signedness == signedness)
            info.bits
        else
            @compileError("value must be " ++ @tagName(signedness) ++ " integer"),
        else => @compileError("value must be " ++ @tagName(signedness) ++ " integer"),
    };
}

test "util.leb128.getBitCount()" {
    try expectEqual(@as(u6, 16), getBitCount(u16, .unsigned));
    try expectEqual(@as(u7, 32), getBitCount(u32, .unsigned));
    try expectEqual(@as(u8, 64), getBitCount(u64, .unsigned));
    try expectEqual(@as(u6, 16), getBitCount(i16, .signed));
    try expectEqual(@as(u7, 32), getBitCount(i32, .signed));
    try expectEqual(@as(u8, 64), getBitCount(i64, .signed));
}

fn getMaxBytes(comptime bitCount: anytype) @TypeOf(bitCount) {
    return (1 + (bitCount - 1) / 7);
}

test "util.leb128.getMaxBytes()" {
    try expectEqual(3, getMaxBytes(16));
    try expectEqual(5, getMaxBytes(32));
    try expectEqual(10, getMaxBytes(64));
}
