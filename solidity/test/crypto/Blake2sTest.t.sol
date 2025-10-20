// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "forge-std/Test.sol";

import "../../contracts/crypto/Blake2s.sol";

contract Blake2sTest is Test {
    using Blake2s for Blake2s.Instance;

    event HashResult(string input, bytes hash);

    function testSingleHashA() public {
        // Use simple hash function
        bytes32 hash = Blake2s.hash("a");

        emit HashResult("a", abi.encodePacked(hash));

        // Expected hash for "a": 4a0d129873403037c2cd9b9048203687f6233fb6738956e0349bd4320fec3e90
        bytes32 expectedHash = 0x4a0d129873403037c2cd9b9048203687f6233fb6738956e0349bd4320fec3e90;

        require(
            hash == expectedHash,
            "Hash does not match expected Blake2s result"
        );
    }

    function testKeccakCost() public {
        bytes32 hash = keccak256(abi.encodePacked("a"));
        emit HashResult("a (keccak256)", abi.encodePacked(hash));
    }

    function testHashStateTest() public {
        // Replicate Rust hash_state_test exactly
        Blake2s.Instance memory state = Blake2s.init(hex"", 32);
        state.update("a");
        state.update("b");

        // finalize_reset: finalize and reset state
        bytes memory hash = state.finalizeReset();
        bytes32 hash_result;
        assembly {
            hash_result := mload(add(hash, 32))
        }

        // finalize again on reset state (should produce empty hash)
        bytes memory hash_empty = state.finalize();
        bytes32 hash_empty_result;
        assembly {
            hash_empty_result := mload(add(hash_empty, 32))
        }

        emit HashResult("ab (finalize_reset)", abi.encodePacked(hash_result));
        emit HashResult(
            "empty (after reset)",
            abi.encodePacked(hash_empty_result)
        );

        // Test assertions like in Rust
        // hash should equal Blake2s.hash("ab")
        bytes32 expected_ab = Blake2s.hash("ab");
        require(
            hash_result == expected_ab,
            "Hash ab does not match single hash"
        );

        // hash_empty should equal Blake2s.hash("")
        bytes32 expected_empty = Blake2s.hash("");
        require(
            hash_empty_result == expected_empty,
            "Hash empty does not match single hash"
        );

        // Expected hash for "ab": from Rust test output
        bytes32 expected_ab_rust = 0x19c3ebeed2ee90063cb5a8a4dd700ed7e5852dfc6108c84fac85888682a18f0e;
        require(
            hash_result == expected_ab_rust,
            "Hash ab does not match Rust result"
        );

        // Expected hash for "": from Rust test output
        bytes32 expected_empty_rust = 0x69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9;
        require(
            hash_empty_result == expected_empty_rust,
            "Hash empty does not match Rust result"
        );
    }
}
