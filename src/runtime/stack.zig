const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const test_allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectFmt = std.testing.expectFmt;
const mod = @import("../mod.zig");
const expr = mod.expr;

const ModuleInstance = @import("./instance.zig").ModuleInstance;
const FunctionInstance = @import("./instance.zig").FunctionInstance;

pub const Stack = struct {
    entries: ArrayList(Entry),

    pub fn init(allocator: Allocator) Stack {
        const entries = ArrayList(Entry).init(allocator);
        return .{ .entries = entries };
    }

    pub fn deinit(self: *Stack) void {
        self.entries.deinit();
    }

    pub fn push(self: *Stack, entry: Entry) !void {
        try self.entries.append(entry);
    }

    pub fn pushValue(self: *Stack, value: Value) !void {
        try self.push(.{ .value = value });
    }

    pub fn pushLabel(self: *Stack, label: Label) !void {
        try self.push(.{ .label = label });
    }

    pub fn pushFrame(self: *Stack, frame: Frame) !void {
        try self.push(.{ .frame = frame });
    }

    pub fn pop(self: *Stack) !Entry {
        if (self.entries.items.len > 0) {
            return self.entries.pop();
        }
        return error.StackUnderflow;
    }

    pub fn popValue(self: *Stack) !Value {
        const entry = try self.pop();
        return switch (entry) {
            .value => |v| v,
            else => error.ValueNotFound,
        };
    }

    pub fn popLabel(self: *Stack) !Label {
        const entry = try self.pop();
        if (entry == .label) {
            return entry.label;
        }
        return error.LabelNotFound;
    }

    pub fn popFrame(self: *Stack) !Frame {
        const entry = try self.pop();
        if (entry == .frame) {
            return entry.frame;
        }
        return error.FrameNotFound;
    }

    pub fn peek(self: Stack, depth: usize) !Entry {
        const len = self.entries.items.len;
        if (len > depth) {
            return self.entries.items[len - 1 - depth];
        }
        return error.StackUnderflow;
    }

    pub fn peekValue(self: *Stack, depth: usize) !Value {
        const entry = try self.peek(depth);
        return switch (entry) {
            .value => |v| v,
            else => error.ValueNotFound,
        };
    }

    pub fn peekLabel(self: *Stack, depth: usize) !Label {
        const entry = try self.peek(depth);
        return switch (entry) {
            .label => |l| l,
            else => error.LabelNotFound,
        };
    }

    pub fn peekFrame(self: *Stack, depth: usize) !Frame {
        const entry = try self.peek(depth);
        return switch (entry) {
            .frame => |f| f,
            else => error.FrameNotFound,
        };
    }

    pub fn currentLabel(self: Stack) !Label {
        const len = self.entries.items.len;
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const entry = self.entries.items[len - i - 1];

            if (entry == .label) {
                return entry.label;
            }
        }

        return error.LabelNotFound;
    }

    pub fn currentFrame(self: Stack) !Frame {
        const len = self.entries.items.len;
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const entry = self.entries.items[len - i - 1];

            if (entry == .frame) {
                return entry.frame;
            }
        }

        return error.FrameNotFound;
    }

    test "runtime.Stack" {
        var stack = Stack.init(test_allocator);
        defer stack.deinit();

        const entry1 = Entry{
            .value = Value{
                .i32 = 100,
            },
        };
        const entry2 = Entry{
            .value = Value{
                .i32 = 200,
            },
        };

        try stack.push(entry1);
        try expectEqual(@as(usize, 1), stack.entries.items.len);
        try stack.push(entry2);
        try expectEqual(@as(usize, 2), stack.entries.items.len);

        const p1 = try stack.peek(0);
        try expectEqual(entry2.value.i32, p1.value.i32);
        const p2 = try stack.peek(1);
        try expectEqual(entry1.value.i32, p2.value.i32);

        try expectError(error.StackUnderflow, stack.peek(2));

        const pp1 = try stack.pop();
        try expectEqual(entry2.value.i32, pp1.value.i32);
        const pp2 = try stack.pop();
        try expectEqual(entry1.value.i32, pp2.value.i32);

        try expectError(error.StackUnderflow, stack.pop());
    }
};

pub const Entry = union(enum) {
    value: Value,
    label: Label,
    frame: Frame,
};

pub const Value = union(enum) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        comptime var base = 10;
        comptime var case: std.fmt.Case = .lower;
        if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
            base = 10;
            case = .lower;
        } else if (comptime std.mem.eql(u8, fmt, "x")) {
            base = 16;
            case = .lower;
        } else {
            invalidFormatError(fmt, self);
        }
        switch (self) {
            .i32 => |v| try std.fmt.formatInt(v, base, case, options, writer),
            .i64 => |v| try std.fmt.formatInt(v, base, case, options, writer),
            .f32 => |v| if (base == 16)
                try std.fmt.formatFloatHexadecimal(v, options, writer)
            else
                try std.fmt.formatFloatDecimal(v, options, writer),
            .f64 => |v| if (base == 16)
                try std.fmt.formatFloatHexadecimal(v, options, writer)
            else
                try std.fmt.formatFloatDecimal(v, options, writer),
        }
    }

    test "runtime.Value.format()" {
        try expectFmt("12345", "{}", .{Value{ .i32 = 12345 }});
        try expectFmt("12345", "{}", .{Value{ .i64 = 12345 }});
        try expectFmt("12345.125", "{}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("12345.125", "{}", .{Value{ .f64 = 12345.125 }});

        try expectFmt("12345", "{d}", .{Value{ .i32 = 12345 }});
        try expectFmt("12345", "{d}", .{Value{ .i64 = 12345 }});
        try expectFmt("12345.125", "{d}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("12345.125", "{d}", .{Value{ .f64 = 12345.125 }});

        try expectFmt("1234abcd", "{x}", .{Value{ .i32 = 0x1234_abcd }});
        try expectFmt("123456789abcef01", "{x}", .{Value{ .i64 = 0x1234_5678_9abc_ef01 }});
        try expectFmt("0x1.81c9p13", "{x}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("0x1.81c9p13", "{x}", .{Value{ .f64 = 12345.125 }});

        try expectFmt("    +12345", "{d: >10}", .{Value{ .i32 = 12345 }});
        try expectFmt("+12345    ", "{d: <10}", .{Value{ .i64 = 12345 }});
        try expectFmt("12345.12500", "{d:.5}", .{Value{ .f32 = 12345.125 }});
        try expectFmt("12345.13", "{d:.2}", .{Value{ .f64 = 12345.125 }});
    }
};

fn invalidFormatError(comptime fmt: []const u8, value: anytype) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
}

const StreamType = @TypeOf(std.io.fixedBufferStream(""));
const ExpressionReader = expr.ExpressionReader(StreamType.Reader);

pub const Label = struct {
    allocator: Allocator,
    stream: *StreamType,

    pub fn init(allocator: Allocator, expressions: []const u8) !Label {
        const stream = try allocator.create(StreamType);
        stream.* = std.io.fixedBufferStream(expressions);
        return .{
            .allocator = allocator,
            .stream = stream,
        };
    }

    pub fn deinit(self: *Label) void {
        self.allocator.destroy(self.stream);
    }

    pub fn reader(self: *Label) ExpressionReader {
        return expr.expressionReader(self.stream.reader());
    }
};

pub const Frame = struct {
    allocator: Allocator,
    locals: []Value,
    instance: ModuleInstance,
    functionInstance: ?FunctionInstance,

    pub fn init(allocator: Allocator, params: []const Value, locals: mod.Locals, instance: ModuleInstance, functionInstance: ?FunctionInstance) !Frame {
        return .{
            .allocator = allocator,
            .locals = try initLocals(allocator, params, locals),
            .instance = instance,
            .functionInstance = functionInstance,
        };
    }

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.locals);
    }

    fn initLocals(allocator: Allocator, params: []const Value, locals: mod.Locals) ![]Value {
        var values = try allocator.alloc(Value, params.len + locals.len);
        var i: usize = 0;
        for (params) |param| {
            values[i] = param;
            i += 1;
        }
        for (locals) |local| {
            values[i] = switch (local) {
                .i32 => .{ .i32 = 0 },
                .i64 => .{ .i64 = 0 },
                .f32 => .{ .f32 = 0 },
                .f64 => .{ .f64 = 0 },
                else => return error.UnsupportedType,
            };
            i += 1;
        }
        return values;
    }

    pub fn getLocal(self: Frame, idx: u32) !Value {
        if (idx < self.locals.len) {
            return self.locals[idx];
        }
        return error.OutOfRange;
    }

    pub fn setLocal(self: Frame, idx: u32, value: Value) !void {
        if (idx < self.locals.len) {
            self.locals[idx] = value;
        }
        return error.OutOfRange;
    }
};

test {
    _ = Stack;
    _ = Value;
    _ = Label;
    _ = Frame;
}
