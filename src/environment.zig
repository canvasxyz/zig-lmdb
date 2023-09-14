const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");

const Stat = @import("stat.zig");

const Environment = @This();

pub const Options = struct {
    map_size: usize = 10485760,
    max_dbs: u32 = 0,
    mode: u16 = 0o664,
};

pub const Error = error{
    LmdbVersionMismatch,
    LmdbEnvironmentError,
    LmdbCorruptDatabase,
    ACCES,
    NOENT,
    AGAIN,
};

ptr: ?*c.MDB_env = null,

pub fn open(path: [*:0]const u8, options: Options) !Environment {
    var env = Environment{};
    try env.init(path, options);
    return env;
}

pub fn init(self: *Environment, path: [*:0]const u8, options: Options) !void {
    try switch (c.mdb_env_create(&self.ptr)) {
        0 => {},
        else => error.LmdbEnvironmentCreateError,
    };

    try switch (c.mdb_env_set_mapsize(self.ptr, options.map_size)) {
        0 => {},
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbEnvironmentError,
    };

    try switch (c.mdb_env_set_maxdbs(self.ptr, options.max_dbs)) {
        0 => {},
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        else => error.LmdbEnvironmentError,
    };

    const flags: u32 = c.MDB_NOTLS;

    errdefer c.mdb_env_close(self.ptr);
    try switch (c.mdb_env_open(self.ptr, path, flags, options.mode)) {
        0 => {},
        c.MDB_VERSION_MISMATCH => error.LmdbEnvironmentVersionMismatch,
        c.MDB_INVALID => error.LmdbCorruptDatabase,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.NOENT) => error.NOENT,
        @intFromEnum(std.os.E.AGAIN) => error.AGAIN,
        else => error.LmdbEnvironmentError,
    };
}

pub fn close(self: Environment) void {
    c.mdb_env_close(self.ptr);
}

pub fn flush(self: Environment) !void {
    try switch (c.mdb_env_sync(self.ptr, 0)) {
        0 => {},
        @intFromEnum(std.os.E.INVAL) => error.INVAL,
        @intFromEnum(std.os.E.ACCES) => error.ACCES,
        @intFromEnum(std.os.E.IO) => error.IO,
        else => error.LmdbEnvironmentError,
    };
}

pub fn stat(self: Environment) !Stat {
    var result: c.MDB_stat = undefined;
    try switch (c.mdb_env_stat(self.ptr, &result)) {
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
