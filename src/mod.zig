const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const test_allocator = std.testing.allocator;

pub const Module = struct {
    version: u32,

    custom_sections: []const CustomSection = &[_]CustomSection{},
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
        const v = @intToEnum(SectionCode, n);
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
};

pub const TypeSection = struct {
    function_types: []const FunctionType,
};

pub const FunctionType = struct {
    parameter_types: ResultType,
    result_types: ResultType,
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

    // Type Indices
    block = 0x40,

    _,

    pub fn fromInt(n: i8) !ValueType {
        const v = @intToEnum(ValueType, n);
        return switch (v) {
            .i32, .i64, .f32, .f64, .v128, .funcref, .externref, .block => v,
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
            .block => "block",
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

test "mod.mod.ValueType.fromInt()" {
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

    // block type
    try expectEqual(ValueType.block, try ValueType.fromInt(@as(i8, 0x40)));

    // invalid value
    try expectError(error.InvalidValueType, ValueType.fromInt(@as(i8, 0x00)));
}

test "mod.mod.ValueType.format()" {
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

    const block_string = try std.fmt.allocPrint(test_allocator, "{s}", .{ValueType.block});
    defer test_allocator.free(block_string);
    try expectEqualStrings("block", block_string);
}

pub const ImportSection = struct {
    imports: []const Import,
};

pub const Import = struct {
    module: []u8,
    name: []u8,
    description: ImportDescription,
};

pub const ImportDescriptionType = enum(u8) {
    function = 0x00,
    table = 0x01,
    memory = 0x02,
    global = 0x03,
    _,

    pub fn fromInt(n: u8) !ImportDescriptionType {
        const v = @intToEnum(ImportDescriptionType, n);
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
};

pub const TableSection = struct {
    tables: []const Table,
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
        const v = @intToEnum(LimitsFlag, n);
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
};

pub const Global = struct {
    global_type: GlobalType,
    expressions: []u8,
};

pub const Mutability = enum(u8) {
    immutable = 0x00,
    mutable = 0x01,

    _,

    pub fn fromInt(n: u8) !Mutability {
        const v = @intToEnum(Mutability, n);
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
};

pub const Export = struct {
    name: []const u8,
    description: ExportDescription,
};

pub const ExportDescriptionType = enum(u8) {
    function = 0x00,
    table = 0x01,
    memory = 0x02,
    global = 0x03,
    _,

    pub fn fromInt(n: u8) !ExportDescriptionType {
        const v = @intToEnum(ExportDescriptionType, n);
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
};

pub const Code = struct {
    locals: Locals,
    expressions: []u8,
};

pub const Locals = []Local;

pub const Local = struct {
    count: u32,
    value_type: ValueType,
};

pub const DataSection = struct {
    datas: []Data,
};

pub const DataMode = packed struct {
    passive: bool,
    memory: bool,

    reserved: u30,

    pub fn fromInt(n: u32) DataMode {
        return @bitCast(DataMode, n);
    }

    pub fn toInt(self: DataMode) u32 {
        return @bitCast(u32, self);
    }
};

pub const Data = struct {
    mode: DataMode,
    memory_index: u32,
    offset: []const u8,
    data: []const u8,
};

pub const DataCountSection = struct {};

pub const Decoder = @import("mod/decoder.zig").Decoder;
pub const WatEncoder = @import("mod/encoder.zig").WatEncoder;
pub const TeeReader = @import("mod/tee_reader.zig").TeeReader;
pub const teeReader = @import("mod/tee_reader.zig").teeReader;

pub const expr = @import("mod/expr.zig");
pub const instr = @import("mod/instr.zig");
pub const leb128 = @import("mod/leb128.zig");
