// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/vcs/MerkleVerifier.sol";

/// @title ArrayUtilsTest
/// @notice Test for array utility functions used in bounds calculation
contract ArrayUtilsTest is Test {
    using MerkleVerifier for MerkleVerifier.Verifier;

    // Test hash node 
    function test_hashNode() public {
        console.log("=== Testing MerkleVerifier.hashNode ===");
        
        bytes32 leftChild = bytes32(uint256(0x323d69c4e57b6c363160b7c8e9753e38343dc13adbd124db4c14ba472c046423));
        bytes32 rightChild = bytes32(uint256(0x323d69c4e57b6c363160b7c8e9753e38343dc13adbd124db4c14ba472c046423));
        uint32[] memory values = new uint32[](2);
        values[0] = 42;
        values[1] = 45;
        
        bytes32 nodeHash = MerkleVerifier._hashNode(leftChild, rightChild, values);
        
        console.log("Node hash:");
        console.logBytes32(nodeHash);

        // Expected hash calculated from Rust implementation 0xa64ea736c1006827835eb86cb9884e6e233e366c8c5e65cf7ff21439d4cd7c91
        bytes32 expectedHash = bytes32(uint256(0xa64ea736c1006827835eb86cb9884e6e233e366c8c5e65cf7ff21439d4cd7c91));
        assertEq(nodeHash, expectedHash, "Node hash does not match expected value");
    }

    function test_hashLeaf() public {
        console.log("=== Testing MerkleVerifier._hashLeaf ===");
        
        uint32[] memory values = new uint32[](2);
        values[0] = 123;
        values[1] = 456;
        
        bytes32 nodeHash = MerkleVerifier._hashLeaf(values);
        
        console.log("Node hash:");
        console.logBytes32(nodeHash);

        bytes32 expectedHash = bytes32(uint256(0x28389b9b87013995783e4550ac039f5dc8012b354ac1d5a6fe132ce1a8523bd2));
        assertEq(nodeHash, expectedHash, "Leaf hash does not match expected value");
    }

    function test_hashNodeWithValues() public {
        console.log("=== Testing MerkleVerifier._hashNode with values ===");
        
        bytes32 left = bytes32(uint256(0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732));
        bytes32 right = bytes32(uint256(0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732));
        
        uint32[] memory values = new uint32[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;
        
        bytes32 nodeHash = MerkleVerifier._hashNode(left, right, values);
        
        console.log("Node hash:");
        console.logBytes32(nodeHash);
        console.log("As uint256: %s", uint256(nodeHash));

        // Expected from Rust: 0x320952af220acfd45875691415e9c3c28d734e6f76d241dc3fff941c6bb06fb5
        bytes32 expectedHash = bytes32(uint256(0x320952af220acfd45875691415e9c3c28d734e6f76d241dc3fff941c6bb06fb5));
        assertEq(nodeHash, expectedHash, "Node hash does not match expected value from Rust");
    }

    function test_hashNodeLayer2() public {
        console.log("=== Testing MerkleVerifier._hashNode for Layer 2 ===");
        
        // From Rust: witness[4] and witness[5] (both same value, no column values)
        //  -> Expected hash: 0xa1fc824da49a6a1bc650b925ade3aed54b417e34ff4c5d5d1f79193ee9beffcf
        bytes32 left = bytes32(uint256(0xe2b91c8a056ab56173631dac91996c3d06f09d3c26e6a3db289253b995bfbff5));
        bytes32 right = bytes32(uint256(0xe2b91c8a056ab56173631dac91996c3d06f09d3c26e6a3db289253b995bfbff5));
        
        uint32[] memory values = new uint32[](0); // Empty - no column values
        
        bytes32 nodeHash = MerkleVerifier._hashNode(left, right, values);
        
        console.log("Node hash:");
        console.logBytes32(nodeHash);

        // Expected from Rust
        bytes32 expectedHash = bytes32(uint256(0xa1fc824da49a6a1bc650b925ade3aed54b417e34ff4c5d5d1f79193ee9beffcf));
        assertEq(nodeHash, expectedHash, "Layer 2 node hash does not match Rust");
    }

    /// @notice Test Merkle verification with real data from Rust test
    /// @dev This matches test_merkle_verification_with_real_data in keccak_merkle.rs
    function test_merkleVerificationWithRealData() public {
        console.log("=== Testing MerkleVerifier.verify with real data ===");
        
        // Root commitment (matches Rust test data)
        bytes32 root = bytes32(uint256(0x0479634094cbd214ceac4e10d239a5bf2b70da4c1e692af3a3f80a070eb95949));
        
        // Column log sizes: vec![5, 5, 5, 5, 4, 4, 4, 4]
        uint32[] memory columnLogSizes = new uint32[](8);
        columnLogSizes[0] = 5;
        columnLogSizes[1] = 5;
        columnLogSizes[2] = 5;
        columnLogSizes[3] = 5;
        columnLogSizes[4] = 4;
        columnLogSizes[5] = 4;
        columnLogSizes[6] = 4;
        columnLogSizes[7] = 4;
        
        // Create verifier
        MerkleVerifier.Verifier memory verifier = MerkleVerifier.newVerifier(root, columnLogSizes);
        
        console.log("Verifier created with %d unique log sizes:", verifier.logSizes.length);
        for (uint256 i = 0; i < verifier.logSizes.length; i++) {
            console.log("  logSize %d: %d columns", verifier.logSizes[i], verifier.nColumnsPerLogSize[i]);
        }
        
        // Hash witness - 7 hashes (matches Rust test data)
        bytes32[] memory hashWitness = new bytes32[](7);
        hashWitness[0] = bytes32(uint256(0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732));
        hashWitness[1] = bytes32(uint256(0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732));
        hashWitness[2] = bytes32(uint256(0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732));
        hashWitness[3] = bytes32(uint256(0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732));
        hashWitness[4] = bytes32(uint256(0xe2b91c8a056ab56173631dac91996c3d06f09d3c26e6a3db289253b995bfbff5));
        hashWitness[5] = bytes32(uint256(0xe2b91c8a056ab56173631dac91996c3d06f09d3c26e6a3db289253b995bfbff5));
        hashWitness[6] = bytes32(uint256(0x9abb28a9741d922bf889d55f1e6f22b8559d229a79a2dfaff5b910b32f7db3da));
        
        // Empty column witness (all values are queried)
        uint32[] memory columnWitness = new uint32[](0);
        
        MerkleVerifier.Decommitment memory decommitment = MerkleVerifier.Decommitment({
            hashWitness: hashWitness,
            columnWitness: columnWitness
        });
        
        // Queries per log size (matches Rust: queries.insert(4, vec![2, 3, 6, 7]) and queries.insert(5, vec![4, 5, 12, 13]))
        // NOTE: Queries must be sorted within each log size!
        MerkleVerifier.QueriesPerLogSize[] memory queriesPerLogSize = new MerkleVerifier.QueriesPerLogSize[](2);
        
        // Log size 5 queries (sorted)
        queriesPerLogSize[0].logSize = 5;
        queriesPerLogSize[0].queries = new uint256[](4);
        queriesPerLogSize[0].queries[0] = 4;
        queriesPerLogSize[0].queries[1] = 5;
        queriesPerLogSize[0].queries[2] = 12;
        queriesPerLogSize[0].queries[3] = 13;
        
        // Log size 4 queries (sorted)
        queriesPerLogSize[1].logSize = 4;
        queriesPerLogSize[1].queries = new uint256[](4);
        queriesPerLogSize[1].queries[0] = 2;
        queriesPerLogSize[1].queries[1] = 3;
        queriesPerLogSize[1].queries[2] = 6;
        queriesPerLogSize[1].queries[3] = 7;
        
        // Queried values - 32 zeros (8 columns × 4 field elements per QM31)
        // This matches the Rust test data with all zeros
        uint32[] memory queriedValues = new uint32[](32);
        for (uint256 i = 0; i < 32; i++) {
            queriedValues[i] = 0;
        }
        
        // Verify the decommitment
        console.log("Calling MerkleVerifier.verify...");
        console.log("Expected root:", uint256(root));
        
        MerkleVerifier.verify(verifier, queriesPerLogSize, queriedValues, decommitment);
        
        console.log("Merkle verification PASSED!");
        console.log("Root verified: 0x%s", uint256(root));
    }
}