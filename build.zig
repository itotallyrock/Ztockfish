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

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opts = b.addOptions();

    const embed_nets = b.option(bool, "embed-nets", "Whether or not to embed the NNUE file in the executable (default: true)") orelse true;
    opts.addOption(bool, "embed-nets", embed_nets);

    const small_net = b.option([]const u8, "small-net", "Name of the small NNUE (default: \"nn-37f18f62d772.nnue\")") orelse "nn-37f18f62d772.nnue";
    opts.addOption([]const u8, "small-net", small_net);

    const big_net = b.option([]const u8, "big-net", "Name of the big NNUE (default: \"nn-1111cefa1111.nnue\")") orelse "nn-1111cefa1111.nnue";
    opts.addOption([]const u8, "big-net", big_net);

    try downloadNNUE(b, small_net);
    try downloadNNUE(b, big_net);

    const stockfish_dep = b.dependency("Stockfish", .{});
    const stockfish_src_path = stockfish_dep.path("src/");

    const exe = b.addExecutable(.{
        .name = "stockfish",
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Build and run stockfish");
    run_step.dependOn(&run_cmd.step);

    exe.linkLibC();
    exe.linkLibCpp();

    if (optimize != .Debug) {
        exe.root_module.pic = true;
        exe.pie = true;
        exe.root_module.omit_frame_pointer = true;
        exe.root_module.strip = true;
        exe.want_lto = switch (builtin.os.tag) {
            .macos => false,
            else => true,
        };
    }

    exe.addCSourceFiles(.{
        .root = stockfish_src_path,
        .files = &.{
            "movegen.cpp",
            "engine.cpp",
            "nnue/features/half_ka_v2_hm.cpp",
            "nnue/nnue_misc.cpp",
            "nnue/network.cpp",
            "memory.cpp",
            "uci.cpp",
            "search.cpp",
            "ucioption.cpp",
            "tt.cpp",
            "bitboard.cpp",
            "score.cpp",
            "main.cpp",
            "thread.cpp",
            "benchmark.cpp",
            "position.cpp",
            "movepick.cpp",
            "timeman.cpp",
            "misc.cpp",
            "tune.cpp",
            "syzygy/tbprobe.cpp",
            "evaluate.cpp",
        },
        .flags = &.{
            if (embed_nets) "" else "-DNNUE_EMBEDDING_OFF=1",
        },
    });
}

/// The first time we run "zig build", we need to download a nnue file from the
/// internet. We search for the correct file to download in the macro
/// #define EvalFileDefaultName in evaluate.h.
fn downloadNNUE(b: *Build, nnue_file: []const u8) !void {
    _ = fs.cwd().statFile(nnue_file) catch |err| {
        switch (err) {
            error.FileNotFound => {
                const url = try fmt.allocPrint(b.allocator, "https://data.stockfishchess.org/nn/{s}", .{nnue_file});
                std.debug.print("No nnue file found, downloading {s}\n\n", .{url});

                var child = std.process.Child.init(&.{ "curl", "-o", nnue_file, url }, b.allocator);
                try child.spawn();
                _ = try child.wait();
            },
            else => return err,
        }
    };
}
