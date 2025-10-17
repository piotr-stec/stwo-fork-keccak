// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/fields/CM31FieldWrapper.sol";

/**
 * @title CM31FieldBatchTest
 * @notice Phase 5: Batch operations tests for CM31 complex field
 * @dev Tests batch inversion using Montgomery's trick and other batch operations
 */
contract CM31FieldBatchTest is Test {
    using CM31Field for CM31Field.CM31;

    CM31FieldWrapper wrapper;
    
    // Constants from M31 field
    uint32 constant P = 2147483647; // 2^31 - 1

    function setUp() public {
        wrapper = new CM31FieldWrapper();
    }

    function test_BatchInverse() public pure {
        // Test batch inversion with known values
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](5);
        elements[0] = CM31Field.fromM31(1, 2);   // 1 + 2i
        elements[1] = CM31Field.fromM31(3, 4);   // 3 + 4i  
        elements[2] = CM31Field.fromM31(0, 1);   // i
        elements[3] = CM31Field.fromM31(5, 0);   // 5 (real)
        elements[4] = CM31Field.fromM31(2, 3);   // 2 + 3i
        
        CM31Field.CM31[] memory inverses = CM31Field.batchInverse(elements);
        
        assertEq(inverses.length, elements.length);
        
        // Verify each inverse is correct: a * a^(-1) = 1
        for (uint i = 0; i < elements.length; i++) {
            CM31Field.CM31 memory product = CM31Field.mul(elements[i], inverses[i]);
            assertTrue(CM31Field.isOne(product));
        }
        
        // Also verify against individual inverses
        for (uint i = 0; i < elements.length; i++) {
            CM31Field.CM31 memory individualInverse = CM31Field.inverse(elements[i]);
            assertTrue(CM31Field.eq(inverses[i], individualInverse));
        }
    }

    function test_BatchInverseWithZero() public {
        // Test that batch inversion reverts if any element is zero
        uint32[] memory reals = new uint32[](3);
        uint32[] memory imags = new uint32[](3);
        
        reals[0] = 1;
        imags[0] = 2;
        reals[1] = 0;  // Zero element
        imags[1] = 0;
        reals[2] = 3;
        imags[2] = 4;
        
        vm.expectRevert("CM31Field: division by zero");
        wrapper.batchInverse(reals, imags);
    }

    function test_BatchInverseEmpty() public pure {
        // Test batch inversion with empty array
        CM31Field.CM31[] memory empty = new CM31Field.CM31[](0);
        CM31Field.CM31[] memory result = CM31Field.batchInverse(empty);
        
        assertEq(result.length, 0);
    }

    function test_BatchInverseSingle() public pure {
        // Test batch inversion with single element
        CM31Field.CM31[] memory single = new CM31Field.CM31[](1);
        single[0] = CM31Field.fromM31(3, 4);
        
        CM31Field.CM31[] memory result = CM31Field.batchInverse(single);
        
        assertEq(result.length, 1);
        
        CM31Field.CM31 memory product = CM31Field.mul(single[0], result[0]);
        assertTrue(CM31Field.isOne(product));
    }

    function test_BatchInverseLarger() public pure {
        // Test with larger batch to verify Montgomery's trick efficiency
        uint256 batchSize = 10;
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](batchSize);
        
        // Create test elements
        for (uint256 i = 0; i < batchSize; i++) {
            elements[i] = CM31Field.fromM31(
                uint32(i + 1),      // real part: 1, 2, 3, ...
                uint32(i + 5)       // imag part: 5, 6, 7, ...
            );
        }
        
        CM31Field.CM31[] memory inverses = CM31Field.batchInverse(elements);
        
        // Verify all inverses
        for (uint256 i = 0; i < batchSize; i++) {
            CM31Field.CM31 memory product = CM31Field.mul(elements[i], inverses[i]);
            assertTrue(CM31Field.isOne(product));
        }
    }

    function test_BatchConjugateComprehensive() public pure {
        // Test batch conjugation with various complex numbers
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](6);
        elements[0] = CM31Field.zero();           // 0
        elements[1] = CM31Field.one();            // 1
        elements[2] = CM31Field.imaginaryUnit();  // i
        elements[3] = CM31Field.fromM31(3, 4);    // 3 + 4i
        elements[4] = CM31Field.fromM31(0, 7);    // 7i (purely imaginary)
        elements[5] = CM31Field.fromM31(5, 0);    // 5 (purely real)
        
        CM31Field.CM31[] memory conjugates = CM31Field.batchConjugate(elements);
        
        assertEq(conjugates.length, elements.length);
        
        // Verify each conjugate
        assertTrue(CM31Field.eq(conjugates[0], CM31Field.zero()));
        assertTrue(CM31Field.eq(conjugates[1], CM31Field.one()));
        assertTrue(CM31Field.eq(conjugates[2], CM31Field.fromM31(0, P - 1))); // -i
        assertTrue(CM31Field.eq(conjugates[3], CM31Field.fromM31(3, P - 4))); // 3 - 4i
        assertTrue(CM31Field.eq(conjugates[4], CM31Field.fromM31(0, P - 7))); // -7i
        assertTrue(CM31Field.eq(conjugates[5], CM31Field.fromM31(5, 0)));     // 5 (unchanged)
        
        // Verify against individual conjugates
        for (uint i = 0; i < elements.length; i++) {
            CM31Field.CM31 memory individualConj = CM31Field.conjugate(elements[i]);
            assertTrue(CM31Field.eq(conjugates[i], individualConj));
        }
    }

    function test_BatchConjugateEmpty() public pure {
        // Test batch conjugation with empty array
        CM31Field.CM31[] memory empty = new CM31Field.CM31[](0);
        CM31Field.CM31[] memory result = CM31Field.batchConjugate(empty);
        
        assertEq(result.length, 0);
    }

    function test_BatchInverseGasComparison() public view {
        // Compare gas usage of batch vs individual inversions
        uint256 batchSize = 5;
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](batchSize);
        
        for (uint256 i = 0; i < batchSize; i++) {
            elements[i] = CM31Field.fromM31(uint32(i + 2), uint32(i + 3));
        }
        
        // Measure batch inversion gas
        uint256 gasBefore = gasleft();
        CM31Field.batchInverse(elements);
        uint256 gasAfter = gasleft();
        uint256 batchGas = gasBefore - gasAfter;
        
        // Measure individual inversions gas
        gasBefore = gasleft();
        for (uint256 i = 0; i < batchSize; i++) {
            CM31Field.inverse(elements[i]);
        }
        gasAfter = gasleft();
        uint256 individualGas = gasBefore - gasAfter;
        
        console.log("Batch inversion gas (n=5):", batchGas);
        console.log("Individual inversions gas (n=5):", individualGas);
        console.log("Gas saved:", individualGas > batchGas ? individualGas - batchGas : 0);
        
        // For 5 elements, batch should be more efficient
        // (Montgomery's trick becomes beneficial for n >= 3-4 typically)
        assertTrue(batchGas < individualGas, "Batch inversion should be more efficient");
        assertTrue(batchGas < 50000, "Batch inversion should be under 50K gas");
    }

    function test_BatchInverseStressTest() public pure {
        // Stress test with many different complex numbers
        uint256 stressSize = 20;
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](stressSize);
        
        // Generate diverse test cases
        for (uint256 i = 0; i < stressSize; i++) {
            uint32 real = uint32((i * 17 + 7) % (P - 1)) + 1;  // Avoid zero
            uint32 imag = uint32((i * 23 + 11) % P);
            elements[i] = CM31Field.fromM31(real, imag);
        }
        
        CM31Field.CM31[] memory inverses = CM31Field.batchInverse(elements);
        
        // Verify all products are 1
        for (uint256 i = 0; i < stressSize; i++) {
            CM31Field.CM31 memory product = CM31Field.mul(elements[i], inverses[i]);
            assertTrue(CM31Field.isOne(product));
        }
    }

    // Property-based testing for batch operations
    function testFuzz_BatchInverseProperty(uint32[5] memory reals, uint32[5] memory imags) public pure {
        // Convert to valid M31 elements and ensure non-zero
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](5);
        for (uint i = 0; i < 5; i++) {
            uint32 real = (reals[i] % (P - 1)) + 1;  // Ensure non-zero real part
            uint32 imag = imags[i] % P;
            elements[i] = CM31Field.fromM31(real, imag);
        }
        
        CM31Field.CM31[] memory inverses = CM31Field.batchInverse(elements);
        
        // Verify all inverses are correct
        for (uint i = 0; i < 5; i++) {
            CM31Field.CM31 memory product = CM31Field.mul(elements[i], inverses[i]);
            assertTrue(CM31Field.isOne(product));
        }
    }

    function testFuzz_BatchConjugateProperty(uint32[3] memory reals, uint32[3] memory imags) public pure {
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](3);
        for (uint i = 0; i < 3; i++) {
            elements[i] = CM31Field.fromM31(reals[i] % P, imags[i] % P);
        }
        
        CM31Field.CM31[] memory conjugates = CM31Field.batchConjugate(elements);
        
        // Verify double conjugation returns original
        CM31Field.CM31[] memory doubleConj = CM31Field.batchConjugate(conjugates);
        
        for (uint i = 0; i < 3; i++) {
            assertTrue(CM31Field.eq(elements[i], doubleConj[i]));
        }
    }

    function test_MontgomeryTrickCorrectness() public pure {
        // Explicit test of Montgomery's trick algorithm correctness
        // This verifies that our batch implementation follows the algorithm correctly
        
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](4);
        elements[0] = CM31Field.fromM31(2, 1);
        elements[1] = CM31Field.fromM31(3, 2);
        elements[2] = CM31Field.fromM31(1, 3);
        elements[3] = CM31Field.fromM31(4, 1);
        
        // Manual Montgomery's trick calculation for verification
        // Forward pass: compute cumulative products
        CM31Field.CM31 memory p0 = elements[0];
        CM31Field.CM31 memory p1 = CM31Field.mul(p0, elements[1]);
        CM31Field.CM31 memory p2 = CM31Field.mul(p1, elements[2]);
        CM31Field.CM31 memory p3 = CM31Field.mul(p2, elements[3]);
        
        // Invert the final product
        CM31Field.CM31 memory invP3 = CM31Field.inverse(p3);
        
        // Backward pass to compute individual inverses
        CM31Field.CM31 memory inv3 = CM31Field.mul(invP3, p2);
        CM31Field.CM31 memory inv2 = CM31Field.mul(CM31Field.mul(invP3, elements[3]), p1);
        CM31Field.CM31 memory inv1 = CM31Field.mul(CM31Field.mul(CM31Field.mul(invP3, elements[3]), elements[2]), p0);
        CM31Field.CM31 memory inv0 = CM31Field.mul(CM31Field.mul(CM31Field.mul(invP3, elements[3]), elements[2]), elements[1]);
        
        // Compare with batch result
        CM31Field.CM31[] memory batchInverses = CM31Field.batchInverse(elements);
        
        assertTrue(CM31Field.eq(batchInverses[0], inv0));
        assertTrue(CM31Field.eq(batchInverses[1], inv1));
        assertTrue(CM31Field.eq(batchInverses[2], inv2));
        assertTrue(CM31Field.eq(batchInverses[3], inv3));
    }

    function test_BatchOperationsConsistency() public pure {
        // Test that batch operations are consistent with individual operations
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](7);
        
        // Mix of different types of complex numbers
        elements[0] = CM31Field.zero();
        elements[1] = CM31Field.one();
        elements[2] = CM31Field.imaginaryUnit();
        elements[3] = CM31Field.fromM31(5, 12);  // 5 + 12i
        elements[4] = CM31Field.fromM31(8, 0);   // 8 (real)
        elements[5] = CM31Field.fromM31(0, 6);   // 6i (imaginary)
        elements[6] = CM31Field.fromM31(3, 4);   // 3 + 4i
        
        // Skip zero for inversion test
        CM31Field.CM31[] memory nonZeroElements = new CM31Field.CM31[](6);
        for (uint i = 0; i < 6; i++) {
            nonZeroElements[i] = elements[i + 1];
        }
        
        // Test batch inversion consistency
        CM31Field.CM31[] memory batchInverses = CM31Field.batchInverse(nonZeroElements);
        for (uint i = 0; i < nonZeroElements.length; i++) {
            CM31Field.CM31 memory individualInverse = CM31Field.inverse(nonZeroElements[i]);
            assertTrue(CM31Field.eq(batchInverses[i], individualInverse));
        }
        
        // Test batch conjugation consistency
        CM31Field.CM31[] memory batchConjugates = CM31Field.batchConjugate(elements);
        for (uint i = 0; i < elements.length; i++) {
            CM31Field.CM31 memory individualConjugate = CM31Field.conjugate(elements[i]);
            assertTrue(CM31Field.eq(batchConjugates[i], individualConjugate));
        }
    }
}