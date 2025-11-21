// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./IFrameworkEval.sol";
import "./PointEvaluatorLib.sol";
import "../fields/QM31Field.sol";

/// @title WideFibonacciEval
/// @notice Wide Fibonacci component with normal addition: f(n) = f(n-1) + f(n-2)
/// @dev Each row contains a COMPLETE Fibonacci sequence of length n_columns
/// 

/// This is different from SimpleFibonacci which is vertical (3 cols, many rows)
contract FibonacciEval is IFrameworkEval {
    using QM31Field for QM31Field.QM31;
    using PointEvaluatorLib for PointEvaluatorLib.PointEvaluator;

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Log2 of the number of rows in the trace
    /// @dev Maps to: pub log_n_rows: u32
    uint32 public immutable logNRows;

    /// @notice Component name for identification
    string public constant COMPONENT_NAME = "FibonacciEval";

    /// @notice Component description
    string public constant DESCRIPTION = "Fibonacci component ";

    // =============================================================================
    // Constructor
    // =============================================================================
    constructor(uint32 _logNRows) {
        require(_logNRows > 0, "Invalid log_n_rows");
        
        logNRows = _logNRows;
    }

    // =============================================================================
    // IFrameworkEval Implementation
    // =============================================================================

    /// @inheritdoc IFrameworkEval
    function logSize() external view override returns (uint32 logSize_) {
        return logNRows;
    }

    /// @inheritdoc IFrameworkEval
    function maxConstraintLogDegreeBound() external view override returns (uint32 maxLogDegreeBound) {
        return logNRows + 1;
    }

    /// @inheritdoc IFrameworkEval
    function evaluate(PointEvaluatorLib.PointEvaluator memory eval) 
        external
        view  
        override 
        returns (PointEvaluatorLib.PointEvaluator memory updatedEval) 
    {
        // Get first two Fibonacci values: f(0) and f(1)
        QM31Field.QM31 memory a;
        QM31Field.QM31 memory b;
        QM31Field.QM31 memory c;

        
        (eval, a) = PointEvaluatorLib.nextTraceMask(eval); // f(n-2)
        (eval, b) = PointEvaluatorLib.nextTraceMask(eval); // f(n-1)
        (eval, c) = PointEvaluatorLib.nextTraceMask(eval); // f(n)
        // Enforce Fibonacci constraint: f(n) = f(n-1) + f(n-2)
        QM31Field.QM31 memory sum = a.add(b);
        QM31Field.QM31 memory diff = c.sub(sum);
        eval = eval.addConstraint(diff);

        return eval;
    }

    // =============================================================================
    // Additional Getters
    // =============================================================================


    /// @notice Get the log number of rows
    /// @return logNRows_ Log2 of the number of rows
    function getLogNRows() external view returns (uint32 logNRows_) {
        return logNRows;
    }

    // =============================================================================
    // Internal Helper Functions
    // =============================================================================

    /// @notice Calculate log2 of a number (rounded up)
    /// @param value Input value
    /// @return log2Value Log2 of the value
    function _log2(uint256 value) internal pure returns (uint256 log2Value) {
        if (value == 0) return 0;
        
        uint256 result = 0;
        uint256 temp = value;
        
        while (temp > 1) {
            temp >>= 1;
            result++;
        }
        
        // Round up if not exact power of 2
        if ((1 << result) < value) {
            result++;
        }
        
        return result;
    }
}