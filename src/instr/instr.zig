const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const mod = @import("../mod.zig");
const BlockType = mod.BlockType;

pub const Opecode = enum(u8) {
    Prefix = 0xfc,

    // ==== Control Instructions ====
    @"unreachable" = 0x00,
    @"nop" = 0x01,
    @"block" = 0x02,
    @"loop" = 0x03,
    @"if" = 0x04,
    @"else" = 0x05,
    @"end" = 0x0b,
    @"br" = 0x0c,
    @"br_if" = 0x0d,
    @"br_table" = 0x0e,
    @"return" = 0x0f,
    @"call" = 0x10,
    @"call_indirect" = 0x11,

    // ==== Reference Instructions ====
    @"ref.null" = 0xd0,
    @"ref.is_null" = 0xd1,
    @"ref.func" = 0xd2,

    // ==== Parametric Instructions ====
    @"drop" = 0x1a,
    @"select" = 0x1b,
    @"select_types" = 0x1c,

    // ==== Variable Instructions ====
    @"local.get" = 0x20,
    @"local.set" = 0x21,
    @"local.tee" = 0x22,
    @"global.get" = 0x23,
    @"global.set" = 0x24,

    // ==== Table Instructions ====
    @"table.get" = 0x25,
    @"table.set" = 0x26,

    // ==== Memory Instructions ====
    @"i32.load" = 0x28,
    @"i64.load" = 0x29,
    @"f32.load" = 0x2a,
    @"f64.load" = 0x2b,
    @"i32.load8_s" = 0x2c,
    @"i32.load8_u" = 0x2d,
    @"i32.load16_s" = 0x2e,
    @"i32.load16_u" = 0x2f,
    @"i64.load8_s" = 0x30,
    @"i64.load8_u" = 0x31,
    @"i64.load16_s" = 0x32,
    @"i64.load16_u" = 0x33,
    @"i64.load32_s" = 0x34,
    @"i64.load32_u" = 0x35,
    @"i32.store" = 0x36,
    @"i64.store" = 0x37,
    @"f32.store" = 0x38,
    @"f64.store" = 0x39,
    @"i32.store8" = 0x3a,
    @"i32.store16" = 0x3b,
    @"i64.store8" = 0x3c,
    @"i64.store16" = 0x3d,
    @"i64.store32" = 0x3e,
    @"memory.size" = 0x3f,
    @"memory.grow" = 0x40,

    // ==== Numeric Instructions ====
    @"i32.const" = 0x41,
    @"i64.const" = 0x42,
    @"f32.const" = 0x43,
    @"f64.const" = 0x44,

    @"i32.eqz" = 0x45,
    @"i32.eq" = 0x46,
    @"i32.ne" = 0x47,
    @"i32.lt_s" = 0x48,
    @"i32.lt_u" = 0x49,
    @"i32.gt_s" = 0x4a,
    @"i32.gt_u" = 0x4b,
    @"i32.le_s" = 0x4c,
    @"i32.le_u" = 0x4d,
    @"i32.ge_s" = 0x4e,
    @"i32.ge_u" = 0x4f,

    @"i64.eqz" = 0x50,
    @"i64.eq" = 0x51,
    @"i64.ne" = 0x52,
    @"i64.lt_s" = 0x53,
    @"i64.lt_u" = 0x54,
    @"i64.gt_s" = 0x55,
    @"i64.gt_u" = 0x56,
    @"i64.le_s" = 0x57,
    @"i64.le_u" = 0x58,
    @"i64.ge_s" = 0x59,
    @"i64.ge_u" = 0x5a,

    @"f32.eq" = 0x5b,
    @"f32.ne" = 0x5c,
    @"f32.lt" = 0x5d,
    @"f32.gt" = 0x5e,
    @"f32.le" = 0x5f,
    @"f32.ge" = 0x60,

    @"f64.eq" = 0x61,
    @"f64.ne" = 0x62,
    @"f64.lt" = 0x63,
    @"f64.gt" = 0x64,
    @"f64.le" = 0x65,
    @"f64.ge" = 0x66,

    @"i32.clz" = 0x67,
    @"i32.ctz" = 0x68,
    @"i32.popcnt" = 0x69,
    @"i32.add" = 0x6a,
    @"i32.sub" = 0x6b,
    @"i32.mul" = 0x6c,
    @"i32.div_s" = 0x6d,
    @"i32.div_u" = 0x6e,
    @"i32.rem_s" = 0x6f,
    @"i32.rem_u" = 0x70,
    @"i32.and" = 0x71,
    @"i32.or" = 0x72,
    @"i32.xor" = 0x73,
    @"i32.shl" = 0x74,
    @"i32.shr_s" = 0x75,
    @"i32.shr_u" = 0x76,
    @"i32.rotl" = 0x77,
    @"i32.rotr" = 0x78,

    @"i64.clz" = 0x79,
    @"i64.ctz" = 0x7a,
    @"i64.popcnt" = 0x7b,
    @"i64.add" = 0x7c,
    @"i64.sub" = 0x7d,
    @"i64.mul" = 0x7e,
    @"i64.div_s" = 0x7f,
    @"i64.div_u" = 0x80,
    @"i64.rem_s" = 0x81,
    @"i64.rem_u" = 0x82,
    @"i64.and" = 0x83,
    @"i64.or" = 0x84,
    @"i64.xor" = 0x85,
    @"i64.shl" = 0x86,
    @"i64.shr_s" = 0x87,
    @"i64.shr_u" = 0x88,
    @"i64.rotl" = 0x89,
    @"i64.rotr" = 0x8a,

    @"f32.abs" = 0x8b,
    @"f32.neg" = 0x8c,
    @"f32.ceil" = 0x8d,
    @"f32.floor" = 0x8e,
    @"f32.trunc" = 0x8f,
    @"f32.nearest" = 0x90,
    @"f32.sqrt" = 0x91,
    @"f32.add" = 0x92,
    @"f32.sub" = 0x93,
    @"f32.mul" = 0x94,
    @"f32.div" = 0x95,
    @"f32.min" = 0x96,
    @"f32.max" = 0x97,
    @"f32.copysign" = 0x98,

    @"f64.abs" = 0x99,
    @"f64.neg" = 0x9a,
    @"f64.ceil" = 0x9b,
    @"f64.floor" = 0x9c,
    @"f64.trunc" = 0x9d,
    @"f64.nearest" = 0x9e,
    @"f64.sqrt" = 0x9f,
    @"f64.add" = 0xa0,
    @"f64.sub" = 0xa1,
    @"f64.mul" = 0xa2,
    @"f64.div" = 0xa3,
    @"f64.min" = 0xa4,
    @"f64.max" = 0xa5,
    @"f64.copysign" = 0xa6,

    @"i32.wrap_i64" = 0xa7,
    @"i32.trunc_f32_s" = 0xa8,
    @"i32.trunc_f32_u" = 0xa9,
    @"i32.trunc_f64_s" = 0xaa,
    @"i32.trunc_f64_u" = 0xab,
    @"i64.extend_i32_s" = 0xac,
    @"i64.extend_i32_u" = 0xad,
    @"i64.trunc_f32_s" = 0xae,
    @"i64.trunc_f32_u" = 0xaf,
    @"i64.trunc_f64_s" = 0xb0,
    @"i64.trunc_f64_u" = 0xb1,
    @"f32.convert_i32_s" = 0xb2,
    @"f32.convert_i32_u" = 0xb3,
    @"f32.convert_i64_s" = 0xb4,
    @"f32.convert_i64_u" = 0xb5,
    @"f32.demote_f64" = 0xb6,
    @"f64.convert_i32_s" = 0xb7,
    @"f64.convert_i32_u" = 0xb8,
    @"f64.convert_i64_s" = 0xb9,
    @"f64.convert_i64_u" = 0xba,
    @"f64.promote_f64" = 0xbb,
    @"i32.reinterpret_f32" = 0xbc,
    @"i64.reinterpret_f64" = 0xbd,
    @"f32.reinterpret_i32" = 0xbe,
    @"f64.reinterpret_i64" = 0xbf,

    @"i32.extend8_s" = 0xc0,
    @"i32.extend16_s" = 0xc1,
    @"i64.extend8_s" = 0xc2,
    @"i64.extend16_s" = 0xc3,
    @"i64.extend32_s" = 0xc4,

    // ==== Vector Instructions ====
    VectorPrefix = 0xfd,

    _,

    pub fn fromInt(n: u8) !Opecode {
        const v = @intToEnum(Opecode, n);
        return switch (v) {
            .Prefix,

            // ==== Control Instructions ====
            .@"unreachable",
            .@"nop",
            .@"block",
            .@"loop",
            .@"if",
            .@"else",
            .@"end",
            .@"br",
            .@"br_if",
            .@"br_table",
            .@"return",
            .@"call",
            .@"call_indirect",

            // ==== Reference Instructions ====
            .@"ref.null",
            .@"ref.is_null",
            .@"ref.func",

            // ==== Parametric Instructions ====
            .@"drop",
            .@"select",
            .@"select_types",

            // ==== Variable Instructions ====
            .@"local.get",
            .@"local.set",
            .@"local.tee",
            .@"global.get",
            .@"global.set",

            // ==== Table Instructions ====
            .@"table.get",
            .@"table.set",

            // ==== Memory Instructions ====
            .@"i32.load",
            .@"i64.load",
            .@"f32.load",
            .@"f64.load",
            .@"i32.load8_s",
            .@"i32.load8_u",
            .@"i32.load16_s",
            .@"i32.load16_u",
            .@"i64.load8_s",
            .@"i64.load8_u",
            .@"i64.load16_s",
            .@"i64.load16_u",
            .@"i64.load32_s",
            .@"i64.load32_u",
            .@"i32.store",
            .@"i64.store",
            .@"f32.store",
            .@"f64.store",
            .@"i32.store8",
            .@"i32.store16",
            .@"i64.store8",
            .@"i64.store16",
            .@"i64.store32",
            .@"memory.size",
            .@"memory.grow",

            // ==== Numeric Instructions ====
            .@"i32.const",
            .@"i64.const",
            .@"f32.const",
            .@"f64.const",

            .@"i32.eqz",
            .@"i32.eq",
            .@"i32.ne",
            .@"i32.lt_s",
            .@"i32.lt_u",
            .@"i32.gt_s",
            .@"i32.gt_u",
            .@"i32.le_s",
            .@"i32.le_u",
            .@"i32.ge_s",
            .@"i32.ge_u",

            .@"i64.eqz",
            .@"i64.eq",
            .@"i64.ne",
            .@"i64.lt_s",
            .@"i64.lt_u",
            .@"i64.gt_s",
            .@"i64.gt_u",
            .@"i64.le_s",
            .@"i64.le_u",
            .@"i64.ge_s",
            .@"i64.ge_u",

            .@"f32.eq",
            .@"f32.ne",
            .@"f32.lt",
            .@"f32.gt",
            .@"f32.le",
            .@"f32.ge",

            .@"f64.eq",
            .@"f64.ne",
            .@"f64.lt",
            .@"f64.gt",
            .@"f64.le",
            .@"f64.ge",

            .@"i32.clz",
            .@"i32.ctz",
            .@"i32.popcnt",
            .@"i32.add",
            .@"i32.sub",
            .@"i32.mul",
            .@"i32.div_s",
            .@"i32.div_u",
            .@"i32.rem_s",
            .@"i32.rem_u",
            .@"i32.and",
            .@"i32.or",
            .@"i32.xor",
            .@"i32.shl",
            .@"i32.shr_s",
            .@"i32.shr_u",
            .@"i32.rotl",
            .@"i32.rotr",

            .@"i64.clz",
            .@"i64.ctz",
            .@"i64.popcnt",
            .@"i64.add",
            .@"i64.sub",
            .@"i64.mul",
            .@"i64.div_s",
            .@"i64.div_u",
            .@"i64.rem_s",
            .@"i64.rem_u",
            .@"i64.and",
            .@"i64.or",
            .@"i64.xor",
            .@"i64.shl",
            .@"i64.shr_s",
            .@"i64.shr_u",
            .@"i64.rotl",
            .@"i64.rotr",

            .@"f32.abs",
            .@"f32.neg",
            .@"f32.ceil",
            .@"f32.floor",
            .@"f32.trunc",
            .@"f32.nearest",
            .@"f32.sqrt",
            .@"f32.add",
            .@"f32.sub",
            .@"f32.mul",
            .@"f32.div",
            .@"f32.min",
            .@"f32.max",
            .@"f32.copysign",

            .@"f64.abs",
            .@"f64.neg",
            .@"f64.ceil",
            .@"f64.floor",
            .@"f64.trunc",
            .@"f64.nearest",
            .@"f64.sqrt",
            .@"f64.add",
            .@"f64.sub",
            .@"f64.mul",
            .@"f64.div",
            .@"f64.min",
            .@"f64.max",
            .@"f64.copysign",

            .@"i32.wrap_i64",
            .@"i32.trunc_f32_s",
            .@"i32.trunc_f32_u",
            .@"i32.trunc_f64_s",
            .@"i32.trunc_f64_u",
            .@"i64.extend_i32_s",
            .@"i64.extend_i32_u",
            .@"i64.trunc_f32_s",
            .@"i64.trunc_f32_u",
            .@"i64.trunc_f64_s",
            .@"i64.trunc_f64_u",
            .@"f32.convert_i32_s",
            .@"f32.convert_i32_u",
            .@"f32.convert_i64_s",
            .@"f32.convert_i64_u",
            .@"f32.demote_f64",
            .@"f64.convert_i32_s",
            .@"f64.convert_i32_u",
            .@"f64.convert_i64_s",
            .@"f64.convert_i64_u",
            .@"f64.promote_f64",
            .@"i32.reinterpret_f32",
            .@"i64.reinterpret_f64",
            .@"f32.reinterpret_i32",
            .@"f64.reinterpret_i64",

            .@"i32.extend8_s",
            .@"i32.extend16_s",
            .@"i64.extend8_s",
            .@"i64.extend16_s",
            .@"i64.extend32_s",

            // ==== .Vector Instructions ====
            .VectorPrefix,
            => v,
            _ => error.InvalidOpecode,
        };
    }
};

pub const Instruction = union(Opecode) {
    Prefix: void, // not implemented

    // ==== Control Instructions ====
    @"unreachable": void, // not implemented
    @"nop": void, // not implemented
    @"block": struct {
        block_type: BlockType,
        branch_target: u32,
    },
    @"loop": struct {
        block_type: BlockType,
        branch_target: u32,
    },
    @"if": struct {
        block_type: BlockType,
        branch_target: u32,
        else_pointer: u32,
    },
    @"else": void,
    @"end": void,
    @"br": u32,
    @"br_if": u32,
    @"br_table": void, // not implemented
    @"return": void,
    @"call": u32,
    @"call_indirect": void, // not implemented

    // ==== Reference Instructions ====
    @"ref.null": void, // not implemented
    @"ref.is_null": void, // not implemented
    @"ref.func": void, // not implemented

    // ==== Parametric Instructions ====
    @"drop": void,
    @"select": void, // not implemented
    @"select_types": void, // not implemented

    // ==== Variable Instructions ====
    @"local.get": u32,
    @"local.set": u32,
    @"local.tee": u32,
    @"global.get": u32, // not implemented
    @"global.set": void, // not implemented

    // ==== Table Instructions ====
    @"table.get": void, // not implemented
    @"table.set": void, // not implemented

    // ==== Memory Instructions ====
    @"i32.load": void, // not implemented
    @"i64.load": void, // not implemented
    @"f32.load": void, // not implemented
    @"f64.load": void, // not implemented
    @"i32.load8_s": void, // not implemented
    @"i32.load8_u": void, // not implemented
    @"i32.load16_s": void, // not implemented
    @"i32.load16_u": void, // not implemented
    @"i64.load8_s": void, // not implemented
    @"i64.load8_u": void, // not implemented
    @"i64.load16_s": void, // not implemented
    @"i64.load16_u": void, // not implemented
    @"i64.load32_s": void, // not implemented
    @"i64.load32_u": void, // not implemented
    @"i32.store": void, // not implemented
    @"i64.store": void, // not implemented
    @"f32.store": void, // not implemented
    @"f64.store": void, // not implemented
    @"i32.store8": void, // not implemented
    @"i32.store16": void, // not implemented
    @"i64.store8": void, // not implemented
    @"i64.store16": void, // not implemented
    @"i64.store32": void, // not implemented
    @"memory.size": void, // not implemented
    @"memory.grow": void, // not implemented

    // ==== Numeric Instructions ====
    @"i32.const": i32,
    @"i64.const": i64, // not implemented
    @"f32.const": f32, // not implemented
    @"f64.const": f64, // not implemented

    @"i32.eqz": void,
    @"i32.eq": void,
    @"i32.ne": void,
    @"i32.lt_s": void,
    @"i32.lt_u": void, // not implemented
    @"i32.gt_s": void,
    @"i32.gt_u": void, // not implemented
    @"i32.le_s": void,
    @"i32.le_u": void, // not implemented
    @"i32.ge_s": void,
    @"i32.ge_u": void, // not implemented

    @"i64.eqz": void, // not implemented
    @"i64.eq": void, // not implemented
    @"i64.ne": void, // not implemented
    @"i64.lt_s": void, // not implemented
    @"i64.lt_u": void, // not implemented
    @"i64.gt_s": void, // not implemented
    @"i64.gt_u": void, // not implemented
    @"i64.le_s": void, // not implemented
    @"i64.le_u": void, // not implemented
    @"i64.ge_s": void, // not implemented
    @"i64.ge_u": void, // not implemented

    @"f32.eq": void, // not implemented
    @"f32.ne": void, // not implemented
    @"f32.lt": void, // not implemented
    @"f32.gt": void, // not implemented
    @"f32.le": void, // not implemented
    @"f32.ge": void, // not implemented

    @"f64.eq": void, // not implemented
    @"f64.ne": void, // not implemented
    @"f64.lt": void, // not implemented
    @"f64.gt": void, // not implemented
    @"f64.le": void, // not implemented
    @"f64.ge": void, // not implemented

    @"i32.clz": void, // not implemented
    @"i32.ctz": void, // not implemented
    @"i32.popcnt": void, // not implemented
    @"i32.add": void,
    @"i32.sub": void,
    @"i32.mul": void,
    @"i32.div_s": void,
    @"i32.div_u": void, // not implemented
    @"i32.rem_s": void, // not implemented
    @"i32.rem_u": void, // not implemented
    @"i32.and": void, // not implemented
    @"i32.or": void, // not implemented
    @"i32.xor": void, // not implemented
    @"i32.shl": void, // not implemented
    @"i32.shr_s": void, // not implemented
    @"i32.shr_u": void, // not implemented
    @"i32.rotl": void, // not implemented
    @"i32.rotr": void, // not implemented

    @"i64.clz": void, // not implemented
    @"i64.ctz": void, // not implemented
    @"i64.popcnt": void, // not implemented
    @"i64.add": void, // not implemented
    @"i64.sub": void, // not implemented
    @"i64.mul": void, // not implemented
    @"i64.div_s": void, // not implemented
    @"i64.div_u": void, // not implemented
    @"i64.rem_s": void, // not implemented
    @"i64.rem_u": void, // not implemented
    @"i64.and": void, // not implemented
    @"i64.or": void, // not implemented
    @"i64.xor": void, // not implemented
    @"i64.shl": void, // not implemented
    @"i64.shr_s": void, // not implemented
    @"i64.shr_u": void, // not implemented
    @"i64.rotl": void, // not implemented
    @"i64.rotr": void, // not implemented

    @"f32.abs": void, // not implemented
    @"f32.neg": void, // not implemented
    @"f32.ceil": void, // not implemented
    @"f32.floor": void, // not implemented
    @"f32.trunc": void, // not implemented
    @"f32.nearest": void, // not implemented
    @"f32.sqrt": void, // not implemented
    @"f32.add": void, // not implemented
    @"f32.sub": void, // not implemented
    @"f32.mul": void, // not implemented
    @"f32.div": void, // not implemented
    @"f32.min": void, // not implemented
    @"f32.max": void, // not implemented
    @"f32.copysign": void, // not implemented

    @"f64.abs": void, // not implemented
    @"f64.neg": void, // not implemented
    @"f64.ceil": void, // not implemented
    @"f64.floor": void, // not implemented
    @"f64.trunc": void, // not implemented
    @"f64.nearest": void, // not implemented
    @"f64.sqrt": void, // not implemented
    @"f64.add": void, // not implemented
    @"f64.sub": void, // not implemented
    @"f64.mul": void, // not implemented
    @"f64.div": void, // not implemented
    @"f64.min": void, // not implemented
    @"f64.max": void, // not implemented
    @"f64.copysign": void, // not implemented

    @"i32.wrap_i64": void, // not implemented
    @"i32.trunc_f32_s": void, // not implemented
    @"i32.trunc_f32_u": void, // not implemented
    @"i32.trunc_f64_s": void, // not implemented
    @"i32.trunc_f64_u": void, // not implemented
    @"i64.extend_i32_s": void, // not implemented
    @"i64.extend_i32_u": void, // not implemented
    @"i64.trunc_f32_s": void, // not implemented
    @"i64.trunc_f32_u": void, // not implemented
    @"i64.trunc_f64_s": void, // not implemented
    @"i64.trunc_f64_u": void, // not implemented
    @"f32.convert_i32_s": void, // not implemented
    @"f32.convert_i32_u": void, // not implemented
    @"f32.convert_i64_s": void, // not implemented
    @"f32.convert_i64_u": void, // not implemented
    @"f32.demote_f64": void, // not implemented
    @"f64.convert_i32_s": void, // not implemented
    @"f64.convert_i32_u": void, // not implemented
    @"f64.convert_i64_s": void, // not implemented
    @"f64.convert_i64_u": void, // not implemented
    @"f64.promote_f64": void, // not implemented
    @"i32.reinterpret_f32": void, // not implemented
    @"i64.reinterpret_f64": void, // not implemented
    @"f32.reinterpret_i32": void, // not implemented
    @"f64.reinterpret_i64": void, // not implemented

    @"i32.extend8_s": void, // not implemented
    @"i32.extend16_s": void, // not implemented
    @"i64.extend8_s": void, // not implemented
    @"i64.extend16_s": void, // not implemented
    @"i64.extend32_s": void, // not implemented

    VectorPrefix: void, // not implemented
};
