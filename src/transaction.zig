const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");
const Environment = @import("environment.zig");

const Transaction = @This();

pub const Options = struct {
    mode: Mode,
    parent: ?Transaction = null,
};

pub const Mode = enum { ReadOnly, ReadWrite };

mode: Mode,
ptr: ?*c.MDB_txn,

pub fn open(env: Environment, options: Options) !Transaction {
    var txn: Transaction = undefined;
    try txn.init(env, options);
    return txn;
}

pub fn init(self: *Transaction, env: Environment, options: Options) !void {
    self.mode = options.mode;
    self.ptr = null;

    var flags: c_uint = 0;
    switch (options.mode) {
        .ReadOnly => {
            flags |= c.MDB_RDONLY;
        },
        .ReadWrite => {},
    }

    var parentPtr: ?*c.MDB_txn = null;
    if (options.parent) |parent| {
        parentPtr = parent.ptr;
    }

    try switch (c.mdb_txn_begin(env.ptr, parentPtr, flags, &self.ptr)) {
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

pub fn getEnvironment(self: Transaction) !Environment {
    return Environment{ .ptr = c.mdb_txn_env(self.ptr) };
}

pub fn abort(self: Transaction) void {
    c.mdb_txn_abort(self.ptr);
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
