const std = @import("std");
const Hardfork = @import("../hardforks/hardfork.zig").Hardfork;
const build_options = @import("build_options");

/// Storage slot status for gas calculation
pub const StorageStatus = enum(u8) {
    /// Slot value remains unchanged (current == new)
    Unchanged = 0,
    /// Slot goes from zero to non-zero (current == 0, new != 0)
    Added = 1,
    /// Slot goes from non-zero to zero (current != 0, new == 0)
    Deleted = 2,
    /// Slot goes from non-zero to different non-zero (current != 0 && new != 0 && current != new)
    Modified = 3,

    /// Determine storage status from current and new values
    pub fn fromValues(current: u256, new: u256) StorageStatus {
        if (current == new) return .Unchanged;
        if (current == 0) return .Added;
        if (new == 0) return .Deleted;
        return .Modified;
    }
};

/// Storage operation cost and refund information
pub const StorageCost = struct {
    /// Gas cost for the storage operation
    gas: u64,
    /// Gas refund amount (if any)
    refund: u64,
};

/// Number of hardforks we support in the table
const HARDFORK_COUNT = @typeInfo(Hardfork).@"enum".fields.len;

/// Number of storage status types
const STATUS_COUNT = @typeInfo(StorageStatus).@"enum".fields.len;

/// Pre-computed storage cost table indexed by [hardfork][status]
/// This provides O(1) lookup for storage costs across all hardforks
/// Only generated when not optimizing for size
pub const STORAGE_COST_TABLE = if (build_options.optimize_size) void else blk: {
    @setEvalBranchQuota(10000);
    var table: [HARDFORK_COUNT][STATUS_COUNT]StorageCost = undefined;
    
    // Helper to get hardfork index
    const getIndex = struct {
        fn get(fork: Hardfork) usize {
            return @intFromEnum(fork);
        }
    }.get;
    
    // Pre-Constantinople costs (Frontier through Byzantium)
    const pre_constantinople_costs = [STATUS_COUNT]StorageCost{
        StorageCost{ .gas = 200, .refund = 0 },      // Unchanged
        StorageCost{ .gas = 20000, .refund = 0 },    // Added
        StorageCost{ .gas = 5000, .refund = 15000 }, // Deleted
        StorageCost{ .gas = 5000, .refund = 0 },     // Modified
    };
    
    // Constantinople/Petersburg costs (EIP-1283, but reverted in Petersburg)
    // Petersburg reverted to pre-Constantinople costs
    
    // Istanbul costs (EIP-2200)
    const istanbul_costs = [STATUS_COUNT]StorageCost{
        StorageCost{ .gas = 800, .refund = 0 },      // Unchanged (warm slot)
        StorageCost{ .gas = 20000, .refund = 0 },    // Added
        StorageCost{ .gas = 5000, .refund = 15000 }, // Deleted
        StorageCost{ .gas = 5000, .refund = 0 },     // Modified
    };
    
    // Berlin costs (EIP-2929 cold/warm access)
    // Note: These are base costs, cold access adds 2100
    const berlin_costs = [STATUS_COUNT]StorageCost{
        StorageCost{ .gas = 0, .refund = 0 },        // Unchanged (no-op)
        StorageCost{ .gas = 20000, .refund = 0 },    // Added
        StorageCost{ .gas = 2900, .refund = 4800 },  // Deleted
        StorageCost{ .gas = 2900, .refund = 0 },     // Modified
    };
    
    // London costs (EIP-3529 reduced refunds)
    const london_costs = [STATUS_COUNT]StorageCost{
        StorageCost{ .gas = 0, .refund = 0 },        // Unchanged (no-op)
        StorageCost{ .gas = 20000, .refund = 0 },    // Added
        StorageCost{ .gas = 2900, .refund = 4800 },  // Deleted (max refund is gas/5)
        StorageCost{ .gas = 2900, .refund = 0 },     // Modified
    };
    
    // Fill the table for each hardfork
    for (@typeInfo(Hardfork).@"enum".fields) |field| {
        const fork = @field(Hardfork, field.name);
        const idx = getIndex(fork);
        
        // Determine which cost set to use based on hardfork
        if (@intFromEnum(fork) >= getIndex(.LONDON)) {
            table[idx] = london_costs;
        } else if (@intFromEnum(fork) >= getIndex(.BERLIN)) {
            table[idx] = berlin_costs;
        } else if (@intFromEnum(fork) >= getIndex(.ISTANBUL)) {
            table[idx] = istanbul_costs;
        } else {
            table[idx] = pre_constantinople_costs;
        }
    }
    
    break :blk table;
};

/// Get storage cost for a given hardfork and storage status
/// Uses pre-computed table for O(1) lookup when available, otherwise calculates at runtime
pub fn getStorageCost(hardfork: Hardfork, status: StorageStatus) StorageCost {
    if (build_options.optimize_size) {
        return calculateStorageCostRuntime(hardfork, status);
    } else {
        const fork_idx = @intFromEnum(hardfork);
        const status_idx = @intFromEnum(status);
        return STORAGE_COST_TABLE[fork_idx][status_idx];
    }
}

/// Calculate storage cost from current and new values
/// Convenience function that combines status determination and cost lookup
pub fn calculateStorageCost(hardfork: Hardfork, current: u256, new: u256) StorageCost {
    const status = StorageStatus.fromValues(current, new);
    return getStorageCost(hardfork, status);
}

/// Calculate storage cost for a given hardfork and status at runtime
/// Used internally when optimize_size is enabled
fn calculateStorageCostRuntime(hardfork: Hardfork, status: StorageStatus) StorageCost {
    // Handle unchanged case first (most common)
    if (status == .Unchanged) {
        if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.BERLIN)) {
            return StorageCost{ .gas = 0, .refund = 0 };
        } else if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.ISTANBUL)) {
            return StorageCost{ .gas = 800, .refund = 0 };
        } else {
            return StorageCost{ .gas = 200, .refund = 0 };
        }
    }
    
    // Handle other cases
    switch (status) {
        .Added => return StorageCost{ .gas = 20000, .refund = 0 },
        .Deleted => {
            if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.BERLIN)) {
                return StorageCost{ .gas = 2900, .refund = 4800 };
            } else {
                return StorageCost{ .gas = 5000, .refund = 15000 };
            }
        },
        .Modified => {
            if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.BERLIN)) {
                return StorageCost{ .gas = 2900, .refund = 0 };
            } else {
                return StorageCost{ .gas = 5000, .refund = 0 };
            }
        },
        .Unchanged => unreachable, // Already handled above
    }
}

/// Manual calculation for size-optimized builds
/// This trades performance for smaller binary size
pub fn calculateStorageCostManual(hardfork: Hardfork, current: u256, new: u256) StorageCost {
    const status = StorageStatus.fromValues(current, new);
    
    // Handle unchanged case first (most common)
    if (status == .Unchanged) {
        if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.BERLIN)) {
            return StorageCost{ .gas = 0, .refund = 0 };
        } else if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.ISTANBUL)) {
            return StorageCost{ .gas = 800, .refund = 0 };
        } else {
            return StorageCost{ .gas = 200, .refund = 0 };
        }
    }
    
    // Handle other cases
    switch (status) {
        .Added => return StorageCost{ .gas = 20000, .refund = 0 },
        .Deleted => {
            if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.BERLIN)) {
                return StorageCost{ .gas = 2900, .refund = 4800 };
            } else {
                return StorageCost{ .gas = 5000, .refund = 15000 };
            }
        },
        .Modified => {
            if (@intFromEnum(hardfork) >= @intFromEnum(Hardfork.BERLIN)) {
                return StorageCost{ .gas = 2900, .refund = 0 };
            } else {
                return StorageCost{ .gas = 5000, .refund = 0 };
            }
        },
        .Unchanged => unreachable, // Already handled above
    }
}

// Tests
test "StorageStatus.fromValues" {
    const testing = std.testing;
    
    // Test unchanged
    try testing.expectEqual(StorageStatus.Unchanged, StorageStatus.fromValues(0, 0));
    try testing.expectEqual(StorageStatus.Unchanged, StorageStatus.fromValues(100, 100));
    try testing.expectEqual(StorageStatus.Unchanged, StorageStatus.fromValues(std.math.maxInt(u256), std.math.maxInt(u256)));
    
    // Test added (0 -> non-zero)
    try testing.expectEqual(StorageStatus.Added, StorageStatus.fromValues(0, 1));
    try testing.expectEqual(StorageStatus.Added, StorageStatus.fromValues(0, 100));
    try testing.expectEqual(StorageStatus.Added, StorageStatus.fromValues(0, std.math.maxInt(u256)));
    
    // Test deleted (non-zero -> 0)
    try testing.expectEqual(StorageStatus.Deleted, StorageStatus.fromValues(1, 0));
    try testing.expectEqual(StorageStatus.Deleted, StorageStatus.fromValues(100, 0));
    try testing.expectEqual(StorageStatus.Deleted, StorageStatus.fromValues(std.math.maxInt(u256), 0));
    
    // Test modified (non-zero -> different non-zero)
    try testing.expectEqual(StorageStatus.Modified, StorageStatus.fromValues(1, 2));
    try testing.expectEqual(StorageStatus.Modified, StorageStatus.fromValues(100, 200));
    try testing.expectEqual(StorageStatus.Modified, StorageStatus.fromValues(std.math.maxInt(u256), 1));
}

test "getStorageCost table lookup" {
    const testing = std.testing;
    
    // Test Frontier costs
    const frontier_unchanged = getStorageCost(.FRONTIER, .Unchanged);
    try testing.expectEqual(@as(u64, 200), frontier_unchanged.gas);
    try testing.expectEqual(@as(u64, 0), frontier_unchanged.refund);
    
    const frontier_added = getStorageCost(.FRONTIER, .Added);
    try testing.expectEqual(@as(u64, 20000), frontier_added.gas);
    try testing.expectEqual(@as(u64, 0), frontier_added.refund);
    
    const frontier_deleted = getStorageCost(.FRONTIER, .Deleted);
    try testing.expectEqual(@as(u64, 5000), frontier_deleted.gas);
    try testing.expectEqual(@as(u64, 15000), frontier_deleted.refund);
    
    // Test Berlin costs
    const berlin_unchanged = getStorageCost(.BERLIN, .Unchanged);
    try testing.expectEqual(@as(u64, 0), berlin_unchanged.gas);
    try testing.expectEqual(@as(u64, 0), berlin_unchanged.refund);
    
    const berlin_deleted = getStorageCost(.BERLIN, .Deleted);
    try testing.expectEqual(@as(u64, 2900), berlin_deleted.gas);
    try testing.expectEqual(@as(u64, 4800), berlin_deleted.refund);
    
    // Test London costs (same as Berlin for base costs)
    const london_unchanged = getStorageCost(.LONDON, .Unchanged);
    try testing.expectEqual(@as(u64, 0), london_unchanged.gas);
    try testing.expectEqual(@as(u64, 0), london_unchanged.refund);
    
    const london_added = getStorageCost(.LONDON, .Added);
    try testing.expectEqual(@as(u64, 20000), london_added.gas);
    try testing.expectEqual(@as(u64, 0), london_added.refund);
}

test "calculateStorageCost convenience function" {
    const testing = std.testing;
    
    // Test unchanged value
    const unchanged = calculateStorageCost(.LONDON, 100, 100);
    try testing.expectEqual(@as(u64, 0), unchanged.gas);
    try testing.expectEqual(@as(u64, 0), unchanged.refund);
    
    // Test adding new value
    const added = calculateStorageCost(.LONDON, 0, 100);
    try testing.expectEqual(@as(u64, 20000), added.gas);
    try testing.expectEqual(@as(u64, 0), added.refund);
    
    // Test deleting value
    const deleted = calculateStorageCost(.LONDON, 100, 0);
    try testing.expectEqual(@as(u64, 2900), deleted.gas);
    try testing.expectEqual(@as(u64, 4800), deleted.refund);
    
    // Test modifying value
    const modified = calculateStorageCost(.LONDON, 100, 200);
    try testing.expectEqual(@as(u64, 2900), modified.gas);
    try testing.expectEqual(@as(u64, 0), modified.refund);
}

test "calculateStorageCostManual matches table lookup" {
    const testing = std.testing;
    
    // Test across different hardforks and statuses
    const hardforks = [_]Hardfork{ .FRONTIER, .ISTANBUL, .BERLIN, .LONDON, .CANCUN };
    const test_cases = [_]struct { current: u256, new: u256 }{
        .{ .current = 0, .new = 0 },       // Unchanged
        .{ .current = 100, .new = 100 },   // Unchanged
        .{ .current = 0, .new = 100 },     // Added
        .{ .current = 100, .new = 0 },     // Deleted
        .{ .current = 100, .new = 200 },   // Modified
    };
    
    for (hardforks) |fork| {
        for (test_cases) |tc| {
            const table_result = calculateStorageCost(fork, tc.current, tc.new);
            const runtime_result = calculateStorageCostManual(fork, tc.current, tc.new);
            
            try testing.expectEqual(table_result.gas, runtime_result.gas);
            try testing.expectEqual(table_result.refund, runtime_result.refund);
        }
    }
}

test "storage cost table compile-time verification" {
    const testing = std.testing;
    
    // Skip test if optimizing for size
    if (build_options.optimize_size) {
        return;
    }
    
    // Verify table is properly sized
    try testing.expectEqual(HARDFORK_COUNT, STORAGE_COST_TABLE.len);
    try testing.expectEqual(STATUS_COUNT, STORAGE_COST_TABLE[0].len);
    
    // Verify specific known costs
    const frontier_idx = @intFromEnum(Hardfork.FRONTIER);
    const london_idx = @intFromEnum(Hardfork.LONDON);
    
    // Frontier unchanged cost
    try testing.expectEqual(@as(u64, 200), STORAGE_COST_TABLE[frontier_idx][@intFromEnum(StorageStatus.Unchanged)].gas);
    
    // London unchanged cost
    try testing.expectEqual(@as(u64, 0), STORAGE_COST_TABLE[london_idx][@intFromEnum(StorageStatus.Unchanged)].gas);
    
    // Added cost is consistent across forks
    for (0..HARDFORK_COUNT) |i| {
        try testing.expectEqual(@as(u64, 20000), STORAGE_COST_TABLE[i][@intFromEnum(StorageStatus.Added)].gas);
    }
}