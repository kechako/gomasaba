const std = @import("std");
const io = std.io;

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
