// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/PointEvaluationAccumulator.sol";
import "../../contracts/fields/QM31Field.sol";

/// @title SimpleAccumulatorTest
/// @notice Simple standalone test for PointEvaluationAccumulator
contract SimpleAccumulatorTest is Test {
    using QM31Field for QM31Field.QM31;

    /// @notice Test simple accumulator with known values
    function testAccumulatorSimple() public {
        console.log("=== Simple Accumulator Test ===");
        
        // Simple test values
        QM31Field.QM31 memory alpha = QM31Field.fromM31(2, 0, 0, 0); // Just (2, 0, 0, 0)
        console.log("Alpha: (2, 0, 0, 0)");
        
        // Simple evaluations: [1, 2, 3]
        QM31Field.QM31[] memory evaluations = new QM31Field.QM31[](3);
        evaluations[0] = QM31Field.fromM31(1, 0, 0, 0);
        evaluations[1] = QM31Field.fromM31(2, 0, 0, 0);
        evaluations[2] = QM31Field.fromM31(3, 0, 0, 0);
        
        console.log("Evaluations: [1, 2, 3]");
        
        // Expected result: ((0 * 2 + 1) * 2 + 2) * 2 + 3 = (1 * 2 + 2) * 2 + 3 = 4 * 2 + 3 = 11
        console.log("Expected result: 11");
        
        // Test accumulator
        PointEvaluationAccumulator.Accumulator memory accumulator = PointEvaluationAccumulator.newAccumulator(alpha);
        for (uint256 i = 0; i < evaluations.length; i++) {
            accumulator = PointEvaluationAccumulator.accumulate(accumulator, evaluations[i]);
            console.log("After step %d: accumulation = %d", i, accumulator.accumulation.first.real);
        }
        
        QM31Field.QM31 memory result = PointEvaluationAccumulator.finalize(accumulator);
        console.log("Final accumulator result: %d", result.first.real);
        
        // Test direct computation
        QM31Field.QM31 memory directResult = PointEvaluationAccumulator.directComputation(evaluations, alpha);
        console.log("Direct computation result: %d", directResult.first.real);
        
        // Verify
        assertEq(result.first.real, 11, "Accumulator should give 11");
        assertEq(directResult.first.real, 11, "Direct computation should give 11");
        assertTrue(result.first.real == directResult.first.real && 
                  result.first.imag == directResult.first.imag &&
                  result.second.real == directResult.second.real &&
                  result.second.imag == directResult.second.imag, "Both methods should match");
        
        console.log("SUCCESS: Simple test PASSED");
    }

    /// @notice Test QM31 alpha values like Rust test
    function testRustAlpha() public {
        // console.log("=== Rust Alpha Test ===");
        
        // Alpha from Rust: qm31!(2, 3, 4, 5)
        QM31Field.QM31 memory alpha = QM31Field.fromM31(2, 3, 4, 5);
        // console.log("Alpha components: (%d, %d, %d, %d)", 
        //     alpha.first.real, alpha.first.imag, 
        //     alpha.second.real, alpha.second.imag);
        
        // Simple evaluations converted to QM31
        uint32[] memory m31Values = new uint32[](3);
        m31Values[0] = 100;
        m31Values[1] = 200;
        m31Values[2] = 300;
        
        QM31Field.QM31[] memory evaluations = PointEvaluationAccumulator.m31ArrayToQM31Array(m31Values);
        
        // console.log("M31 evaluations: [100, 200, 300]");
        
        // Test accumulator
        PointEvaluationAccumulator.Accumulator memory accumulator = PointEvaluationAccumulator.newAccumulator(alpha);
        for (uint256 i = 0; i < evaluations.length; i++) {
            accumulator = PointEvaluationAccumulator.accumulate(accumulator, evaluations[i]);
        }
        
        QM31Field.QM31 memory result = PointEvaluationAccumulator.finalize(accumulator);
        // console.log("Result with QM31 alpha: (%d, %d, %d, %d)",
        //     result.first.real, result.first.imag,
        //     result.second.real, result.second.imag);
        
        // Test direct computation
        QM31Field.QM31 memory directResult = PointEvaluationAccumulator.directComputation(evaluations, alpha);
        // console.log("Direct result: (%d, %d, %d, %d)",
        //     directResult.first.real, directResult.first.imag,
        //     directResult.second.real, directResult.second.imag);
        
        assertTrue(result.first.real == directResult.first.real && 
                  result.first.imag == directResult.first.imag &&
                  result.second.real == directResult.second.real &&
                  result.second.imag == directResult.second.imag, "QM31 alpha test should match");
        // console.log("SUCCESS: QM31 alpha test PASSED");
    }

    /// @notice Manual verification of Horner's method
    function testHornerManual() public view {
        console.log("=== Manual Horner's Method Verification ===");
        
        // Manual calculation for [1, 2, 3] with alpha = 2
        // Step 0: acc = 0, eval = 1 => acc = 0 * 2 + 1 = 1
        // Step 1: acc = 1, eval = 2 => acc = 1 * 2 + 2 = 4  
        // Step 2: acc = 4, eval = 3 => acc = 4 * 2 + 3 = 11
        
        console.log("Horner's method for [1, 2, 3] with alpha = 2:");
        console.log("Step 0: 0 * 2 + 1 = 1");
        console.log("Step 1: 1 * 2 + 2 = 4");
        console.log("Step 2: 4 * 2 + 3 = 11");
        console.log("Expected final result: 11");
    }

    /// @notice Test with larger values  
    function testLargerValues() public {
        console.log("=== Larger Values Test ===");
        
        QM31Field.QM31 memory alpha = QM31Field.fromM31(17, 0, 0, 0);
        
        // Larger evaluations
        QM31Field.QM31[] memory evaluations = new QM31Field.QM31[](5);
        evaluations[0] = QM31Field.fromM31(123, 0, 0, 0);
        evaluations[1] = QM31Field.fromM31(456, 0, 0, 0);
        evaluations[2] = QM31Field.fromM31(789, 0, 0, 0);
        evaluations[3] = QM31Field.fromM31(111, 0, 0, 0);
        evaluations[4] = QM31Field.fromM31(222, 0, 0, 0);
        
        console.log("Alpha: 17");
        console.log("Evaluations: [123, 456, 789, 111, 222]");
        
        // Test accumulator
        PointEvaluationAccumulator.Accumulator memory accumulator = PointEvaluationAccumulator.newAccumulator(alpha);
        for (uint256 i = 0; i < evaluations.length; i++) {
            accumulator = PointEvaluationAccumulator.accumulate(accumulator, evaluations[i]);
        }
        
        QM31Field.QM31 memory result = PointEvaluationAccumulator.finalize(accumulator);
        
        // Test direct computation
        QM31Field.QM31 memory directResult = PointEvaluationAccumulator.directComputation(evaluations, alpha);
        
        console.log("Accumulator result: %d", result.first.real);
        console.log("Direct result: %d", directResult.first.real);
        
        assertTrue(result.first.real == directResult.first.real && 
                  result.first.imag == directResult.first.imag &&
                  result.second.real == directResult.second.real &&
                  result.second.imag == directResult.second.imag, "Larger values test should match");
        console.log("SUCCESS: Larger values test PASSED");
    }
}