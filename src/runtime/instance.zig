const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const mod = @import("../mod.zig");
const expr = mod.expr;
const instr = mod.instr;

pub const ModuleInstance = struct {
    allocator: Allocator,
    module: mod.Module,
    functions: []const FunctionInstance,
    start: ?StartInstance,
    exports: []const ExportInstance,

    pub fn init(allocator: Allocator, module: mod.Module) !ModuleInstance {
        return .{
            .allocator = allocator,
            .module = module,
            .functions = try initFunctions(allocator, module),
            .start = initStart(module),
            .exports = try initExports(allocator, module),
        };
    }

    pub fn deinit(self: *ModuleInstance) void {
        self.allocator.free(self.functions);
        self.allocator.free(self.exports);
    }

    fn initFunctions(allocator: Allocator, module: mod.Module) ![]const FunctionInstance {
        var functions: []FunctionInstance = &[_]FunctionInstance{};
        const funcSec = module.function_section orelse return functions;
        const codeSec = module.code_section orelse return error.CodeSectionNotFound;
        const typeSec = module.type_section orelse return error.TypeSectionNotFound;

        if (funcSec.type_indexes.len != codeSec.codes.len) {
            return error.MismatchCodeSection;
        }

        functions = try allocator.alloc(FunctionInstance, funcSec.type_indexes.len);
        for (funcSec.type_indexes) |idx, i| {
            if (idx >= typeSec.function_types.len) {
                return error.InvalidFunctionAddress;
            }

            functions[i] = .{
                .function_type = typeSec.function_types[idx],
                .code = codeSec.codes[i],
            };
        }

        return functions;
    }

    fn initStart(module: mod.Module) ?StartInstance {
        const sec = module.start_section orelse return null;

        return .{
            .function_index = sec.start.function_index,
        };
    }

    fn initExports(allocator: Allocator, module: mod.Module) ![]const ExportInstance {
        var exports: []ExportInstance = &[_]ExportInstance{};
        const exportSec = module.export_section orelse return exports;

        exports = try allocator.alloc(ExportInstance, exportSec.exports.len);
        for (exportSec.exports) |exp, i| {
            exports[i] = .{
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

    pub fn findFunctionInstance(self: ModuleInstance, name: []const u8) !FunctionInstance {
        const exp = try self.findExport(name);
        const idx = switch (exp.value) {
            .function => |f| f,
            else => return error.FunctionNotFound,
        };

        return try self.getFunctionInstance(idx);
    }

    pub fn getFunctionInstance(self: ModuleInstance, idx: u32) !FunctionInstance {
        if (self.functions.len <= idx) {
            return error.FunctionNotFound;
        }
        return self.functions[idx];
    }

    fn findExport(self: ModuleInstance, name: []const u8) !ExportInstance {
        for (self.exports) |exp| {
            if (mem.eql(u8, name, exp.name)) {
                return exp;
            }
        }
        return error.ExportNotFound;
    }
};

pub const FunctionInstance = struct {
    function_type: mod.FunctionType,
    code: mod.Code,
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
