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
