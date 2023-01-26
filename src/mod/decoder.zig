const std = @import("std");
const Allocator = std.mem.Allocator;
const mod = @import("../mod.zig");
const leb128 = mod.leb128;
const expr = mod.expr;

pub const Decoder = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Decoder {
        return .{
            .allocator = allocator,
        };
    }

    pub fn decode(self: Decoder, reader: anytype) !mod.Module {
        try self.readMagic(reader);

        const version = try self.readVersion(reader);

        var m = try self.readSections(reader);
        m.version = version;

        return m;
    }

    const binaryMagic: u32 = 0x6d736100;

    fn readMagic(_: Decoder, reader: anytype) !void {
        const magic = try reader.readInt(u32, std.builtin.Endian.Little);

        if (magic != binaryMagic) {
            return error.InvalidMagic;
        }
    }

    const binaryVersion: u32 = 0x00000001;

    fn readVersion(_: Decoder, reader: anytype) !u32 {
        const version = try reader.readInt(u32, std.builtin.Endian.Little);
        if (version != binaryVersion) {
            return error.UnsupportedVersion;
        }
        return version;
    }

    fn readSections(self: Decoder, reader: anytype) !mod.Module {
        var custom_sections = std.ArrayList(mod.CustomSection).init(self.allocator);
        defer custom_sections.deinit();

        var type_section: ?mod.TypeSection = null;
        var import_section: ?mod.ImportSection = null;
        var function_section: ?mod.FunctionSection = null;
        var table_section: ?mod.TableSection = null;
        var memory_section: ?mod.MemorySection = null;
        var global_section: ?mod.GlobalSection = null;
        var export_section: ?mod.ExportSection = null;
        var start_section: ?mod.StartSection = null;
        var code_section: ?mod.CodeSection = null;

        while (true) {
            var id: mod.SectionCode = undefined;
            var size: u32 = undefined;
            self.readSectionHeader(reader, &id, &size) catch |err| {
                if (err == error.EndOfStream) {
                    break;
                }
                return err;
            };
            if (size == 0) {
                continue;
            }

            var lr = std.io.limitedReader(reader, size);
            var limited = lr.reader();
            switch (id) {
                .Custom => {
                    const sec = try self.readCustomSection(&lr);
                    try custom_sections.append(sec);
                },
                .Type => {
                    type_section = try self.readTypeSection(limited);
                },
                .Import => {
                    import_section = try self.readImportSection(limited);
                },
                .Function => {
                    function_section = try self.readFunctionSection(limited);
                },
                .Table => {
                    table_section = try self.readTableSection(limited);
                },
                .Memory => {
                    memory_section = try self.readMemorySection(limited);
                },
                .Global => {
                    global_section = try self.readGlobalSection(limited);
                },
                .Export => {
                    export_section = try self.readExportSection(limited);
                },
                .Start => {
                    start_section = try self.readStartSection(limited);
                },
                .Code => {
                    code_section = try self.readCodeSection(limited);
                },
                else => {
                    // unsupported sections
                    const buf = try self.allocator.alloc(u8, size);
                    defer self.allocator.free(buf);
                    _ = try reader.readAll(buf);
                    std.debug.print("section: {x:0>2}, size: {d}\n", .{ id, size });
                },
            }
        }

        return .{
            .version = 0,
            .custom_sections = custom_sections.toOwnedSlice(),
            .type_section = type_section,
            .import_section = import_section,
            .function_section = function_section,
            .table_section = table_section,
            .memory_section = memory_section,
            .global_section = global_section,
            .export_section = export_section,
            .start_section = start_section,
            .code_section = code_section,
        };
    }

    fn readSectionHeader(self: Decoder, reader: anytype, id: *mod.SectionCode, size: *u32) !void {
        const b = try reader.readByte();
        id.* = try mod.SectionCode.fromInt(b);
        size.* = try self.readUnsigned(u32, reader);
    }

    fn readCustomSection(self: Decoder, limited_reader: anytype) !mod.CustomSection {
        const name = try self.readName(limited_reader.reader());
        var bytes = try self.allocator.alloc(u8, limited_reader.bytes_left);
        _ = try limited_reader.reader().readAll(bytes);
        return .{
            .name = name,
            .bytes = bytes,
        };
    }

    fn readTypeSection(self: Decoder, reader: anytype) !mod.TypeSection {
        const size = try self.readUnsigned(u32, reader);

        const func_types = try self.allocator.alloc(mod.FunctionType, size);
        var i: usize = 0;
        while (i < func_types.len) : (i += 1) {
            func_types[i] = try self.readFunctionType(reader);
        }

        return .{
            .function_types = func_types,
        };
    }

    const funcTypeByte: u8 = 0x60;

    fn readFunctionType(self: Decoder, reader: anytype) !mod.FunctionType {
        const b = try reader.readByte();
        if (b != funcTypeByte) {
            return error.InvalidFunctionTypeEncoding;
        }

        const parameter_types = try self.readValueTypes(reader);
        const result_types = try self.readValueTypes(reader);

        return .{
            .parameter_types = parameter_types,
            .result_types = result_types,
        };
    }

    fn readValueTypes(self: Decoder, reader: anytype) ![]mod.ValueType {
        const size = try self.readUnsigned(u32, reader);

        if (size == 0) {
            return &[_]mod.ValueType{};
        }

        const value_types = try self.allocator.alloc(mod.ValueType, size);
        var i: usize = 0;
        while (i < value_types.len) : (i += 1) {
            value_types[i] = try self.readValueType(reader);
        }

        return value_types;
    }

    fn readValueType(self: Decoder, reader: anytype) !mod.ValueType {
        const n = try self.readSigned(i8, reader);
        return try mod.ValueType.fromInt(n);
    }

    fn readImportSection(self: Decoder, reader: anytype) !mod.ImportSection {
        const size = try self.readUnsigned(u32, reader);

        const imports = try self.allocator.alloc(mod.Import, size);
        var i: usize = 0;
        while (i < imports.len) : (i += 1) {
            imports[i] = try self.readImport(reader);
        }

        return .{
            .imports = imports,
        };
    }

    fn readImport(self: Decoder, reader: anytype) !mod.Import {
        const module = try self.readName(reader);
        const name = try self.readName(reader);

        const b = try reader.readByte();
        const descType = try mod.ImportDescriptionType.fromInt(b);

        var desc: mod.ImportDescription = undefined;
        switch (descType) {
            .function => {
                const idx = try self.readUnsigned(u32, reader);
                desc = .{
                    .function = .{
                        .type_index = idx,
                    },
                };
            },
            .table => {
                const typ = try self.readTableType(reader);
                desc = .{
                    .table = .{
                        .table_type = typ,
                    },
                };
            },
            .memory => {
                const typ = try self.readMemoryType(reader);
                desc = .{
                    .memory = .{
                        .memory_type = typ,
                    },
                };
            },
            .global => {
                const typ = try self.readGlobalType(reader);
                desc = .{
                    .global = .{
                        .global_type = typ,
                    },
                };
            },
            else => return error.UnsupportedImportDescription,
        }

        return .{
            .module = module,
            .name = name,
            .description = desc,
        };
    }

    fn readName(self: Decoder, reader: anytype) ![]u8 {
        const size = try self.readUnsigned(u32, reader);
        if (size == 0) {
            return "";
        }

        const buf = try self.allocator.alloc(u8, size);
        _ = try reader.readAll(buf);

        return buf;
    }

    fn readFunctionSection(self: Decoder, reader: anytype) !mod.FunctionSection {
        const size = try self.readUnsigned(u32, reader);

        const type_indexes = try self.allocator.alloc(u32, size);
        var i: usize = 0;
        while (i < type_indexes.len) : (i += 1) {
            const idx = try self.readUnsigned(u32, reader);
            type_indexes[i] = idx;
        }

        return .{
            .type_indexes = type_indexes,
        };
    }

    fn readTableSection(self: Decoder, reader: anytype) !mod.TableSection {
        const size = try self.readUnsigned(u32, reader);

        const tables = try self.allocator.alloc(mod.Table, size);
        var i: usize = 0;
        while (i < tables.len) : (i += 1) {
            tables[i] = try self.readTable(reader);
        }

        return .{
            .tables = tables,
        };
    }

    fn readTable(self: Decoder, reader: anytype) !mod.Table {
        const typ = try self.readTableType(reader);

        return .{
            .table_type = typ,
        };
    }

    fn readTableType(self: Decoder, reader: anytype) !mod.TableType {
        const typ = try self.readValueType(reader);
        if (!typ.isReferenceType()) {
            return error.InvalidReferenceType;
        }
        const limits = try self.readLimits(reader);

        return .{
            .reftype = typ,
            .limits = limits,
        };
    }

    fn readMemorySection(self: Decoder, reader: anytype) !mod.MemorySection {
        const size = try self.readUnsigned(u32, reader);

        const memories = try self.allocator.alloc(mod.Memory, size);
        var i: usize = 0;
        while (i < memories.len) : (i += 1) {
            memories[i] = try self.readMemory(reader);
        }

        return .{
            .memories = memories,
        };
    }

    fn readMemory(self: Decoder, reader: anytype) !mod.Memory {
        const typ = try self.readMemoryType(reader);

        return .{
            .memory_type = typ,
        };
    }

    fn readMemoryType(self: Decoder, reader: anytype) !mod.MemoryType {
        const limits = try self.readLimits(reader);

        return .{
            .limits = limits,
        };
    }

    fn readLimits(self: Decoder, reader: anytype) !mod.Limits {
        const b = try reader.readByte();
        const flag = try mod.LimitsFlag.fromInt(b);

        const min = try self.readUnsigned(u32, reader);

        var max: u32 = 0;
        if (flag == .max_present) {
            max = try self.readUnsigned(u32, reader);
        }

        return .{
            .flag = flag,
            .min = min,
            .max = max,
        };
    }

    fn readGlobalSection(self: Decoder, reader: anytype) !mod.GlobalSection {
        const size = try self.readUnsigned(u32, reader);

        const globals = try self.allocator.alloc(mod.Global, size);
        var i: usize = 0;
        while (i < globals.len) : (i += 1) {
            globals[i] = try self.readGlobal(reader);
        }

        return .{
            .globals = globals,
        };
    }

    fn readGlobal(self: Decoder, reader: anytype) !mod.Global {
        const typ = try self.readGlobalType(reader);

        const expressions = try self.readConstantExpressions(reader, typ.type);

        return .{
            .global_type = typ,
            .expressions = expressions,
        };
    }

    fn readGlobalType(self: Decoder, reader: anytype) !mod.GlobalType {
        const typ = try self.readValueType(reader);

        const b = try reader.readByte();
        const flag = try mod.Mutability.fromInt(b);

        return .{
            .type = typ,
            .flag = flag,
        };
    }

    fn readConstantExpressions(self: Decoder, reader: anytype, typ: mod.ValueType) ![]u8 {
        var list = std.ArrayList(u8).init(self.allocator);
        var tr = mod.teeReader(reader, list.writer());

        try expr.skipConstantExpression(tr.reader(), typ);

        const expressions = list.toOwnedSlice();
        return expressions;
    }

    fn readExportSection(self: Decoder, reader: anytype) !mod.ExportSection {
        const size = try self.readUnsigned(u32, reader);

        const exports = try self.allocator.alloc(mod.Export, size);
        var i: usize = 0;
        while (i < exports.len) : (i += 1) {
            exports[i] = try self.readExport(reader);
        }

        return .{
            .exports = exports,
        };
    }

    fn readExport(self: Decoder, reader: anytype) !mod.Export {
        const name = try self.readName(reader);

        const b = try reader.readByte();
        const descType = try mod.ExportDescriptionType.fromInt(b);

        const idx = try self.readUnsigned(u32, reader);

        const desc: mod.ExportDescription = switch (descType) {
            .function => .{
                .function = .{
                    .function_index = idx,
                },
            },
            .table => .{
                .table = .{
                    .table_index = idx,
                },
            },
            .memory => .{
                .memory = .{
                    .memory_index = idx,
                },
            },
            .global => .{
                .global = .{
                    .global_index = idx,
                },
            },
            else => return error.UnsupportedExportDescription,
        };

        return .{
            .name = name,
            .description = desc,
        };
    }

    fn readStartSection(self: Decoder, reader: anytype) !mod.StartSection {
        const start = try self.readStart(reader);

        return .{
            .start = start,
        };
    }

    fn readStart(self: Decoder, reader: anytype) !mod.Start {
        const idx = try self.readUnsigned(u32, reader);

        return .{
            .function_index = idx,
        };
    }

    fn readCodeSection(self: Decoder, reader: anytype) !mod.CodeSection {
        const size = try self.readUnsigned(u32, reader);

        const codes = try self.allocator.alloc(mod.Code, size);
        var i: usize = 0;
        while (i < codes.len) : (i += 1) {
            codes[i] = try self.readCode(reader);
        }

        return .{
            .codes = codes,
        };
    }

    fn readCode(self: Decoder, reader: anytype) !mod.Code {
        const size = try self.readUnsigned(u32, reader);

        var limited = std.io.limitedReader(reader, size);

        const locals = try self.readLocals(limited.reader());

        const expression = try self.allocator.alloc(u8, limited.bytes_left);
        _ = try limited.reader().readAll(expression);

        return .{
            .locals = locals,
            .expressions = expression,
        };
    }

    fn readLocals(self: Decoder, reader: anytype) !mod.Locals {
        return try self.readValueTypes(reader);
    }

    fn readUnsigned(_: Decoder, comptime T: type, reader: anytype) !T {
        var v: T = undefined;
        _ = try leb128.readUnsigned(T, reader, &v);
        return v;
    }

    fn readSigned(_: Decoder, comptime T: type, reader: anytype) !T {
        var v: T = undefined;
        _ = try leb128.readSigned(T, reader, &v);
        return v;
    }
};
