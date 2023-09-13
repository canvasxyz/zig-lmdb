const std = @import("std");
const assert = std.debug.assert;
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");

const Transaction = @import("transaction.zig");
const Database = @import("database.zig");
const Cursor = @This();

ptr: ?*c.MDB_cursor,

pub const Entry = struct { key: []const u8, value: []const u8 };

pub fn open(db: Database) !Cursor {
    var cursor = Cursor{ .ptr = null };

    try switch (c.mdb_cursor_open(db.txn.ptr, db.dbi, &cursor.ptr)) {
        0 => {},
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorOpenError,
    };

    return cursor;
}

pub fn close(self: Cursor) void {
    c.mdb_cursor_close(self.ptr);
}

pub fn getCurrentEntry(self: Cursor) !Entry {
    var k: c.MDB_val = undefined;
    var v: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, &k, &v, c.MDB_GET_CURRENT)) {
        0 => .{
            .key = @as([*]u8, @ptrCast(k.mv_data))[0..k.mv_size],
            .value = @as([*]u8, @ptrCast(v.mv_data))[0..v.mv_size],
        },
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn getCurrentKey(self: Cursor) ![]const u8 {
    var slice: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, &slice, null, c.MDB_GET_CURRENT)) {
        0 => @as([*]u8, @ptrCast(slice.mv_data))[0..slice.mv_size],
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorError,
    };
}

pub fn getCurrentValue(self: Cursor) ![]const u8 {
    var v: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, null, &v, c.MDB_GET_CURRENT)) {
        0 => @as([*]u8, @ptrCast(v.mv_data))[0..v.mv_size],
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn setCurrentValue(self: Cursor, value: []const u8) !void {
    var k: c.MDB_val = undefined;
    try switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_GET_CURRENT)) {
        0 => {},
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorError,
    };

    var v: c.MDB_val = .{ .mv_size = value.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(value.ptr))) };
    try switch (c.mdb_cursor_put(self.ptr, &k, &v, c.MDB_CURRENT)) {
        0 => {},
        c.MDB_MAP_FULL => error.LmdbMapFull,
        c.MDB_TXN_FULL => error.LmdbTxnFull,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        else => error.LmdbCursorError,
    };
}

pub fn deleteCurrentKey(self: Cursor) !void {
    try switch (c.mdb_cursor_del(self.ptr, 0)) {
        0 => {},
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorDeleteError,
    };
}

pub fn goToNext(self: Cursor) !?[]const u8 {
    var k: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_NEXT)) {
        0 => @as([*]u8, @ptrCast(k.mv_data))[0..k.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn goToPrevious(self: Cursor) !?[]const u8 {
    var k: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_PREV)) {
        0 => @as([*]u8, @ptrCast(k.mv_data))[0..k.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn goToLast(self: Cursor) !?[]const u8 {
    var k: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_LAST)) {
        0 => @as([*]u8, @ptrCast(k.mv_data))[0..k.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn goToFirst(self: Cursor) !?[]const u8 {
    var k: c.MDB_val = undefined;
    return switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_FIRST)) {
        0 => @as([*]u8, @ptrCast(k.mv_data))[0..k.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn goToKey(self: Cursor, key: []const u8) !void {
    var k: c.MDB_val = undefined;
    k.mv_size = key.len;
    k.mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr)));
    try switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_SET_KEY)) {
        0 => {},
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}

pub fn seek(self: Cursor, key: []const u8) !?[]const u8 {
    var k: c.MDB_val = undefined;
    k.mv_size = key.len;
    k.mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr)));
    return switch (c.mdb_cursor_get(self.ptr, &k, null, c.MDB_SET_RANGE)) {
        0 => @as([*]u8, @ptrCast(k.mv_data))[0..k.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbCursorGetError,
    };
}
