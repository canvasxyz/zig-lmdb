# zig-lmdb

Zig bindings for LMDB.

Built and tested with Zig version `0.14.1`.

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
            .url = "https://github.com/canvasxyz/zig-lmdb/archive/refs/tags/v0.2.0.tar.gz",
            // .hash = "...",
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
| get random 1 entry       |        100 |   0.0001 |   0.0069 |   0.0002 | 0.0007 |  4082799 |
| get random 100 entries   |        100 |   0.0089 |   0.0204 |   0.0118 | 0.0045 |  8473664 |
| iterate over all entries |        100 |   0.0175 |   0.0290 |   0.0221 | 0.0023 | 45156084 |
| set random 1 entry       |        100 |   0.0498 |   0.1814 |   0.0582 | 0.0159 |    17169 |
| set random 100 entries   |        100 |   0.0750 |   0.1275 |   0.0841 | 0.0068 |  1189692 |
| set random 1k entries    |         10 |   0.2495 |   0.2606 |   0.2557 | 0.0035 |  3911596 |
| set random 50k entries   |         10 |   8.8281 |  12.4414 |   9.8183 | 1.1449 |  5092551 |

### 50k entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0002 |   0.0072 |   0.0011 | 0.0008 |   914620 |
| get random 100 entries   |        100 |   0.0194 |   0.0562 |   0.0232 | 0.0058 |  4312356 |
| iterate over all entries |        100 |   0.4243 |   0.7743 |   0.5451 | 0.0315 | 91727484 |
| set random 1 entry       |        100 |   0.0446 |   0.3028 |   0.0577 | 0.0263 |    17342 |
| set random 100 entries   |        100 |   0.3673 |   0.6541 |   0.4756 | 0.0776 |   210273 |
| set random 1k entries    |         10 |   0.7499 |   0.9015 |   0.8379 | 0.0474 |  1193519 |
| set random 50k entries   |         10 |  14.2130 |  14.7817 |  14.4931 | 0.1797 |  3449915 |

### 1m entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0004 |   0.0270 |   0.0025 | 0.0029 |   397152 |
| get random 100 entries   |        100 |   0.0440 |   0.1758 |   0.0668 | 0.0198 |  1496224 |
| iterate over all entries |        100 |   9.9925 |  13.8858 |  10.6677 | 0.5131 | 93741223 |
| set random 1 entry       |        100 |   0.0538 |   0.3763 |   0.0721 | 0.0374 |    13874 |
| set random 100 entries   |        100 |   0.6510 |   2.2153 |   1.7443 | 0.1971 |    57330 |
| set random 1k entries    |         10 |   6.9965 |  11.5011 |  10.2719 | 1.6529 |    97353 |
| set random 50k entries   |         10 |  39.9164 |  42.6653 |  41.1931 | 1.0043 |  1213796 |
