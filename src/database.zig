const std = @import("std");

const c = @import("c.zig");
const Transaction = @import("transaction.zig");
const Stat = @import("stat.zig");
const utils = @import("utils.zig");

const Database = @This();

txn: Transaction,
dbi: c.MDB_dbi,

pub const Options = struct {
    name: ?[*:0]const u8 = null,
    create: bool = true,
};

pub fn open(txn: Transaction, options: Options) !Database {
    var db: Database = undefined;
    try db.init(txn, options);
    return db;
}

pub fn init(self: *Database, txn: Transaction, options: Options) !void {
    self.txn = txn;
    self.dbi = 0;

    var flags: c_uint = 0;
    if (options.create) {
        flags |= c.MDB_CREATE;
    }

    try switch (c.mdb_dbi_open(txn.ptr, options.name, flags, &self.dbi)) {
        0 => {},
        c.MDB_NOTFOUND => error.LmdbDatabaseNotFound,
        c.MDB_DBS_FULL => error.LmdbDatabaseFull,
        else => error.LmdbDatabaseOpenError,
    };
}

pub fn close(self: Database) void {
    const env = self.txn.getEnvironment();
    c.mdb_dbi_close(env.ptr, self.dbi);
}

pub fn stat(self: Database) !Stat {
    var result: c.MDB_stat = undefined;
    try switch (c.mdb_stat(self.txn.ptr, self.dbi, &result)) {
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

pub fn get(self: Database, key: []const u8) !?[]const u8 {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = 0, .mv_data = null };
    return switch (c.mdb_get(self.txn.ptr, self.dbi, &k, &v)) {
        0 => @as([*]u8, @ptrCast(v.mv_data))[0..v.mv_size],
        c.MDB_NOTFOUND => null,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseGetError,
    };
}

pub fn set(self: Database, key: []const u8, value: []const u8) !void {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = value.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(value.ptr))) };
    try switch (c.mdb_put(self.txn.ptr, self.dbi, &k, &v, 0)) {
        0 => {},
        c.MDB_MAP_FULL => error.LmdbMapFull,
        c.MDB_TXN_FULL => error.LmdbTxnFull,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseSetError,
    };
}

pub fn delete(self: Database, key: []const u8) !void {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    try switch (c.mdb_del(self.txn.ptr, self.dbi, &k, null)) {
        0 => {},
        c.MDB_NOTFOUND => error.KeyNotFound,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbDatabaseDeleteError,
    };
}
