const std = @import("std");
const evm = @import("evm");
const primitives = @import("primitives");
const testing = std.testing;

test "fuzz_environment_address_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const contract_address = primitives.Address.from_u256(0x1234567890ABCDEF);
    const test_code = [_]u8{0x01};
    var contract = evm.Contract.init(
        primitives.Address.ZERO,
        contract_address,
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
    
    // Test ADDRESS operation
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x30); // ADDRESS opcode
    
    const result = try frame.stack.pop();
    try testing.expectEqual(primitives.Address.to_u256(contract_address), result);
}

test "fuzz_environment_caller_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const caller_address = primitives.Address.from_u256(0xABCDEF1234567890);
    const test_code = [_]u8{0x01};
    var contract = evm.Contract.init(
        caller_address,
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
    
    // Test CALLER operation
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x33); // CALLER opcode
    
    const result = try frame.stack.pop();
    try testing.expectEqual(primitives.Address.to_u256(caller_address), result);
}

test "fuzz_environment_callvalue_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const call_value: u256 = 1000000000000000000; // 1 ETH in wei
    const test_code = [_]u8{0x01};
    var contract = evm.Contract.init(
        primitives.Address.ZERO,
        primitives.Address.ZERO,
        call_value,
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
    
    // Test CALLVALUE operation
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x34); // CALLVALUE opcode
    
    const result = try frame.stack.pop();
    try testing.expectEqual(call_value, result);
}

test "fuzz_environment_codesize_operations" {
    const allocator = testing.allocator;
    
    var db = evm.MemoryDatabase.init(allocator);
    defer db.deinit();
    
    var vm = try evm.Evm.init(allocator, db.to_database_interface());
    defer vm.deinit();
    
    const test_code = [_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }; // Simple bytecode
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
    
    // Test CODESIZE operation
    const interpreter_ptr: *evm.Operation.Interpreter = @ptrCast(&vm);
    const state_ptr: *evm.Operation.State = @ptrCast(&frame);
    _ = try vm.table.execute(0, interpreter_ptr, state_ptr, 0x38); // CODESIZE opcode
    
    const result = try frame.stack.pop();
    try testing.expectEqual(@as(u256, test_code.len), result);
}