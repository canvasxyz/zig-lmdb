const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const c = @import("c.zig");
const Stat = @import("stat.zig");
const errors = @import("errors.zig");
const utils = @import("utils.zig");

const Environment = @This();

pub const EnvironmentOptions = struct {
    map_size: usize = 10 * 1024 * 1024,
    max_dbs: u32 = 0,
    mode: u16 = 0o664,
};

pub const EnvironmentInfo = struct {
    map_size: usize,
    max_readers: u32,
    num_readers: u32,
};

ptr: ?*c.MDB_env = null,

pub fn open(dir: std.fs.Dir, options: EnvironmentOptions) !Environment {
    var env = Environment{};

    try errors.throw(c.mdb_env_create(&env.ptr));
    try errors.throw(c.mdb_env_set_mapsize(env.ptr, options.map_size));
    try errors.throw(c.mdb_env_set_maxdbs(env.ptr, options.max_dbs));

    const flags: u32 = c.MDB_NOTLS;

    errdefer c.mdb_env_close(env.ptr);

    const path = try std.os.getFdPath(dir.fd, &utils.path_buffer);
    utils.path_buffer[path.len] = 0;
    try errors.throw(c.mdb_env_open(env.ptr, @ptrCast(path.ptr), flags, options.mode));

    return env;
}

pub fn close(self: Environment) void {
    c.mdb_env_close(self.ptr);
}

pub fn flush(self: Environment) !void {
    try errors.throw(c.mdb_env_sync(self.ptr, 0));
}

pub fn stat(self: Environment) !Stat {
    var result: c.MDB_stat = undefined;
    try errors.throw(c.mdb_env_stat(self.ptr, &result));

    return .{
        .psize = result.ms_psize,
        .depth = result.ms_depth,
        .branch_pages = result.ms_branch_pages,
        .leaf_pages = result.ms_leaf_pages,
        .overflow_pages = result.ms_overflow_pages,
        .entries = result.ms_entries,
    };
}

pub fn info(self: Environment) !EnvironmentInfo {
    var result: c.MDB_envinfo = undefined;
    try errors.throw(c.mdb_env_info(self.ptr, &result));

    return .{
        .map_size = result.me_mapsize,
        .max_readers = result.me_maxreaders,
        .num_readers = result.me_numreaders,
    };
}

pub fn resize(self: Environment, size: usize) !void {
    try errors.throw(c.mdb_env_set_mapsize(self.ptr, size));
}
