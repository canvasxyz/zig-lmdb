const std = @import("std");
const allocator = std.heap.c_allocator;
const hex = std.fmt.fmtSliceHexLower;

const lmdb = @import("lmdb");
const utils = @import("utils.zig");

const data_directory_name = "data";
const value_size = 8;

var prng = std.rand.DefaultPrng.init(0x0000000000000000);
var random = prng.random();

const ms: f64 = 1_000_000.0;

const Context = struct {
    env: lmdb.Environment,
    size: u32,
    log: std.fs.File.Writer,

    pub fn exec(name: []const u8, size: u32, log: std.fs.File.Writer, options: lmdb.Environment.Options) !void {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        try tmp.dir.makeDir(name);
        const path = try utils.resolvePath(&tmp.dir, name);
        const env = try lmdb.Environment.open(path, options);
        defer env.close();

        const ctx = Context{ .env = env, .size = size, .log = log };
        try ctx.initialize();
        try ctx.printHeader();

        try ctx.getRandomEntries("get random 1 entry", 100, 1);
        try ctx.getRandomEntries("get random 100 entries", 100, 100);
        try iterateEntries(ctx, 100);
        try ctx.setRandomEntries("set random 1 entry", 100, 1);
        try ctx.setRandomEntries("set random 100 entries", 100, 100);
        try ctx.setRandomEntries("set random 1000 entries", 10, 1000);
        try ctx.setRandomEntries("set random 50000 entries", 10, 50000);
    }

    fn initialize(ctx: Context) !void {
        const txn = try lmdb.Transaction.open(ctx.env, .{ .read_only = false });
        errdefer txn.abort();

        var key: [4]u8 = undefined;
        var value: [value_size]u8 = undefined;

        var i: u32 = 0;
        while (i < ctx.size) : (i += 1) {
            std.mem.writeIntBig(u32, &key, i);
            std.crypto.hash.Blake3.hash(&key, &value, .{});
            try txn.set(&key, &value);
        }

        try txn.commit();
        try ctx.env.flush();
    }

    fn printHeader(ctx: Context) !void {
        try ctx.log.print("### DB size: {d} entries\n\n", .{ctx.size});
        try ctx.log.print(
            "| {s: <30} | {s: >10} | {s: >10} | {s: >10} | {s: >10} | {s: >8} | {s: >10} |\n",
            .{ "", "iterations", "min (ms)", "max (ms)", "avg (ms)", "std", "ops / s" },
        );
        try ctx.log.print(
            "| {s:-<30} | {s:->10} | {s:->10} | {s:->10} | {s:->10} | {s:->8} | {s:->10} |\n",
            .{ ":", ":", ":", ":", ":", ":", ":" },
        );
    }

    fn getRandomEntries(ctx: Context, comptime name: []const u8, comptime iterations: u32, comptime batch_size: usize) !void {
        var runtimes: [iterations]f64 = undefined;
        var timer = try std.time.Timer.start();

        var operations: usize = 0;
        for (&runtimes) |*t| {
            timer.reset();
            operations += batch_size;

            const txn = try lmdb.Transaction.open(ctx.env, .{ .read_only = true });
            defer txn.abort();

            var key: [4]u8 = undefined;

            var n: u32 = 0;
            while (n < batch_size) : (n += 1) {
                std.mem.writeIntBig(u32, &key, random.uintLessThan(u32, ctx.size));
                const value = try txn.get(&key);
                std.debug.assert(value.?.len == value_size);
            }

            t.* = @as(f64, @floatFromInt(timer.read())) / ms;
        }

        try utils.printRow(ctx.log, name, &runtimes, operations);
    }

    fn setRandomEntries(ctx: Context, comptime name: []const u8, comptime iterations: u32, comptime batch_size: usize) !void {
        var runtimes: [iterations]f64 = undefined;
        var timer = try std.time.Timer.start();

        var operations: usize = 0;
        for (&runtimes, 0..) |*t, i| {
            timer.reset();

            const txn = try lmdb.Transaction.open(ctx.env, .{ .read_only = false });
            errdefer txn.abort();

            var key: [4]u8 = undefined;
            var seed: [12]u8 = undefined;
            var value: [8]u8 = undefined;

            std.mem.writeIntBig(u32, seed[0..4], ctx.size);
            std.mem.writeIntBig(u32, seed[4..8], @as(u32, @intCast(i)));

            var n: u32 = 0;
            while (n < batch_size) : (n += 1) {
                std.mem.writeIntBig(u32, &key, random.uintLessThan(u32, ctx.size));
                std.mem.writeIntBig(u32, seed[8..], n);
                std.crypto.hash.Blake3.hash(&seed, &value, .{});
                try txn.set(&key, &value);
            }

            try txn.commit();
            try ctx.env.flush();

            t.* = @as(f64, @floatFromInt(timer.read())) / ms;
            operations += batch_size;
        }

        try utils.printRow(ctx.log, name, &runtimes, operations);
    }

    fn iterateEntries(ctx: Context, comptime iterations: u32) !void {
        var runtimes: [iterations]f64 = undefined;
        var timer = try std.time.Timer.start();

        var operations: usize = 0;
        for (&runtimes) |*t| {
            timer.reset();
            operations += ctx.size;

            const txn = try lmdb.Transaction.open(ctx.env, .{ .read_only = true });
            defer txn.abort();

            const cursor = try lmdb.Cursor.open(txn);
            defer cursor.close();

            if (try cursor.goToFirst()) |first_key| {
                std.debug.assert(first_key.len == 4);
                const first_value = try cursor.getCurrentValue();
                std.debug.assert(first_value.len == value_size);

                while (try cursor.goToNext()) |key| {
                    std.debug.assert(key.len == 4);
                    const value = try cursor.getCurrentValue();
                    std.debug.assert(value.len == value_size);
                }
            }

            try ctx.env.flush();
            t.* = @as(f64, @floatFromInt(timer.read())) / ms;
        }

        try utils.printRow(ctx.log, "iterate over all entries", &runtimes, operations);
    }
};

pub fn main() !void {
    const log = std.io.getStdOut().writer();

    _ = try log.write("## Benchmarks\n\n");

    try Context.exec("iota-1000", 1_000, log, .{});
    _ = try log.write("\n");
    try Context.exec("iota-50000", 50_000, log, .{});
    _ = try log.write("\n");
    try Context.exec("iota-1000000", 1_000_000, log, .{ .map_size = 2 * 1024 * 1024 * 1024 });
}