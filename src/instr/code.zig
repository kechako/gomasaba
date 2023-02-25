const std = @import("std");
const io = std.io;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const util = @import("../util.zig");
const leb128 = util.leb128;
const instr = @import("../instr.zig");

const Opecode = instr.Opecode;
const Instruction = instr.Instruction;

pub const Code = []const Instruction;

pub fn CodeParser(comptime ReaderType: type) type {
    return struct {
        reader: ReaderType,
        parsed_code: ArrayList(Instruction),
        scope: usize,

        const Self = @This();

        pub fn init(allocator: Allocator, reader: ReaderType) Self {
            return .{
                .reader = reader,
                .parsed_code = ArrayList(Instruction).init(allocator),
                .scope = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.parsed_code.deinit();
        }

        pub fn parse(self: *Self) !Code {
            while (true) {
                const inst = try self.readInstruction();
                try self.pushInstruction(inst);
                if (inst == .@"end" and self.scope == 0) {
                    break;
                }
            }

            return self.parsed_code.toOwnedSlice();
        }

        fn readInstruction(self: *Self) !Instruction {
            const op = try self.readOpecode();
            //std.debug.print("OP: {s}\n", .{@tagName(op)});

            var inst: Instruction = undefined;
            switch (op) {
                .@"end" => {
                    inst = Instruction.@"end";
                },
                .@"return" => inst = Instruction.@"return",
                .@"call" => {
                    const idx = try self.readUnsigned(u32);
                    inst = .{ .@"call" = idx };
                },
                .@"drop" => inst = Instruction.@"drop",
                .@"local.get" => {
                    const idx = try self.readUnsigned(u32);
                    inst = .{ .@"local.get" = idx };
                },
                .@"local.set" => {
                    const idx = try self.readUnsigned(u32);
                    inst = .{ .@"local.set" = idx };
                },
                .@"local.tee" => {
                    const idx = try self.readUnsigned(u32);
                    inst = .{ .@"local.tee" = idx };
                },
                .@"i32.const" => {
                    const v = try self.readSigned(i32);
                    inst = .{ .@"i32.const" = v };
                },
                .@"i32.eqz" => inst = Instruction.@"i32.eqz",
                .@"i32.eq" => inst = Instruction.@"i32.eq",
                .@"i32.ne" => inst = Instruction.@"i32.ne",
                .@"i32.lt_s" => inst = Instruction.@"i32.lt_s",
                .@"i32.gt_s" => inst = Instruction.@"i32.gt_s",
                .@"i32.le_s" => inst = Instruction.@"i32.le_s",
                .@"i32.ge_s" => inst = Instruction.@"i32.ge_s",
                .@"i32.add" => inst = Instruction.@"i32.add",
                .@"i32.sub" => inst = Instruction.@"i32.sub",
                .@"i32.mul" => inst = Instruction.@"i32.mul",
                .@"i32.div_s" => inst = Instruction.@"i32.div_s",
                else => return error.UnsupportedInstruction,
            }

            return inst;
        }

        fn pushInstruction(self: *Self, inst: Instruction) !void {
            try self.parsed_code.append(inst);
        }

        fn readOpecode(self: *Self) !instr.Opecode {
            const b = self.reader.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    return error.UnexpectedEndOfStream;
                }

                return err;
            };

            return try instr.Opecode.fromInt(b);
        }

        fn readUnsigned(self: *Self, comptime T: type) !T {
            var v: T = undefined;
            _ = try leb128.readUnsigned(T, self.reader, &v);

            return v;
        }

        fn readSigned(self: *Self, comptime T: type) !T {
            var v: T = undefined;
            _ = try leb128.readSigned(T, self.reader, &v);

            return v;
        }

        fn BinaryInt(comptime T: type) type {
            return switch (@typeInfo(T)) {
                .Float => |info| switch (info.bits) {
                    16 => u16,
                    32 => u32,
                    64 => u64,
                    else => @compileError("invalid float type"),
                },
                else => @compileError("value must be float"),
            };
        }

        fn readFloat(self: *Self, comptime T: type) !T {
            const i = try self.reader.readInt(BinaryInt(T), .Little);
            return @bitCast(T, i);
        }

        fn readByte(self: *Self) !u8 {
            return try self.reader.readByte();
        }
    };
}

pub fn codeParser(allocator: Allocator, reader: anytype) CodeParser(@TypeOf(reader)) {
    return CodeParser(@TypeOf(reader)).init(allocator, reader);
}

pub const CodeReader = struct {
    code: Code,
    pointer: u32,

    pub fn init(code: Code) CodeReader {
        return .{
            .code = code,
            .pointer = 0,
        };
    }

    pub fn next(self: *CodeReader) ?Instruction {
        if (self.pointer >= self.code.len) {
            return null;
        }
        defer self.pointer += 1;
        return self.code[self.pointer];
    }

    pub fn setPointer(self: *CodeReader, pointer: u32) !void {
        if (pointer >= self.code.len) {
            return error.OutOfCode;
        }
        self.pointer = pointer;
    }
};

const test_allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "instr.Code" {
    const rawCode = &[_]u8{
        0x41, 0x0a, // i32.const 10
        0x41, 0x14, // i32.const 20
        0x6a, // i32.add
        0x0b, // end
    };
    var stream = io.fixedBufferStream(rawCode);
    var parser = codeParser(test_allocator, stream.reader());
    defer parser.deinit();

    const code = try parser.parse();
    defer test_allocator.free(code);

    var reader = CodeReader.init(code);

    {
        // i32.const 10
        const inst = reader.next();
        if (inst) |i| {
            try expectEqual(Opecode.@"i32.const", i);
            try expectEqual(@as(i32, 10), i.@"i32.const");
        } else {
            return error.EndOfCode;
        }
    }

    {
        // i32.const 20
        const inst = reader.next();
        if (inst) |i| {
            try expectEqual(Opecode.@"i32.const", i);
            try expectEqual(@as(i32, 20), i.@"i32.const");
        } else {
            return error.EndOfCode;
        }
    }

    {
        // i32.add
        const inst = reader.next();
        if (inst) |i| {
            try expectEqual(Opecode.@"i32.add", i);
        } else {
            return error.EndOfCode;
        }
    }

    {
        // end
        const inst = reader.next();
        if (inst) |i| {
            try expectEqual(Opecode.@"end", i);
        } else {
            return error.EndOfCode;
        }
    }
}
