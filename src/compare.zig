const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Cursor = @import("cursor.zig");

const Options = struct {
    log: ?std.fs.File.Writer = null,
};

pub fn compareEnvironments(env_a: Environment, env_b: Environment, dbs: ?[][]const u8, options: Options) !usize {
    const txn_a = try Transaction.open(env_a, .{ .mode = .ReadOnly });
    defer txn_a.abort();

    const txn_b = try Transaction.open(env_b, .{ .mode = .ReadOnly });
    defer txn_b.abort();

    if (dbs) |names| {
        var sum: usize = 0;
        for (names) |name| {
            const dbi_a = try txn_a.openDatabase(name, .{});
            const dbi_b = try txn_b.openDatabase(name, .{});
            sum += try compareDatabases(txn_a, dbi_a, txn_b, dbi_b, options);
        }

        return sum;
    } else {
        const dbi_a = try txn_a.openDatabaseZ(null, .{});
        const dbi_b = try txn_b.openDatabaseZ(null, .{});
        return try compareDatabases(txn_a, dbi_a, txn_b, dbi_b, options);
    }
}

pub fn compareDatabases(txn_a: Transaction, dbi_a: Transaction.DBI, txn_b: Transaction, dbi_b: Transaction.DBI, options: Options) !usize {
    if (options.log) |log| try log.print("{s:-<80}\n", .{"START DIFF "});

    var differences: usize = 0;

    const cursor_a = try Cursor.open(txn_a, dbi_a);
    defer cursor_a.close();

    const cursor_b = try Cursor.open(txn_b, dbi_b);
    defer cursor_b.close();

    var key_a = try cursor_a.goToFirst();
    var key_b = try cursor_b.goToFirst();
    while (key_a != null or key_b != null) {
        if (key_a) |key_a_bytes| {
            const value_a = try cursor_a.getCurrentValue();
            if (key_b) |key_b_bytes| {
                const value_b = try cursor_b.getCurrentValue();
                switch (std.mem.order(u8, key_a_bytes, key_b_bytes)) {
                    .lt => {
                        differences += 1;
                        if (options.log) |log|
                            try log.print("{s}\n- a: {s}\n- b: null\n", .{ hex(key_a_bytes), hex(value_a) });

                        key_a = try cursor_a.goToNext();
                    },
                    .gt => {
                        differences += 1;
                        if (options.log) |log|
                            try log.print("{s}\n- a: null\n- b: {s}\n", .{
                                hex(key_b_bytes),
                                hex(value_b),
                            });

                        key_b = try cursor_b.goToNext();
                    },
                    .eq => {
                        if (!std.mem.eql(u8, value_a, value_b)) {
                            differences += 1;
                            if (options.log) |log|
                                try log.print("{s}\n- a: {s}\n- b: {s}\n", .{ hex(key_a_bytes), hex(value_a), hex(value_b) });
                        }

                        key_a = try cursor_a.goToNext();
                        key_b = try cursor_b.goToNext();
                    },
                }
            } else {
                differences += 1;
                if (options.log) |log|
                    try log.print("{s}\n- a: {s}\n- b: null\n", .{ hex(key_a_bytes), hex(value_a) });

                key_a = try cursor_a.goToNext();
            }
        } else {
            if (key_b) |bytes_b| {
                const value_b = try cursor_b.getCurrentValue();
                differences += 1;
                if (options.log) |log|
                    try log.print("{s}\n- a: null\n- b: {s}\n", .{ hex(bytes_b), hex(value_b) });

                key_b = try cursor_b.goToNext();
            } else {
                break;
            }
        }
    }

    if (options.log) |log| try log.print("{s:-<80}\n", .{"END DIFF "});

    return differences;
}
