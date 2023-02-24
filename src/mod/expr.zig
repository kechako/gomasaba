const std = @import("std");
const mod = @import("../mod.zig");
const instr = mod.instr;
const leb128 = mod.leb128;

pub fn ExpressionReader(comptime ReaderType: type) type {
    return struct {
        reader: ReaderType,

        const Self = @This();

        pub fn next(self: Self) !?instr.Opecode {
            const b = self.reader.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    return null;
                }

                return err;
            };

            return try instr.Opecode.fromInt(b);
        }

        pub fn readUnsigned(self: Self, comptime T: type) !T {
            var v: T = undefined;
            _ = try leb128.readUnsigned(T, self.reader, &v);

            return v;
        }

        pub fn readSigned(self: Self, comptime T: type) !T {
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

        pub fn readFloat(self: Self, comptime T: type) !T {
            const i = try self.reader.readInt(BinaryInt(T), .Little);
            return @bitCast(T, i);
        }

        pub fn readByte(self: Self) !u8 {
            return try self.reader.readByte();
        }
    };
}

pub fn expressionReader(reader: anytype) ExpressionReader(@TypeOf(reader)) {
    return .{ .reader = reader };
}

pub fn skipConstantExpression(reader: anytype, typ: mod.ValueType) !void {
    const r = expressionReader(reader);
    switch (typ) {
        .i32 => {
            const opcode = try r.next();
            if (opcode) |op|
                switch (op) {
                    .I32Const => {
                        _ = try r.readSigned(i32);
                    },
                    .GlobalGet => {
                        _ = try r.readUnsigned(u32);
                    },
                    else => return error.InvalidConstantExpressions,
                }
            else
                return error.InvalidConstantExpressions;
        },
        .i64 => {
            const opcode = try r.next();
            if (opcode) |op|
                switch (op) {
                    .I64Const => {
                        _ = try r.readSigned(i64);
                    },
                    .GlobalGet => {
                        _ = try r.readUnsigned(u64);
                    },
                    else => return error.InvalidConstantExpressions,
                }
            else
                return error.InvalidConstantExpressions;
        },
        .f32 => {
            const opcode = try r.next();
            if (opcode) |op|
                switch (op) {
                    .F32Const => {
                        _ = try r.readFloat(f32);
                    },
                    .GlobalGet => {
                        _ = try r.readUnsigned(u32);
                    },
                    else => return error.InvalidConstantExpressions,
                }
            else
                return error.InvalidConstantExpressions;
        },
        .f64 => {
            const opcode = try r.next();
            if (opcode) |op|
                switch (op) {
                    .F64Const => {
                        _ = try r.readFloat(f64);
                    },
                    .GlobalGet => {
                        _ = try r.readUnsigned(u32);
                    },
                    else => return error.InvalidConstantExpressions,
                }
            else
                return error.InvalidConstantExpressions;
        },
        .funcref, .externref => {
            const opcode = try r.next();
            if (opcode) |op|
                switch (op) {
                    .RefNull => {
                        const b = try r.readSigned(i8);
                        const valType = try mod.ValueType.fromInt(b);
                        if (valType != .funcref) return error.InvalidConstantExpressions;
                    },
                    .RefFunc => {
                        _ = try r.readUnsigned(u32);
                    },
                    else => return error.InvalidConstantExpressions,
                }
            else
                return error.InvalidConstantExpressions;
        },
        else => return error.InvalidConstantExpressions,
    }

    // End
    {
        const opcode = try r.next();
        if (opcode) |op| {
            if (op != .End) {
                return error.InvalidConstantExpressions;
            }
        }
    }
}
