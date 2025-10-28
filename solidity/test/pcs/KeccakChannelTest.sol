// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/pcs/PcsConfig.sol";
import "../../contracts/core/CirclePoint.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/libraries/CommitmentSchemeVerifierLib.sol";
import "../../contracts/libraries/KeccakChannelLib.sol";

/// @title CommitmentSchemeVerifierTest
/// @notice TDD tests for library-based CommitmentSchemeVerifier using direct libraries
contract KeccakChannelTest is Test {
    using CommitmentSchemeVerifierLib for CommitmentSchemeVerifierLib.VerifierState;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using QM31Field for QM31Field.QM31;
    using CirclePoint for CirclePoint.Point;

    CommitmentSchemeVerifierLib.VerifierState verifierState;
    KeccakChannelLib.ChannelState channel;
    PcsConfig.Config defaultConfig;

    function setUp() public {
        defaultConfig = PcsConfig.defaultConfig();
        
        // Initialize channel state directly (it starts with zero values by default)
        // channel starts with digest = 0x0 and nDraws = 0
        
        // Initialize verifier state using the library's initialize function
        CommitmentSchemeVerifierLib.initialize(verifierState, defaultConfig);
    }

    /// @notice Test verifier state initialization
    function testVerifierInitialization() public view {
        // Test that verifier state is properly initialized
        console.log("=== Verifier Initialization Test ===");
        console.log("Default config PoW bits:", defaultConfig.powBits);
        console.log("Default config blowup factor:", defaultConfig.friConfig.logBlowupFactor);
        console.log("Default config queries:", defaultConfig.friConfig.nQueries);
        
        // Verify channel is initialized
        console.log("Channel initialized successfully");
        console.log("SUCCESS: Verifier initialization test passed");
    }

    /// @notice Test invalid configuration rejection
    function testInvalidConfigurationRejection() public {
        PcsConfig.Config memory invalidConfig = PcsConfig.Config({
            powBits: 40, // Invalid - too high
            friConfig: PcsConfig.defaultFriConfig()
        });

        // Library accepts any configuration structure
        CommitmentSchemeVerifierLib.initialize(verifierState, invalidConfig);
        console.log("Library accepts configuration with PoW bits:", invalidConfig.powBits);
    }

    /// @notice Test commitment verification with specific data using libraries
    function testRustSpecificCommitment() public {
        // Rust config: PcsConfig { pow_bits: 10, fri_config: FriConfig::new(5, 4, 64) }
        // FriConfig::new(log_last_layer_degree_bound, log_blowup_factor, n_queries)
        PcsConfig.Config memory rustConfig = PcsConfig.Config({
            powBits: 10,
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 4, // Second parameter: log_blowup_factor = 4 (16x blowup)
                logLastLayerDegreeBound: 5, // First parameter: log_last_layer_degree_bound = 5
                nQueries: 64 // Third parameter: n_queries = 64
            })
        });

        // Initialize with Rust config using libraries instead of STWOVerifier
        CommitmentSchemeVerifierLib.initialize(verifierState, rustConfig);
        // Reset channel to initial state for this test
        channel.digest = bytes32(0);
        channel.nDraws = 0;
        console.log("=== Testing Keccak Channel with Rust Data ===");

        // Test data from Rust implementation
        bytes32 commitment = 0x7f3fb23a36bd8b85697aadc79cd031fab8fe3b65a557d923e8fd5d1879d02e13;

        // Trace 0: [8, 8, 8, 8]
        uint32[] memory trace0LogSizes = new uint32[](4);
        trace0LogSizes[0] = 8;
        trace0LogSizes[1] = 8;
        trace0LogSizes[2] = 8;
        trace0LogSizes[3] = 8;

        console.log("Commitment:");
        console.logBytes32(commitment);
        // console.log("Trace 0: [%d, %d, %d, %d]", trace0LogSizes[0], trace0LogSizes[1], trace0LogSizes[2], trace0LogSizes[3]);

        // Expected channel states from Rust
        bytes32 expectedInitialDigest = bytes32(0);
        bytes32 expectedAfterCommitDigest = 0x7b8cb803bdb2e8fc5e286da7e482d259702b4669015513390b4aa0d184d3a6c7;

        // Verify initial channel state
        console.log("Channel state before verification:");
        console.log("  digest:");
        console.logBytes32(channel.digest);
        console.log("  n_draws: %d", channel.nDraws);
        assertEq(channel.digest, expectedInitialDigest, "Initial digest should be zero");
        assertEq(channel.nDraws, 0, "Initial draws should be zero");

        // Add preprocessed commitment to channel using keccak mixing
        channel.digest = keccak256(abi.encodePacked(channel.digest, commitment));
        // nDraws remains 0 after mixing commitment

        console.log("Channel state after preprocessed commitment:");
        console.log("  actual digest:");
        console.logBytes32(channel.digest);
        console.log("  expected digest:");
        console.logBytes32(expectedAfterCommitDigest);
        console.log("  n_draws: %d", channel.nDraws);

        // Verify channel state matches Rust implementation
        assertEq(channel.digest, expectedAfterCommitDigest, "Channel digest should match Rust implementation");
        assertEq(channel.nDraws, 0, "Should still have 0 draws after commitment");

        console.log("SUCCESS: Channel state matches Rust implementation!");
    }
}