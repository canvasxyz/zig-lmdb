# zig-lmdb

Zig bindings for LMDB.

Built and tested with Zig version `0.14.0`.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
- [API](#api)
  - [`Environment`](#environment)
  - [`Transaction`](#transaction)
  - [`Database`](#database)
  - [`Cursor`](#cursor)
  - [`Stat`](#stat)
- [Benchmarks](#benchmarks)

## Installation

Add zig-lmdb to `build.zig.zon`

```zig
.{
    .dependencies = .{
        .lmdb = .{
            .url = "https://github.com/canvasxyz/zig-lmdb/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "1220d5ca02660a791ea022d60a032ae56b629002d3930117d8047ecf615f012044f7",
        },
    },
}
```

## Usage

An LMDB environment can either have multiple named databases, or a single unnamed database.

To use a single unnamed database, open a transaction and use the `txn.get`, `txn.set`, `txn.delete`, and `txn.cursor` methods directly.

```zig
const lmdb = @import("lmdb");

pub fn main() !void {
    const env = try lmdb.Environment.init("path/to/db", .{});
    defer env.deinit();

    const txn = try lmdb.Transaction.init(env, .{ .mode = .ReadWrite });
    errdefer txn.abort();

    try txn.set("aaa", "foo");
    try txn.set("bbb", "bar");

    try txn.commit();
}
```

To use named databases, open the environment with a non-zero `max_dbs` value. Then open each named database using `Transaction.database`, which returns a `Database` struct with `db.get`/`db.set`/`db.delete`/`db.cursor` methods. You don't have to close databases, but they're only valid during the lifetime of the transaction.

```zig
const lmdb = @import("lmdb");

pub fn main() !void {
    const env = try lmdb.Environment.init("path/to/db", .{ .max_dbs = 2 });
    defer env.deinit();

    const txn = try lmdb.Transaction.init(env, .{ .mode = .ReadWrite });
    errdefer txn.abort();

    const widgets = try txn.database("widgets", .{ .create = true });
    try widgets.set("aaa", "foo");

    const gadgets = try txn.database("gadgets", .{ .create = true });
    try gadgets.set("aaa", "bar");

    try txn.commit();
}
```

## API

### `Environment`

```zig
pub const Environment = struct {
    pub const Options = struct {
        map_size: usize = 10 * 1024 * 1024,
        max_dbs: u32 = 0,
        max_readers: u32 = 126,
        read_only: bool = false,
        write_map: bool = false,
        no_tls: bool = false,
        no_lock: bool = false,
        mode: u16 = 0o664,
    };

    pub const Info = struct {
        map_size: usize,
        max_readers: u32,
        num_readers: u32,
    };

    pub fn init(path: [*:0]const u8, options: Options) !Environment
    pub fn deinit(self: Environment) void

    pub fn transaction(self: Environment, options: Transaction.Options) !Transaction

    pub fn sync(self: Environment) !void
    pub fn stat(self: Environment) !Stat
    pub fn info(self: Environment) !Info

    pub fn resize(self: Environment, size: usize) !void // mdb_env_set_mapsize
};
```

### `Transaction`

```zig
pub const Transaction = struct {
    pub const Mode = enum { ReadOnly, ReadWrite };

    pub const Options = struct {
        mode: Mode,
        parent: ?Transaction = null,
    };

    pub fn init(env: Environment, options: Options) !Transaction
    pub fn abort(self: Transaction) void
    pub fn commit(self: Transaction) !void

    pub fn get(self: Transaction, key: []const u8) !?[]const u8
    pub fn set(self: Transaction, key: []const u8, value: []const u8) !void
    pub fn delete(self: Transaction, key: []const u8) !void

    pub fn cursor(self: Database) !Cursor
    pub fn database(self: Transaction, name: ?[*:0]const u8, options: Database.Options) !Database
};
```

### `Database`

```zig
pub const Database = struct {
    pub const Options = struct {
        reverse_key: bool = false,
        integer_key: bool = false,
        create: bool = false,
    };

    pub const Stat = struct {
        psize: u32,
        depth: u32,
        branch_pages: usize,
        leaf_pages: usize,
        overflow_pages: usize,
        entries: usize,
    };

    pub fn open(txn: Transaction, name: ?[*:0]const u8, options: Options) !Database

    pub fn get(self: Database, key: []const u8) !?[]const u8
    pub fn set(self: Database, key: []const u8, value: []const u8) !void
    pub fn delete(self: Database, key: []const u8) !void

    pub fn cursor(self: Database) !Cursor

    pub fn stat(self: Database) !Stat
};
```

### `Cursor`

```zig
pub const Cursor = struct {
    pub const Entry = struct { key: []const u8, value: []const u8 };

    pub fn init(db: Database) !Cursor
    pub fn deinit(self: Cursor) void

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

## Benchmarks

```
zig build bench
```

### 1k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0003 |   0.0146 |   0.0006 | 0.0014 |  1623746 |
| get random 100 entries   |        100 |   0.0305 |   0.0364 |   0.0314 | 0.0007 |  3181302 |
| iterate over all entries |        100 |   0.0311 |   0.0340 |   0.0312 | 0.0003 | 32000020 |
| set random 1 entry       |        100 |   0.0931 |   0.3103 |   0.1256 | 0.0332 |     7959 |
| set random 100 entries   |        100 |   0.1151 |   0.2963 |   0.1441 | 0.0279 |   694063 |
| set random 1k entries    |         10 |   0.3931 |   0.4568 |   0.4322 | 0.0196 |  2313543 |
| set random 50k entries   |         10 |  12.2390 |  15.7186 |  12.8449 | 1.0957 |  3892584 |

### 50k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0002 |   0.0129 |   0.0011 | 0.0013 |   934868 |
| get random 100 entries   |        100 |   0.0250 |   0.0531 |   0.0280 | 0.0044 |  3566696 |
| iterate over all entries |        100 |   0.6055 |   0.6735 |   0.6173 | 0.0145 | 81001777 |
| set random 1 entry       |        100 |   0.0551 |   0.6420 |   0.0742 | 0.0610 |    13476 |
| set random 100 entries   |        100 |   0.3705 |   3.3370 |   0.4798 | 0.2896 |   208400 |
| set random 1k entries    |         10 |   0.8556 |   1.0658 |   0.9524 | 0.0709 |  1050002 |
| set random 50k entries   |         10 |  19.3440 |  21.0593 |  19.7118 | 0.5614 |  2536546 |

### 1m entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0004 |   0.0211 |   0.0022 | 0.0022 |   462423 |
| get random 100 entries   |        100 |   0.0517 |   0.1809 |   0.0715 | 0.0251 |  1398510 |
| iterate over all entries |        100 |  12.2841 |  14.0215 |  12.4831 | 0.2681 | 80108379 |
| set random 1 entry       |        100 |   0.0645 |   1.4024 |   0.1043 | 0.1328 |     9587 |
| set random 100 entries   |        100 |   0.6773 |   7.3026 |   2.3796 | 0.6177 |    42025 |
| set random 1k entries    |         10 |   7.3463 |  15.9778 |  13.2091 | 2.9459 |    75705 |
| set random 50k entries   |         10 |  47.9222 |  60.7651 |  52.2927 | 3.4127 |   956156 |
