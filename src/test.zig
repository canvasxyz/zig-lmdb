const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Cursor = @import("cursor.zig");

const compare = @import("compare.zig");
const utils = @import("utils.zig");

const allocator = std.heap.c_allocator;

test "basic operations" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");
    const env = try Environment.open(path, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        try txn.set("x", "foo", .{});
        try txn.set("y", "bar", .{});
        try txn.set("z", "baz", .{});
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        try txn.delete("y", .{});
        try txn.set("x", "FOO", .{});
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();
        try utils.expectEqualEntries(txn, null, &.{
            .{ "x", "FOO" },
            .{ "z", "baz" },
        });
    }
}

test "multiple named databases" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");
    const env = try Environment.open(path, .{ .max_dbs = 2 });
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        const database = try txn.openDatabase(.{ .name = "a" });
        try txn.set("x", "foo", .{ .database = database });
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        const database = try txn.openDatabase(.{ .name = "b" });
        try txn.set("x", "bar", .{ .database = database });
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();
        const database = try txn.openDatabase(.{ .name = "a" });
        try utils.expectEqualKeys(try txn.get("x", .{ .database = database }), "foo");
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();
        const database = try txn.openDatabase(.{ .name = "b" });
        try utils.expectEqualKeys(try txn.get("x", .{ .database = database }), "bar");
    }
}

test "compareEntries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("a");
    try tmp.dir.makeDir("b");

    const path_a = try utils.resolvePath(tmp.dir, "a");
    const env_a = try Environment.open(path_a, .{});
    defer env_a.close();

    {
        const txn = try Transaction.open(env_a, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        try txn.set("x", "foo", .{});
        try txn.set("y", "bar", .{});
        try txn.set("z", "baz", .{});
        try txn.commit();
    }

    const path_b = try utils.resolvePath(tmp.dir, "b");
    const env_b = try Environment.open(path_b, .{});
    defer env_b.close();

    {
        const txn = try Transaction.open(env_b, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        try txn.set("y", "bar", .{});
        try txn.set("z", "qux", .{});
        try txn.commit();
    }

    try expectEqual(try compare.compareEnvironments(env_a, env_b, .{}), 2);
    try expectEqual(try compare.compareEnvironments(env_b, env_a, .{}), 2);

    {
        const txn = try Transaction.open(env_b, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        try txn.set("x", "foo", .{});
        try txn.set("z", "baz", .{});
        try txn.commit();
    }

    try expectEqual(try compare.compareEnvironments(env_a, env_b, .{}), 0);
    try expectEqual(try compare.compareEnvironments(env_b, env_a, .{}), 0);
}

test "set empty value" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");

    const env = try Environment.open(path, .{});
    defer env.close();

    const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
    defer txn.abort();

    try txn.set("a", "", .{});
    if (try txn.get("a", .{})) |value| {
        try expect(value.len == 0);
    } else {
        return error.KeyNotFound;
    }
}

test "stat" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");

    const env = try Environment.open(path, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        try txn.set("a", "foo", .{});
        try txn.set("b", "bar", .{});
        try txn.set("c", "baz", .{});
        try txn.set("a", "aaa", .{});
        try txn.commit();
    }

    {
        const stat = try env.stat();
        try expectEqual(@as(usize, 3), stat.entries);
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();
        try txn.delete("c", .{});
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

    const path = try utils.resolvePath(tmp.dir, ".");
    const env = try Environment.open(path, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        defer txn.abort();

        try txn.set("a", "foo", .{});
        try txn.set("b", "bar", .{});
        try txn.set("c", "baz", .{});
        try txn.set("d", "qux", .{});

        const cursor = try Cursor.open(txn, .{});
        try cursor.goToKey("c");
        try expectEqualSlices(u8, try cursor.getCurrentValue(), "baz");
        try cursor.deleteCurrentKey();
        try expectEqualSlices(u8, try cursor.getCurrentKey(), "d");
        try utils.expectEqualKeys(try cursor.goToPrevious(), "b");

        try utils.expectEqualEntries(txn, null, &.{
            .{ "a", "foo" },
            .{ "b", "bar" },
            .{ "d", "qux" },
        });
    }
}

test "seek" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");
    const env = try Environment.open(path, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        defer txn.abort();

        try txn.set("a", "foo", .{});
        try txn.set("aa", "bar", .{});
        try txn.set("ab", "baz", .{});
        try txn.set("abb", "qux", .{});

        const cursor = try Cursor.open(txn, .{});
        defer cursor.close();
        try utils.expectEqualKeys(try cursor.seek("aba"), "abb");
        try expectEqual(try cursor.seek("b"), null);
    }
}

test "parent transactions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");
    const env = try Environment.open(path, .{});
    defer env.close();

    const parent = try Transaction.open(env, .{ .mode = .ReadWrite });
    defer parent.abort();

    try parent.set("a", "foo", .{});
    try parent.set("b", "bar", .{});
    try parent.set("c", "baz", .{});

    {
        const child = try Transaction.open(env, .{ .mode = .ReadWrite, .parent = parent });
        errdefer child.abort();
        try child.delete("c", .{});
        try child.commit();
    }

    try expectEqual(@as(?[]const u8, null), try parent.get("c", .{}));

    {
        const child = try Transaction.open(env, .{ .mode = .ReadWrite, .parent = parent });
        defer child.abort();
        try child.set("c", "baz", .{});
    }

    try expectEqual(@as(?[]const u8, null), try parent.get("c", .{}));
}
