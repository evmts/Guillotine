//! Guillotine - High-Performance Ethereum Virtual Machine in Zig
//!
//! This is the main entry point for the Guillotine EVM implementation, providing
//! both a Zig API and a C-compatible interface for external integration.
//!
//! ## Architecture Overview
//!
//! Guillotine is structured into several key modules:
//!
//! ### Core EVM (`evm`)
//! - **Virtual Machine**: Complete EVM implementation with bytecode execution
//! - **Stack & Memory**: 256-bit stack and byte-addressable memory
//! - **State Management**: Account state, storage, and code management
//! - **Opcode Dispatch**: Efficient jump table for instruction execution
//! - **Gas Accounting**: Precise gas cost calculations per EVM specification
//!
//! ### Primitives (`primitives`)
//! - **Address Operations**: Ethereum address utilities and validation
//! - **Cryptographic Functions**: Hash functions, signature verification
//! - **Data Encoding**: RLP, ABI, and hex encoding/decoding
//! - **Transaction Types**: Support for all Ethereum transaction formats
//!
//! ### Provider (`provider`)
//! - **RPC Interface**: JSON-RPC client for Ethereum nodes
//! - **Network Transport**: HTTP/WebSocket communication
//! - **Blockchain Queries**: Block, transaction, and state queries
//!
//! ## Usage Examples
//!
//! ### Zig API
//! ```zig
//! const guillotine = @import("guillotine");
//!
//! // Initialize EVM
//! var vm = try guillotine.Evm.init(allocator, database, null, null);
//! defer vm.deinit();
//!
//! // Execute bytecode
//! const result = try vm.interpret(contract, input);
//! ```
//!
//! ### C API
//! ```c
//! // Initialize EVM
//! if (guillotine_init() != 0) {
//!     // Handle error
//! }
//!
//! // Execute bytecode
//! CExecutionResult result;
//! guillotine_execute(bytecode, len, caller, value, gas, &result);
//!
//! // Cleanup
//! guillotine_deinit();
//! ```
//!
//! ## Design Principles
//!
//! 1. **Correctness**: Strict adherence to Ethereum Yellow Paper specification
//! 2. **Performance**: Minimal allocations, efficient memory management
//! 3. **Safety**: Strong typing, comprehensive error handling
//! 4. **Compatibility**: Full EVM specification compliance
//! 5. **Modularity**: Clear separation of concerns and testability
//!
//! ## Memory Management
//!
//! The C API uses a global allocator suitable for WASM environments,
//! while the Zig API allows custom allocator injection for maximum flexibility.
//!
//! ## Error Handling
//!
//! The C API provides error codes compatible with external systems,
//! while the Zig API uses typed error unions for precise error handling.

const std = @import("std");
const builtin = @import("builtin");

const evm_root = @import("evm");
const primitives = @import("primitives");
const provider = @import("provider");

// Simple inline logging that compiles out for freestanding WASM
fn log(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    _ = scope;
    if (builtin.target.cpu.arch != .wasm32 or builtin.target.os.tag != .freestanding) {
        switch (level) {
            .err => std.log.err("[guillotine_c] " ++ format, args),
            .warn => std.log.warn("[guillotine_c] " ++ format, args),
            .info => std.log.info("[guillotine_c] " ++ format, args),
            .debug => std.log.debug("[guillotine_c] " ++ format, args),
        }
    }
}
const MemoryDatabase = evm_root.MemoryDatabase;
const Address = primitives.Address.Address;

// Global allocator for WASM environment
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = if (builtin.target.cpu.arch == .wasm32) std.heap.wasm_allocator else gpa.allocator();

// Global VM instance
var vm_instance: ?*evm_root.Evm = null;

// C-compatible error codes
const GuillotineError = enum(c_int) {
    GUILLOTINE_OK = 0,
    GUILLOTINE_ERROR_MEMORY = 1,
    GUILLOTINE_ERROR_INVALID_PARAM = 2,
    GUILLOTINE_ERROR_VM_NOT_INITIALIZED = 3,
    GUILLOTINE_ERROR_EXECUTION_FAILED = 4,
    GUILLOTINE_ERROR_INVALID_ADDRESS = 5,
    GUILLOTINE_ERROR_INVALID_BYTECODE = 6,
};

// C-compatible execution result
const CExecutionResult = extern struct {
    success: c_int,
    gas_used: c_ulonglong,
    return_data_ptr: [*]const u8,
    return_data_len: usize,
    error_code: c_int,
};

/// Initialize the Guillotine EVM
/// @return Error code (0 = success)
export fn guillotine_init() c_int {
    log(.info, .guillotine_c, "Initializing Guillotine EVM", .{});

    if (vm_instance != null) {
        log(.warn, .guillotine_c, "VM already initialized", .{});
        return @intFromEnum(GuillotineError.GUILLOTINE_OK);
    }

    var memory_db = MemoryDatabase.init(allocator);
    const db_interface = memory_db.to_database_interface();

    const vm = allocator.create(evm_root.Evm) catch {
        log(.err, .guillotine_c, "Failed to allocate memory for VM", .{});
        return @intFromEnum(GuillotineError.GUILLOTINE_ERROR_MEMORY);
    };

    vm.* = evm_root.Evm.init(allocator, db_interface) catch |err| {
        log(.err, .guillotine_c, "Failed to initialize VM: {}", .{err});
        allocator.destroy(vm);
        return @intFromEnum(GuillotineError.GUILLOTINE_ERROR_MEMORY);
    };

    vm_instance = vm;
    log(.info, .guillotine_c, "Guillotine EVM initialized successfully", .{});
    return @intFromEnum(GuillotineError.GUILLOTINE_OK);
}

/// Cleanup and destroy the Guillotine EVM
export fn guillotine_deinit() void {
    log(.info, .guillotine_c, "Destroying Guillotine EVM", .{});

    if (vm_instance) |vm| {
        vm.deinit();
        allocator.destroy(vm);
        vm_instance = null;
    }
}

/// Execute bytecode on the EVM
/// @param bytecode_ptr Pointer to bytecode
/// @param bytecode_len Length of bytecode
/// @param caller_ptr Pointer to caller address (20 bytes)
/// @param value Value to transfer (as bytes, little endian)
/// @param gas_limit Gas limit for execution
/// @param result_ptr Pointer to result structure to fill
/// @return Error code (0 = success)
export fn guillotine_execute(
    bytecode_ptr: [*]const u8,
    bytecode_len: usize,
    caller_ptr: [*]const u8,
    value: c_ulonglong,
    gas_limit: c_ulonglong,
    result_ptr: *CExecutionResult,
) c_int {
    log(.info, .guillotine_c, "Executing bytecode: {} bytes, gas_limit: {}", .{ bytecode_len, gas_limit });

    const vm = vm_instance orelse {
        log(.err, .guillotine_c, "VM not initialized", .{});
        return @intFromEnum(GuillotineError.GUILLOTINE_ERROR_VM_NOT_INITIALIZED);
    };

    // Validate inputs
    if (bytecode_len == 0) {
        log(.err, .guillotine_c, "Invalid bytecode", .{});
        return @intFromEnum(GuillotineError.GUILLOTINE_ERROR_INVALID_BYTECODE);
    }

    // Convert inputs
    const bytecode = bytecode_ptr[0..bytecode_len];
    const caller_bytes = caller_ptr[0..20];
    const caller_address: primitives.Address.Address = caller_bytes.*;

    // Create contract for execution
    const target_address = primitives.Address.ZERO_ADDRESS; // Use zero address for contract execution
    var contract = evm_root.Contract.init_at_address(caller_address, target_address, @as(u256, value), gas_limit, bytecode, &[_]u8{}, // empty input for now
        false // not static
    );
    defer contract.deinit(allocator, null);

    // Set bytecode in state
    vm.state.set_code(target_address, bytecode) catch |err| {
        log(.err, .guillotine_c, "Failed to set bytecode: {}", .{err});
        result_ptr.success = 0;
        result_ptr.error_code = @intFromEnum(GuillotineError.GUILLOTINE_ERROR_EXECUTION_FAILED);
        return @intFromEnum(GuillotineError.GUILLOTINE_ERROR_EXECUTION_FAILED);
    };

    // Execute bytecode
    const run_result = vm.interpret(&contract, &[_]u8{}) catch |err| {
        log(.err, .guillotine_c, "Execution failed: {}", .{err});
        result_ptr.success = 0;
        result_ptr.error_code = @intFromEnum(GuillotineError.GUILLOTINE_ERROR_EXECUTION_FAILED);
        return @intFromEnum(GuillotineError.GUILLOTINE_ERROR_EXECUTION_FAILED);
    };

    // Fill result structure
    result_ptr.success = if (run_result.status == .Success) 1 else 0;
    result_ptr.gas_used = run_result.gas_used;
    if (run_result.output) |output| {
        result_ptr.return_data_ptr = output.ptr;
        result_ptr.return_data_len = output.len;
    } else {
        result_ptr.return_data_ptr = &[_]u8{};
        result_ptr.return_data_len = 0;
    }
    result_ptr.error_code = @intFromEnum(GuillotineError.GUILLOTINE_OK);

    log(.info, .guillotine_c, "Execution completed: status={}, gas_used={}", .{ run_result.status, run_result.gas_used });
    return @intFromEnum(GuillotineError.GUILLOTINE_OK);
}

/// Get the current VM state (for debugging)
/// @return 1 if VM is initialized, 0 otherwise
export fn guillotine_is_initialized() c_int {
    return if (vm_instance != null) 1 else 0;
}

/// Get version string
/// @return Pointer to null-terminated version string
export fn guillotine_version() [*:0]const u8 {
    return "1.0.0";
}

// Test to ensure this compiles
test "C interface compilation" {
    std.testing.refAllDecls(@This());
}

// Re-export modules
pub const Evm = evm_root.Evm;
pub const Primitives = primitives;
pub const Provider = provider;

test "Evm module" {
    std.testing.refAllDecls(Evm);
}
