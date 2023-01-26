const std = @import("std");
const process = std.process;
const Allocator = std.mem.Allocator;
const mod = @import("./mod.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var iter = try process.ArgIterator.initWithAllocator(arena.allocator());
    _ = iter.next(); // exec args

    const sub_cmd = iter.next();
    if (sub_cmd) |cmd| {
        if (std.mem.eql(u8, cmd, "run"))
            try run(&iter, arena.allocator())
        else if (std.mem.eql(u8, cmd, "dump"))
            try dump(&iter, arena.allocator())
        else
            return error.InvalidSubCommand;
    } else return error.SubCommandNotSpecified;
}

fn run(iter: *process.ArgIterator, allocator: Allocator) !void {
    const name = iter.next() orelse null;
    if (name == null) {
        return error.FileNameNotSpecified;
    }

    const m = try loadWasm(name.?, allocator);
    _ = m;
}

fn dump(iter: *process.ArgIterator, allocator: Allocator) !void {
    const name = iter.next() orelse null;
    if (name == null) {
        return error.FileNameNotSpecified;
    }

    const m = try loadWasm(name.?, allocator);

    const stdout = std.io.getStdOut();

    var enc = mod.WatEncoder.init();
    try enc.encode(stdout.writer(), m);
}

fn loadWasm(name: []const u8, allocator: Allocator) !mod.Module {
    //const file = try std.fs.openFileAbsolute(name.?, .{});
    const file = try std.fs.cwd().openFile(name, .{});
    defer file.close();

    return try mod.Decoder.init(allocator).decode(file.reader());
}
