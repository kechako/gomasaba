const std = @import("std");
const mod = @import("../mod.zig");
const expr = mod.expr;
const instr = mod.instr;

pub const WatEncoder = struct {
    indent: usize,
    type_index: usize,
    func_index: usize,

    pub fn init() WatEncoder {
        return .{
            .indent = 0,
            .type_index = 0,
            .func_index = 0,
        };
    }

    pub fn encode(self: *WatEncoder, writer: anytype, m: mod.Module) !void {
        try writer.writeAll("(module");

        self.increaseIndent();

        const func_types = if (m.type_section) |sec| sec.function_types else &[_]mod.FunctionType{};

        if (m.type_section) |sec| {
            try self.writeTypeSection(writer, sec);
        }

        if (m.import_section) |sec| {
            try self.writeImportSection(writer, sec);
        }

        const codes = if (m.code_section) |sec| sec.codes else &[_]mod.Code{};

        if (m.function_section) |sec| {
            try self.writeFunctionSection(writer, sec, func_types, codes);
        }

        if (m.table_section) |sec| {
            try self.writeTableSection(writer, sec);
        }

        if (m.memory_section) |sec| {
            try self.writeMemorySection(writer, sec);
        }

        if (m.global_section) |sec| {
            try self.writeGlobalSection(writer, sec);
        }

        if (m.export_section) |sec| {
            try self.writeExportSection(writer, sec);
        }

        if (m.start_section) |sec| {
            try self.writeStartSection(writer, sec);
        }

        self.decreaseIndent();

        try writer.writeByte(')');
    }

    fn writeTypeSection(self: *WatEncoder, writer: anytype, sec: mod.TypeSection) !void {
        for (sec.function_types) |typ| {
            try self.writeIndent(writer);

            try writer.print("(type (;{d};) ", .{self.getTypeIndex()});

            try self.writeFunctionType(writer, typ);

            try writer.writeByte(')');
        }
    }

    fn writeFunctionType(self: *WatEncoder, writer: anytype, func_type: mod.FunctionType) !void {
        try writer.writeAll("(func");

        if (func_type.parameter_types.len > 0) {
            try writer.writeByte(' ');

            try self.writeValueTypes(writer, "param", func_type.parameter_types);
        }
        if (func_type.result_types.len > 0) {
            try writer.writeByte(' ');

            try self.writeValueTypes(writer, "result", func_type.result_types);
        }

        try writer.writeByte(')');
    }

    fn writeValueTypes(_: *WatEncoder, writer: anytype, name: []const u8, value_types: []const mod.ValueType) !void {
        if (value_types.len == 0) {
            return;
        }

        try writer.print("({s}", .{name});

        for (value_types) |typ| {
            try writer.writeByte(' ');

            try writer.print("{s}", .{typ});
        }

        try writer.writeByte(')');
    }

    fn writeImportSection(self: *WatEncoder, writer: anytype, sec: mod.ImportSection) !void {
        for (sec.imports) |imp| {
            try self.writeIndent(writer);

            try writer.writeAll("(import ");

            try self.writeName(writer, imp.module);

            try writer.writeByte(' ');

            try self.writeName(writer, imp.name);

            try writer.writeByte(' ');

            switch (imp.description) {
                .function => |func| {
                    try self.writeFunctionImport(writer, func);
                },
                .table => |table| {
                    try self.writeTableImport(writer, table);
                },
                .memory => |memory| {
                    try self.writeMemoryImport(writer, memory);
                },
                .global => |global| {
                    try self.writeGlobalImport(writer, global);
                },
                else => return error.UnsupportedImportDescription,
            }

            try writer.writeByte(')');
        }
    }

    fn writeName(_: *WatEncoder, writer: anytype, name: []const u8) !void {
        try writer.writeByte('"');

        const unicode = std.unicode;

        var iter = (try unicode.Utf8View.init(name)).iterator();
        while (iter.nextCodepoint()) |codepoint| {
            if (codepoint >= 0x20 and codepoint != 0x7f and codepoint != '"' and codepoint != '\\') {
                var buf: [8]u8 = undefined;
                const n = try unicode.utf8Encode(codepoint, &buf);
                try writer.writeAll(buf[0..n]);
                continue;
            }

            switch (codepoint) {
                0x09 => try writer.writeAll("\\t"),
                0x0a => try writer.writeAll("\\n"),
                0x0d => try writer.writeAll("\\r"),
                0x22 => try writer.writeAll("\\\""),
                0x27 => try writer.writeAll("\\'"),
                0x5c => try writer.writeAll("\\\\"),
                else => {
                    if (codepoint < 0xd800 or (codepoint >= 0xe000 and codepoint < 0x110000)) {
                        try writer.print("\\u{{{x}}}", .{codepoint});
                    }
                },
            }
        }

        try writer.writeByte('"');
    }

    fn writeFunctionImport(self: *WatEncoder, writer: anytype, imp: mod.FunctionImport) !void {
        try writer.print("(func (;{d};) (type {d}))", .{ self.getFuncIndex(), imp.type_index });
    }

    fn writeTableImport(self: *WatEncoder, writer: anytype, imp: mod.TableImport) !void {
        try writer.print("(table (;{d};) ", .{self.getFuncIndex()});
        try self.writeTableType(writer, imp.table_type);
        try writer.writeByte(')');
    }

    fn writeMemoryImport(self: *WatEncoder, writer: anytype, imp: mod.MemoryImport) !void {
        try writer.print("(memory (;{d};) ", .{self.getFuncIndex()});
        try self.writeMemoryType(writer, imp.memory_type);
        try writer.writeByte(')');
    }

    fn writeGlobalImport(self: *WatEncoder, writer: anytype, imp: mod.GlobalImport) !void {
        try writer.print("(global (;{d};) ", .{self.getFuncIndex()});
        try self.writeGlobalType(writer, imp.global_type);
        try writer.writeByte(')');
    }

    fn writeFunctionSection(self: *WatEncoder, writer: anytype, sec: mod.FunctionSection, func_types: []const mod.FunctionType, codes: []const mod.Code) !void {
        for (sec.type_indexes) |idx, i| {
            if (i >= codes.len) {
                return error.FunctionCodeNotFound;
            }
            const code = codes[i];

            if (idx >= func_types.len) {
                return error.TypeIndexOutOfRange;
            }
            const func_type = func_types[idx];

            try self.writeIndent(writer);

            try writer.print("(func (;{d};) (type {d})", .{ self.getFuncIndex(), idx });

            if (func_type.parameter_types.len > 0) {
                try writer.writeByte(' ');

                try self.writeValueTypes(writer, "param", func_type.parameter_types);
            }

            if (func_type.result_types.len > 0) {
                try writer.writeByte(' ');

                try self.writeValueTypes(writer, "result", func_type.result_types);
            }

            self.increaseIndent();

            for (code.locals) |local, ii| {
                try self.writeIndent(writer);
                try self.writeLocal(writer, local, ii);
            }

            try self.writeExpressions(writer, code.expressions);

            self.decreaseIndent();

            try writer.writeAll(")");
        }
    }

    fn writeLocal(_: *WatEncoder, writer: anytype, local: mod.ValueType, index: usize) !void {
        try writer.print("(local (;{d};) {s})", .{ index, local });
    }

    fn writeExpressions(self: *WatEncoder, writer: anytype, exp: []const u8) !void {
        var fbs = std.io.fixedBufferStream(exp);
        const r = expr.expressionReader(fbs.reader());
        while (try r.next()) |op| {
            if (op == .End) {
                break;
            }

            try self.writeIndent(writer);

            switch (op) {
                .Call => {
                    const v = try r.readUnsigned(u32);
                    try writer.print("call {d}", .{v});
                },
                .LocalGet => {
                    const v = try r.readUnsigned(u32);
                    try writer.print("local.get {d}", .{v});
                },
                .I32Const => {
                    const v = try r.readUnsigned(u32);
                    try writer.print("i32.const {d}", .{v});
                },
                .I32Add => {
                    try writer.writeAll("i32.add");
                },
                .I32Sub => {
                    try writer.writeAll("i32.sub");
                },
                else => return error.UnsupportedInstruction,
            }
        }
    }

    fn writeTableSection(self: *WatEncoder, writer: anytype, sec: mod.TableSection) !void {
        for (sec.tables) |table, i| {
            try self.writeIndent(writer);

            try writer.print("(table (;{d};) ", .{i});

            try self.writeTableType(writer, table.table_type);

            try writer.writeAll(")");
        }
    }

    fn writeTableType(self: *WatEncoder, writer: anytype, table_type: mod.TableType) !void {
        try self.writeLimits(writer, table_type.limits);
        try writer.writeByte(' ');
        try writer.print("{s}", .{table_type.reftype});
    }

    fn writeMemorySection(self: *WatEncoder, writer: anytype, sec: mod.MemorySection) !void {
        for (sec.memories) |mem, i| {
            try self.writeIndent(writer);

            try writer.print("(memory (;{d};) ", .{i});

            try self.writeMemoryType(writer, mem.memory_type);

            try writer.writeAll(")");
        }
    }

    fn writeMemoryType(self: *WatEncoder, writer: anytype, memory_type: mod.MemoryType) !void {
        try self.writeLimits(writer, memory_type.limits);
    }

    fn writeLimits(_: *WatEncoder, writer: anytype, limits: mod.Limits) !void {
        try writer.print("{d}", .{limits.min});

        if (limits.flag == .max_present) {
            try writer.writeByte(' ');

            try writer.print("{d}", .{limits.max});
        }
    }

    fn writeGlobalSection(self: *WatEncoder, writer: anytype, sec: mod.GlobalSection) !void {
        for (sec.globals) |global, i| {
            try self.writeIndent(writer);

            try writer.print("(global (;{d};) ", .{i});

            try self.writeGlobalType(writer, global.global_type);

            try self.writeConstantExpressions(writer, global.expressions);

            try writer.writeByte(')');
        }
    }

    fn writeGlobalType(_: *WatEncoder, writer: anytype, global_type: mod.GlobalType) !void {
        switch (global_type.flag) {
            .immutable => {
                try writer.print("{s} ", .{global_type.type});
            },
            .mutable => {
                try writer.print("(mut {s}) ", .{global_type.type});
            },
            else => return error.InvalidMutability,
        }
    }

    fn writeConstantExpressions(_: *WatEncoder, writer: anytype, exp: []const u8) !void {
        try writer.writeByte('(');

        var fbs = std.io.fixedBufferStream(exp);
        const r = expr.expressionReader(fbs.reader());
        var first = true;
        while (try r.next()) |op| {
            if (op == .End) {
                break;
            }

            if (first)
                first = false
            else
                try writer.writeByte(' ');

            switch (op) {
                .I32Const => {
                    const v = try r.readSigned(i32);
                    try writer.print("i32.const {d}", .{v});
                },
                .I64Const => {
                    const v = try r.readSigned(i64);
                    try writer.print("i64.const {d}", .{v});
                },
                .F32Const => {
                    const v = try r.readFloat(f32);
                    try writer.print("f32.const {d}", .{v});
                },
                .F64Const => {
                    const v = try r.readFloat(f64);
                    try writer.print("f64.const {d}", .{v});
                },
                .GlobalGet => {
                    const id = try r.readUnsigned(u32);
                    try writer.print("globa.get {d}", .{id});
                },
                .RefNull => {
                    const b = try r.readSigned(i8);
                    const heapType = try mod.ValueType.fromInt(b);
                    try writer.print("ref.null {s}", .{heapType});
                },
                .RefFunc => {
                    const idx = try r.readUnsigned(u32);
                    try writer.print("ref.func {d}", .{idx});
                },
                else => return error.UnsupportedInstruction,
            }
        }

        try writer.writeByte(')');
    }

    fn writeExportSection(self: *WatEncoder, writer: anytype, sec: mod.ExportSection) !void {
        for (sec.exports) |exp| {
            try self.writeIndent(writer);

            try writer.writeAll("(export ");

            try self.writeName(writer, exp.name);

            try writer.writeByte(' ');

            switch (exp.description) {
                .function => |func| try self.writeFunctionExport(writer, func),
                .table => |table| try self.writeTableExport(writer, table),
                .memory => |memory| try self.writeMemoryExport(writer, memory),
                .global => |global| try self.writeGlobalExport(writer, global),
                else => return error.UnsupportedExportDescription,
            }

            try writer.writeByte(')');
        }
    }

    fn writeFunctionExport(_: *WatEncoder, writer: anytype, exp: mod.FunctionExport) !void {
        try writer.print("(func {d})", .{exp.function_index});
    }

    fn writeTableExport(_: *WatEncoder, writer: anytype, exp: mod.TableExport) !void {
        try writer.print("(table {d})", .{exp.table_index});
    }

    fn writeMemoryExport(_: *WatEncoder, writer: anytype, exp: mod.MemoryExport) !void {
        try writer.print("(memory {d})", .{exp.memory_index});
    }

    fn writeGlobalExport(_: *WatEncoder, writer: anytype, exp: mod.GlobalExport) !void {
        try writer.print("(global {d})", .{exp.global_index});
    }

    fn writeStartSection(self: *WatEncoder, writer: anytype, sec: mod.StartSection) !void {
        try self.writeIndent(writer);
        try self.writeStart(writer, sec.start);
    }

    fn writeStart(_: *WatEncoder, writer: anytype, start: mod.Start) !void {
        try writer.print("(start {d})", .{start.function_index});
    }

    fn getTypeIndex(self: *WatEncoder) usize {
        const idx = self.type_index;
        self.type_index += 1;
        return idx;
    }

    fn getFuncIndex(self: *WatEncoder) usize {
        const idx = self.func_index;
        self.func_index += 1;
        return idx;
    }

    fn writeIndent(self: *WatEncoder, writer: anytype) !void {
        try writer.writeByte('\n');

        var i: usize = 0;
        while (i < self.indent) : (i += 1) {
            try writer.writeByte(' ');
        }
    }
    fn increaseIndent(self: *WatEncoder) void {
        self.indent += 2;
    }

    fn decreaseIndent(self: *WatEncoder) void {
        self.indent -= 2;
    }
};
