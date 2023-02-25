const std = @import("std");
const io = std.io;
const testing = std.testing;
const test_allocator = testing.allocator;

pub fn TeeReader(comptime ReaderType: type, comptime WriterType: type) type {
    return struct {
        inner_reader: ReaderType,
        inner_writer: WriterType,

        pub const Error = ReaderType.Error || WriterType.Error;
        pub const Reader = io.Reader(*Self, Error, read);

        const Self = @This();

        pub fn read(self: *Self, dest: []u8) Error!usize {
            const n = try self.inner_reader.read(dest);
            try self.inner_writer.writeAll(dest[0..n]);
            return n;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

pub fn teeReader(inner_reader: anytype, inner_writer: anytype) TeeReader(@TypeOf(inner_reader), @TypeOf(inner_writer)) {
    return .{ .inner_reader = inner_reader, .inner_writer = inner_writer };
}

test "util.TeeReader" {
    const str = "TeeReader test";
    var stream = io.fixedBufferStream(str);
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();

    var tr = teeReader(stream.reader(), list.writer());

    const buf = try test_allocator.alloc(u8, 20);
    defer test_allocator.free(buf);
    const n = try tr.reader().readAll(buf);

    try testing.expectEqualSlices(u8, str, buf[0..n]);
    try testing.expectEqualSlices(u8, str, list.items);
}
