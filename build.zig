const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    // const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const lmdb = b.addModule("lmdb", .{ .root_source_file = LazyPath.relative("src/lib.zig") });
    const lmdb_dep = b.dependency("lmdb", .{});

    lmdb.addIncludePath(lmdb_dep.path("libraries/liblmdb"));
    lmdb.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/mdb.c") });
    lmdb.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/midl.c") });

    // Tests
    const tests = b.addTest(.{ .root_source_file = LazyPath.relative("src/test.zig") });

    tests.addIncludePath(lmdb_dep.path("libraries/liblmdb"));
    tests.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/mdb.c") });
    tests.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/midl.c") });

    const run_tests = b.addRunArtifact(tests);

    b.step("test", "Run LMDB tests").dependOn(&run_tests.step);

    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "lmdb-benchmark",
        .root_source_file = LazyPath.relative("benchmarks/main.zig"),
        .optimize = .ReleaseFast,
        .target = target,
    });

    bench.root_module.addImport("lmdb", lmdb);

    const run_bench = b.addRunArtifact(bench);
    b.step("bench", "Run LMDB benchmarks").dependOn(&run_bench.step);
}
