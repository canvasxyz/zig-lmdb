const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");
const Environment = @import("environment.zig");

const Transaction = @This();

pub const Options = struct {
    read_only: bool = true,
    parent: ?Transaction = null,
};

ptr: ?*c.MDB_txn,

pub fn open(env: Environment, options: Options) !Transaction {
    var txn = Transaction{ .ptr = null };

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

    return txn;
}

pub fn getEnvironment(self: Transaction) !Environment {
    return Environment{ .ptr = c.mdb_txn_env(self.ptr) };
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
