const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Database = @import("database.zig");
const Cursor = @import("cursor.zig");

var buffer: [4096]u8 = undefined;

pub fn resolvePath(dir: std.fs.Dir, name: []const u8) ![*:0]const u8 {
    const path = try dir.realpath(name, &buffer);
    buffer[path.len] = 0;
    return @as([*:0]const u8, @ptrCast(buffer[0..path.len]));
}

pub fn getCString(value: []const u8) [*:0]const u8 {
    @memcpy(buffer[0..value.len], value);
    return @as([*:0]const u8, @ptrCast(&buffer));
}

pub fn expectEqualKeys(actual: ?[]const u8, expected: ?[]const u8) !void {
    if (actual) |actual_bytes| {
        if (expected) |expected_bytes| {
            try expectEqualSlices(u8, actual_bytes, expected_bytes);
        } else {
            return error.TestExpectedEqualKeys;
        }
    } else if (expected != null) {
        return error.TestExpectedEqualKeys;
    }
}

pub fn expectEqualEntries(db: Database, entries: []const [2][]const u8) !void {
    const cursor = try Cursor.open(db);
    defer cursor.close();

    var i: usize = 0;
    var key = try cursor.goToFirst();
    while (key != null) : (key = try cursor.goToNext()) {
        try expect(i < entries.len);
        try expectEqualSlices(u8, entries[i][0], try cursor.getCurrentKey());
        try expectEqualSlices(u8, entries[i][1], try cursor.getCurrentValue());
        i += 1;
    }

    try expectEqual(entries.len, i);
}

test "expectEqualEntries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try resolvePath(tmp.dir, ".");

    const env = try Environment.open(path, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .read_only = false });
        errdefer txn.abort();

        const db = try Database.open(txn, .{});

        try db.set("a", "foo");
        try db.set("b", "bar");
        try db.set("c", "baz");
        try db.set("d", "qux");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .read_only = true });
        defer txn.abort();

        const db = try Database.open(txn, .{});

        try expectEqualEntries(db, &[_][2][]const u8{
            .{ "a", "foo" },
            .{ "b", "bar" },
            .{ "c", "baz" },
            .{ "d", "qux" },
        });
    }
}
