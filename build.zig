const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = mem.Allocator;
const Build = std.Build;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const http = std.http;
const math = std.math;
const mem = std.mem;

const default_networks = .{
    .small_net = "nn-37f18f62d772.nnue",
    .big_net = "nn-1c0000000000.nnue",
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stockfish_dep = b.dependency("Stockfish", .{});
    const stockfish_nets_dep = b.dependency("stockfish_nets", .{});

    const copy_nets = b.addUpdateSourceFiles();
    copy_nets.addCopyFileToSource(stockfish_nets_dep.path(default_networks.small_net), default_networks.small_net);
    copy_nets.addCopyFileToSource(stockfish_nets_dep.path(default_networks.big_net), default_networks.big_net);
    copy_nets.step.name = "copy embedded neural networks";

    // x86/x86_64 SIMD and ISA
    const use_64bit   = target.result.cpu.has(.x86, std.Target.x86.Feature.@"64bit");
    const use_prefetch = target.result.cpu.has(.x86, std.Target.x86.Feature.prefetchi);// TODO: Check
    const use_popcnt  = target.result.cpu.has(.x86, std.Target.x86.Feature.popcnt);
    const use_pext    = use_64bit and target.result.cpu.has(.x86, std.Target.x86.Feature.bmi2);
    const use_sse2    = target.result.cpu.has(.x86, std.Target.x86.Feature.sse2);
    const use_ssse3   = target.result.cpu.has(.x86, std.Target.x86.Feature.ssse3);
    const use_sse41   = target.result.cpu.has(.x86, std.Target.x86.Feature.sse4_1);
    const use_avx2    = target.result.cpu.has(.x86, std.Target.x86.Feature.avx2);
    const use_avxvnni = target.result.cpu.has(.x86, std.Target.x86.Feature.avxvnni);
    const use_avx512f   = target.result.cpu.has(.x86, std.Target.x86.Feature.avx512f);
    const use_avx512bw  = target.result.cpu.has(.x86, std.Target.x86.Feature.avx512bw);
    const use_avx512dq  = target.result.cpu.has(.x86, std.Target.x86.Feature.avx512dq);
    const use_avx512vl  = target.result.cpu.has(.x86, std.Target.x86.Feature.avx512vl);
    const use_avx512vnni = target.result.cpu.has(.x86, std.Target.x86.Feature.avx512vnni);

    // ARM/ARM64
    const use_neon    = target.result.cpu.has(.aarch64, std.Target.aarch64.Feature.neon) or target.result.cpu.has(.arm, std.Target.arm.Feature.neon);
    const use_dotprod = target.result.cpu.has(.aarch64, std.Target.aarch64.Feature.dotprod) or target.result.cpu.has(.arm, std.Target.arm.Feature.dotprod);

    // Setup main module
    const main_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .pic = if (optimize != .Debug) true else null,
        .omit_frame_pointer = if (optimize != .Debug) true else null,
        .strip = if (optimize != .Debug) true else null,
    });

    main_module.addCMacro("__DATE__", "\"Jan 1 1970\"");
    main_module.addCMacro("ARCH", @tagName(target.result.cpu.arch));
    if (use_64bit) main_module.addCMacro("IS_64BIT", "1");
    if (!use_prefetch) main_module.addCMacro("NO_PREFETCH", "1");
    if (use_popcnt) main_module.addCMacro("USE_POPCNT", "1");
    if (use_pext) main_module.addCMacro("USE_PEXT", "1");
    if (use_sse2) main_module.addCMacro("USE_SSE2", "1");
    if (use_ssse3) main_module.addCMacro("USE_SSSE3", "1");
    if (use_sse41) main_module.addCMacro("USE_SSE41", "1");
    if (use_avx2) main_module.addCMacro("USE_AVX2", "1");
    if (use_avxvnni or use_avx512vnni) main_module.addCMacro("USE_AVXVNNI", "1");
    if (use_avx512f or use_avx512bw or use_avx512dq or use_avx512vl or use_avx512vnni) main_module.addCMacro("USE_AVX512", "1");
    if (use_neon) main_module.addCMacro("USE_NEON", "1");
    if (use_dotprod) main_module.addCMacro("USE_NEON_DOTPROD", "1");
    if (optimize != .Debug) main_module.addCMacro("NDEBUG", "1");

    main_module.addCSourceFiles(.{
        .root = stockfish_dep.path("src/"),
        .files = &.{
            "benchmark.cpp",
            "bitboard.cpp",
            "engine.cpp",
            "evaluate.cpp",
            "main.cpp",
            "memory.cpp",
            "misc.cpp",
            "movegen.cpp",
            "movepick.cpp",
            "nnue/features/half_ka_v2_hm.cpp",
            "nnue/network.cpp",
            "nnue/nnue_accumulator.cpp",
            "nnue/nnue_misc.cpp",
            "position.cpp",
            "score.cpp",
            "search.cpp",
            "syzygy/tbprobe.cpp",
            "thread.cpp",
            "timeman.cpp",
            "tt.cpp",
            "tune.cpp",
            "uci.cpp",
            "ucioption.cpp",
        },
    });

    // Setup exe
    const exe = b.addExecutable(.{
        .name = "stockfish",
        .root_module = main_module,
        .linkage = .static,
    });
    exe.step.dependOn(&copy_nets.step);
    if (optimize != .Debug) {
        exe.pie = true;
        exe.lto = switch (builtin.os.tag) {
            .macos => null,
            else => .full,
        };
    }
    b.installArtifact(exe);

    // Setup run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Build and run stockfish").dependOn(&run_cmd.step);
}
