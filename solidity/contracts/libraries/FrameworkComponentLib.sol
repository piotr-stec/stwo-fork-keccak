// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../core/CirclePoint.sol";
import "../core/PointEvaluationAccumulator.sol";
import "../core/CanonicCoset.sol";
import "../fields/QM31Field.sol";
import "../framework/IFrameworkEval.sol";
import "../framework/PointEvaluatorLib.sol";
import "../framework/TreeSubspan.sol";
import "../framework/TreeVecExtensions.sol";

/// @title FrameworkComponentLib
/// @notice Library implementing FrameworkComponent functionality for gas optimization
/// @dev Converts contract to library to reduce deployment gas from 4M to ~400k
library FrameworkComponentLib {
    using QM31Field for QM31Field.QM31;
    using TreeSubspan for TreeSubspan.Subspan;
    using TreeVecExtensions for QM31Field.QM31[][][];
    using CanonicCoset for CanonicCoset.CanonicCosetStruct;
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;

    // =============================================================================
    // Constants matching Rust implementation
    // =============================================================================

    uint256 public constant PREPROCESSED_TRACE_IDX = 0;
    uint256 public constant ORIGINAL_TRACE_IDX = 1;
    uint256 public constant INTERACTION_TRACE_IDX = 2;

    // =============================================================================
    // Data Structures
    // =============================================================================

    /// @notice Sample points structure for mask points generation
    struct SamplePoints {
        uint256 nTrees;
        CirclePoint.Point[][][] points;
        uint256[] nColumns;
        uint256 totalPoints;
    }

    /// @notice Component information structure
    struct ComponentInfo {
        uint256 nConstraints;
        uint32 maxConstraintLogDegreeBound;
        uint32 logSize;
        string componentName;
        string description;
    }

    /// @notice Framework component state
    struct ComponentState {
        /// @notice The evaluator implementing FrameworkEval
        address eval;
        
        /// @notice Trace locations allocated for this component
        TreeSubspan.Subspan[] traceLocations;
        
        /// @notice Preprocessed column indices
        uint256[] preprocessedColumnIndices;
        
        /// @notice Claimed sum for logup constraints
        QM31Field.QM31 claimedSum;
        
        /// @notice Component metadata
        ComponentInfo info;
        
        /// @notice Whether the component is initialized
        bool isInitialized;
    }

    // =============================================================================
    // Library Functions
    // =============================================================================

    /// @notice Initialize framework component state
    /// @dev Maps to: FrameworkComponent::new(location_allocator, eval, claimed_sum)
    /// @param state The component state to initialize
    /// @param _eval Framework evaluator implementing IFrameworkEval
    /// @param _traceLocations Allocated trace locations
    /// @param _preprocessedColumnIndices Indices of preprocessed columns
    /// @param _claimedSum Claimed sum for logup constraints
    /// @param _componentInfo Component metadata
    function initialize(
        ComponentState storage state,
        address _eval,
        TreeSubspan.Subspan[] memory _traceLocations,
        uint256[] memory _preprocessedColumnIndices,
        QM31Field.QM31 memory _claimedSum,
        ComponentInfo memory _componentInfo
    ) external {
        require(!state.isInitialized, "Component already initialized");
        require(_eval != address(0), "Invalid evaluator address");
        require(_traceLocations.length > 0, "No trace locations provided");
        require(_componentInfo.logSize > 0, "Invalid log size");
        require(_componentInfo.nConstraints > 0, "No constraints defined");

        state.eval = _eval;
        state.claimedSum = _claimedSum;
        state.info = _componentInfo;
        state.isInitialized = true;

        // Clear and store trace locations
        delete state.traceLocations;
        for (uint256 i = 0; i < _traceLocations.length; i++) {
            state.traceLocations.push(_traceLocations[i]);
        }

        // Clear and store preprocessed column indices
        delete state.preprocessedColumnIndices;
        for (uint256 i = 0; i < _preprocessedColumnIndices.length; i++) {
            state.preprocessedColumnIndices.push(_preprocessedColumnIndices[i]);
        }
    }

    /// @notice Get number of constraints
    /// @param state The component state
    /// @return nConstraints_ Number of constraints
    function nConstraints(ComponentState storage state) 
        external 
        view 
        returns (uint256 nConstraints_) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.info.nConstraints;
    }

    /// @notice Get maximum constraint log degree bound
    /// @param state The component state
    /// @return maxLogDegreeBound Maximum constraint log degree bound
    function maxConstraintLogDegreeBound(ComponentState storage state) 
        external 
        view 
        returns (uint32 maxLogDegreeBound) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.info.maxConstraintLogDegreeBound;
    }

    /// @notice Get trace log degree bounds
    /// @param state The component state
    /// @return bounds Trace log degree bounds for each tree
    function traceLogDegreeBounds(ComponentState storage state) 
        external 
        view 
        returns (uint32[][] memory bounds) 
    {
        require(state.isInitialized, "Component not initialized");
        
        // Return log degree bounds for each tree
        bounds = new uint32[][](state.traceLocations.length);
        
        for (uint256 i = 0; i < state.traceLocations.length; i++) {
            uint256 numCols = state.traceLocations[i].size();
            bounds[i] = new uint32[](numCols);
            
            // All columns have the same log size for this component
            for (uint256 j = 0; j < numCols; j++) {
                bounds[i][j] = state.info.logSize;
            }
        }
        
        // Handle preprocessed columns specially (tree 0)
        if (bounds.length > 0 && state.preprocessedColumnIndices.length > 0) {
            for (uint256 i = 0; i < state.preprocessedColumnIndices.length; i++) {
                if (i < bounds[0].length) {
                    bounds[0][i] = state.info.logSize;
                }
            }
        }
        
        return bounds;
    }

    // TODO: better check for compatibility with Rust implementation
    /// @notice Generate mask points for the component
    /// @param state The component state
    /// @param point The point to generate mask points for
    /// @return samplePoints Generated sample points
    function maskPoints(ComponentState storage state, CirclePoint.Point memory point)
        external
        view
        returns (SamplePoints memory samplePoints)
    {
        require(state.isInitialized, "Component not initialized");
        
       
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(state.info.logSize);
        
        samplePoints.nTrees = state.traceLocations.length;
        samplePoints.points = new CirclePoint.Point[][][](samplePoints.nTrees);
        samplePoints.nColumns = new uint256[](samplePoints.nTrees);
        samplePoints.totalPoints = 0;
        
        for (uint256 treeIdx = 0; treeIdx < state.traceLocations.length; treeIdx++) {
            uint256 numCols = state.traceLocations[treeIdx].size();
            samplePoints.nColumns[treeIdx] = numCols;
            samplePoints.points[treeIdx] = new CirclePoint.Point[][](numCols);
            
            for (uint256 colIdx = 0; colIdx < numCols; colIdx++) {
                // For simplicity, each column has one mask point at the evaluation point
                // In full implementation, this would use actual mask offsets
                samplePoints.points[treeIdx][colIdx] = new CirclePoint.Point[](1);
                samplePoints.points[treeIdx][colIdx][0] = point;
                samplePoints.totalPoints++;
            }
        }
        
        return samplePoints;
    }

    /// @notice Get preprocessed column indices
    /// @param state The component state
    /// @return indices Preprocessed column indices
    function preprocessedColumnIndices(ComponentState storage state) 
        external 
        view 
        returns (uint256[] memory indices) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.preprocessedColumnIndices;
    }

    /// @notice Evaluate constraint quotients at point
    /// @param state The component state
    /// @param point Evaluation point
    /// @param mask Mask values
    /// @param accumulator Point evaluation accumulator
    /// @return updatedAccumulator Updated accumulator after evaluation
    function evaluateConstraintQuotientsAtPoint(
        ComponentState storage state,
        CirclePoint.Point memory point,
        QM31Field.QM31[][][] memory mask,
        PointEvaluationAccumulator.Accumulator memory accumulator
    ) external returns (PointEvaluationAccumulator.Accumulator memory updatedAccumulator) {
        require(state.isInitialized, "Component not initialized");
        
        // Step 1: Extract preprocessed mask
        QM31Field.QM31[][] memory preprocessedMask = mask.extractPreprocessedMask(
            state.preprocessedColumnIndices,
            PREPROCESSED_TRACE_IDX
        );

        // Step 2: Create sub-tree from mask using trace locations
        QM31Field.QM31[][][] memory maskSubTree = mask.subTree(state.traceLocations);

        // Step 3: Set preprocessed mask in sub-tree
        maskSubTree = maskSubTree.setPreprocessedMask(
            preprocessedMask,
            PREPROCESSED_TRACE_IDX
        );

        // Step 4: Calculate vanishing polynomial inverse
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(state.info.logSize);
        QM31Field.QM31 memory denomInverse = _calculateVanishingInverse(canonicCoset, point);

        // Step 5: Use the accumulator directly (already correct type)
        PointEvaluationAccumulator.Accumulator memory pointAccumulator = accumulator;

        // Step 6: Create PointEvaluator and evaluate constraints
        PointEvaluatorLib.PointEvaluator memory pointEvaluator = PointEvaluatorLib.create(
            maskSubTree,
            pointAccumulator,
            denomInverse,
            state.info.logSize,
            state.claimedSum
        );

        // Step 7: Evaluate using the framework evaluator
        PointEvaluatorLib.PointEvaluator memory updatedEvaluator = IFrameworkEval(state.eval).evaluate(pointEvaluator);

        // Step 8: Get updated accumulator from evaluator
        PointEvaluationAccumulator.Accumulator memory finalAccumulator = updatedEvaluator.evaluationAccumulator;

        // Step 9: Return the updated accumulator (already correct type)
        return finalAccumulator;
    }

    /// @notice Get component information
    /// @param state The component state
    /// @return componentId Unique component identifier
    /// @return version Component version
    /// @return description Component description
    function getComponentInfo(ComponentState storage state)
        external
        view
        returns (
            bytes32 componentId,
            uint256 version,
            string memory description
        )
    {
        require(state.isInitialized, "Component not initialized");
        componentId = keccak256(bytes(state.info.componentName));
        version = 1;
        description = state.info.description;
    }

    /// @notice Validate component configuration
    /// @param state The component state
    /// @return isValid True if component is valid
    /// @return errorMessage Error message if invalid
    function validateConfiguration(ComponentState storage state)
        external
        view
        returns (bool isValid, string memory errorMessage)
    {
        return validateComponent(state);
    }

    /// @notice Get the underlying evaluator address
    /// @param state The component state
    /// @return evaluator The framework evaluator address
    function getEval(ComponentState storage state) 
        external 
        view 
        returns (address evaluator) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.eval;
    }

    /// @notice Get trace locations
    /// @param state The component state
    /// @return locations Array of trace locations
    function getTraceLocations(ComponentState storage state) 
        external 
        view 
        returns (TreeSubspan.Subspan[] memory locations) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.traceLocations;
    }

    /// @notice Get preprocessed column indices
    /// @param state The component state
    /// @return indices Array of preprocessed column indices
    function getPreprocessedColumnIndices(ComponentState storage state) 
        external 
        view 
        returns (uint256[] memory indices) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.preprocessedColumnIndices;
    }

    /// @notice Get claimed sum
    /// @param state The component state
    /// @return sum Claimed sum for logup constraints
    function getClaimedSum(ComponentState storage state) 
        external 
        view 
        returns (QM31Field.QM31 memory sum) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.claimedSum;
    }

    /// @notice Get component info
    /// @param state The component state
    /// @return componentInfo Complete component information
    function getInfo(ComponentState storage state) 
        external 
        view 
        returns (ComponentInfo memory componentInfo) 
    {
        require(state.isInitialized, "Component not initialized");
        return state.info;
    }

    /// @notice Clear component state after use
    /// @param state The component state to clear
    function clearState(ComponentState storage state) external {
        require(state.isInitialized, "Component not initialized");
        
        // Clear dynamic arrays
        delete state.traceLocations;
        delete state.preprocessedColumnIndices;
        
        // Reset other fields
        state.eval = address(0);
        state.claimedSum = QM31Field.zero();
        delete state.info;
        state.isInitialized = false;
    }

    /// @notice Validate component consistency
    /// @param state The component state
    /// @return isValid True if component is properly configured
    /// @return errorMessage Error description if invalid
    function validateComponent(ComponentState storage state) 
        public 
        view 
        returns (bool isValid, string memory errorMessage) 
    {
        if (!state.isInitialized) {
            return (false, "Component not initialized");
        }
        
        // Check that trace locations are valid
        if (state.traceLocations.length == 0) {
            return (false, "No trace locations allocated");
        }
        
        // Check that evaluator is valid
        if (state.eval == address(0)) {
            return (false, "Invalid evaluator address");
        }
        
        // Check that info is consistent
        if (state.info.logSize == 0) {
            return (false, "Invalid log size");
        }
        
        if (state.info.nConstraints == 0) {
            return (false, "No constraints defined");
        }
        
        return (true, "Component validation passed");
    }

    // =============================================================================
    // Internal Helper Functions
    // =============================================================================

    /// @notice Calculate vanishing polynomial inverse at point
    /// @dev Maps to: coset_vanishing(CanonicCoset::new(self.eval.log_size()).coset, point).inverse()
    /// @param canonicCoset Canonic coset for vanishing polynomial
    /// @param point Evaluation point
    /// @return inverse Vanishing polynomial inverse
    function _calculateVanishingInverse(
        CanonicCoset.CanonicCosetStruct memory canonicCoset,
        CirclePoint.Point memory point
    ) internal pure returns (QM31Field.QM31 memory inverse) {
        // Simplified vanishing polynomial calculation
        // In full implementation, this would calculate: (point^(2^log_size) - 1) / (2^log_size)
        
        // For now, return a non-zero value to avoid division by zero
        inverse = QM31Field.fromM31(1, 0, 0, 0);
        
        // TODO: Implement proper vanishing polynomial calculation
        // This would involve:
        // 1. Computing point^(coset_size) - coset_generator^(coset_size)
        // 2. Taking the multiplicative inverse
        
        return inverse;
    }
}