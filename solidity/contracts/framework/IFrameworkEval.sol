// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./PointEvaluatorLib.sol";
import "../core/CirclePoint.sol";

/// @title IFrameworkEval
/// @notice Interface matching Rust FrameworkEval trait for constraint framework
/// @dev Provides the core evaluation interface for AIR components
interface IFrameworkEval {
    // =============================================================================
    // Core FrameworkEval Interface (matching Rust trait)
    // =============================================================================

    /// @notice Get the log size of the trace
    /// @dev Maps to: fn log_size(&self) -> u32
    /// @return logSize Log2 of the number of rows in the trace
    function logSize() external view returns (uint32 logSize);

    /// @notice Get the maximum constraint log degree bound
    /// @dev Maps to: fn max_constraint_log_degree_bound(&self) -> u32
    /// @return maxLogDegreeBound Maximum log degree bound for constraints
    function maxConstraintLogDegreeBound() external view returns (uint32 maxLogDegreeBound);

    /// @notice Evaluate constraints using the provided evaluator
    /// @dev Maps to: fn evaluate<E: EvalAtRow>(&self, eval: E) -> E
    /// @param eval Evaluator implementing IEvalAtRow for constraint evaluation
    /// @return updatedEval The evaluator after constraint evaluation
    function evaluate(PointEvaluatorLib.PointEvaluator memory eval) external returns (PointEvaluatorLib.PointEvaluator memory updatedEval);

    // =============================================================================
    // Additional Metadata
    // =============================================================================

    /// @notice Get evaluation metadata for this component
    /// @return componentName Human-readable component name
    /// @return nConstraints Number of constraints this evaluation generates
    /// @return description Description of the constraints
    function getEvalInfo()
        external
        view
        returns (
            string memory componentName,
            uint256 nConstraints,
            string memory description
        );
}