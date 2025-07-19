const std = @import("std");
const evm = @import("evm");
const primitives = @import("primitives");
const testing = std.testing;

test "fuzz_comparison_lt_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const test_code = [_]u8{0x01};
    var contract = evm.Contract.init(
        primitives.Address.ZERO,
        primitives.Address.ZERO,
        0,
        1000000,
        &test_code,
        [_]u8{0} ** 32,
        &.{},
        false
    );
    defer contract.deinit(allocator, null);
    
    var builder = evm.Frame.builder(allocator);
    var frame = try builder
        .withVm(&vm)
        .withContract(&contract)
        .withGas(1000000)
        .withCaller(.{})
        .build();
    defer frame.deinit();
    
    // Test LT operation: 5 < 10
    try frame.stack.append(5);  // a
    try frame.stack.append(10); // b
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x10);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 1), result); // true
}

test "fuzz_comparison_eq_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const test_code = [_]u8{0x01};
    var contract = evm.Contract.init(
        primitives.Address.ZERO,
        primitives.Address.ZERO,
        0,
        1000000,
        &test_code,
        [_]u8{0} ** 32,
        &.{},
        false
    );
    defer contract.deinit(allocator, null);
    
    var builder = evm.Frame.builder(allocator);
    var frame = try builder
        .withVm(&vm)
        .withContract(&contract)
        .withGas(1000000)
        .withCaller(.{})
        .build();
    defer frame.deinit();
    
    // Test EQ operation: 42 == 42
    try frame.stack.append(42); // b
    try frame.stack.append(42); // a
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x14);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 1), result); // true
}

test "fuzz_comparison_iszero_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const test_code = [_]u8{0x01};
    var contract = evm.Contract.init(
        primitives.Address.ZERO,
        primitives.Address.ZERO,
        0,
        1000000,
        &test_code,
        [_]u8{0} ** 32,
        &.{},
        false
    );
    defer contract.deinit(allocator, null);
    
    var builder = evm.Frame.builder(allocator);
    var frame = try builder
        .withVm(&vm)
        .withContract(&contract)
        .withGas(1000000)
        .withCaller(.{})
        .build();
    defer frame.deinit();
    
    // Test ISZERO operation with zero
    try frame.stack.append(0);
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x15);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 1), result); // true
    
    // Test ISZERO operation with non-zero
    try frame.stack.append(42);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x15);
    
    const result2 = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 0), result2); // false
}