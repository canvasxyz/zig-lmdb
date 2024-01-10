const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const lmdb = @import("lmdb");

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

pub fn expectEqualEntries(db: lmdb.Database, entries: []const [2][]const u8) !void {
    const cursor = try lmdb.Cursor.init(db);
    defer cursor.deinit();

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
