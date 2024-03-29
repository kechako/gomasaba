const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const test_allocator = std.testing.allocator;

const instr = @import("./instr.zig");

pub const Module = struct {
    version: u32,

    custom_sections: ?[]const CustomSection = null,
    type_section: ?TypeSection = null,
    import_section: ?ImportSection = null,
    function_section: ?FunctionSection = null,
    table_section: ?TableSection = null,
    memory_section: ?MemorySection = null,
    global_section: ?GlobalSection = null,
    export_section: ?ExportSection = null,
    start_section: ?StartSection = null,
    element_section: ?ElementSection = null,
    code_section: ?CodeSection = null,
    data_section: ?DataSection = null,
    data_count_section: ?DataCountSection = null,

    pub fn free(self: Module, allocator: Allocator) void {
        if (self.custom_sections) |sections| {
            for (sections) |sec| {
                sec.free(allocator);
            }
        }
        if (self.type_section) |sec| {
            sec.free(allocator);
        }
        if (self.import_section) |sec| {
            sec.free(allocator);
        }
        if (self.function_section) |sec| {
            sec.free(allocator);
        }
        if (self.table_section) |sec| {
            sec.free(allocator);
        }
        if (self.memory_section) |sec| {
            sec.free(allocator);
        }
        if (self.global_section) |sec| {
            sec.free(allocator);
        }
        if (self.export_section) |sec| {
            sec.free(allocator);
        }
        if (self.code_section) |sec| {
            sec.free(allocator);
        }
        if (self.data_section) |sec| {
            sec.free(allocator);
        }
    }
};

pub const SectionCode = enum(u8) {
    Custom = 0,
    Type = 1,
    Import = 2,
    Function = 3,
    Table = 4,
    Memory = 5,
    Global = 6,
    Export = 7,
    Start = 8,
    Element = 9,
    Code = 10,
    Data = 11,
    CodeData = 12,
    _,

    pub fn fromInt(n: u8) !SectionCode {
        const v = @as(SectionCode, @enumFromInt(n));
        return switch (v) {
            .Custom,
            .Type,
            .Import,
            .Function,
            .Table,
            .Memory,
            .Global,
            .Export,
            .Start,
            .Element,
            .Code,
            .Data,
            .CodeData,
            => v,
            _ => error.InvalidSectionCode,
        };
    }
};

pub const CustomSection = struct {
    name: []const u8,
    bytes: []const u8,

    fn free(self: CustomSection, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.bytes);
    }
};

pub const TypeSection = struct {
    function_types: []const FunctionType,

    fn free(self: TypeSection, allocator: Allocator) void {
        for (self.function_types) |typ| {
            typ.free(allocator);
        }
        allocator.free(self.function_types);
    }
};

pub const FunctionType = struct {
    parameter_types: ResultType,
    result_types: ResultType,

    fn free(self: FunctionType, allocator: Allocator) void {
        allocator.free(self.parameter_types);
        allocator.free(self.result_types);
    }
};

pub const ResultType = []const ValueType;

pub const ValueType = enum(i8) {
    // Number Types
    i32 = -0x01,
    i64 = -0x02,
    f32 = -0x03,
    f64 = -0x04,

    // Vector Types
    v128 = -0x05,

    // Reference Type
    funcref = -0x10,
    externref = -0x11,

    _,

    pub fn fromInt(n: i8) !ValueType {
        const v = @as(ValueType, @enumFromInt(n));
        return switch (v) {
            .i32, .i64, .f32, .f64, .v128, .funcref, .externref => v,
            _ => error.InvalidValueType,
        };
    }

    pub fn format(
        self: ValueType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const s = switch (self) {
            .i32 => "i32",
            .i64 => "i64",
            .f32 => "f32",
            .f64 => "f64",
            .v128 => "v128",
            .funcref => "funcref",
            .externref => "externref",
            else => "(unknown)",
        };

        try writer.writeAll(s);
    }

    pub fn isNumberType(self: ValueType) bool {
        return switch (self) {
            .i32, .i64, .f32, .f64 => true,
            else => false,
        };
    }

    pub fn isVectorType(self: ValueType) bool {
        return switch (self) {
            .v128 => true,
            else => false,
        };
    }

    pub fn isReferenceType(self: ValueType) bool {
        return switch (self) {
            .funcref, .externref => true,
            else => false,
        };
    }
};

test "mod.ValueType.fromInt()" {
    // number types
    try expectEqual(ValueType.i32, try ValueType.fromInt(@as(i8, -0x01)));
    try expectEqual(ValueType.i64, try ValueType.fromInt(@as(i8, -0x02)));
    try expectEqual(ValueType.f32, try ValueType.fromInt(@as(i8, -0x03)));
    try expectEqual(ValueType.f64, try ValueType.fromInt(@as(i8, -0x04)));

    // vector types
    try expectEqual(ValueType.v128, try ValueType.fromInt(@as(i8, -0x05)));

    // reference types
    try expectEqual(ValueType.funcref, try ValueType.fromInt(@as(i8, -0x10)));
    try expectEqual(ValueType.externref, try ValueType.fromInt(@as(i8, -0x11)));

    // invalid value
    try expectError(error.InvalidValueType, ValueType.fromInt(@as(i8, 0x00)));
}

test "mod.ValueType.format()" {
    const i32_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.i32});
    defer test_allocator.free(i32_string);
    try expectEqualStrings("i32", i32_string);

    const i64_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.i64});
    defer test_allocator.free(i64_string);
    try expectEqualStrings("i64", i64_string);

    const f32_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.f32});
    defer test_allocator.free(f32_string);
    try expectEqualStrings("f32", f32_string);

    const f64_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.f64});
    defer test_allocator.free(f64_string);
    try expectEqualStrings("f64", f64_string);

    const v128_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.v128});
    defer test_allocator.free(v128_string);
    try expectEqualStrings("v128", v128_string);

    const funcref_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.funcref});
    defer test_allocator.free(funcref_string);
    try expectEqualStrings("funcref", funcref_string);

    const externref_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.externref});
    defer test_allocator.free(externref_string);
    try expectEqualStrings("externref", externref_string);
}

pub const BlockType = union(enum) {
    empty: void,
    value_type: ValueType,
    type_index: i33,
};

pub const ImportSection = struct {
    imports: []const Import,

    fn free(self: ImportSection, allocator: Allocator) void {
        for (self.imports) |import| {
            import.free(allocator);
        }
        allocator.free(self.imports);
    }
};

pub const Import = struct {
    module: []u8,
    name: []u8,
    description: ImportDescription,

    fn free(self: Import, allocator: Allocator) void {
        allocator.free(self.module);
        allocator.free(self.name);
    }
};

pub const ImportDescriptionType = enum(u8) {
    function = 0x00,
    table = 0x01,
    memory = 0x02,
    global = 0x03,
    _,

    pub fn fromInt(n: u8) !ImportDescriptionType {
        const v = @as(ImportDescriptionType, @enumFromInt(n));
        return switch (v) {
            .function, .table, .memory, .global => v,
            _ => error.InvalidImportDescriptionType,
        };
    }
};

pub const ImportDescription = union(ImportDescriptionType) {
    function: FunctionImport,
    table: TableImport,
    memory: MemoryImport,
    global: GlobalImport,
};

pub const FunctionImport = struct {
    type_index: u32,
};

pub const TableImport = struct {
    table_type: TableType,
};

pub const MemoryImport = struct {
    memory_type: MemoryType,
};

pub const GlobalImport = struct {
    global_type: GlobalType,
};

pub const FunctionSection = struct {
    type_indexes: []u32,

    fn free(self: FunctionSection, allocator: Allocator) void {
        allocator.free(self.type_indexes);
    }
};

pub const TableSection = struct {
    tables: []const Table,

    fn free(self: TableSection, allocator: Allocator) void {
        allocator.free(self.tables);
    }
};

pub const Table = struct {
    table_type: TableType,
};

pub const TableType = struct {
    reftype: ValueType,
    limits: Limits,
};

pub const MemorySection = struct {
    memories: []Memory,

    fn free(self: MemorySection, allocator: Allocator) void {
        allocator.free(self.memories);
    }
};

pub const Memory = struct {
    memory_type: MemoryType,
};
pub const MemoryType = struct {
    limits: Limits,
};

pub const LimitsFlag = enum(u8) {
    min_only = 0x00,
    max_present = 0x01,
    _,

    pub fn fromInt(n: u8) !LimitsFlag {
        const v = @as(LimitsFlag, @enumFromInt(n));
        return switch (v) {
            .min_only, .max_present => v,
            _ => error.InvalidLimitsFlag,
        };
    }
};

pub const Limits = struct {
    flag: LimitsFlag,
    min: u32,
    max: u32,
};

pub const GlobalSection = struct {
    globals: []Global,

    fn free(self: GlobalSection, allocator: Allocator) void {
        for (self.globals) |global| {
            global.free(allocator);
        }
        allocator.free(self.globals);
    }
};

pub const Global = struct {
    global_type: GlobalType,
    code: instr.Code,

    fn free(self: Global, allocator: Allocator) void {
        allocator.free(self.code);
    }
};

pub const Mutability = enum(u8) {
    immutable = 0x00,
    mutable = 0x01,

    _,

    pub fn fromInt(n: u8) !Mutability {
        const v = @as(Mutability, @enumFromInt(n));
        return switch (v) {
            .immutable, .mutable => v,
            _ => error.InvalidMutability,
        };
    }
};

pub const GlobalType = struct {
    type: ValueType,
    flag: Mutability,
};

pub const ExportSection = struct {
    exports: []const Export,

    fn free(self: ExportSection, allocator: Allocator) void {
        for (self.exports) |exp| {
            exp.free(allocator);
        }
        allocator.free(self.exports);
    }
};

pub const Export = struct {
    name: []const u8,
    description: ExportDescription,

    fn free(self: Export, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const ExportDescriptionType = enum(u8) {
    function = 0x00,
    table = 0x01,
    memory = 0x02,
    global = 0x03,
    _,

    pub fn fromInt(n: u8) !ExportDescriptionType {
        const v = @as(ExportDescriptionType, @enumFromInt(n));
        return switch (v) {
            .function, .table, .memory, .global => v,
            _ => error.InvalidExportDescriptionType,
        };
    }
};

pub const ExportDescription = union(ExportDescriptionType) {
    function: FunctionExport,
    table: TableExport,
    memory: MemoryExport,
    global: GlobalExport,
};

pub const FunctionExport = struct {
    function_index: u32,
};

pub const TableExport = struct {
    table_index: u32,
};

pub const MemoryExport = struct {
    memory_index: u32,
};

pub const GlobalExport = struct {
    global_index: u32,
};

pub const StartSection = struct {
    start: Start,
};

pub const Start = struct {
    function_index: u32,
};

pub const ElementSection = struct {};

pub const CodeSection = struct {
    codes: []Code,

    fn free(self: CodeSection, allocator: Allocator) void {
        for (self.codes) |code| {
            code.free(allocator);
        }
        allocator.free(self.codes);
    }
};

pub const Code = struct {
    locals: Locals,
    code: instr.Code,

    fn free(self: Code, allocator: Allocator) void {
        allocator.free(self.locals);
        allocator.free(self.code);
    }
};

pub const Locals = []Local;

pub const Local = struct {
    count: u32,
    value_type: ValueType,
};

pub const DataSection = struct {
    datas: []Data,

    fn free(self: DataSection, allocator: Allocator) void {
        for (self.datas) |data| {
            data.free(allocator);
        }
        allocator.free(self.datas);
    }
};

pub const DataMode = packed struct {
    passive: bool,
    memory: bool,

    reserved: u30,

    pub fn fromInt(n: u32) DataMode {
        return @as(DataMode, @bitCast(n));
    }

    pub fn toInt(self: DataMode) u32 {
        return @as(u32, @bitCast(self));
    }
};

pub const Data = struct {
    mode: DataMode,
    memory_index: u32,
    offset: ?instr.Code,
    data: []const u8,

    fn free(self: Data, allocator: Allocator) void {
        if (self.offset) |offset| {
            allocator.free(offset);
        }
        allocator.free(self.data);
    }
};

pub const DataCountSection = struct {};

pub const Decoder = @import("mod/decoder.zig").Decoder;
pub const WatEncoder = @import("mod/encoder.zig").WatEncoder;

test {
    std.testing.refAllDecls(@This());
}
