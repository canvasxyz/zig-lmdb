const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Database = @import("database.zig");
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
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();
        const db = try Database.open(txn, .{});
        try db.set("x", "foo");
        try db.set("y", "bar");
        try db.set("z", "baz");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();
        const db = try Database.open(txn, .{});
        try db.delete("y");
        try db.set("x", "FOO");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = true });
        defer txn.abort();
        const db = try Database.open(txn, .{});
        try utils.expectEqualEntries(db, &.{
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
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();
        const db = try Database.open(txn, .{ .name = "a", .create = true });
        try db.set("x", "foo");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();
        const db = try Database.open(txn, .{ .name = "b", .create = true });
        try db.set("x", "bar");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = true });
        defer txn.abort();
        const db = try Database.open(txn, .{ .name = "a" });
        try utils.expectEqualKeys(try db.get("x"), "foo");
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = true });
        defer txn.abort();
        const db = try Database.open(txn, .{ .name = "b" });
        try utils.expectEqualKeys(try db.get("x"), "bar");
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
        const txn = try Transaction.open(env_a, .{ .read_only = false });
        errdefer txn.abort();
        const db = try Database.open(txn, .{ .create = true });
        try db.set("x", "foo");
        try db.set("y", "bar");
        try db.set("z", "baz");
        try txn.commit();
    }

    const path_b = try utils.resolvePath(tmp.dir, "b");
    const env_b = try Environment.open(path_b, .{});
    defer env_b.close();

    {
        const txn = try Transaction.open(env_b, .{ .read_only = false });
        const db = try Database.open(txn, .{ .create = true });
        errdefer txn.abort();
        try db.set("y", "bar");
        try db.set("z", "qux");
        try txn.commit();
    }

    try expectEqual(try compare.compareEnvironments(env_a, env_b, .{}), 2);
    try expectEqual(try compare.compareEnvironments(env_b, env_a, .{}), 2);

    {
        const txn = try Transaction.open(env_b, .{ .read_only = false });
        const db = try Database.open(txn, .{});
        errdefer txn.abort();
        try db.set("x", "foo");
        try db.set("z", "baz");
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

    const txn = try Transaction.open(env, .{ .read_only = false });
    defer txn.abort();

    const db = try Database.open(txn, .{});

    try db.set("a", "");
    if (try db.get("a")) |value| {
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
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();

        const db = try Database.open(txn, .{ .create = true });
        try db.set("a", "foo");
        try db.set("b", "bar");
        try db.set("c", "baz");
        try db.set("a", "aaa");

        try txn.commit();
    }

    {
        const stat = try env.stat();
        try expectEqual(@as(usize, 3), stat.entries);
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();
        const db = try Database.open(txn, .{});
        try db.delete("c");
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
        const txn = try Transaction.open(env, .{ .read_only = false });
        defer txn.abort();

        const db = try Database.open(txn, .{ .create = true });
        try db.set("a", "foo");
        try db.set("b", "bar");
        try db.set("c", "baz");
        try db.set("d", "qux");

        const cursor = try Cursor.open(db);
        try cursor.goToKey("c");
        try expectEqualSlices(u8, try cursor.getCurrentValue(), "baz");
        try cursor.deleteCurrentKey();
        try expectEqualSlices(u8, try cursor.getCurrentKey(), "d");
        try utils.expectEqualKeys(try cursor.goToPrevious(), "b");

        try utils.expectEqualEntries(db, &.{
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
        const txn = try Transaction.open(env, .{ .read_only = false });
        defer txn.abort();

        const db = try Database.open(txn, .{ .create = true });
        try db.set("a", "foo");
        try db.set("aa", "bar");
        try db.set("ab", "baz");
        try db.set("abb", "qux");

        const cursor = try Cursor.open(db);
        try utils.expectEqualKeys(try cursor.seek("aba"), "abb");
        try expectEqual(try cursor.seek("b"), null);

        try utils.expectEqualEntries(db, &.{
            .{ "a", "foo" },
            .{ "aa", "bar" },
            .{ "ab", "baz" },
            .{ "abb", "qux" },
        });
    }
}

test "parent transactions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try utils.resolvePath(tmp.dir, ".");
    const env = try Environment.open(path, .{});
    defer env.close();

    const parent = try Transaction.open(env, .{ .read_only = false });
    defer parent.abort();

    const parent_db = try Database.open(parent, .{ .create = true });
    try parent_db.set("a", "foo");
    try parent_db.set("b", "bar");
    try parent_db.set("c", "baz");

    {
        const child = try Transaction.open(env, .{ .read_only = false, .parent = parent });
        errdefer child.abort();
        const child_db = try Database.open(child, .{});
        try child_db.delete("c");
        try child.commit();
    }

    try expectEqual(@as(?[]const u8, null), try parent_db.get("c"));

    {
        const child = try Transaction.open(env, .{ .read_only = false, .parent = parent });
        defer child.abort();
        const child_db = try Database.open(child, .{});
        try child_db.set("c", "baz");
    }

    try expectEqual(@as(?[]const u8, null), try parent_db.get("c"));
}
