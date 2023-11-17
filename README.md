# zig-lmdb

Zig bindings for LMDB. Built and tested with Zig version `0.11.0`.

## Table of Contents

- [Usage](#usage)
- [API](#api)
  - [`Environment`](#environment)
  - [`Transaction`](#transaction)
  - [`Cursor`](#cursor)
  - [`Stat`](#stat)
- [Benchmarks](#benchmarks)

## Usage

An LMDB environment can either have multiple named databases, or a single unnamed database.

To use named databases, make sure to open the environment with a non-zero `EnvironmentOptions.max_dbs` value. Databases must be opened within each transaction using `Transaction.openDatabase`, which returns a `u32` database ID that can be passed as the first argument to `txn.get`, `txn.set`, `txn.delete`, etc. You don't have to close databases.

```zig
const lmdb = @import("lmdb");

pub fn main() !void {
    const env = try lmdb.Environment.open("db", .{ .max_dbs = 4 });
    defer env.close();

    {
        const txn = try lmdb.Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        const widgets = try txn.openDatabase(.{ .name = "widgets" });
        try txn.set(widgets, "a", "foo");

        const gadgets = try txn.openDatabase(.{ .name = "gadgets" });
        try txn.set(gadgets, "b", "bar");

        try txn.commit();
    }
}
```

To use a single unnamed database, just use `null` as the database ID.

```zig
const lmdb = @import("lmdb");

pub fn main() !void {
    const env = try lmdb.Environment.open("db", .{ .max_dbs = 4 });
    defer env.close();

    {
        const txn = try lmdb.Transaction.open(env, .{ .mode = .ReadWrite });
        errdefer txn.abort();

        try txn.set(null, "a", "foo");
        try txn.set(null, "b", "bar");

        try txn.commit();
    }
}
```

## API

### `Environment`

```zig
pub const Environment = struct {
    pub const EnvironmentOptions = struct {
        map_size: usize = 10485760,
        max_dbs: u32 = 0,
        mode: u16 = 0o664,
    };

    pub const EnvironmentInfo = struct {
        map_size: usize,
        max_readers: u32,
        num_readers: u32,
    };

    pub fn open(path: [*:0]const u8, options: EnvironmentOptions) !Environment
    pub fn close(self: Environment) void

    pub fn flush(self: Environment) !void
    pub fn stat(self: Environment) !Stat
    pub fn info(self: Environment) !EnvironmentInfo

    pub fn resize(self: Environment, size: usize) !void // mdb_env_set_mapsize
};
```

### `Transaction`

```zig
pub const Transaction = struct {
    pub const Mode = enum { ReadOnly, ReadWrite };

    pub const TransactionOptions = struct {
        mode: Mode,
        parent: ?Transaction = null,
    };

    pub const DBI = u32;

    pub const DatabaseOptions = struct {
        name: ?[*:0]const u8 = null,
        create: bool = true,
    };

    pub fn open(env: Environment, options: Options) !Transaction
    pub fn init(self: *Transaction, env: Environment, options: Options) !void
    pub fn commit(self: Transaction) !void
    pub fn abort(self: Transaction) void

    pub fn openDatabase(self: Transaction, options: DatabaseOptions) !DBI
    pub fn getEnvironment(self: Transaction) !Environment {}
    pub fn stat(self: Transaction, dbi: ?DBI) !Stat

    pub fn get(self: Transaction, dbi: ?DBI, key: []const u8) !?[]const u8
    pub fn set(self: Transaction, dbi: ?DBI, key: []const u8, value: []const u8) !void
    pub fn delete(self: Transaction, dbi: ?DBI, key: []const u8) !void
};
```

### `Cursor`

```zig
pub const Cursor = struct {
    pub const Entry = struct { key: []const u8, value: []const u8 };

    pub fn open(txn: Transaction, dbi: ?Transaction.DBI) !Cursor
    pub fn close(self: Cursor) void

    pub fn getTransaction(self: Cursor) Transaction
    pub fn getDatabase(self: Cursor) Transaction.DBI

    pub fn getCurrentEntry(self: Cursor) !Entry
    pub fn getCurrentKey(self: Cursor) ![]const u8
    pub fn getCurrentValue(self: Cursor) ![]const u8

    pub fn setCurrentValue(self: Cursor, value: []const u8) !void
    pub fn deleteCurrentKey(self: Cursor) !void

    pub fn goToNext(self: Cursor) !?[]const u8
    pub fn goToPrevious(self: Cursor) !?[]const u8
    pub fn goToLast(self: Cursor) !?[]const u8
    pub fn goToFirst(self: Cursor) !?[]const u8
    pub fn goToKey(self: Cursor, key: []const u8) !void

    pub fn seek(self: Cursor, key: []const u8) !?[]const u8
};
```

### `Stat`

```zig
pub const Stat = struct {
    psize: u32,
    depth: u32,
    branch_pages: usize,
    leaf_pages: usize,
    overflow_pages: usize,
    entries: usize,
};
```

## Benchmarks

Run the benchmarks with `zig build bench`.

### 1k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0015 |   0.0168 |   0.0018 | 0.0016 |   543100 |
| get random 100 entries   |        100 |   0.0232 |   0.0287 |   0.0260 | 0.0018 |  3848182 |
| iterate over all entries |        100 |   0.0241 |   0.0251 |   0.0242 | 0.0001 | 41301049 |
| set random 1 entry       |        100 |   0.0798 |   0.2491 |   0.1067 | 0.0281 |     9376 |
| set random 100 entries   |        100 |   0.1073 |   0.2113 |   0.1401 | 0.0185 |   713967 |
| set random 1k entries    |         10 |   0.4005 |   0.4723 |   0.4230 | 0.0200 |  2364137 |
| set random 50k entries   |         10 |  15.7136 |  16.2638 |  15.9125 | 0.2038 |  3142188 |

### 50k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0008 |   0.0083 |   0.0016 | 0.0008 |   610366 |
| get random 100 entries   |        100 |   0.0237 |   0.0552 |   0.0278 | 0.0046 |  3593512 |
| iterate over all entries |        100 |   0.6061 |   0.7458 |   0.6231 | 0.0257 | 80248291 |
| set random 1 entry       |        100 |   0.0547 |   0.6264 |   0.0766 | 0.0770 |    13059 |
| set random 100 entries   |        100 |   0.3853 |   0.6939 |   0.4729 | 0.0530 |   211455 |
| set random 1k entries    |         10 |   0.9270 |   1.0725 |   0.9918 | 0.0452 |  1008234 |
| set random 50k entries   |         10 |  22.5148 |  24.3988 |  22.8831 | 0.5661 |  2185021 |

### 1m entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0010 |   0.0212 |   0.0026 | 0.0021 |   382834 |
| get random 100 entries   |        100 |   0.0558 |   0.1683 |   0.0731 | 0.0195 |  1367335 |
| iterate over all entries |        100 |  12.2588 |  13.6815 |  12.4136 | 0.2387 | 80556698 |
| set random 1 entry       |        100 |   0.0676 |   0.7070 |   0.0930 | 0.0719 |    10758 |
| set random 100 entries   |        100 |   0.5910 |   3.2007 |   2.3102 | 0.3127 |    43287 |
| set random 1k entries    |         10 |   7.6770 |  14.2947 |  12.6750 | 2.5024 |    78895 |
| set random 50k entries   |         10 |  51.5173 |  61.5861 |  54.2918 | 2.9450 |   920950 |
