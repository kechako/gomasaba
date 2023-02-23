const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const mod = @import("./mod.zig");

const Context = @import("runtime/context.zig").Context;
const Stack = @import("runtime/stack.zig").Stack;

pub const VM = struct {
    allocator: std.mem.Allocator,
    module: mod.Module,

    pub fn init(allocator: Allocator, module: mod.Module) VM {
        return .{ .allocator = allocator, .module = module };
    }

    pub fn callFunction(self: *VM, name: []const u8) !Value {
        _ = name;

        const ctx = try self.initVM();
        _ = ctx;

        return .{
            .i32 = 0,
        };
    }

    fn initVM(self: *VM) !Context {
        const ctx = Context.init(self.allocator);

        return ctx;
    }
};

pub const Value = @import("runtime/stack.zig").Value;
