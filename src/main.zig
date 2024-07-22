const std = @import("std");

const stats = @import("stats.zig");

var prng = std.Random.DefaultPrng.init(42);
const rand = prng.random();

pub fn main() !void {

    ///////////////////////////////////////////////
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // default timer - call reset before each measurement
    var timer = std.time.Timer.start() catch @panic("Clock not found.");

    // create csv for testing purposes
    var csv = try std.fs.cwd().createFile("results/test.csv", .{ });
    const writer = csv.writer();

    // add the header row to the csv
    try writer.writeAll(stats.CSV_COLUMN_NAMES);

    /////////////////////////////////////////////

    var data = try stats.DataBlock.init(allocator, 1000);
        defer data.deinit(allocator);

    const haystack = try allocator.alloc(u8, 100_000);
        defer allocator.free(haystack);

    rand.bytes(haystack);

    ////////////////////////////////////////////

    data.reset();

    for (0..data.samples()) |_| {

        //const needle = rand.int(u8);

        const desc = stats.hw.all_start();

        timer.reset();
    
        for (0..1000) |i| {
            stats.forceCall(foo, .{ i, i + 1 });
        }

        data.append(timer.read(), desc);
    }

    const foo_stats = data.stats("foo");

    ////////////////////////////////////////////

    data.reset();

    for (0..data.samples()) |_| {

        //const needle = rand.int(u8);

        const desc = stats.hw.all_start();

        timer.reset();
    
        for (0..1000) |i| {
            stats.forceCall(bar, .{ i, i + 1 });
        }

        data.append(timer.read(), desc);
    }

    const bar_stats = data.stats("bar");

    ////////////////////////////////////////////

    // append stats as a new row in the csv
    try foo_stats.write(writer);
    try bar_stats.write(writer);

    std.debug.print("{}", .{ foo_stats });
    std.debug.print("{}", .{ bar_stats });

    ////////////////////////////////////////////
}

// helpers to normalize the interface - not necessary
//pub fn foo(haystack: []const u8, needle: u8) ?usize {
//    return std.mem.indexOfScalar(u8, haystack, needle);
//}
//
//pub fn bar(haystack: []const u8, needle: u8) ?usize {
//    return std.mem.indexOfPosLinear(u8, haystack, 0, &.{ needle });
//}

pub fn foo(x: usize, y: usize) usize {
    if (rand.float(f64) <= 0.50) {
        return x + y;
    }
    return x * y;
}

pub fn bar(x: usize, y: usize) usize {
    return x + y;
}

