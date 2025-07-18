const std = @import("std");
const Operation = @import("../opcodes/operation.zig");
const ExecutionError = @import("execution_error.zig");
const Stack = @import("../stack/stack.zig");
const Frame = @import("../frame/frame.zig");

// Helper function to extract frame from state
inline fn getFrame(state: *Operation.State) *Frame {
    return @as(*Frame, @ptrCast(@alignCast(state)));
}

pub fn op_pop(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    _ = pc;
    _ = interpreter;

    const frame = getFrame(state);

    _ = try frame.stack.pop();

    return Operation.ExecutionResult{};
}

pub fn op_push0(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    _ = pc;
    _ = interpreter;

    const frame = getFrame(state);

    try frame.stack.append(0);

    return Operation.ExecutionResult{};
}

// Optimized PUSH1 implementation with direct byte access
pub fn op_push1(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    _ = interpreter;
    
    const frame = @as(*Frame, @ptrCast(@alignCast(state)));
    
    if (frame.stack.size >= Stack.CAPACITY) {
        @branchHint(.cold);
        unreachable;
    }
    
    const code = frame.contract.code;
    const value: u256 = if (pc + 1 < code.len) code[pc + 1] else 0;
    
    frame.stack.append_unsafe(value);
    
    return Operation.ExecutionResult{ .bytes_consumed = 2 };
}

// Optimized PUSH2-PUSH8 implementations using u64 arithmetic
pub fn make_push_small(comptime n: u8) fn (usize, *Operation.Interpreter, *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    return struct {
        pub fn push(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
            _ = interpreter;
            
            const frame = @as(*Frame, @ptrCast(@alignCast(state)));
            
            if (frame.stack.size >= Stack.CAPACITY) {
                @branchHint(.cold);
                unreachable;
            }
            
            var value: u64 = 0;
            const code = frame.contract.code;
            
            for (0..n) |i| {
                if (pc + 1 + i < code.len) {
                    @branchHint(.likely);
                    value = (value << 8) | code[pc + 1 + i];
                } else {
                    value = value << 8;
                }
            }
            
            frame.stack.append_unsafe(@as(u256, value));
            
            return Operation.ExecutionResult{ .bytes_consumed = 1 + n };
        }
    }.push;
}

// Generate push operations for PUSH1 through PUSH32
pub fn make_push(comptime n: u8) fn (usize, *Operation.Interpreter, *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    return struct {
        pub fn push(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
            _ = interpreter;

            const frame = getFrame(state);

            if (frame.stack.size >= Stack.CAPACITY) {
                unreachable;
            }
            var value: u256 = 0;
            const code = frame.contract.code;

            for (0..n) |i| {
                if (pc + 1 + i < code.len) {
                    value = (value << 8) | code[pc + 1 + i];
                } else {
                    value = value << 8;
                }
            }

            frame.stack.append_unsafe(value);

            // PUSH operations consume 1 + n bytes
            // (1 for the opcode itself, n for the immediate data)
            return Operation.ExecutionResult{ .bytes_consumed = 1 + n };
        }
    }.push;
}

// Runtime dispatch version for PUSH operations (used in ReleaseSmall mode)
pub fn push_n(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    _ = interpreter;

    const frame = getFrame(state);
    const opcode = frame.contract.code[pc];
    const n = opcode - 0x5f; // PUSH1 is 0x60, so n = opcode - 0x5f

    if (frame.stack.size >= Stack.CAPACITY) {
        unreachable;
    }
    var value: u256 = 0;
    const code = frame.contract.code;

    for (0..n) |i| {
        if (pc + 1 + i < code.len) {
            value = (value << 8) | code[pc + 1 + i];
        } else {
            value = value << 8;
        }
    }

    frame.stack.append_unsafe(value);

    return Operation.ExecutionResult{ .bytes_consumed = 1 + n };
}

// PUSH operations are now generated directly in jump_table.zig using make_push()

// Generate dup operations
pub fn make_dup(comptime n: u8) fn (usize, *Operation.Interpreter, *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    return struct {
        pub fn dup(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
            _ = pc;
            _ = interpreter;

            const frame = getFrame(state);

            if (frame.stack.size < n) {
                unreachable;
            }
            if (frame.stack.size >= Stack.CAPACITY) {
                unreachable;
            }
            frame.stack.dup_unsafe(n);

            return Operation.ExecutionResult{};
        }
    }.dup;
}

// Runtime dispatch version for DUP operations (used in ReleaseSmall mode)
pub fn dup_n(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    _ = interpreter;

    const frame = getFrame(state);
    const opcode = frame.contract.code[pc];
    const n = opcode - 0x7f; // DUP1 is 0x80, so n = opcode - 0x7f

    if (frame.stack.size < n) {
        unreachable;
    }
    if (frame.stack.size >= Stack.CAPACITY) {
        unreachable;
    }
    frame.stack.dup_unsafe(@intCast(n));

    return Operation.ExecutionResult{};
}

// DUP operations are now generated directly in jump_table.zig using make_dup()

// Generate swap operations
pub fn make_swap(comptime n: u8) fn (usize, *Operation.Interpreter, *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    return struct {
        pub fn swap(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
            _ = pc;
            _ = interpreter;

            const frame = getFrame(state);

            if (frame.stack.size < n + 1) {
                unreachable;
            }
            frame.stack.swap_unsafe(n);

            return Operation.ExecutionResult{};
        }
    }.swap;
}

// Runtime dispatch version for SWAP operations (used in ReleaseSmall mode)
pub fn swap_n(pc: usize, interpreter: *Operation.Interpreter, state: *Operation.State) ExecutionError.Error!Operation.ExecutionResult {
    _ = interpreter;

    const frame = getFrame(state);
    const opcode = frame.contract.code[pc];
    const n = opcode - 0x8f; // SWAP1 is 0x90, so n = opcode - 0x8f

    if (frame.stack.size < n + 1) {
        unreachable;
    }
    frame.stack.swap_unsafe(@intCast(n));

    return Operation.ExecutionResult{};
}

// SWAP operations are now generated directly in jump_table.zig using make_swap()

test "optimized PUSH1 handles value correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test with PUSH1 0xFF
    const code = [_]u8{ 0x60, 0xFF };
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const result = try op_push1(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 2), result.bytes_consumed);
    
    const value = try frame.stack.pop();
    try std.testing.expectEqual(@as(u256, 0xFF), value);
}

test "optimized PUSH1 handles bytecode boundary" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test with PUSH1 at end of bytecode (no value byte)
    const code = [_]u8{0x60};
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const result = try op_push1(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 2), result.bytes_consumed);
    
    const value = try frame.stack.pop();
    try std.testing.expectEqual(@as(u256, 0), value);
}

test "optimized PUSH2-PUSH8 handle values correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test PUSH2 with 0x1234
    const code2 = [_]u8{ 0x61, 0x12, 0x34 };
    var contract2 = try Contract.init(allocator, &code2, .{ .address = primitives.Address.ZERO });
    defer contract2.deinit(allocator, null);
    
    var frame2 = try Frame.init(allocator, &vm, 1000000, contract2, primitives.Address.ZERO, &.{});
    defer frame2.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr2: *Operation.State = @ptrCast(&frame2);
    
    const push2_fn = make_push_small(2);
    const result2 = try push2_fn(0, interpreter_ptr, state_ptr2);
    try std.testing.expectEqual(@as(usize, 3), result2.bytes_consumed);
    
    const value2 = try frame2.stack.pop();
    try std.testing.expectEqual(@as(u256, 0x1234), value2);
    
    // Test PUSH8 with max u64 value
    const code8 = [_]u8{ 0x67, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    var contract8 = try Contract.init(allocator, &code8, .{ .address = primitives.Address.ZERO });
    defer contract8.deinit(allocator, null);
    
    var frame8 = try Frame.init(allocator, &vm, 1000000, contract8, primitives.Address.ZERO, &.{});
    defer frame8.deinit();
    
    const state_ptr8: *Operation.State = @ptrCast(&frame8);
    
    const push8_fn = make_push_small(8);
    const result8 = try push8_fn(0, interpreter_ptr, state_ptr8);
    try std.testing.expectEqual(@as(usize, 9), result8.bytes_consumed);
    
    const value8 = try frame8.stack.pop();
    try std.testing.expectEqual(@as(u256, 0xFFFFFFFFFFFFFFFF), value8);
}

test "optimized PUSH handles partial bytecode correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test PUSH4 with only 2 bytes available
    const code = [_]u8{ 0x63, 0x12, 0x34 };
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const push4_fn = make_push_small(4);
    const result = try push4_fn(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 5), result.bytes_consumed);
    
    const value = try frame.stack.pop();
    // Should be 0x12340000 (padded with zeros)
    try std.testing.expectEqual(@as(u256, 0x12340000), value);
}

// ============================================================================
// POP Operation Tests
// ============================================================================

test "POP removes top stack element" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x50}; // POP opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Push some values first
    try frame.stack.append(100);
    try frame.stack.append(200);
    try frame.stack.append(300);
    
    try std.testing.expectEqual(@as(usize, 3), frame.stack.size);
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const result = try op_pop(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 0), result.bytes_consumed);
    
    // Stack should have 2 elements, top value should be 200
    try std.testing.expectEqual(@as(usize, 2), frame.stack.size);
    try std.testing.expectEqual(@as(u256, 200), try frame.stack.peek());
}

test "POP discards value correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x50}; // POP opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Push a large value
    const large_value: u256 = std.math.maxInt(u256);
    try frame.stack.append(large_value);
    try frame.stack.append(42);
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    _ = try op_pop(0, interpreter_ptr, state_ptr);
    
    // Should have popped 42, leaving large_value on top
    try std.testing.expectEqual(@as(u256, large_value), try frame.stack.peek());
}

test "multiple POP operations in sequence" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x50}; // POP opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Fill stack with known values
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try frame.stack.append(i);
    }
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Pop 5 values
    i = 0;
    while (i < 5) : (i += 1) {
        _ = try op_pop(0, interpreter_ptr, state_ptr);
    }
    
    // Should have 5 elements left, top should be 4
    try std.testing.expectEqual(@as(usize, 5), frame.stack.size);
    try std.testing.expectEqual(@as(u256, 4), try frame.stack.peek());
}

// ============================================================================
// PUSH0 Operation Tests
// ============================================================================

test "PUSH0 pushes zero value" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x5f}; // PUSH0 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), frame.stack.size);
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const result = try op_push0(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 0), result.bytes_consumed);
    
    try std.testing.expectEqual(@as(usize, 1), frame.stack.size);
    try std.testing.expectEqual(@as(u256, 0), try frame.stack.pop());
}

test "PUSH0 multiple times" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x5f}; // PUSH0 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Push 5 zeros
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        _ = try op_push0(0, interpreter_ptr, state_ptr);
    }
    
    try std.testing.expectEqual(@as(usize, 5), frame.stack.size);
    
    // Verify all are zeros
    i = 0;
    while (i < 5) : (i += 1) {
        try std.testing.expectEqual(@as(u256, 0), try frame.stack.pop());
    }
}

test "PUSH0 mixed with other values" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x5f}; // PUSH0 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Push non-zero value
    try frame.stack.append(42);
    
    // Push zero via PUSH0
    _ = try op_push0(0, interpreter_ptr, state_ptr);
    
    // Push another non-zero value
    try frame.stack.append(100);
    
    try std.testing.expectEqual(@as(usize, 3), frame.stack.size);
    
    // Check values in order (LIFO)
    try std.testing.expectEqual(@as(u256, 100), try frame.stack.pop());
    try std.testing.expectEqual(@as(u256, 0), try frame.stack.pop());
    try std.testing.expectEqual(@as(u256, 42), try frame.stack.pop());
}

test "PUSH0 performance vs manual zero push" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x5f}; // PUSH0 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const Timer = std.time.Timer;
    var timer = try Timer.start();
    
    // Time PUSH0 operations
    timer.reset();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try op_push0(0, interpreter_ptr, state_ptr);
        if (frame.stack.size >= 500) {
            frame.stack.size = 0;
        }
    }
    const push0_time = timer.read();
    
    // Time manual zero pushes for comparison
    frame.stack.clear();
    timer.reset();
    i = 0;
    while (i < 1000) : (i += 1) {
        try frame.stack.append(0);
        if (frame.stack.size >= 500) {
            frame.stack.size = 0;
        }
    }
    const manual_time = timer.read();
    
    // Both should complete in reasonable time
    try std.testing.expect(push0_time > 0);
    try std.testing.expect(manual_time > 0);
}

// ============================================================================
// PUSH1-PUSH32 Operation Tests
// ============================================================================

test "PUSH operations handle all sizes correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test PUSH1 through PUSH32 with incrementing values
    const test_cases = [_]struct { n: u8, expected: u256, bytes: []const u8 }{
        .{ .n = 1, .expected = 0x01, .bytes = &[_]u8{ 0x60, 0x01 } },
        .{ .n = 2, .expected = 0x0102, .bytes = &[_]u8{ 0x61, 0x01, 0x02 } },
        .{ .n = 3, .expected = 0x010203, .bytes = &[_]u8{ 0x62, 0x01, 0x02, 0x03 } },
        .{ .n = 4, .expected = 0x01020304, .bytes = &[_]u8{ 0x63, 0x01, 0x02, 0x03, 0x04 } },
        .{ .n = 8, .expected = 0x0102030405060708, .bytes = &[_]u8{ 0x67, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 } },
    };
    
    for (test_cases) |case| {
        var contract = try Contract.init(allocator, case.bytes, .{ .address = primitives.Address.ZERO });
        defer contract.deinit(allocator, null);
        
        var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
        defer frame.deinit();
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr: *Operation.State = @ptrCast(&frame);
        
        if (case.n <= 8) {
            const push_fn = make_push_small(case.n);
            const result = try push_fn(0, interpreter_ptr, state_ptr);
            try std.testing.expectEqual(@as(usize, 1 + case.n), result.bytes_consumed);
        } else {
            const push_fn = make_push(case.n);
            const result = try push_fn(0, interpreter_ptr, state_ptr);
            try std.testing.expectEqual(@as(usize, 1 + case.n), result.bytes_consumed);
        }
        
        const value = try frame.stack.pop();
        try std.testing.expectEqual(case.expected, value);
    }
}

test "PUSH32 handles maximum value" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Create bytecode for PUSH32 with all 0xFF bytes
    var code: [33]u8 = undefined;
    code[0] = 0x7f; // PUSH32 opcode
    @memset(code[1..], 0xFF);
    
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const push32_fn = make_push(32);
    const result = try push32_fn(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 33), result.bytes_consumed);
    
    const value = try frame.stack.pop();
    try std.testing.expectEqual(std.math.maxInt(u256), value);
}

test "PUSH operations with insufficient bytecode" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test cases: PUSH operations with missing bytes
    const test_cases = [_]struct { 
        opcode: u8, 
        expected_size: usize, 
        code: []const u8, 
        expected_value: u256,
        push_n: u8,
    }{
        .{ .opcode = 0x61, .expected_size = 3, .code = &[_]u8{0x61}, .expected_value = 0, .push_n = 2 }, // PUSH2 with no data
        .{ .opcode = 0x61, .expected_size = 3, .code = &[_]u8{ 0x61, 0x12 }, .expected_value = 0x1200, .push_n = 2 }, // PUSH2 with 1 byte
        .{ .opcode = 0x64, .expected_size = 6, .code = &[_]u8{ 0x64, 0x12, 0x34 }, .expected_value = 0x123400000000, .push_n = 5 }, // PUSH5 with 2 bytes
    };
    
    for (test_cases) |case| {
        var contract = try Contract.init(allocator, case.code, .{ .address = primitives.Address.ZERO });
        defer contract.deinit(allocator, null);
        
        var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
        defer frame.deinit();
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr: *Operation.State = @ptrCast(&frame);
        
        if (case.push_n <= 8) {
            const push_fn = make_push_small(case.push_n);
            const result = try push_fn(0, interpreter_ptr, state_ptr);
            try std.testing.expectEqual(case.expected_size, result.bytes_consumed);
        } else {
            const push_fn = make_push(case.push_n);
            const result = try push_fn(0, interpreter_ptr, state_ptr);
            try std.testing.expectEqual(case.expected_size, result.bytes_consumed);
        }
        
        const value = try frame.stack.pop();
        try std.testing.expectEqual(case.expected_value, value);
    }
}

test "PUSH operations comparison small vs general" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test that small and general implementations produce same results for PUSH2-PUSH8
    const test_values = [_]struct { n: u8, bytes: []const u8, expected: u256 }{
        .{ .n = 2, .bytes = &[_]u8{ 0x61, 0x12, 0x34 }, .expected = 0x1234 },
        .{ .n = 3, .bytes = &[_]u8{ 0x62, 0xAB, 0xCD, 0xEF }, .expected = 0xABCDEF },
        .{ .n = 4, .bytes = &[_]u8{ 0x63, 0x11, 0x22, 0x33, 0x44 }, .expected = 0x11223344 },
        .{ .n = 8, .bytes = &[_]u8{ 0x67, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }, .expected = 0x0102030405060708 },
    };
    
    for (test_values) |test_val| {
        // Test small implementation
        var contract_small = try Contract.init(allocator, test_val.bytes, .{ .address = primitives.Address.ZERO });
        defer contract_small.deinit(allocator, null);
        
        var frame_small = try Frame.init(allocator, &vm, 1000000, contract_small, primitives.Address.ZERO, &.{});
        defer frame_small.deinit();
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr_small: *Operation.State = @ptrCast(&frame_small);
        
        const push_small_fn = make_push_small(test_val.n);
        const result_small = try push_small_fn(0, interpreter_ptr, state_ptr_small);
        const value_small = try frame_small.stack.pop();
        
        // Test general implementation
        var contract_general = try Contract.init(allocator, test_val.bytes, .{ .address = primitives.Address.ZERO });
        defer contract_general.deinit(allocator, null);
        
        var frame_general = try Frame.init(allocator, &vm, 1000000, contract_general, primitives.Address.ZERO, &.{});
        defer frame_general.deinit();
        
        const state_ptr_general: *Operation.State = @ptrCast(&frame_general);
        
        const push_general_fn = make_push(test_val.n);
        const result_general = try push_general_fn(0, interpreter_ptr, state_ptr_general);
        const value_general = try frame_general.stack.pop();
        
        // Both should produce identical results
        try std.testing.expectEqual(result_small.bytes_consumed, result_general.bytes_consumed);
        try std.testing.expectEqual(value_small, value_general);
        try std.testing.expectEqual(test_val.expected, value_small);
        try std.testing.expectEqual(test_val.expected, value_general);
    }
}

test "PUSH extreme values and edge cases" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    // Test edge values for different PUSH sizes
    const edge_cases = [_]struct { 
        name: []const u8,
        n: u8, 
        code: []const u8, 
        expected: u256 
    }{
        .{ .name = "PUSH1 max", .n = 1, .code = &[_]u8{ 0x60, 0xFF }, .expected = 0xFF },
        .{ .name = "PUSH2 max", .n = 2, .code = &[_]u8{ 0x61, 0xFF, 0xFF }, .expected = 0xFFFF },
        .{ .name = "PUSH4 max", .n = 4, .code = &[_]u8{ 0x63, 0xFF, 0xFF, 0xFF, 0xFF }, .expected = 0xFFFFFFFF },
        .{ .name = "PUSH8 max", .n = 8, .code = &[_]u8{ 0x67, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, .expected = 0xFFFFFFFFFFFFFFFF },
        .{ .name = "PUSH16 alternating", .n = 16, .code = &[_]u8{ 0x6f, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00 }, .expected = 0xAABBCCDDEEFF112233445566778899000 },
    };
    
    for (edge_cases) |case| {
        var contract = try Contract.init(allocator, case.code, .{ .address = primitives.Address.ZERO });
        defer contract.deinit(allocator, null);
        
        var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
        defer frame.deinit();
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr: *Operation.State = @ptrCast(&frame);
        
        if (case.n <= 8) {
            const push_fn = make_push_small(case.n);
            _ = try push_fn(0, interpreter_ptr, state_ptr);
        } else {
            const push_fn = make_push(case.n);
            _ = try push_fn(0, interpreter_ptr, state_ptr);
        }
        
        const value = try frame.stack.pop();
        try std.testing.expectEqual(case.expected, value);
    }
}
// ============================================================================
// DUP1-DUP16 Operation Tests
// ============================================================================

test "DUP1 duplicates top stack element" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x80}; // DUP1 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Push a value to duplicate
    try frame.stack.append(42);
    try std.testing.expectEqual(@as(usize, 1), frame.stack.size);
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const dup1_fn = make_dup(1);
    const result = try dup1_fn(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 0), result.bytes_consumed);
    
    // Should have 2 elements, both 42
    try std.testing.expectEqual(@as(usize, 2), frame.stack.size);
    try std.testing.expectEqual(@as(u256, 42), try frame.stack.pop());
    try std.testing.expectEqual(@as(u256, 42), try frame.stack.pop());
}

test "DUP operations all variants" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x80}; // DUP1 opcode (placeholder)
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Test DUP1 through DUP16
    var n: u8 = 1;
    while (n <= 16) : (n += 1) {
        frame.stack.clear();
        
        // Push n+5 values so we have enough to duplicate from position n
        var i: usize = 0;
        while (i < n + 5) : (i += 1) {
            try frame.stack.append(@as(u256, i + 100));
        }
        
        const original_size = frame.stack.size;
        const value_to_dup = try frame.stack.peek_n(n - 1);
        
        const dup_fn = make_dup(n);
        _ = try dup_fn(0, interpreter_ptr, state_ptr);
        
        // Should have one more element
        try std.testing.expectEqual(original_size + 1, frame.stack.size);
        
        // Top element should be the duplicated value
        const top_value = try frame.stack.pop();
        try std.testing.expectEqual(value_to_dup, top_value);
    }
}

test "DUP16 duplicates 16th element correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x8f}; // DUP16 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Push 20 values
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try frame.stack.append(@as(u256, i * 10));
    }
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // The 16th element from top (index 15 from top, which is value at index 4 from bottom)
    const expected_value: u256 = 40; // i=4, value=4*10=40
    
    const dup16_fn = make_dup(16);
    _ = try dup16_fn(0, interpreter_ptr, state_ptr);
    
    try std.testing.expectEqual(@as(usize, 21), frame.stack.size);
    try std.testing.expectEqual(expected_value, try frame.stack.pop());
}

test "DUP operations with edge values" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x80}; // DUP1 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const edge_values = [_]u256{
        0,
        1,
        std.math.maxInt(u8),
        std.math.maxInt(u16),
        std.math.maxInt(u32),
        std.math.maxInt(u64),
        std.math.maxInt(u128),
        std.math.maxInt(u256),
        1 << 128,
        (1 << 255),
    };
    
    for (edge_values) |value| {
        frame.stack.clear();
        try frame.stack.append(value);
        
        const dup1_fn = make_dup(1);
        _ = try dup1_fn(0, interpreter_ptr, state_ptr);
        
        try std.testing.expectEqual(@as(usize, 2), frame.stack.size);
        try std.testing.expectEqual(value, try frame.stack.pop());
        try std.testing.expectEqual(value, try frame.stack.pop());
    }
}// ============================================================================
// SWAP1-SWAP16 Operation Tests
// ============================================================================

test "SWAP1 swaps top two elements" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x90}; // SWAP1 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    try frame.stack.append(100);
    try frame.stack.append(200);
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const swap1_fn = make_swap(1);
    const result = try swap1_fn(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(@as(usize, 0), result.bytes_consumed);
    
    try std.testing.expectEqual(@as(u256, 100), try frame.stack.pop());
    try std.testing.expectEqual(@as(u256, 200), try frame.stack.pop());
}

test "SWAP operations all variants" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x90}; // SWAP1 opcode (placeholder)
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Test SWAP1 through SWAP16
    var n: u8 = 1;
    while (n <= 16) : (n += 1) {
        frame.stack.clear();
        
        // Push n+5 values so we have enough to swap with position n+1
        var i: usize = 0;
        while (i < n + 5) : (i += 1) {
            try frame.stack.append(@as(u256, i + 100));
        }
        
        const top_value = try frame.stack.peek_n(0);
        const target_value = try frame.stack.peek_n(n);
        
        const swap_fn = make_swap(n);
        _ = try swap_fn(0, interpreter_ptr, state_ptr);
        
        try std.testing.expectEqual(target_value, try frame.stack.peek_n(0));
        try std.testing.expectEqual(top_value, try frame.stack.peek_n(n));
    }
}

test "SWAP16 swaps correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x9f}; // SWAP16 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Push 20 values
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try frame.stack.append(@as(u256, i * 10));
    }
    
    const top_value = try frame.stack.peek_n(0);
    const target_value = try frame.stack.peek_n(16);
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    const swap16_fn = make_swap(16);
    _ = try swap16_fn(0, interpreter_ptr, state_ptr);
    
    try std.testing.expectEqual(target_value, try frame.stack.peek_n(0));
    try std.testing.expectEqual(top_value, try frame.stack.peek_n(16));
}

// ============================================================================
// Runtime Dispatch Tests (push_n, dup_n, swap_n)
// ============================================================================

test "runtime push_n handles all PUSH opcodes" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const test_cases = [_]struct { opcode: u8, n: u8, bytes: []const u8, expected: u256 }{
        .{ .opcode = 0x60, .n = 1, .bytes = &[_]u8{ 0x60, 0x42 }, .expected = 0x42 },
        .{ .opcode = 0x61, .n = 2, .bytes = &[_]u8{ 0x61, 0x12, 0x34 }, .expected = 0x1234 },
        .{ .opcode = 0x64, .n = 5, .bytes = &[_]u8{ 0x64, 0x01, 0x02, 0x03, 0x04, 0x05 }, .expected = 0x0102030405 },
    };
    
    for (test_cases) |case| {
        var contract = try Contract.init(allocator, case.bytes, .{ .address = primitives.Address.ZERO });
        defer contract.deinit(allocator, null);
        
        var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
        defer frame.deinit();
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr: *Operation.State = @ptrCast(&frame);
        
        const result = try push_n(0, interpreter_ptr, state_ptr);
        try std.testing.expectEqual(@as(usize, 1 + case.n), result.bytes_consumed);
        
        const value = try frame.stack.pop();
        try std.testing.expectEqual(case.expected, value);
    }
}

test "runtime dup_n handles all DUP opcodes" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const test_cases = [_]struct { opcode: u8, n: u8 }{
        .{ .opcode = 0x80, .n = 1 }, // DUP1
        .{ .opcode = 0x81, .n = 2 }, // DUP2
        .{ .opcode = 0x8f, .n = 16 }, // DUP16
    };
    
    for (test_cases) |case| {
        var code = [_]u8{case.opcode};
        var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
        defer contract.deinit(allocator, null);
        
        var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
        defer frame.deinit();
        
        // Push enough values
        var i: usize = 0;
        while (i < case.n + 5) : (i += 1) {
            try frame.stack.append(@as(u256, i + 100));
        }
        
        const original_size = frame.stack.size;
        const value_to_dup = try frame.stack.peek_n(case.n - 1);
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr: *Operation.State = @ptrCast(&frame);
        
        _ = try dup_n(0, interpreter_ptr, state_ptr);
        
        try std.testing.expectEqual(original_size + 1, frame.stack.size);
        try std.testing.expectEqual(value_to_dup, try frame.stack.pop());
    }
}

test "runtime swap_n handles all SWAP opcodes" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const test_cases = [_]struct { opcode: u8, n: u8 }{
        .{ .opcode = 0x90, .n = 1 }, // SWAP1
        .{ .opcode = 0x91, .n = 2 }, // SWAP2
        .{ .opcode = 0x9f, .n = 16 }, // SWAP16
    };
    
    for (test_cases) |case| {
        var code = [_]u8{case.opcode};
        var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
        defer contract.deinit(allocator, null);
        
        var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
        defer frame.deinit();
        
        // Push enough values
        var i: usize = 0;
        while (i < case.n + 5) : (i += 1) {
            try frame.stack.append(@as(u256, i + 100));
        }
        
        const top_value = try frame.stack.peek_n(0);
        const target_value = try frame.stack.peek_n(case.n);
        
        const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
        const state_ptr: *Operation.State = @ptrCast(&frame);
        
        _ = try swap_n(0, interpreter_ptr, state_ptr);
        
        try std.testing.expectEqual(target_value, try frame.stack.peek_n(0));
        try std.testing.expectEqual(top_value, try frame.stack.peek_n(case.n));
    }
}

// ============================================================================
// Edge Case and Error Handling Tests  
// ============================================================================

test "stack operations handle maximum capacity correctly" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x5f}; // PUSH0 opcode
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    // Fill stack to near capacity
    var i: usize = 0;
    while (i < Stack.CAPACITY - 1) : (i += 1) {
        try frame.stack.append(i);
    }
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Should be able to push one more
    _ = try op_push0(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(Stack.CAPACITY, frame.stack.size);
    
    // Now stack is full, verify operations work correctly
    // Can still pop
    _ = try op_pop(0, interpreter_ptr, state_ptr);
    try std.testing.expectEqual(Stack.CAPACITY - 1, frame.stack.size);
    
    // Can dup when there's space
    if (frame.stack.size >= 1) {
        const dup1_fn = make_dup(1);
        _ = try dup1_fn(0, interpreter_ptr, state_ptr);
        try std.testing.expectEqual(Stack.CAPACITY, frame.stack.size);
    }
}

test "stack operations maintain consistency under stress" {
    const allocator = std.testing.allocator;
    const Vm = @import("../evm.zig");
    const MemoryDatabase = @import("../state/memory_database.zig");
    const Contract = @import("../frame/contract.zig");
    const primitives = @import("primitives");
    
    var memory_db = MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.toDatabaseInterface();
    var vm = try Vm.init(allocator, db_interface, null, null);
    defer vm.deinit();
    
    const code = [_]u8{0x60, 0x42}; // PUSH1 0x42
    var contract = try Contract.init(allocator, &code, .{ .address = primitives.Address.ZERO });
    defer contract.deinit(allocator, null);
    
    var frame = try Frame.init(allocator, &vm, 1000000, contract, primitives.Address.ZERO, &.{});
    defer frame.deinit();
    
    const interpreter_ptr: *Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *Operation.State = @ptrCast(&frame);
    
    // Stress test with rapid push/pop/dup/swap operations
    var ops: usize = 0;
    while (ops < 1000) : (ops += 1) {
        const op_type = ops % 6;
        
        switch (op_type) {
            0 => { // PUSH
                if (frame.stack.size < Stack.CAPACITY - 50) {
                    _ = try op_push1(0, interpreter_ptr, state_ptr);
                }
            },
            1 => { // POP
                if (frame.stack.size > 0) {
                    _ = try op_pop(0, interpreter_ptr, state_ptr);
                }
            },
            2 => { // DUP1
                if (frame.stack.size >= 1 and frame.stack.size < Stack.CAPACITY) {
                    const dup1_fn = make_dup(1);
                    _ = try dup1_fn(0, interpreter_ptr, state_ptr);
                }
            },
            3 => { // SWAP1  
                if (frame.stack.size >= 2) {
                    const swap1_fn = make_swap(1);
                    _ = try swap1_fn(0, interpreter_ptr, state_ptr);
                }
            },
            4 => { // DUP5
                if (frame.stack.size >= 5 and frame.stack.size < Stack.CAPACITY) {
                    const dup5_fn = make_dup(5);
                    _ = try dup5_fn(0, interpreter_ptr, state_ptr);
                }
            },
            5 => { // SWAP3
                if (frame.stack.size >= 4) {
                    const swap3_fn = make_swap(3);
                    _ = try swap3_fn(0, interpreter_ptr, state_ptr);
                }
            },
            else => unreachable,
        }
        
        // Verify stack integrity
        try std.testing.expect(frame.stack.size <= Stack.CAPACITY);
    }
}