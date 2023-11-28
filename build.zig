const std = @import("std");
const LazyPath = std.build.LazyPath;

pub fn build(b: *std.build.Builder) void {
    const lmdb = b.addModule("lmdb", .{ .source_file = LazyPath.relative("src/lib.zig") });

    const lmdb_dep = b.dependency("lmdb", .{});

    // Tests
    const tests = b.addTest(.{ .root_source_file = LazyPath.relative("src/test.zig") });

    tests.addIncludePath(lmdb_dep.path("libraries/liblmdb"));
    tests.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/mdb.c"), .flags = &.{} });
    tests.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/midl.c"), .flags = &.{} });

    const run_tests = b.addRunArtifact(tests);

    b.step("test", "Run LMDB tests").dependOn(&run_tests.step);

    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "lmdb-benchmark",
        .root_source_file = LazyPath.relative("benchmarks/main.zig"),
        .optimize = .ReleaseFast,
    });

    bench.addModule("lmdb", lmdb);
    bench.addIncludePath(lmdb_dep.path("libraries/liblmdb"));
    bench.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/mdb.c"), .flags = &.{} });
    bench.addCSourceFile(.{ .file = lmdb_dep.path("libraries/liblmdb/midl.c"), .flags = &.{} });

    const run_bench = b.addRunArtifact(bench);
    b.step("bench", "Run LMDB benchmarks").dependOn(&run_bench.step);
}
