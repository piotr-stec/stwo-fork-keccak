// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/framework/WideFibonacciEval.sol";
import "../../contracts/libraries/FrameworkComponentLib.sol";
import "../../contracts/libraries/TraceLocationAllocatorLib.sol";
import "../../contracts/framework/TreeSubspan.sol";
import "../../contracts/core/PointEvaluationAccumulator.sol";
import "../../contracts/core/CirclePoint.sol";
import "../../contracts/fields/QM31Field.sol";

/// @title WideFibonacciFrameworkTest
/// @notice Test using FrameworkComponentLib with WideFibonacciEval - exact replica of Rust test_evaluate_at_point
/// @dev Replicates: component.evaluate_constraint_quotients_at_point(CirclePoint::zero(), &mask, &mut eval_accumulator)
contract WideFibonacciFrameworkTest is Test {
    using QM31Field for QM31Field.QM31;
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;
    using FrameworkComponentLib for FrameworkComponentLib.ComponentState;
    using TraceLocationAllocatorLib for TraceLocationAllocatorLib.AllocatorState;

    WideFibonacciEval wideFibEval;
    FrameworkComponentLib.ComponentState componentState;
    TraceLocationAllocatorLib.AllocatorState allocatorState;

    /// @notice Exact replica of Rust test_evaluate_at_point function
    function testEvaluateAtPointRustMatch() public {
        allocatorState.initialize();

        console.log("=== Testing evaluate_constraint_quotients_at_point - Rust Match ===");
        
        // Exact same parameters as Rust test
        uint32 log_n_rows = 3; // 8 rows
        uint256 n_columns = 10;

        console.log("Parameters: log_n_rows=%d, n_columns=%d", log_n_rows, n_columns);

        // Step 1: Create WideFibonacciEval 
        wideFibEval = new WideFibonacciEval(log_n_rows, n_columns);
        console.log("Created WideFibonacciEval");

        // Step 2: Create PointEvaluationAccumulator with SecureField::zero()
        PointEvaluationAccumulator.Accumulator memory eval_accumulator = 
            PointEvaluationAccumulator.newAccumulator(QM31Field.zero());
        console.log("Created accumulator with alpha=SecureField::zero()");

        // Step 3: Create mask exactly as in Rust
        // mask_values: Vec<Vec<SecureField>> = (0..n_columns).map(|i| vec![SecureField::from(i as u32 + 5)]).collect()
        // Result: [[5], [6], [7], [8], [9], [10], [11], [12], [13], [14]]
        QM31Field.QM31[][][] memory mask = _createRustEvaluateAtPointMask(n_columns);
        console.log("Created mask with values [5, 6, 7, 8, 9, 10, 11, 12, 13, 14]");

        // Step 4: Initialize FrameworkComponent 
        _initializeFrameworkComponent(log_n_rows, n_columns);
        console.log("Initialized FrameworkComponent equivalent");

        // Step 5: Call evaluate_constraint_quotients_at_point exactly as in Rust:
        // component.evaluate_constraint_quotients_at_point(CirclePoint::<SecureField>::zero(), &mask, &mut eval_accumulator)
        CirclePoint.Point memory zeroPoint = CirclePoint.Point({
            x: QM31Field.zero(),
            y: QM31Field.zero()
        });

        console.log("Calling evaluateConstraintQuotientsAtPoint...");
        PointEvaluationAccumulator.Accumulator memory result = 
            componentState.evaluateConstraintQuotientsAtPoint(zeroPoint, mask, eval_accumulator);

        // Step 6: Get finalized result equivalent to eval_accumulator.finalize()
        QM31Field.QM31 memory finalResult = result.accumulation;
        
        console.log("Evaluation at point completed!");
        console.log("Final result (equivalent to eval_accumulator.finalize()):");
        console.log("  accumulation.a: %d", finalResult.first.real);
        console.log("  accumulation.b: %d", finalResult.first.imag);
        console.log("  accumulation.c: %d", finalResult.second.real);
        console.log("  accumulation.d: %d", finalResult.second.imag);

        // Expected: 8 constraints processed (n_columns - 2 = 10 - 2)
        // Note: The actual constraint count is tracked inside the PointEvaluator during evaluation
        
        // Verify that accumulation is non-zero (constraints were processed)
        bool hasAccumulation = !QM31Field.eq(finalResult, QM31Field.zero());
        assertTrue(hasAccumulation, "Should have accumulated constraint values");

        assertEq(finalResult.first.real, 2147483636, "Final accumulation should match expected value");

    }

    /// @notice Initialize FrameworkComponent equivalent to Rust WideFibonacciComponent::new()
    function _initializeFrameworkComponent(uint32 log_n_rows, uint256 n_columns) internal {
        // Create trace locations for the component (equivalent to TraceLocationAllocator usage)
        uint256[] memory treeSizes = new uint256[](3);
        treeSizes[0] = 0;        // Preprocessed: empty
        treeSizes[1] = n_columns; // Original trace: n_columns
        treeSizes[2] = 0;        // Interaction: empty

        // Allocate trace locations
        TreeSubspan.Subspan[] memory traceLocations = allocatorState.nextForStructure(treeSizes, 1);

        // No preprocessed columns for WideFibonacci
        uint256[] memory preprocessedColumnIndices = new uint256[](0);

        // Component info
        FrameworkComponentLib.ComponentInfo memory componentInfo = FrameworkComponentLib.ComponentInfo({
            nConstraints: n_columns >= 2 ? n_columns - 2 : 0,
            maxConstraintLogDegreeBound: log_n_rows + 1,
            logSize: log_n_rows,
            componentName: "WideFibonacciComponent",
            description: "Wide Fibonacci component for testing"
        });

        // Initialize the component (equivalent to WideFibonacciComponent::new)
        componentState.initialize(
            address(wideFibEval),           // The evaluator
            traceLocations,                 // Trace locations
            preprocessedColumnIndices,      // No preprocessed columns
            QM31Field.zero(),              // claimed_sum = SecureField::zero()
            componentInfo                   // Component metadata
        );

        console.log("FrameworkComponent initialized:");
        console.log("  nConstraints: %d", componentInfo.nConstraints);
        console.log("  logSize: %d", componentInfo.logSize);
        console.log("  maxConstraintLogDegreeBound: %d", componentInfo.maxConstraintLogDegreeBound);
    }

    /// @notice Create mask for evaluate_at_point test - values [5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    /// @dev Replicates: (0..n_columns).map(|i| vec![SecureField::from(i as u32 + 5)])
    function _createRustEvaluateAtPointMask(uint256 n_columns) internal pure returns (QM31Field.QM31[][][] memory mask) {
        mask = new QM31Field.QM31[][][](3);
        
        // Tree 0 (Preprocessed): empty (vec![])
        mask[0] = new QM31Field.QM31[][](0);
        
        // Tree 1 (Original trace): values [5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
        // This matches: (0..n_columns).map(|i| vec![SecureField::from(i as u32 + 5)])
        mask[1] = new QM31Field.QM31[][](n_columns);
        for (uint256 i = 0; i < n_columns; i++) {
            mask[1][i] = new QM31Field.QM31[](1);
            mask[1][i][0] = QM31Field.fromM31(uint32(i + 5), 0, 0, 0); // i+5: [5, 6, 7, ...]
        }
        
        // Tree 2 (Interaction): empty
        mask[2] = new QM31Field.QM31[][](0);
        
        return mask;
    }


}