const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");
const Environment = @import("environment.zig");

const Transaction = @This();

pub const Options = struct {
    read_only: bool = true,
    dbi: ?[*:0]const u8 = null,
    parent: ?Transaction = null,
};

ptr: ?*c.MDB_txn,
dbi: c.MDB_dbi,

pub fn open(env: Environment, options: Options) !Transaction {
    var txn = Transaction{ .ptr = null, .dbi = 0 };

    {
        var flags: c_uint = 0;
        if (options.read_only) {
            flags |= c.MDB_RDONLY;
        }

        var parentPtr: ?*c.MDB_txn = null;
        if (options.parent) |parent| {
            parentPtr = parent.ptr;
        }

        try switch (c.mdb_txn_begin(env.ptr, parentPtr, flags, &txn.ptr)) {
            0 => {},
            @intFromEnum(std.os.E.ACCES) => error.ACCES,
            @intFromEnum(std.os.E.NOMEM) => error.NOMEM,
            c.MDB_PANIC => error.LmdbPanic,
            c.MDB_BAD_TXN => error.LmdbInvalidTransaction,
            c.MDB_MAP_RESIZED => error.LmdbMapResized,
            c.MDB_READERS_FULL => error.LmdbReadersFull,
            c.MDB_BAD_RSLOT => error.LmdbBadReaderSlot,
            else => error.LmdbTransactionBeginError,
        };
    }

    {
        const flags: c_uint = if (options.read_only) 0 else c.MDB_CREATE;
        try switch (c.mdb_dbi_open(txn.ptr, options.dbi, flags, &txn.dbi)) {
            0 => {},
            c.MDB_NOTFOUND => error.LmdbDbiNotFound,
            c.MDB_DBS_FULL => error.LmdbDbsFull,
            else => error.LmdbDbiOpenError,
        };
    }

    return txn;
}

pub fn commit(self: Transaction) !void {
    try switch (c.mdb_txn_commit(self.ptr)) {
        0 => {},
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        @intFromEnum(std.os.E.NOSPC) => error.NOSPC,
        @intFromEnum(std.os.E.IO) => error.IO,
        @intFromEnum(std.os.E.NOMEM) => error.NOMEM,
        else => error.LmdbTransactionCommitError,
    };
}

pub fn abort(self: Transaction) void {
    c.mdb_txn_abort(self.ptr);
}

pub fn get(self: Transaction, key: []const u8) !?[]const u8 {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = 0, .mv_data = null };
    return switch (c.mdb_get(self.ptr, self.dbi, &k, &v)) {
        0 => @as([*]u8, @ptrCast(v.mv_data))[0..v.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbTransactionGetError,
    };
}

pub fn set(self: Transaction, key: []const u8, value: []const u8) !void {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = value.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(value.ptr))) };
    try switch (c.mdb_put(self.ptr, self.dbi, &k, &v, 0)) {
        0 => {},
        c.MDB_MAP_FULL => error.LmdbMapFull,
        c.MDB_TXN_FULL => error.LmdbTxnFull,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbTransactionSetError,
    };
}

pub fn delete(self: Transaction, key: []const u8) !void {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    try switch (c.mdb_del(self.ptr, self.dbi, &k, null)) {
        0 => {},
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbTransactionDeleteError,
    };
}
