const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");
const Environment = @import("environment.zig");

const Stat = @import("stat.zig");
const Transaction = @This();

pub const TransactionOptions = struct {
    mode: Mode,
    parent: ?Transaction = null,
};

pub const DatabaseOptions = struct {
    name: ?[*:0]const u8 = null,
    create: bool = true,
};

pub const Mode = enum { ReadOnly, ReadWrite };

pub const DBI = u32;

ptr: ?*c.MDB_txn = null,

pub fn open(env: Environment, options: TransactionOptions) !Transaction {
    var txn = Transaction{};

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

    return txn;
}

pub fn openDatabase(self: Transaction, options: DatabaseOptions) !DBI {
    var dbi: DBI = 0;

    var flags: c_uint = 0;
    if (options.create) {
        flags |= c.MDB_CREATE;
    }

    try switch (c.mdb_dbi_open(self.ptr, options.name, flags, &dbi)) {
        0 => {},
        c.MDB_NOTFOUND => error.LmdbDatabaseNotFound,
        c.MDB_DBS_FULL => error.LmdbDatabaseFull,
        else => error.LmdbDatabaseOpenError,
    };

    return dbi;
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

pub fn stat(self: Transaction, dbi: ?DBI) !Stat {
    const database = dbi orelse try self.openDatabase(.{});

    var result: c.MDB_stat = undefined;
    try switch (c.mdb_stat(self.txn.ptr, database, &result)) {
        0 => {},
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseStatError,
    };

    return .{
        .psize = result.ms_psize,
        .depth = result.ms_psize,
        .branch_pages = result.ms_branch_pages,
        .leaf_pages = result.ms_leaf_pages,
        .overflow_pages = result.ms_overflow_pages,
        .entries = result.ms_entries,
    };
}

pub fn get(self: Transaction, dbi: ?DBI, key: []const u8) !?[]const u8 {
    const database = dbi orelse try self.openDatabase(.{});

    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = 0, .mv_data = null };

    return switch (c.mdb_get(self.ptr, database, &k, &v)) {
        0 => @as([*]u8, @ptrCast(v.mv_data))[0..v.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseGetError,
    };
}

pub fn set(self: Transaction, dbi: ?DBI, key: []const u8, value: []const u8) !void {
    const database = dbi orelse try self.openDatabase(.{});

    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = value.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(value.ptr))) };

    try switch (c.mdb_put(self.ptr, database, &k, &v, 0)) {
        0 => {},
        c.MDB_MAP_FULL => error.LmdbMapFull,
        c.MDB_TXN_FULL => error.LmdbTxnFull,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseSetError,
    };
}

pub fn delete(self: Transaction, dbi: ?DBI, key: []const u8) !void {
    const database = dbi orelse try self.openDatabase(.{});

    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    try switch (c.mdb_del(self.ptr, database, &k, null)) {
        0 => {},
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseDeleteError,
    };
}
