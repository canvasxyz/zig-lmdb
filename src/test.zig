const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Cursor = @import("cursor.zig");

const compare = @import("compare.zig");
const errors = @import("errors.zig");
const utils = @import("utils.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

test "basic operations" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "x", "foo");
        try txn.set(dbi, "y", "bar");
        try txn.set(dbi, "z", "baz");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.delete(dbi, "y");
        try txn.set(dbi, "x", "FOO");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try utils.expectEqualEntries(txn, dbi, &.{
            .{ "x", "FOO" },
            .{ "z", "baz" },
        });
    }
}

test "multiple named databases" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{ .max_dbs = 2 });
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase("a", .{});

        try txn.set(dbi, "x", "foo");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase("b", .{});

        try txn.set(dbi, "x", "bar");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();

        const dbi = try txn.openDatabase("a", .{});

        try utils.expectEqualKeys(try txn.get(dbi, "x"), "foo");
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();

        const dbi = try txn.openDatabase("b", .{});

        try utils.expectEqualKeys(try txn.get(dbi, "x"), "bar");
    }
}

test "compareEntries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("a");
    try tmp.dir.makeDir("b");

    var dir_a = try tmp.dir.openDir("a", .{});
    defer dir_a.close();

    const env_a = try Environment.openDir(dir_a, .{});
    defer env_a.close();

    {
        const txn = try Transaction.open(env_a, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "x", "foo");
        try txn.set(dbi, "y", "bar");
        try txn.set(dbi, "z", "baz");
        try txn.commit();
    }

    var dir_b = try tmp.dir.openDir("b", .{});
    defer dir_b.close();

    const env_b = try Environment.openDir(dir_b, .{});
    defer env_b.close();

    {
        const txn = try Transaction.open(env_b, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "y", "bar");
        try txn.set(dbi, "z", "qux");
        try txn.commit();
    }

    try expectEqual(try compare.compareEnvironments(env_a, env_b, null, .{}), 2);
    try expectEqual(try compare.compareEnvironments(env_b, env_a, null, .{}), 2);

    {
        const txn = try Transaction.open(env_b, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "x", "foo");
        try txn.set(dbi, "z", "baz");
        try txn.commit();
    }

    try expectEqual(try compare.compareEnvironments(env_a, env_b, null, .{}), 0);
    try expectEqual(try compare.compareEnvironments(env_b, env_a, null, .{}), 0);
}

test "set empty value" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{});
    defer env.close();

    const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
    defer txn.abort();

    const dbi = try txn.openDatabase(null, .{});

    try txn.set(dbi, "a", "");

    if (try txn.get(dbi, "a")) |value| {
        try expect(value.len == 0);
    } else {
        return error.KeyNotFound;
    }
}

test "Environment.stat" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "a", "foo");
        try txn.set(dbi, "b", "bar");
        try txn.set(dbi, "c", "baz");
        try txn.set(dbi, "a", "aaa");
        try txn.commit();
    }

    {
        const stat = try env.stat();
        try expectEqual(@as(usize, 3), stat.entries);
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.delete(dbi, "c");
        try txn.commit();
    }

    {
        const stat = try env.stat();
        try expectEqual(@as(usize, 2), stat.entries);
    }
}

test "Cursor.deleteCurrentKey()" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        defer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "a", "foo");
        try txn.set(dbi, "b", "bar");
        try txn.set(dbi, "c", "baz");
        try txn.set(dbi, "d", "qux");

        const cursor = try Cursor.open(txn, dbi);
        try cursor.goToKey("c");
        try expectEqualSlices(u8, try cursor.getCurrentValue(), "baz");
        try cursor.deleteCurrentKey();
        try expectEqualSlices(u8, try cursor.getCurrentKey(), "d");
        try utils.expectEqualKeys(try cursor.goToPrevious(), "b");

        try utils.expectEqualEntries(txn, dbi, &.{
            .{ "a", "foo" },
            .{ "b", "bar" },
            .{ "d", "qux" },
        });
    }
}

test "Cursor.seek" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        defer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "a", "foo");
        try txn.set(dbi, "aa", "bar");
        try txn.set(dbi, "ab", "baz");
        try txn.set(dbi, "abb", "qux");

        const cursor = try Cursor.open(txn, dbi);
        defer cursor.close();
        try utils.expectEqualKeys(try cursor.seek("aba"), "abb");
        try expectEqual(try cursor.seek("b"), null);
    }
}

test "parent transactions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const env = try Environment.openDir(tmp.dir, .{});
    defer env.close();

    const parent = try Transaction.open(env, .{ .mode = .ReadWrite });
    defer parent.abort();

    const parent_dbi = try parent.openDatabase(null, .{});

    try parent.set(parent_dbi, "a", "foo");
    try parent.set(parent_dbi, "b", "bar");
    try parent.set(parent_dbi, "c", "baz");

    {
        const child = try Transaction.open(env, .{ .mode = .ReadWrite, .parent = parent });
        errdefer child.abort();

        const child_dbi = try child.openDatabase(null, .{});
        try child.delete(child_dbi, "c");
        try child.commit();
    }

    try expectEqual(@as(?[]const u8, null), try parent.get(parent_dbi, "c"));

    {
        const child = try Transaction.open(env, .{ .mode = .ReadWrite, .parent = parent });
        defer child.abort();

        const child_dbi = try child.openDatabase(null, .{});
        try child.set(child_dbi, "c", "baz");
    }

    try expectEqual(@as(?[]const u8, null), try parent.get(parent_dbi, "c"));
}

test "resize map" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var map_size: usize = 64 * 4096;

    const env = try Environment.openDir(tmp.dir, .{ .map_size = map_size });
    defer env.close();

    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        setEntry(env, i) catch |err| {
            if (err == errors.Error.MDB_MAP_FULL) {
                map_size = 2 * map_size;
                try env.resize(map_size);
                try setEntry(env, i);
            } else {
                return err;
            }
        };
    }

    const stat = try env.stat();
    try expectEqual(@as(usize, 10000), stat.entries);
}

fn setEntry(env: Environment, i: u32) !void {
    var key: [4]u8 = undefined;
    var value: [32]u8 = undefined;

    const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
    const dbi = try txn.openDatabase(null, .{});
    std.mem.writeInt(u32, &key, i, .big);
    std.crypto.hash.Blake3.hash(&key, &value, .{});
    try txn.set(dbi, &key, &value);

    try txn.commit();
}
