// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/pcs/PcsConfig.sol";

/// @title PcsConfigTest
/// @notice TDD tests for PcsConfig library and configuration management
contract PcsConfigTest is Test {
    using PcsConfig for PcsConfig.Config;
    using PcsConfig for PcsConfig.FriConfig;

    /// @notice Test default configuration creation
    function testDefaultConfigurations() public pure {
        // Test default FRI config
        PcsConfig.FriConfig memory friConfig = PcsConfig.defaultFriConfig();
        assertEq(friConfig.logBlowupFactor, 1, "Default blowup factor should be 1");
        assertEq(friConfig.logLastLayerDegreeBound, 0, "Default last layer bound should be 0");
        assertEq(friConfig.nQueries, 84, "Default queries should be 84");
        assertTrue(PcsConfig.isValidFriConfig(friConfig), "Default FRI config should be valid");

        // Test default PCS config
        PcsConfig.Config memory config = PcsConfig.defaultConfig();
        assertEq(config.powBits, 20, "Default PoW bits should be 20");
        assertTrue(config.isValidConfig(), "Default PCS config should be valid");
        
        // Verify FRI config is included
        assertEq(config.friConfig.logBlowupFactor, 1, "Default should include FRI config");
        assertEq(config.friConfig.nQueries, 84, "Default should include FRI queries");
    }

    /// @notice Test secure configuration 
    function testSecureConfiguration() public pure {
        PcsConfig.Config memory secureConfig = PcsConfig.secureConfig();
        
        assertEq(secureConfig.powBits, 26, "Secure PoW should be 26 bits");
        assertTrue(secureConfig.isValidConfig(), "Secure config should be valid");
        
        // Secure config should have higher PoW requirement
        PcsConfig.Config memory defaultConfig = PcsConfig.defaultConfig();
        assertTrue(secureConfig.powBits > defaultConfig.powBits, "Secure should have higher PoW");
    }

    /// @notice Test configuration validation
    function testConfigValidation() public pure {
        // Test valid FRI configurations
        PcsConfig.FriConfig memory validFri = PcsConfig.FriConfig({
            logBlowupFactor: 2,
            logLastLayerDegreeBound: 5,
            nQueries: 50
        });
        assertTrue(PcsConfig.isValidFriConfig(validFri), "Valid FRI config should pass");

        // Test invalid FRI configurations
        PcsConfig.FriConfig memory invalidFri1 = PcsConfig.FriConfig({
            logBlowupFactor: 10, // Too high
            logLastLayerDegreeBound: 0,
            nQueries: 84
        });
        assertFalse(PcsConfig.isValidFriConfig(invalidFri1), "High blowup factor should be invalid");

        PcsConfig.FriConfig memory invalidFri2 = PcsConfig.FriConfig({
            logBlowupFactor: 1,
            logLastLayerDegreeBound: 20, // Too high
            nQueries: 84
        });
        assertFalse(PcsConfig.isValidFriConfig(invalidFri2), "High degree bound should be invalid");

        PcsConfig.FriConfig memory invalidFri3 = PcsConfig.FriConfig({
            logBlowupFactor: 1,
            logLastLayerDegreeBound: 0,
            nQueries: 10 // Too low
        });
        assertFalse(PcsConfig.isValidFriConfig(invalidFri3), "Low query count should be invalid");

        PcsConfig.FriConfig memory invalidFri4 = PcsConfig.FriConfig({
            logBlowupFactor: 1,
            logLastLayerDegreeBound: 0,
            nQueries: 300 // Too high
        });
        assertFalse(PcsConfig.isValidFriConfig(invalidFri4), "High query count should be invalid");
    }

    /// @notice Test PCS configuration validation
    function testPcsConfigValidation() public pure {
        // Test valid PCS config
        PcsConfig.Config memory validConfig = PcsConfig.Config({
            powBits: 16,
            friConfig: PcsConfig.defaultFriConfig()
        });
        assertTrue(validConfig.isValidConfig(), "Valid PCS config should pass");

        // Test invalid PoW bits
        PcsConfig.Config memory invalidConfig = PcsConfig.Config({
            powBits: 40, // Too high
            friConfig: PcsConfig.defaultFriConfig()
        });
        assertFalse(invalidConfig.isValidConfig(), "High PoW bits should be invalid");
    }

    /// @notice Test extended log sizes calculation
    function testExtendedLogSizes() public pure {
        uint32[] memory originalSizes = new uint32[](3);
        originalSizes[0] = 10;
        originalSizes[1] = 12;
        originalSizes[2] = 8;

        PcsConfig.FriConfig memory friConfig = PcsConfig.FriConfig({
            logBlowupFactor: 2, // 4x blowup
            logLastLayerDegreeBound: 0,
            nQueries: 84
        });

        uint32[] memory extended = PcsConfig.getExtendedLogSizes(originalSizes, friConfig);
        
        assertEq(extended.length, originalSizes.length, "Extended should have same length");
        assertEq(extended[0], 12, "First extended size: 10 + 2 = 12");
        assertEq(extended[1], 14, "Second extended size: 12 + 2 = 14");
        assertEq(extended[2], 10, "Third extended size: 8 + 2 = 10");
    }

    /// @notice Test degree bounds calculation
    function testDegreeBounds() public pure {
        uint32[] memory columnLogSizes = new uint32[](2);
        columnLogSizes[0] = 4; // 2^4 = 16 elements
        columnLogSizes[1] = 6; // 2^6 = 64 elements

        PcsConfig.FriConfig memory friConfig = PcsConfig.FriConfig({
            logBlowupFactor: 1, // 2x blowup
            logLastLayerDegreeBound: 0,
            nQueries: 84
        });

        uint256[] memory bounds = PcsConfig.calculateDegreeBounds(columnLogSizes, friConfig);
        
        assertEq(bounds.length, 2, "Should have bounds for each column");
        // Degree bound = 2^(log_size + blowup_factor) - 1
        assertEq(bounds[0], (1 << (4 + 1)) - 1, "First bound: 2^5 - 1 = 31");
        assertEq(bounds[1], (1 << (6 + 1)) - 1, "Second bound: 2^7 - 1 = 127");
    }

    /// @notice Test security level calculations
    function testSecurityLevel() public pure {
        assertEq(PcsConfig.getSecurityLevel(80), 80, "Security level should match query count");
        assertEq(PcsConfig.getSecurityLevel(100), 100, "Security level should match query count");
        
        assertEq(PcsConfig.calculateRequiredQueries(80), 84, "Required queries with safety margin");
        assertEq(PcsConfig.calculateRequiredQueries(100), 104, "Required queries with safety margin");
    }

    /// @notice Test configuration encoding and decoding
    function testEncodingDecoding() public pure {
        PcsConfig.Config memory originalConfig = PcsConfig.Config({
            powBits: 24,
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 3,
                logLastLayerDegreeBound: 2,
                nQueries: 90
            })
        });

        // Test encoding
        bytes memory encoded = PcsConfig.encode(originalConfig);
        assertTrue(encoded.length > 0, "Encoded data should not be empty");

        // Test decoding
        PcsConfig.Config memory decodedConfig = PcsConfig.decode(encoded);
        
        assertEq(decodedConfig.powBits, originalConfig.powBits, "PoW bits should match");
        assertEq(
            decodedConfig.friConfig.logBlowupFactor, 
            originalConfig.friConfig.logBlowupFactor, 
            "Blowup factor should match"
        );
        assertEq(
            decodedConfig.friConfig.logLastLayerDegreeBound,
            originalConfig.friConfig.logLastLayerDegreeBound,
            "Degree bound should match"
        );
        assertEq(
            decodedConfig.friConfig.nQueries,
            originalConfig.friConfig.nQueries,
            "Queries should match"
        );
    }

    /// @notice Test configuration hashing
    function testConfigHashing() public pure {
        PcsConfig.Config memory config1 = PcsConfig.defaultConfig();
        PcsConfig.Config memory config2 = PcsConfig.defaultConfig();
        PcsConfig.Config memory config3 = PcsConfig.secureConfig();

        bytes32 hash1 = PcsConfig.hash(config1);
        bytes32 hash2 = PcsConfig.hash(config2);
        bytes32 hash3 = PcsConfig.hash(config3);

        // Same configurations should have same hash
        assertEq(hash1, hash2, "Identical configs should have same hash");
        
        // Different configurations should have different hashes
        assertTrue(hash1 != hash3, "Different configs should have different hashes");
        assertTrue(hash2 != hash3, "Different configs should have different hashes");
        
        // Hashes should be non-zero
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");
        assertTrue(hash3 != bytes32(0), "Hash should not be zero");
    }

    /// @notice Test configuration edge cases
    function testEdgeCases() public pure {
        // Test minimum valid configuration
        PcsConfig.Config memory minConfig = PcsConfig.Config({
            powBits: 0, // Minimum PoW
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 0, // Minimum blowup
                logLastLayerDegreeBound: 0, // Minimum degree bound
                nQueries: 40 // Minimum queries
            })
        });
        assertTrue(minConfig.isValidConfig(), "Minimum config should be valid");

        // Test maximum valid configuration
        PcsConfig.Config memory maxConfig = PcsConfig.Config({
            powBits: 32, // Maximum PoW
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 4, // Maximum blowup
                logLastLayerDegreeBound: 10, // Maximum degree bound
                nQueries: 200 // Maximum queries
            })
        });
        assertTrue(maxConfig.isValidConfig(), "Maximum config should be valid");

        // Test empty log sizes
        uint32[] memory emptyLogSizes = new uint32[](0);
        uint32[] memory extendedEmpty = PcsConfig.getExtendedLogSizes(
            emptyLogSizes, 
            PcsConfig.defaultFriConfig()
        );
        assertEq(extendedEmpty.length, 0, "Extended empty should remain empty");
    }

    /// @notice Test real-world configuration scenarios
    function testRealWorldScenarios() public pure {
        // Test configuration for small proof system
        PcsConfig.Config memory smallSystem = PcsConfig.Config({
            powBits: 16, // ~65k operations
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 1, // 2x blowup
                logLastLayerDegreeBound: 0,
                nQueries: 60 // ~60-bit security
            })
        });
        assertTrue(smallSystem.isValidConfig(), "Small system config should be valid");

        // Test configuration for production system
        PcsConfig.Config memory production = PcsConfig.Config({
            powBits: 24, // ~16M operations
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 1, // 2x blowup
                logLastLayerDegreeBound: 0,
                nQueries: 100 // ~100-bit security
            })
        });
        assertTrue(production.isValidConfig(), "Production config should be valid");

        // Test configuration for high-security system
        PcsConfig.Config memory highSecurity = PcsConfig.Config({
            powBits: 28, // ~268M operations
            friConfig: PcsConfig.FriConfig({
                logBlowupFactor: 2, // 4x blowup for better soundness
                logLastLayerDegreeBound: 0,
                nQueries: 128 // ~128-bit security
            })
        });
        assertTrue(highSecurity.isValidConfig(), "High security config should be valid");
    }
}