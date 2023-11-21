const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Cursor = @import("cursor.zig");

pub var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

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

pub fn expectEqualEntries(txn: Transaction, dbi: Transaction.DBI, entries: []const [2][]const u8) !void {
    const cursor = try Cursor.open(txn, dbi);
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

    const env = try Environment.open(tmp.dir, .{});
    defer env.close();

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try txn.set(dbi, "a", "foo");
        try txn.set(dbi, "b", "bar");
        try txn.set(dbi, "c", "baz");
        try txn.set(dbi, "d", "qux");
        try txn.commit();
    }

    {
        const txn = try Transaction.open(env, .{ .mode = .ReadOnly });
        defer txn.abort();

        const dbi = try txn.openDatabase(null, .{});

        try expectEqualEntries(txn, dbi, &[_][2][]const u8{
            .{ "a", "foo" },
            .{ "b", "bar" },
            .{ "c", "baz" },
            .{ "d", "qux" },
        });
    }
}
