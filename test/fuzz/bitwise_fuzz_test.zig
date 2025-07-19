const std = @import("std");
const evm = @import("evm");
const primitives = @import("primitives");
const testing = std.testing;

test "fuzz_bitwise_and_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface(), null, null);
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
    
    // Test AND operation
    try frame.stack.append(0xF0F0F0F0F0F0F0F0);
    try frame.stack.append(0x0F0F0F0F0F0F0F0F);
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x16);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 0), result);
}

test "fuzz_bitwise_or_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface(), null, null);
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
    
    // Test OR operation
    try frame.stack.append(0xF0F0F0F0F0F0F0F0);
    try frame.stack.append(0x0F0F0F0F0F0F0F0F);
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x17);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 0xFFFFFFFFFFFFFFFF), result);
}

test "fuzz_bitwise_xor_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface(), null, null);
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
    
    // Test XOR operation
    try frame.stack.append(0xAAAAAAAAAAAAAAAA);
    try frame.stack.append(0x5555555555555555);
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x18);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, 0xFFFFFFFFFFFFFFFF), result);
}

test "fuzz_bitwise_not_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface(), null, null);
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
    
    // Test NOT operation
    try frame.stack.append(0);
    
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x19);
    
    const result = try frame.stack.pop();
    try testing.expectEqual(std.math.maxInt(u256), result);
}