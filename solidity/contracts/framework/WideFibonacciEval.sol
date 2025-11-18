// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./IFrameworkEval.sol";
import "./PointEvaluatorLib.sol";
import "../fields/QM31Field.sol";

/// @title WideFibonacciEval
/// @notice Wide Fibonacci component with normal addition: f(n) = f(n-1) + f(n-2)
/// @dev Each row contains a COMPLETE Fibonacci sequence of length n_columns
/// 
/// Structure (horizontal):
/// Row 0: [f(0), f(1), f(2), f(3), ..., f(n_columns-1)]
/// Row 1: [f(0), f(1), f(2), f(3), ..., f(n_columns-1)]  (another instance)
/// Row 2: [f(0), f(1), f(2), f(3), ..., f(n_columns-1)]  (another instance)
///
/// This is different from SimpleFibonacci which is vertical (3 cols, many rows)
contract WideFibonacciEval is IFrameworkEval {
    using QM31Field for QM31Field.QM31;
    using PointEvaluatorLib for PointEvaluatorLib.PointEvaluator;

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Log2 of the number of rows in the trace
    /// @dev Maps to: pub log_n_rows: u32
    uint32 public immutable logNRows;

    /// @notice Number of columns in each row (runtime parameter!)
    /// @dev Maps to: pub n_columns: usize
    uint256 public nColumns;

    /// @notice Component name for identification
    string public constant COMPONENT_NAME = "WideFibonacciEval";

    /// @notice Component description
    string public constant DESCRIPTION = "Wide Fibonacci component with horizontal sequences";

    // =============================================================================
    // Constructor
    // =============================================================================

    /// @notice Create WideFibonacciEval with specified parameters
    /// @param _logNRows Log2 of the number of rows
    /// @param _nColumns Number of columns in each Fibonacci sequence
    constructor(uint32 _logNRows, uint256 _nColumns) {
        require(_logNRows > 0, "Invalid log_n_rows");
        require(_nColumns >= 2, "Need at least 2 columns for Fibonacci sequence");
        
        logNRows = _logNRows;
        nColumns = _nColumns;
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
        
        (eval, a) = PointEvaluatorLib.nextTraceMask(eval); // Column 0: f(0)
        (eval, b) = PointEvaluatorLib.nextTraceMask(eval); // Column 1: f(1)

        // Chain constraints across columns in the same row
        for (uint256 i = 2; i < nColumns; i++) {
            // Get next Fibonacci value: f(i)
            QM31Field.QM31 memory c;
            (eval, c) = PointEvaluatorLib.nextTraceMask(eval); // Column i: f(i)

            // Constraint: f(i) = f(i-1) + f(i-2)
            // This enforces continuity ACROSS COLUMNS in the same row
            QM31Field.QM31 memory expectedSum = QM31Field.add(a, b);
            QM31Field.QM31 memory constraint = QM31Field.sub(c, expectedSum);
            
            // Add the constraint: c - (a + b) = 0
            eval = PointEvaluatorLib.addConstraint(eval, constraint);

            // Shift for next iteration: next check will be f(i+1) = f(i) + f(i-1)
            a = b;
            b = c;
        }

        // Return the modified eval with all state changes preserved
        return eval;
    }

    // =============================================================================
    // Additional Getters
    // =============================================================================

    /// @notice Get the number of columns
    /// @return nColumns_ Number of columns in each Fibonacci sequence
    function getNumColumns() external view returns (uint256 nColumns_) {
        return nColumns;
    }

    /// @notice Get the log number of rows
    /// @return logNRows_ Log2 of the number of rows
    function getLogNRows() external view returns (uint32 logNRows_) {
        return logNRows;
    }

    /// @notice Get the total trace size
    /// @return traceSize Total number of elements in the trace (2^logNRows * nColumns)
    function getTraceSize() external view returns (uint256 traceSize) {
        return (1 << logNRows) * nColumns;
    }

    /// @notice Update the number of columns for Fibonacci sequence
    /// @param _nColumns New number of columns
    function setNumColumns(uint256 _nColumns) external {
        require(_nColumns >= 2, "Need at least 2 columns for Fibonacci sequence");
        require(_nColumns <= 1000, "Too many columns (max 1000)");
        nColumns = _nColumns;
    }

    /// @notice Check if the configuration is valid
    /// @return isValid True if the configuration can generate valid constraints
    /// @return errorMessage Error description if invalid
    function validateConfiguration() 
        external 
        view 
        returns (bool isValid, string memory errorMessage) 
    {
        if (logNRows == 0) {
            return (false, "logNRows must be greater than 0");
        }
        
        if (nColumns < 2) {
            return (false, "nColumns must be at least 2 for Fibonacci sequence");
        }
        
        // Check for potential overflow in trace size calculation
        if (logNRows > 32) {
            return (false, "logNRows too large (max 32)");
        }
        
        // Check if trace size would be reasonable (< 2^40 to avoid huge memory usage)
        if (logNRows + _log2(nColumns) > 40) {
            return (false, "Trace size too large (logNRows + log2(nColumns) > 40)");
        }
        
        return (true, "Configuration is valid");
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