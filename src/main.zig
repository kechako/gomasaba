const std = @import("std");
const io = std.io;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const build_options = @import("build_options");
const mod = @import("./mod.zig");
const runtime = @import("./runtime.zig");

const usage =
    \\Usage: gomasaba [command] [options]
    \\
    \\Commands:
    \\
    \\  run              Run WebAssembly
    \\  dump             Dump WebAssembly in text format
    \\
    \\  help             Print this help and exit
    \\  version          Print version number and exit
;

const version = "0.1.0-dev";

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    process.exit(1);
}

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();

    const arena = arena_instance.allocator();

    const args = try process.argsAlloc(arena);
    if (args.len < 2) {
        std.log.info("{s}", .{usage});
        fatal("expected command argument", .{});
    }

    const cmd = args[1];
    const cmd_args = args[2..];
    if (mem.eql(u8, cmd, "run")) {
        return runCommand(arena, cmd_args);
    } else if (mem.eql(u8, cmd, "dump")) {
        return dumpCommand(arena, cmd_args);
    } else if (mem.eql(u8, cmd, "help")) {
        return io.getStdOut().writeAll(usage);
    } else if (mem.eql(u8, cmd, "version")) {
        try std.io.getStdOut().writeAll(build_options.version ++ "\n");
    } else {
        std.log.info("{s}", .{usage});
        fatal("unknown command: {s}", .{cmd});
    }
}

fn runCommand(arena: Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        fatal("wasm file is not specified", .{});
    }

    const name = args[args.len - 1];

    const options = parseRunOptions(arena, args[0 .. args.len - 1]) catch {
        std.log.info("{s}", .{usage});
        fatal("invalid options", .{});
    };

    const m = try loadWasm(name, arena);

    var vm = try runtime.VM.init(arena, m);
    defer vm.deinit();

    var ret: runtime.VM.Result = undefined;
    if (options.invoke.len == 0) {
        ret = try vm.start();
    } else {
        ret = try vm.call(options.invoke);
    }

    for (ret.values) |value| {
        try std.io.getStdOut().writer().print("{}\n", .{value});
    }
}

const RunOptions = struct {
    invoke: []const u8,
};

fn parseRunOptions(arena: Allocator, args: []const []const u8) !RunOptions {
    var invoke: []const u8 = "";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        var arg = args[i];
        if (mem.eql(u8, arg, "--invoke")) {
            i += 1;
            if (i >= args.len) {
                return error.InvalidOptions;
            }
            invoke = try arena.dupe(u8, args[i]);
            continue;
        }

        return error.InvalidOptions;
    }

    return .{
        .invoke = invoke,
    };
}

fn dumpCommand(arena: Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        fatal("wasm file is not specified", .{});
    }

    const name = args[0];

    const m = try loadWasm(name, arena);

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

test {
    std.testing.refAllDeclsRecursive(@This());
}
