const std = @import("std");
const hex = std.fmt.fmtSliceHexLower;

const Environment = @import("environment.zig");
const Transaction = @import("transaction.zig");
const Database = @import("database.zig");
const Cursor = @import("cursor.zig");

const Options = struct {
    dbs: ?[][]const u8 = null,
    log: ?std.fs.File.Writer = null,
};

pub fn compareEnvironments(env_a: Environment, env_b: Environment, options: Options) !usize {
    const txn_a = try Transaction.open(env_a, .{ .read_only = true });
    defer txn_a.abort();
    const txn_b = try Transaction.open(env_b, .{ .read_only = true });
    defer txn_b.abort();

    if (options.dbs) |dbs| {
        var sum: usize = 0;
        for (dbs) |name| {
            const db_a = try Database.open(txn_a, .{ .name = name });
            const db_b = try Database.open(txn_b, .{ .name = name });
            sum += try compareDatabases(db_a, db_b, options);
        }

        return sum;
    } else {
        const db_a = try Database.open(txn_a, .{});
        const db_b = try Database.open(txn_b, .{});
        return try compareDatabases(db_a, db_b, options);
    }
}

pub fn compareDatabases(db_a: Database, db_b: Database, options: Options) !usize {
    if (options.log) |log| try log.print("{s:-<80}\n", .{"START DIFF "});

    var differences: usize = 0;

    const cursor_a = try Cursor.open(db_a);
    defer cursor_a.close();
    const cursor_b = try Cursor.open(db_b);
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
