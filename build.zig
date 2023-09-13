const std = @import("std");
const FileSource = std.build.FileSource;

const lmdb_source_files = [_][]const u8{
    "libs/openldap/libraries/liblmdb/mdb.c",
    "libs/openldap/libraries/liblmdb/midl.c",
};

pub fn build(b: *std.build.Builder) void {
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    // // openldap static library
    // const openldap = b.addStaticLibrary(.{ .name = "openldap", .target = target, .optimize = optimize });
    // openldap.addIncludePath(.{ .path = "./libs/openldap/libraries/liblmdb" });
    // openldap.addCSourceFiles(&.{
    //     "libs/openldap/libraries/liblmdb/mdb.c",
    //     "libs/openldap/libraries/liblmdb/midl.c",
    // }, &.{});

    // b.installArtifact(openldap);

    const lmdb = b.addModule("lmdb", .{ .source_file = FileSource.relative("src/lib.zig") });

    // Tests
    const tests = b.addTest(.{ .root_source_file = FileSource.relative("src/test.zig") });
    tests.addIncludePath(.{ .path = "./libs/openldap/libraries/liblmdb" });
    tests.addCSourceFiles(&lmdb_source_files, &.{});
    const run_tests = b.addRunArtifact(tests);

    b.step("test", "Run LMDB tests").dependOn(&run_tests.step);

    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "lmdb-benchmark",
        .root_source_file = FileSource.relative("benchmarks/main.zig"),
        .optimize = .ReleaseFast,
    });

    bench.addModule("lmdb", lmdb);
    bench.addIncludePath(.{ .path = "libs/openldap/libraries/liblmdb" });
    bench.addCSourceFiles(&lmdb_source_files, &.{});

    const run_bench = b.addRunArtifact(bench);
    b.step("bench", "Run LMDB benchmarks").dependOn(&run_bench.step);
}
