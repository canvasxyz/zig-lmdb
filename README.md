# zig-lmdb

Zig bindings for LMDB.

## API

### `Environment`

```zig
pub const Options = struct {
    map_size: usize = 10485760,
    max_dbs: u32 = 0,
    mode: u16 = 0o664,
};

pub fn open(path: [*:0]const u8, options: Options) !Environment
pub fn close(self: Environment) void
pub fn flush(self: Environment) !void
pub fn stat(self: Environment) !Stat
```

### `Transaction`

```zig
pub const Options = struct {
    read_only: bool = true,
    parent: ?Transaction = null,
};

pub fn open(env: Environment, options: Options) !Transaction
pub fn getEnvironment(self: Transaction) !Environment
pub fn commit(self: Transaction) !void
pub fn abort(self: Transaction) void
```

### `Database`

```zig
pub const Options = struct {
    name: ?[]const u8 = null,
    create: bool = false,
};

pub fn open(txn: Transaction, options: Options) !Database
pub fn close(self: Database) void
pub fn stat(self: Database) !Stat
pub fn get(self: Database, key: []const u8) !?[]const u8
pub fn set(self: Database, key: []const u8, value: []const u8) !void
pub fn delete(self: Database, key: []const u8) !void
```

### `Cursor`

```zig
pub const Entry = struct { key: []const u8, value: []const u8 };

pub fn open(db: Database) !Cursor
pub fn close(self: Cursor) void
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
```

## Benchmarks

Run the benchmarks with

```
$ zig build bench
```

### DB size: 1000 entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0009 |   0.0077 |   0.0011 | 0.0009 |   872707 |
| get random 100 entries   |        100 |   0.0164 |   0.0182 |   0.0169 | 0.0003 |  5902310 |
| iterate over all entries |        100 |   0.0129 |   0.0147 |   0.0140 | 0.0002 | 71379574 |
| set random 1 entry       |        100 |   0.0588 |   0.1584 |   0.0744 | 0.0161 |    13450 |
| set random 100 entries   |        100 |   0.1008 |   0.1852 |   0.1156 | 0.0139 |   865202 |
| set random 1000 entries  |         10 |   0.4014 |   0.5032 |   0.4260 | 0.0285 |  2347165 |
| set random 50000 entries |         10 |  15.9588 |  16.6936 |  16.2522 | 0.2063 |  3076516 |

### DB size: 50000 entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0008 |   0.0140 |   0.0018 | 0.0017 |   545432 |
| get random 100 entries   |        100 |   0.0235 |   0.0538 |   0.0281 | 0.0065 |  3561937 |
| iterate over all entries |        100 |   0.4822 |   0.6143 |   0.5037 | 0.0242 | 99267401 |
| set random 1 entry       |        100 |   0.0563 |   0.5940 |   0.0837 | 0.0567 |    11949 |
| set random 100 entries   |        100 |   0.3773 |   0.6046 |   0.4917 | 0.0458 |   203357 |
| set random 1000 entries  |         10 |   0.9573 |   1.0953 |   1.0129 | 0.0403 |   987228 |
| set random 50000 entries |         10 |  22.5542 |  25.4074 |  23.2075 | 0.8461 |  2154474 |

### DB size: 1000000 entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0011 |   0.0194 |   0.0024 | 0.0019 |   422608 |
| get random 100 entries   |        100 |   0.0526 |   0.1447 |   0.0690 | 0.0168 |  1448383 |
| iterate over all entries |        100 |   9.7933 |  11.0624 |  10.0263 | 0.2579 | 99737645 |
| set random 1 entry       |        100 |   0.0670 |   0.6880 |   0.0924 | 0.0672 |    10819 |
| set random 100 entries   |        100 |   0.6090 |   2.9320 |   2.3315 | 0.3231 |    42890 |
| set random 1000 entries  |         10 |   8.1651 |  14.9001 |  13.2508 | 2.1128 |    75467 |
| set random 50000 entries |         10 |  51.8944 |  60.3553 |  55.4721 | 2.6411 |   901354 |
