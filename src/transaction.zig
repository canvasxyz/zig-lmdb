const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");
const Environment = @import("environment.zig");
const errors = @import("errors.zig");

const Stat = @import("stat.zig");
const utils = @import("utils.zig");

const Transaction = @This();

pub const TransactionOptions = struct {
    mode: Mode,
    parent: ?Transaction = null,
};

pub const DatabaseOptions = struct {
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

    try errors.throw(c.mdb_txn_begin(env.ptr, parentPtr, flags, &txn.ptr));

    return txn;
}

pub fn openDatabase(self: Transaction, name: ?[]const u8, options: DatabaseOptions) !DBI {
    if (name) |n| {
        @memcpy(utils.path_buffer[0..n.len], n);
        utils.path_buffer[n.len] = 0;
        return try openDatabaseZ(self, @ptrCast(&utils.path_buffer), options);
    } else {
        return try openDatabaseZ(self, null, options);
    }
}

pub fn openDatabaseZ(self: Transaction, name: ?[*:0]const u8, options: DatabaseOptions) !DBI {
    var dbi: DBI = 0;

    var flags: c_uint = 0;
    if (options.create) {
        flags |= c.MDB_CREATE;
    }

    try errors.throw(c.mdb_dbi_open(self.ptr, name, flags, &dbi));

    return dbi;
}

pub fn getEnvironment(self: Transaction) !Environment {
    return Environment{ .ptr = c.mdb_txn_env(self.ptr) };
}

pub fn abort(self: Transaction) void {
    c.mdb_txn_abort(self.ptr);
}

pub fn commit(self: Transaction) !void {
    try errors.throw(c.mdb_txn_commit(self.ptr));
}

pub fn stat(self: Transaction, dbi: DBI) !Stat {
    var result: c.MDB_stat = undefined;
    try errors.throw(c.mdb_stat(self.ptr, dbi, &result));

    return .{
        .psize = result.ms_psize,
        .depth = result.ms_depth,
        .branch_pages = result.ms_branch_pages,
        .leaf_pages = result.ms_leaf_pages,
        .overflow_pages = result.ms_overflow_pages,
        .entries = result.ms_entries,
    };
}

pub fn get(self: Transaction, dbi: DBI, key: []const u8) !?[]const u8 {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = 0, .mv_data = null };

    switch (c.mdb_get(self.ptr, dbi, &k, &v)) {
        c.MDB_NOTFOUND => return null,
        else => |rc| try errors.throw(rc),
    }

    return @as([*]u8, @ptrCast(v.mv_data))[0..v.mv_size];
}

pub fn set(self: Transaction, dbi: DBI, key: []const u8, value: []const u8) !void {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    var v: c.MDB_val = .{ .mv_size = value.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(value.ptr))) };

    try errors.throw(c.mdb_put(self.ptr, dbi, &k, &v, 0));
}

pub fn delete(self: Transaction, dbi: DBI, key: []const u8) !void {
    var k: c.MDB_val = .{ .mv_size = key.len, .mv_data = @as([*]u8, @ptrFromInt(@intFromPtr(key.ptr))) };
    try errors.throw(c.mdb_del(self.ptr, dbi, &k, null));
}
