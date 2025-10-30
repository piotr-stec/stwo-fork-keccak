// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/framework/WideFibonacciEval.sol";
import "../../contracts/framework/PointEvaluatorLib.sol";
import "../../contracts/core/PointEvaluationAccumulator.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/core/CirclePoint.sol";

/// @title WideFibonacciEvalRustMatchTest
/// @notice Exact match test for Rust WideFibonacciEval to compare results
/// @dev Replicates the exact Rust test with same parameters and data
contract WideFibonacciEvalRustMatchTest is Test {
    using QM31Field for QM31Field.QM31;
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;

    WideFibonacciEval wideFibEval;
    
    /// @notice Exact replica of the Rust test_evaluate() function
    function testEvaluateRustMatch() public {
        console.log("=== Testing WideFibonacci - Rust Match ===");
        
        // Exact same parameters as Rust test
        uint32 log_n_rows = 3; // 8 rows
        uint256 n_columns = 10;
        
        // Create WideFibonacciEval with exact same parameters
        wideFibEval = new WideFibonacciEval(log_n_rows, n_columns);
        
        
        QM31Field.QM31 memory denom_inverse = QM31Field.fromM31(1, 0, 0, 0);
        

        QM31Field.QM31 memory alpha = QM31Field.zero();
        PointEvaluationAccumulator.Accumulator memory eval_accumulator = 
            PointEvaluationAccumulator.newAccumulator(alpha);

        console.log("Evaluator accumulator created with alpha=0", eval_accumulator.randomCoeff.first.real);
        
        // console.log("Created accumulator with alpha=0");
        
        // Create mask values exactly as in Rust:
        // let mask_values: Vec<Vec<SecureField>> = (0..n_columns)
        //     .map(|i| vec![SecureField::from(i as u32 + 1)])
        //     .collect();
        QM31Field.QM31[][][] memory mask = _createRustMatchingMask(n_columns);
        
        console.log("Created mask with values 1 to %d:", n_columns);
        
        // Create PointEvaluator exactly as in Rust
        PointEvaluatorLib.PointEvaluator memory point_evaluator = PointEvaluatorLib.create(
            mask,
            eval_accumulator,
            denom_inverse,
            log_n_rows,
            QM31Field.zero() // claimed_sum = SecureField::zero()
        );
        
        console.log("Created PointEvaluator");
        
        // Evaluate exactly as in Rust: wide_fib_eval.evaluate(point_evaluator)
        console.log("Running evaluation...");
        PointEvaluatorLib.PointEvaluator memory result = wideFibEval.evaluate(point_evaluator);
        
        QM31Field.QM31 memory finalAccumulation = result.evaluationAccumulator.accumulation;
        
        console.log("Evaluation completed!");
        console.log("Final evaluation result:");
        console.log("  accumulation first real: ", finalAccumulation.first.real);
        console.log("  accumulation first imag: ", finalAccumulation.first.imag);
        console.log("  accumulation second real: ", finalAccumulation.second.real);
        console.log("  accumulation second imag: ", finalAccumulation.second.imag);
        
        assertEq(finalAccumulation.first.real, 2147483640, "Final accumulation first.real mismatch");
        
        }

  
    /// @notice Create mask exactly matching Rust test data
    /// @dev Creates mask where each column has value (i+1): [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    function _createRustMatchingMask(uint256 n_columns) internal pure returns (QM31Field.QM31[][][] memory mask) {
        mask = new QM31Field.QM31[][][](3);
        
        // Tree 0 (Preprocessed): empty (vec![])
        mask[0] = new QM31Field.QM31[][](0);
        
        // Tree 1 (Original trace): n_columns with values [1, 2, 3, ..., n_columns]
        // This matches: (0..n_columns).map(|i| vec![SecureField::from(i as u32 + 1)])
        mask[1] = new QM31Field.QM31[][](n_columns);
        for (uint256 i = 0; i < n_columns; i++) {
            mask[1][i] = new QM31Field.QM31[](1);
            mask[1][i][0] = QM31Field.fromM31(uint32(i + 1), 0, 0, 0); // i+1: [1, 2, 3, ...]
        }
        
        // Tree 2 (Interaction): empty
        mask[2] = new QM31Field.QM31[][](0);
        
        return mask;
    }

}