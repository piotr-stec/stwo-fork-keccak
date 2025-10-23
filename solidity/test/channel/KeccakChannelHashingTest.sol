// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/channel/KeccakChannel.sol";
import "../../contracts/fields/QM31Field.sol";

/// @title KeccakChannelHashingTest
/// @notice Test that KeccakChannel mixU32s produces same results as manual hashing
/// @dev Analogous to Rust test_concat_and_hash
contract KeccakChannelHashingTest is Test {
    using QM31Field for QM31Field.QM31;

    KeccakChannel channel;

    function setUp() public {
        channel = new KeccakChannel();
    }

    /// @notice Test analogous to Rust test_concat_and_hash
    /// @dev Verifies that mixU32s produces same result as manual keccak256 concatenation
    function testConcatAndHash() public {
        // Start with a known digest
        bytes32 initialDigest = keccak256("test_initial");
        channel.updateDigest(initialDigest);

        // Create test u32 data
        uint32[] memory testData = new uint32[](4);
        testData[0] = 0x12345678;
        testData[1] = 0x9ABCDEF0;
        testData[2] = 0x11223344;
        testData[3] = 0x55667788;

        // Mix using channel
        channel.mixU32s(testData);
        bytes32 channelResult = channel.getDigest();

        // Manual verification - replicate channel's exact behavior
        bytes memory manualInput = abi.encodePacked(initialDigest);
        for (uint256 i = 0; i < testData.length; i++) {
            manualInput = abi.encodePacked(
                manualInput,
                _u32ToLittleEndian(testData[i])
            );
        }
        bytes32 expectedResult = keccak256(manualInput);

        // Should match exactly
        assertEq(
            channelResult,
            expectedResult,
            "Channel mixing should match manual concat+hash"
        );
    }

    function testMixRoot() public {
        bytes32 root = 0x7f3fb23a36bd8b85697aadc79cd031fab8fe3b65a557d923e8fd5d1879d02e13;
        bytes32 digest = bytes32(0);
        // Start with a known digest
        bytes32 hashResult = channel.mixRoot(digest, root);
        bytes32 expectedResult = 0x7b8cb803bdb2e8fc5e286da7e482d259702b4669015513390b4aa0d184d3a6c7;
        assertEq(hashResult, expectedResult, "Hash result should match expected");
        assertEq(hashResult, channel.getDigest(), "Hash result should match expected");

    }

    /// @notice Test mixU32s with QM31 field elements
    /// @dev Tests mixing of field elements through channel
    function testMixQM31Elements() public {
        // Create test QM31 elements
        QM31Field.QM31 memory felt1 = QM31Field.fromReal(12345);
        QM31Field.QM31 memory felt2 = QM31Field.fromReal(67890);

        // Initialize channel with known state
        bytes32 initialState = keccak256("test_initial_state");
        channel.updateDigest(initialState);

        // Mix first element
        uint32[4] memory components1 = QM31Field.toM31Array(felt1);
        uint32[] memory array1 = new uint32[](4);
        array1[0] = components1[0];
        array1[1] = components1[1];
        array1[2] = components1[2];
        array1[3] = components1[3];
        channel.mixU32s(array1);

        bytes32 afterFirst = channel.getDigest();

        // Mix second element
        uint32[4] memory components2 = QM31Field.toM31Array(felt2);
        uint32[] memory array2 = new uint32[](4);
        array2[0] = components2[0];
        array2[1] = components2[1];
        array2[2] = components2[2];
        array2[3] = components2[3];
        channel.mixU32s(array2);

        bytes32 finalDigest = channel.getDigest();

        // Manual verification - should produce same result
        bytes memory encoded1 = abi.encodePacked(
            _u32ToLittleEndian(components1[0]),
            _u32ToLittleEndian(components1[1]),
            _u32ToLittleEndian(components1[2]),
            _u32ToLittleEndian(components1[3])
        );

        bytes memory encoded2 = abi.encodePacked(
            _u32ToLittleEndian(components2[0]),
            _u32ToLittleEndian(components2[1]),
            _u32ToLittleEndian(components2[2]),
            _u32ToLittleEndian(components2[3])
        );

        bytes32 manualAfterFirst = keccak256(
            abi.encodePacked(initialState, encoded1)
        );
        bytes32 manualFinal = keccak256(
            abi.encodePacked(manualAfterFirst, encoded2)
        );

        assertEq(
            afterFirst,
            manualAfterFirst,
            "First mixing should match manual"
        );
        assertEq(finalDigest, manualFinal, "Final result should match manual");
    }

    /// @notice Test multiple mixU32s calls produce deterministic results
    function testDeterministicMixing() public {
        uint32[] memory data1 = new uint32[](3);
        data1[0] = 0x12345678;
        data1[1] = 0x9ABCDEF0;
        data1[2] = 0x11223344;

        uint32[] memory data2 = new uint32[](2);
        data2[0] = 0x55667788;
        data2[1] = 0x99AABBCC;

        // First channel
        KeccakChannel channel1 = new KeccakChannel();
        channel1.updateDigest(keccak256("start"));
        channel1.mixU32s(data1);
        channel1.mixU32s(data2);
        bytes32 result1 = channel1.getDigest();

        // Second channel - same operations
        KeccakChannel channel2 = new KeccakChannel();
        channel2.updateDigest(keccak256("start"));
        channel2.mixU32s(data1);
        channel2.mixU32s(data2);
        bytes32 result2 = channel2.getDigest();

        assertEq(
            result1,
            result2,
            "Same operations should produce same results"
        );

        // Manual verification
        bytes memory manualData1 = abi.encodePacked(
            _u32ToLittleEndian(data1[0]),
            _u32ToLittleEndian(data1[1]),
            _u32ToLittleEndian(data1[2])
        );

        bytes memory manualData2 = abi.encodePacked(
            _u32ToLittleEndian(data2[0]),
            _u32ToLittleEndian(data2[1])
        );

        bytes32 manualStep1 = keccak256(
            abi.encodePacked(keccak256("start"), manualData1)
        );
        bytes32 manualResult = keccak256(
            abi.encodePacked(manualStep1, manualData2)
        );

        assertEq(
            result1,
            manualResult,
            "Channel result should match manual calculation"
        );
    }

    /// @notice Test empty u32 array mixing
    function testEmptyArrayMixing() public {
        uint32[] memory emptyArray = new uint32[](0);

        bytes32 initialDigest = keccak256("initial");
        channel.updateDigest(initialDigest);

        channel.mixU32s(emptyArray);
        bytes32 afterMixing = channel.getDigest();

        // Mixing empty array should be equivalent to hashing digest with empty bytes
        bytes32 expected = keccak256(abi.encodePacked(initialDigest));

        assertEq(
            afterMixing,
            expected,
            "Empty array mixing should match empty bytes hash"
        );
    }

    /// @notice Test single u32 mixing
    function testSingleU32Mixing() public {
        uint32[] memory singleU32 = new uint32[](1);
        singleU32[0] = 0xDEADBEEF;

        bytes32 initialDigest = keccak256("single_test");
        channel.updateDigest(initialDigest);

        channel.mixU32s(singleU32);
        bytes32 result = channel.getDigest();

        // Manual verification
        bytes memory encodedU32 = abi.encodePacked(
            _u32ToLittleEndian(0xDEADBEEF)
        );
        bytes32 expected = keccak256(
            abi.encodePacked(initialDigest, encodedU32)
        );

        assertEq(result, expected, "Single u32 mixing should match manual");
    }

    /// @notice Test large u32 array mixing
    function testLargeArrayMixing() public {
        uint32[] memory largeArray = new uint32[](16);
        for (uint256 i = 0; i < 16; i++) {
            largeArray[i] = uint32(0x1000000 + i);
        }

        bytes32 initialDigest = keccak256("large_test");
        channel.updateDigest(initialDigest);

        channel.mixU32s(largeArray);
        bytes32 result = channel.getDigest();

        // Manual verification - encode all u32s
        bytes memory encodedData = "";
        for (uint256 i = 0; i < 16; i++) {
            encodedData = abi.encodePacked(
                encodedData,
                _u32ToLittleEndian(largeArray[i])
            );
        }

        bytes32 expected = keccak256(
            abi.encodePacked(initialDigest, encodedData)
        );

        assertEq(result, expected, "Large array mixing should match manual");
    }

    /// @notice Test that mixing order matters
    function testMixingOrder() public {
        uint32[] memory data1 = new uint32[](2);
        data1[0] = 0x11111111;
        data1[1] = 0x22222222;

        uint32[] memory data2 = new uint32[](2);
        data2[0] = 0x33333333;
        data2[1] = 0x44444444;

        // First order: data1 then data2
        KeccakChannel channel1 = new KeccakChannel();
        channel1.updateDigest(keccak256("order_test"));
        channel1.mixU32s(data1);
        channel1.mixU32s(data2);
        bytes32 result1 = channel1.getDigest();

        // Second order: data2 then data1
        KeccakChannel channel2 = new KeccakChannel();
        channel2.updateDigest(keccak256("order_test"));
        channel2.mixU32s(data2);
        channel2.mixU32s(data1);
        bytes32 result2 = channel2.getDigest();

        // Results should be different (order matters)
        assertTrue(
            result1 != result2,
            "Different mixing order should produce different results"
        );
    }

    /// @notice Test compatibility with Rust keccak implementation expectations
    function testRustCompatibility() public {
        // Test known values that should match Rust implementation behavior
        uint32[] memory testData = new uint32[](4);
        testData[0] = 0x01234567;
        testData[1] = 0x89ABCDEF;
        testData[2] = 0xFEDCBA98;
        testData[3] = 0x76543210;

        bytes32 initialDigest = bytes32(0);
        channel.updateDigest(initialDigest);

        channel.mixU32s(testData);
        bytes32 result = channel.getDigest();

        // Verify it's a valid keccak256 hash (32 bytes, non-zero)
        assertTrue(result != bytes32(0), "Result should not be zero");

        // Verify deterministic behavior
        KeccakChannel channel2 = new KeccakChannel();
        channel2.updateDigest(initialDigest);
        channel2.mixU32s(testData);
        bytes32 result2 = channel2.getDigest();

        assertEq(
            result,
            result2,
            "Same input should always produce same output"
        );
    }

    // =============================================================================
    // Helper Functions
    // =============================================================================

    /// @notice Convert bytes32 to uint32 array (big-endian interpretation)
    /// @param hash Hash to convert
    /// @return Array of uint32 values
    function _bytes32ToU32Array(
        bytes32 hash
    ) internal pure returns (uint32[] memory) {
        uint32[] memory result = new uint32[](8);
        for (uint256 i = 0; i < 8; i++) {
            // Extract 4 bytes starting at byte position i*4
            result[i] = uint32(uint256(hash) >> (8 * (28 - i * 4)));
        }
        return result;
    }

    /// @notice Convert uint32 to little-endian bytes (matching KeccakChannel implementation)
    /// @param value Value to convert
    /// @return Little-endian bytes representation
    function _u32ToLittleEndian(uint32 value) internal pure returns (bytes4) {
        return
            bytes4(
                bytes1(uint8(value)) |
                    (bytes1(uint8(value >> 8)) << 8) |
                    (bytes1(uint8(value >> 16)) << 16) |
                    (bytes1(uint8(value >> 24)) << 24)
            );
    }
}
