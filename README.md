# zig-lmdb

Zig bindings for LMDB.

Built and tested with Zig version `0.12.0-dev.2030+2ac315c24`.

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
    const env = try lmdb.Environment.open("path/to/db", .{ .max_dbs = 2 });
    defer env.close();

    const txn = try lmdb.Transaction.open(env, .{ .mode = .ReadWrite });
    errdefer txn.abort();

    const widgets = try txn.openDatabase("widgets", .{});
    try txn.set(widgets, "a", "foo");

    const gadgets = try txn.openDatabase("gadgets", .{});
    try txn.set(gadgets, "b", "bar");

    try txn.commit();
}
```

To use a single unnamed database, use `null` as the database name.

```zig
const lmdb = @import("lmdb");

pub fn main() !void {
    const env = try lmdb.Environment.open("path/to/db", .{});
    defer env.close();

    const txn = try lmdb.Transaction.open(env, .{ .mode = .ReadWrite });
    errdefer txn.abort();

    const dbi = try txn.openDatabase(null, .{});

    try txn.set(dbi, "a", "foo");
    try txn.set(dbi, "b", "bar");

    try txn.commit();
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

    pub fn open(path: []const u8, options: EnvironmentOptions) !Environment
    pub fn openZ(path: [:0]const u8, options: EnvironmentOptions) !Environment
    pub fn openDir(dir: std.fs.Dir, options: EnvironmentOptions) !Environment

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

    pub fn openDatabase(self: Transaction, name: ?[]const u8, options: DatabaseOptions) !DBI
    pub fn openDatabaseZ(self: Transaction, name: ?[*:0]u8, options: DatabaseOptions) !DBI

    pub fn getEnvironment(self: Transaction) !Environment {}
    pub fn stat(self: Transaction, dbi: DBI) !Stat

    pub fn get(self: Transaction, dbi: DBI, key: []const u8) !?[]const u8
    pub fn set(self: Transaction, dbi: DBI, key: []const u8, value: []const u8) !void
    pub fn delete(self: Transaction, dbi: DBI, key: []const u8) !void
};
```

### `Cursor`

```zig
pub const Cursor = struct {
    pub const Entry = struct { key: []const u8, value: []const u8 };

    pub fn open(txn: Transaction, dbi: Transaction.DBI) !Cursor
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

> ⚠️ Always close cursors **before** committing or aborting the transaction.

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

```
zig build bench
```

### 1k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0009 |   0.0142 |   0.0012 | 0.0013 |   859298 |
| get random 100 entries   |        100 |   0.0164 |   0.0178 |   0.0170 | 0.0002 |  5865959 |
| iterate over all entries |        100 |   0.0173 |   0.0181 |   0.0173 | 0.0001 | 57723023 |
| set random 1 entry       |        100 |   0.0613 |   0.1613 |   0.0826 | 0.0181 |    12109 |
| set random 100 entries   |        100 |   0.0930 |   0.4078 |   0.1249 | 0.0327 |   800633 |
| set random 1k entries    |         10 |   0.4011 |   0.4233 |   0.4124 | 0.0077 |  2424709 |
| set random 50k entries   |         10 |  15.8565 |  16.9226 |  16.1385 | 0.3964 |  3098176 |

### 50k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0008 |   0.0135 |   0.0017 | 0.0013 |   582686 |
| get random 100 entries   |        100 |   0.0236 |   0.0561 |   0.0282 | 0.0058 |  3546626 |
| iterate over all entries |        100 |   0.6060 |   0.6867 |   0.6203 | 0.0175 | 80607307 |
| set random 1 entry       |        100 |   0.0553 |   0.6738 |   0.0759 | 0.0661 |    13170 |
| set random 100 entries   |        100 |   0.3644 |   0.5885 |   0.4624 | 0.0404 |   216278 |
| set random 1k entries    |         10 |   0.9273 |   1.3168 |   1.0381 | 0.1162 |   963267 |
| set random 50k entries   |         10 |  23.0990 |  25.0138 |  23.5197 | 0.6563 |  2125879 |

### 1m entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0010 |   0.0288 |   0.0028 | 0.0028 |   360359 |
| get random 100 entries   |        100 |   0.0498 |   0.1970 |   0.0746 | 0.0314 |  1339794 |
| iterate over all entries |        100 |  12.2684 |  13.0028 |  12.3550 | 0.1304 | 80939213 |
| set random 1 entry       |        100 |   0.0630 |   0.7330 |   0.0827 | 0.0683 |    12098 |
| set random 100 entries   |        100 |   0.6055 |   3.5569 |   2.2590 | 0.3394 |    44267 |
| set random 1k entries    |         10 |   7.2128 |  17.8363 |  13.0217 | 3.1923 |    76795 |
| set random 50k entries   |         10 |  53.1443 |  62.6031 |  56.2486 | 2.6658 |   888911 |
