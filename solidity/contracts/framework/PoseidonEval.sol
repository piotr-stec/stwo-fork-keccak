// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./IFrameworkEval.sol";
import "./PointEvaluatorLib.sol";
import "../fields/QM31Field.sol";

/// @title PoseidonEval
/// @notice Poseidon evaluation component
contract PoseidonEval is IFrameworkEval {
    using QM31Field for QM31Field.QM31;
    using PointEvaluatorLib for PointEvaluatorLib.PointEvaluator;

    struct LookupElements {
        QM31Field.QM31 z;
        QM31Field.QM31 alpha;
        QM31Field.QM31[16] alpha_powers;
    }

    struct PoseidonElements {
        LookupElements inner;
    }

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Log2 of the number of rows in the trace
    /// @dev Maps to: pub log_n_rows: u32
    uint32 public immutable logNRows;

    PoseidonElements public poseidonElements;

    QM31Field.QM31 public claimed_sum;
    string public isFirstId;

    string public isActiveId;

    uint256 public nActiveRows;

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(
        uint32 _logNRows,
        PoseidonElements memory _poseidonElements,
        QM31Field.QM31 memory _claimed_sum,
        string memory _isFirstId,
        string memory _isActiveId,
        uint256 _nActiveRows
    ) {
        logNRows = _logNRows;
        poseidonElements = _poseidonElements;
        claimed_sum = _claimed_sum;
        isFirstId = _isFirstId;
        isActiveId = _isActiveId;
        nActiveRows = _nActiveRows;
    }

    function setParameters(
        PoseidonElements memory _poseidonElements,
        QM31Field.QM31 memory _claimed_sum,
        string memory _isFirstId,
        string memory _isActiveId,
        uint256 _nActiveRows
    ) external {
        poseidonElements = _poseidonElements;
        claimed_sum = _claimed_sum;
        isFirstId = _isFirstId;
        isActiveId = _isActiveId;
        nActiveRows = _nActiveRows;
    }

    // =============================================================================
    // IFrameworkEval Implementation
    // =============================================================================

    /// @inheritdoc IFrameworkEval
    function logSize() external view override returns (uint32 logSize_) {
        return logNRows;
    }

    /// @inheritdoc IFrameworkEval
    function maxConstraintLogDegreeBound()
        external
        view
        override
        returns (uint32 maxLogDegreeBound)
    {
        return logNRows + 2; //self.log_n_rows + LOG_EXPAND
    }

    /// @inheritdoc IFrameworkEval
    function evaluate(
        PointEvaluatorLib.PointEvaluator memory eval
    )
        external
        view
        override
        returns (PointEvaluatorLib.PointEvaluator memory updatedEval)
    {

        // Get is_first and is_active masks
        QM31Field.QM31 memory is_first;
        QM31Field.QM31 memory is_active;

        (eval, is_first) = eval.getPreprocessedColumn(uint256(0)); // is_first
        (eval, is_active) = eval.getPreprocessedColumn(uint256(0)); // is_active
        int256[] memory offsets = new int256[](2);
        offsets[0] = 0;
        offsets[1] = -1;


        (eval, ) = eval.nextInteractionMask(1, offsets);

        // Poseidon hash constraints would go here
        // For brevity, we skip the full Poseidon implementation

        // Return the modified eval with all state changes preserved
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

    /// @notice Get the total trace size

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
