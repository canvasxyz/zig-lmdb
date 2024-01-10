# zig-lmdb

Zig bindings for LMDB.

Built and tested with Zig version `0.12.0-dev.2030+2ac315c24`.

## Table of Contents

- [Usage](#usage)
- [API](#api)
  - [`Environment`](#environment)
  - [`Transaction`](#transaction)
  - [`Database`](#database)
  - [`Cursor`](#cursor)
  - [`Stat`](#stat)
- [Benchmarks](#benchmarks)

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

    const widgets = try txn.database("widgets", .{});
    try widgets.set("aaa", "foo");

    const gadgets = try txn.database("gadgets", .{});
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
