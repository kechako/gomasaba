const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const mod = @import("../mod.zig");
const instr = @import("../instr.zig");

const Module = mod.Module;
const ValueType = mod.ValueType;
const Locals = mod.Locals;
const Code = instr.Code;

pub const ModuleInstance = struct {
    allocator: Allocator,
    module: Module,
    types: ?[]TypeInstance,
    functions: ?[]FunctionInstance,
    start: ?StartInstance,
    exports: ?[]ExportInstance,

    pub fn init(allocator: Allocator, module: Module) ModuleInstance {
        return .{
            .allocator = allocator,
            .module = module,
            .types = null,
            .functions = null,
            .start = null,
            .exports = null,
        };
    }

    pub fn deinit(self: *ModuleInstance) void {
        if (self.functions) |functions| {
            self.allocator.free(functions);
        }
        if (self.exports) |exports| {
            self.allocator.free(exports);
        }
    }

    pub fn instantiate(self: *ModuleInstance) !void {
        self.types = try self.instantiateTypes();
        self.functions = try self.instantiateFunctions();
        self.start = self.instantiateStart();
        self.exports = try self.instantiateExports();
    }

    fn instantiateTypes(self: *ModuleInstance) !?[]TypeInstance {
        const module = self.module;
        const type_sec = module.type_section orelse return null;

        var types = try self.allocator.alloc(TypeInstance, type_sec.function_types.len);
        for (type_sec.function_types, types) |func_type, *typ| {
            typ.* = .{
                .parameter_types = func_type.parameter_types,
                .result_types = func_type.result_types,
            };
        }

        return types;
    }

    fn instantiateFunctions(self: *ModuleInstance) !?[]FunctionInstance {
        const module = self.module;
        const func_sec = module.function_section orelse return null;
        const code_sec = module.code_section orelse return error.CodeSectionNotFound;
        const type_sec = module.type_section orelse return error.TypeSectionNotFound;

        const func_len = func_sec.type_indexes.len;
        if (func_len != code_sec.codes.len) {
            return error.MismatchCodeSection;
        }

        var functions = try self.allocator.alloc(FunctionInstance, func_len);
        for (func_sec.type_indexes, code_sec.codes, functions) |idx, code, *func| {
            if (idx >= type_sec.function_types.len) {
                return error.InvalidFunctionAddress;
            }
            const func_type = type_sec.function_types[idx];

            func.* = .{
                .parameter_types = func_type.parameter_types,
                .result_types = func_type.result_types,
                .locals = code.locals,
                .code = code.code,
            };
        }

        return functions;
    }

    fn instantiateStart(self: *ModuleInstance) ?StartInstance {
        const sec = self.module.start_section orelse return null;

        return .{
            .function_index = sec.start.function_index,
        };
    }

    fn instantiateExports(self: *ModuleInstance) !?[]ExportInstance {
        const export_sec = self.module.export_section orelse return null;

        var exports = try self.allocator.alloc(ExportInstance, export_sec.exports.len);
        for (export_sec.exports, exports) |exp, *instance| {
            instance.* = .{
                .name = exp.name,
                .value = switch (exp.description) {
                    .function => |f| .{
                        .function = f.function_index,
                    },
                    .table => |f| .{
                        .table = f.table_index,
                    },
                    .memory => |f| .{
                        .memory = f.memory_index,
                    },
                    .global => |f| .{
                        .global = f.global_index,
                    },
                },
            };
        }

        return exports;
    }

    pub fn getType(self: *ModuleInstance, idx: u32) !*TypeInstance {
        const types = self.types orelse return error.TypeNotFound;
        if (idx < types.len) {
            return &types[idx];
        }
        return error.TypeNotFound;
    }

    pub fn findFunction(self: *ModuleInstance, name: []const u8) !*FunctionInstance {
        const exp = self.getExport(name) catch |err| {
            if (err == error.ExportNotFound) {
                return error.FunctionNotFound;
            }
            return err;
        };

        if (exp.value != .function) {
            return error.FunctionNotFound;
        }

        return try self.getFunction(exp.value.function);
    }

    pub fn getStartFunction(self: *ModuleInstance) !*FunctionInstance {
        if (self.start) |start| {
            return try self.getFunction(start.function_index);
        }

        return error.StartSectionNotFound;
    }

    pub fn getFunction(self: *ModuleInstance, idx: u32) !*FunctionInstance {
        const functions = self.functions orelse return error.FunctionNotFound;
        if (idx < functions.len) {
            return &functions[idx];
        }
        return error.FunctionNotFound;
    }

    pub fn getExport(self: *ModuleInstance, name: []const u8) !*ExportInstance {
        const exports = self.exports orelse return error.ExportNotFound;
        for (exports) |*exp| {
            if (mem.eql(u8, name, exp.name)) {
                return exp;
            }
        }
        return error.ExportNotFound;
    }
};

pub const TypeInstance = struct {
    parameter_types: []const ValueType,
    result_types: []const ValueType,
};

pub const FunctionInstance = struct {
    parameter_types: []const ValueType,
    result_types: []const ValueType,
    locals: Locals,
    code: Code,
};

pub const StartInstance = struct {
    function_index: u32,
};

pub const ExportInstance = struct {
    name: []const u8,
    value: ExportValue,
};

pub const ExportValue = union(enum) {
    function: u32,
    table: u32,
    memory: u32,
    global: u32,
};

test {
    _ = ModuleInstance;
}
