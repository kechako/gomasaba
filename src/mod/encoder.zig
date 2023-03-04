const std = @import("std");
const Allocator = std.mem.Allocator;

const mod = @import("../mod.zig");
const instr = @import("../instr.zig");
const util = @import("../util.zig");

pub const WatEncoder = struct {
    allocator: Allocator,
    indent: usize,
    type_index: usize,
    func_index: usize,

    pub fn init(allocator: Allocator) WatEncoder {
        return .{
            .allocator = allocator,
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

        if (m.data_section) |sec| {
            try self.writeDataSection(writer, sec);
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

            try self.writeString(writer, imp.module);

            try writer.writeByte(' ');

            try self.writeString(writer, imp.name);

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

    fn writeString(_: *WatEncoder, writer: anytype, s: []const u8) !void {
        try writer.writeByte('"');

        const unicode = std.unicode;

        var iter = (try unicode.Utf8View.init(s)).iterator();
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

            var localIdx: usize = 0;
            for (code.locals) |local| {
                var c: usize = 0;
                while (c < local.count) : (c += 1) {
                    try self.writeIndent(writer);
                    try self.writeLocal(writer, local.value_type, localIdx);
                    localIdx += 1;
                }
            }

            try self.writeCode(writer, code.code, func_types);
        }
    }

    fn writeLocal(_: *WatEncoder, writer: anytype, local: mod.ValueType, index: usize) !void {
        try writer.print("(local (;{d};) {s})", .{ index, local });
    }

    fn writeCode(self: *WatEncoder, writer: anytype, code: instr.Code, func_types: []const mod.FunctionType) !void {
        var reader = instr.CodeReader.init(code);

        var instrStack = util.Stack(instr.Instruction).init(self.allocator);
        defer instrStack.deinit();

        var scope: usize = 1;

        while (reader.next()) |instruction| {
            if (scope == 0) {
                break;
            }

            if (instruction != .@"end" and instruction != .@"else") {
                try self.writeIndent(writer);
            }

            switch (instruction) {
                .@"block" => |b| {
                    try writer.writeAll("(block");
                    self.increaseIndent();

                    try self.writeBlockType(writer, b.block_type, func_types);

                    try instrStack.push(instruction);
                    scope += 1;
                },
                .@"loop" => |b| {
                    try writer.writeAll("(loop");
                    self.increaseIndent();

                    try self.writeBlockType(writer, b.block_type, func_types);

                    try instrStack.push(instruction);
                    scope += 1;
                },
                .@"if" => |b| {
                    try writer.writeAll("(if");
                    self.increaseIndent();

                    try self.writeBlockType(writer, b.block_type, func_types);

                    try self.writeIndent(writer);
                    try writer.writeAll("(then");
                    self.increaseIndent();

                    try instrStack.push(instruction);
                    scope += 1;
                },
                .@"else" => {
                    try writer.writeByte(')');
                    self.decreaseIndent();

                    try self.writeIndent(writer);
                    try writer.writeAll("(else");
                    self.increaseIndent();
                },
                .@"end" => {
                    scope -= 1;
                    const pushedInstr = instrStack.tryPop();

                    if (pushedInstr) |i| {
                        if (i == .@"if") {
                            try writer.writeByte(')');
                            self.decreaseIndent();
                        }
                    }
                    try writer.writeByte(')');
                    self.decreaseIndent();
                },
                .@"br" => |idx| try writer.print("br {d}", .{idx}),
                .@"br_if" => |idx| try writer.print("br_if {d}", .{idx}),
                .@"return" => try writer.writeAll("return"),
                .@"call" => |idx| try writer.print("call {d}", .{idx}),
                .@"drop" => try writer.writeAll("drop"),
                .@"local.get" => |idx| try writer.print("local.get {d}", .{idx}),
                .@"local.set" => |idx| try writer.print("local.set {d}", .{idx}),
                .@"local.tee" => |idx| try writer.print("local.tee {d}", .{idx}),
                .@"i32.const" => |v| try writer.print("i32.const {d}", .{v}),
                .@"i32.eqz" => try writer.writeAll("i32.eqz"),
                .@"i32.eq" => try writer.writeAll("i32.eq"),
                .@"i32.ne" => try writer.writeAll("i32.ne"),
                .@"i32.lt_s" => try writer.writeAll("i32.lt_s"),
                .@"i32.gt_s" => try writer.writeAll("i32.gt_s"),
                .@"i32.le_s" => try writer.writeAll("i32.le_s"),
                .@"i32.ge_s" => try writer.writeAll("i32.ge_s"),
                .@"i32.add" => try writer.writeAll("i32.add"),
                .@"i32.sub" => try writer.writeAll("i32.sub"),
                .@"i32.mul" => try writer.writeAll("i32.mul"),
                .@"i32.div_s" => try writer.writeAll("i32.div_s"),
                else => {
                    std.debug.print("op: {any}\n", .{instruction});
                    return error.UnsupportedInstruction;
                },
            }
        }
    }

    fn writeBlockType(self: *WatEncoder, writer: anytype, block_type: mod.BlockType, func_types: []const mod.FunctionType) !void {
        switch (block_type) {
            .empty => {},
            .value_type => |value_type| {
                try self.writeIndent(writer);
                try writer.print("(result {s})", .{value_type});
            },
            .type_index => |idx| {
                if (idx < 0 or idx >= func_types.len) {
                    return error.InvalidTypeIndex;
                }
                const func_type = func_types[@intCast(usize, idx)];
                for (func_type.parameter_types) |value_type| {
                    try self.writeIndent(writer);
                    try writer.print("(param {s})", .{value_type});
                }
                for (func_type.result_types) |value_type| {
                    try self.writeIndent(writer);
                    try writer.print("(result {s})", .{value_type});
                }
            },
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

            try self.writeConstantCode(writer, global.code);

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

    fn writeConstantCode(_: *WatEncoder, writer: anytype, code: instr.Code) !void {
        var reader = instr.CodeReader.init(code);
        try writer.writeByte('(');

        var first = true;
        while (reader.next()) |op| {
            if (op == .@"end") {
                break;
            }

            if (first)
                first = false
            else
                try writer.writeByte(' ');

            switch (op) {
                .@"i32.const" => |v| try writer.print("i32.const {d}", .{v}),
                .@"i64.const" => |v| try writer.print("i64.const {d}", .{v}),
                .@"f32.const" => |v| try writer.print("f32.const {d}", .{v}),
                .@"f64.const" => |v| try writer.print("f64.const {d}", .{v}),
                .@"global.get" => |idx| try writer.print("global.get {d}", .{idx}),
                else => return error.UnsupportedInstruction,
            }
        }

        try writer.writeByte(')');
    }

    fn writeExportSection(self: *WatEncoder, writer: anytype, sec: mod.ExportSection) !void {
        for (sec.exports) |exp| {
            try self.writeIndent(writer);

            try writer.writeAll("(export ");

            try self.writeString(writer, exp.name);

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

    fn writeDataSection(self: *WatEncoder, writer: anytype, sec: mod.DataSection) !void {
        for (sec.datas) |data| {
            try self.writeIndent(writer);

            try writer.writeAll("(data ");

            if (data.mode.memory) {
                try writer.print("(memory {d}) ", .{data.memory_index});
            }

            if (!data.mode.passive) {
                if (data.offset) |offset| {
                    try self.writeConstantCode(writer, offset);
                }
            }

            try writer.writeByte(' ');

            try self.writeString(writer, data.data);

            try writer.writeByte(')');
        }
    }

    fn writeData(_: *WatEncoder, writer: anytype, start: mod.Data) !void {
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
