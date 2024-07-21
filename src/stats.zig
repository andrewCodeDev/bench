const std = @import("std");

pub const hw = @cImport({
    @cInclude("/home/andrew/ZigCode/Stats/src/hw_counter.h");
});

pub const CSV_COLUMN_NAMES: []const u8 =
        "name,clock_mean,clock_median,clock_variance,clock_stddev,clock_curtosis,clock_skew,instructions,branches,branch_misses,cache_misses\n";

pub const Measurement = enum {
    wall_clock,  
    instructions,
    branches,
    branch_misses,
    cache_misses,
};

pub const DataBlock = struct {
    wall_clock: []f64,  
    instructions: []f64,
    branches: []f64,
    branch_misses: []f64,
    cache_misses: []f64,
    index: usize,
    pub fn init(allocator: std.mem.Allocator, sample_size: usize) !DataBlock {
        return .{
            .wall_clock = try allocator.alloc(f64, sample_size),
            .instructions = try allocator.alloc(f64, sample_size),
            .branches = try allocator.alloc(f64, sample_size),
            .branch_misses = try allocator.alloc(f64, sample_size),
            .cache_misses = try allocator.alloc(f64, sample_size),
            .index = 0,
        };
    }

    pub fn deinit(self: *DataBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.wall_clock);
        allocator.free(self.instructions);
        allocator.free(self.branches);
        allocator.free(self.branch_misses);
        allocator.free(self.cache_misses);
    }

    pub fn samples(self: DataBlock) usize {
        return self.wall_clock.len;
    }

    pub fn slice(self: DataBlock, comptime field: Measurement) []f64 {
        return @field(self, @tagName(field))[0..self.index];
    }

    pub fn append(self: *DataBlock, time_delta: u64, desc: hw.Descriptors) void {

        if (self.index >= self.samples())
            return;

        const counts = hw.all_read(desc);
        self.wall_clock[self.index] = @floatFromInt(time_delta);
        self.instructions[self.index] = @floatFromInt(counts.data[0]);
        self.branches[self.index] = @floatFromInt(counts.data[1]);
        self.branch_misses[self.index] = @floatFromInt(counts.data[2]);
        self.cache_misses[self.index] = @floatFromInt(counts.data[3]);
        self.index += 1;
    }

    pub fn reset(self: *DataBlock) void {
        self.index = 0;
    }

    pub fn stats(self: *const DataBlock, name: []const u8) BaseStats {
        return BaseStats.init(name, self);
    }
};

pub const BaseStats = struct {
    name: []const u8 = "",
    mean: f64 = 0.0,
    median: f64 = 0.0,
    variance: f64 = 0.0,
    stddev: f64 = 0.0,
    kurtosis: f64 = 0.0,
    skew: f64 = 0.0,
    instructions: f64 = 0.0,
    branches: f64 = 0.0,
    branch_misses: f64 = 0.0,
    cache_misses: f64 = 0.0,
    // sorts the incoming array
    fn init(name: []const u8, data: *const DataBlock) BaseStats {

        const values: []f64 = data.slice(.wall_clock);
        
        const N: f64 = @floatFromInt(values.len);

        // sort for calculating the median values
        std.sort.pdq(f64, values, {}, std.sort.asc(f64));

        const cleaned: []const f64 = blk: {
            const Q1 = values[values.len / 4];
            const Q3 = values[values.len - values.len / 4];
            const IQR = Q3 - Q1;
            const lower = Q1 - IQR * 1.5;
            const upper = Q3 + IQR * 1.5;

            var i: usize = 0;
            while (i < values.len) : (i += 1) {
               if (values[i] >= lower) break;
            }
            var j: usize = values.len - 1;
            while (true) : (j -= 1) {
               if (values[j] <= upper) break;
               if (j == 0) break;
            }
            break :blk values[i..j];
        };

        const median: f64 = findMedian(cleaned);

        const mean: f64 = blk: {
            var tmp: f64 = 0.0;
            for (values) |v| tmp += v;
            break :blk tmp / N;
        };

        // use for kurtosis and standard deviation
        const variance: f64  = blk: {
            var tmp: f64 = 0.0;
            for (cleaned) |v| tmp += pow_2(v - mean);
            break :blk tmp / N;
        };

        const stddev: f64 = std.math.sqrt(variance);

        // use for kurtosis and standard deviation
        const kurtosis: f64  = blk: {
            var tmp: f64 = 0.0;
            for (cleaned) |v| tmp += pow_4(v - mean);
            break :blk tmp / (N * pow_4(stddev));
        };

        const skew = (3.0 * (mean - median)) / stddev;

        return .{
            .name = name,
            .mean = mean,  
            .median = median,
            .variance = variance,
            .stddev = stddev,
            .kurtosis = kurtosis,
            .skew = skew,
            .instructions = calcMean(data.slice(.instructions)),
            .branches = calcMean(data.slice(.branches)),
            .branch_misses = calcMean(data.slice(.branch_misses)),
            .cache_misses = calcMean(data.slice(.cache_misses)),
        };
    }

    pub fn isNormal(self: BaseStats) bool {

        // the following are broad heuristics

        // given that a normal distribution has a kurtosis
        // of 3, we check to see if we are with +/-1 of 3
        const check_kurtosis: bool = (1.0 > @abs(self.kurtosis - 3.0));
        
        // likewise, skew should be within +/- 1
        const check_skew: bool = (1.0 > @abs(self.skew));

        return check_kurtosis and check_skew;
    }

    pub fn format(
        base: BaseStats,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = try writer.print("Name: {s}\n", .{ base.name });
        _ = try writer.print("\tclock mean     : {d:.5},\n", .{ base.mean });
        _ = try writer.print("\tclock median   : {d:.5},\n", .{ base.median });
        _ = try writer.print("\tclock variance : {d:.5},\n", .{ base.variance });
        _ = try writer.print("\tclock stddev   : {d:.5},\n", .{ base.stddev });
        _ = try writer.print("\tclock kurtosis : {d:.5},\n", .{ base.kurtosis });
        _ = try writer.print("\tclock skew     : {d:.5},\n", .{ base.skew });
        _ = try writer.print("\tinstructions   : {d:.5},\n", .{ base.instructions });
        _ = try writer.print("\tbranches       : {d:.5},\n", .{ base.branches });
        _ = try writer.print("\tbranch misses  : {d:.5},\n", .{ base.branch_misses });
        _ = try writer.print("\tcache misses   : {d:.5},\n\n", .{ base.cache_misses });
    }

    pub fn write(self: BaseStats, writer: anytype) !void {
        try writer.print("{s},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5}\n", .{
            self.name,
            self.mean,
            self.median,
            self.variance,
            self.stddev,
            self.kurtosis,
            self.skew,
            self.instructions,
            self.branches,
            self.branch_misses,
            self.cache_misses,
        });
    }
};

pub inline fn forceCall(comptime func: anytype, args: anytype) void {

    const T = @TypeOf(@call(.auto, func, args));

    const ptr: *const @TypeOf(func) = func;
    std.mem.doNotOptimizeAway(ptr);

    if (T == void) {
        _ = @call(.never_inline, ptr, args);
    } else {
        // force the compiler to load arguments
        // without the x argument being preserved,
        // the compiler can decide not to load
        // the registers/stack with arguments
        const x = @call(.never_inline, ptr, args);
        std.mem.doNotOptimizeAway(x);
    }
}

fn pow_2(x: f64) f64 {
    return x * x;
}

fn pow_4(x: f64) f64 {
    return x * x * x * x;
}

// assumes that data is sorted
pub fn findMedian(values: []const f64) f64 {

    const N: usize = values.len;

    if (N & 1 == 0) {
        const i: usize = N / 2;
        return (values[i] + values[i + 1]) / 2.0;
    } else {
        const i: usize = (N / 2) + 1;
        return values[i];
    }
}

// assumes that data is sorted
fn calcMean(values: []const f64) f64 {

    var tmp: f64 = 0.0;

    for (values) |v| tmp += v;

    const N: f64 = @floatFromInt(values.len);

    return tmp / N;
}

