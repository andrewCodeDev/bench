const std = @import("std");

pub const hw = @cImport({
    @cInclude("hw_counter.h");
});

pub const CSV_COLUMN_NAMES: []const u8 =
    "name,clock_min,clock_p25,clock_p50,clock_p75,clock_max,instructions,branches,branch_misses,cache_references,cache_misses\n";

pub const Measurement = enum {
    wall_clock,  
    instructions,
    branches,
    branch_misses,
    cache_references,
    cache_misses,
};

pub const DataBlock = struct {
    wall_clock: []f64,  
    instructions: []f64,
    branches: []f64,
    branch_misses: []f64,
    cache_references: []f64,
    cache_misses: []f64,
    index: usize,
    pub fn init(allocator: std.mem.Allocator, sample_size: usize) !DataBlock {
        return .{
            .wall_clock = try allocator.alloc(f64, sample_size),
            .instructions = try allocator.alloc(f64, sample_size),
            .branches = try allocator.alloc(f64, sample_size),
            .branch_misses = try allocator.alloc(f64, sample_size),
            .cache_references = try allocator.alloc(f64, sample_size),
            .cache_misses = try allocator.alloc(f64, sample_size),
            .index = 0,
        };
    }

    pub fn deinit(self: *DataBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.wall_clock);
        allocator.free(self.instructions);
        allocator.free(self.branches);
        allocator.free(self.branch_misses);
        allocator.free(self.cache_references);
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
        self.cache_references[self.index] = @floatFromInt(counts.data[3]);
        self.cache_misses[self.index] = @floatFromInt(counts.data[4]);
        self.index += 1;
    }

    pub fn sort(self: DataBlock) void {
        // sorting helps us remove outliers to
        // calculate means and find percentiles
        std.sort.pdq(f64, self.wall_clock, {}, std.sort.asc(f64));
        std.sort.pdq(f64, self.instructions, {}, std.sort.asc(f64));
        std.sort.pdq(f64, self.branches, {}, std.sort.asc(f64));
        std.sort.pdq(f64, self.branch_misses, {}, std.sort.asc(f64));
        std.sort.pdq(f64, self.cache_references, {}, std.sort.asc(f64));
        std.sort.pdq(f64, self.cache_misses, {}, std.sort.asc(f64));
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
    clock_min: f64 = 0.0,
    clock_p25: f64 = 0.0,
    clock_p50: f64 = 0.0,
    clock_p75: f64 = 0.0,
    clock_max: f64 = 0.0,
    instructions: f64 = 0.0,
    branches: f64 = 0.0,
    branch_misses: f64 = 0.0,
    cache_references: f64 = 0.0,
    cache_misses: f64 = 0.0,
    // sorts the incoming array
    fn init(name: []const u8, data: *const DataBlock) BaseStats {

        data.sort();

        const clock = data.slice(.wall_clock);

        return .{
            .name = name,
            .clock_min = findMin(clock),
            .clock_p25 = findP25(clock),
            .clock_p50 = findP50(clock),
            .clock_p75 = findP75(clock),
            .clock_max = findMax(clock),
            .instructions = findP50(data.slice(.instructions)),
            .branches = findP50(data.slice(.branches)),
            .branch_misses = findP50(data.slice(.branch_misses)),
            .cache_references = findP50(data.slice(.cache_references)),
            .cache_misses = findP50(data.slice(.cache_misses)),
        };
    }

    pub fn format(
        base: BaseStats,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = try writer.print("Name: {s}\n", .{ base.name });
        _ = try writer.print("\tclock min         : {d:.5},\n", .{ base.clock_min });
        _ = try writer.print("\tclock p25         : {d:.5},\n", .{ base.clock_p25 });
        _ = try writer.print("\tclock p50         : {d:.5},\n", .{ base.clock_p50 });
        _ = try writer.print("\tclock p75         : {d:.5},\n", .{ base.clock_p75 });
        _ = try writer.print("\tclock max         : {d:.5},\n", .{ base.clock_max });
        _ = try writer.print("\tinstructions      : {d:.5},\n", .{ base.instructions });
        _ = try writer.print("\tbranches          : {d:.5},\n", .{ base.branches });
        _ = try writer.print("\tbranch misses     : {d:.5},\n", .{ base.branch_misses });
        _ = try writer.print("\tcache references  : {d:.5},\n", .{ base.cache_references });
        _ = try writer.print("\tcache misses      : {d:.5},\n\n", .{ base.cache_misses });
    }

    pub fn write(self: BaseStats, writer: anytype) !void {
        try writer.print("{s},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5},{d:.5}\n", .{
            self.name,
            self.clock_min,
            self.clock_p25,
            self.clock_p50,
            self.clock_p75,
            self.clock_max,
            self.instructions,
            self.branches,
            self.branch_misses,
            self.cache_references,
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

// assumes that data is sorted
pub fn findP25(values: []const f64) f64 {
    const N: f64 = @floatFromInt(values.len);
    const round: usize = @as(usize, @intFromFloat(@round(N * 0.25))) - 1;
    return values[round];
}

// assumes that data is sorted
pub fn findP50(values: []const f64) f64 {

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
pub fn findP75(values: []const f64) f64 {
    const N: f64 = @floatFromInt(values.len);
    const round: usize = @as(usize, @intFromFloat(@round(N * 0.75))) - 1;
    return values[round];
}

// assumes that data is sorted
pub fn findMax(values: []const f64) f64 {
    return values[values.len - 1];
}

// assumes that data is sorted
pub fn findMin(values: []const f64) f64 {
    return values[0];
}
