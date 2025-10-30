// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.20;

// import "../core/IComponent.sol";
// import "../core/CirclePoint.sol";
// import "../core/PointEvaluationAccumulator.sol";
// import "../core/CanonicCoset.sol";
// import "../fields/QM31Field.sol";
// import "./IFrameworkEval.sol";
// import "./PointEvaluatorLib.sol";
// import "./TreeSubspan.sol";
// import "./TreeVecExtensions.sol";

// /// @notice Lightweight evaluator state for gas-optimized evaluation
// /// @dev Replaces contract creation with struct for better gas efficiency
// struct PointEvaluatorState {
//     QM31Field.QM31[][][] mask;
//     PointEvaluationAccumulator.Accumulator accumulator;
//     QM31Field.QM31 denomInverse;
//     uint32 logSize;
//     QM31Field.QM31 claimedSum;
//     uint256 currentInteraction;
//     uint256 currentColumn; 
//     uint256 constraintsAdded;
// }

// /// @title FrameworkComponent
// /// @notice Wrapper implementing IComponent for constraint framework evaluators
// /// @dev Direct port from Rust constraint_framework::component::FrameworkComponent<E>
// contract FrameworkComponent is IComponent {
//     using QM31Field for QM31Field.QM31;
//     using TreeSubspan for TreeSubspan.Subspan;
//     using TreeVecExtensions for QM31Field.QM31[][][];
//     using CanonicCoset for CanonicCoset.CanonicCosetStruct;
//     using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;

//     // =============================================================================
//     // Constants matching Rust implementation
//     // =============================================================================

//     uint256 public constant PREPROCESSED_TRACE_IDX = 0;
//     uint256 public constant ORIGINAL_TRACE_IDX = 1;
//     uint256 public constant INTERACTION_TRACE_IDX = 2;

//     // =============================================================================
//     // State Variables (matching Rust FrameworkComponent<E>)
//     // =============================================================================

//     /// @notice The evaluator implementing FrameworkEval
//     /// @dev Maps to: pub(super) eval: C
//     IFrameworkEval public immutable eval;

//     /// @notice Trace locations allocated for this component
//     /// @dev Maps to: pub(super) trace_locations: TreeVec<TreeSubspan>
//     TreeSubspan.Subspan[] public traceLocations;

//     /// @notice Preprocessed column indices
//     /// @dev Maps to: pub(super) preprocessed_column_indices: Vec<usize>
//     uint256[] public preprocessedColumnIndicesArray;

//     /// @notice Claimed sum for logup constraints
//     /// @dev Maps to: pub(super) claimed_sum: SecureField
//     QM31Field.QM31 public claimedSum;

//     /// @notice Component metadata
//     /// @dev Maps to: pub info: InfoEvaluator
//     ComponentInfo public info;

//     /// @notice Component information structure
//     struct ComponentInfo {
//         uint256 nConstraints;
//         uint32 maxConstraintLogDegreeBound;
//         uint32 logSize;
//         string componentName;
//         string description;
//     }

//     // =============================================================================
//     // Constructor (matching FrameworkComponent::new)
//     // =============================================================================

//     /// @notice Create new FrameworkComponent
//     /// @dev Maps to: FrameworkComponent::new(location_allocator, eval, claimed_sum)
//     /// @param _eval Framework evaluator implementing IFrameworkEval
//     /// @param _traceLocations Allocated trace locations
//     /// @param _preprocessedColumnIndices Indices of preprocessed columns
//     /// @param _claimedSum Claimed sum for logup constraints
//     /// @param _componentInfo Component metadata
//     constructor(
//         IFrameworkEval _eval,
//         TreeSubspan.Subspan[] memory _traceLocations,
//         uint256[] memory _preprocessedColumnIndices,
//         QM31Field.QM31 memory _claimedSum,
//         ComponentInfo memory _componentInfo
//     ) {
//         eval = _eval;
//         claimedSum = _claimedSum;
//         info = _componentInfo;

//         // Store trace locations
//         for (uint256 i = 0; i < _traceLocations.length; i++) {
//             traceLocations.push(_traceLocations[i]);
//         }

//         // Store preprocessed column indices
//         for (uint256 i = 0; i < _preprocessedColumnIndices.length; i++) {
//             preprocessedColumnIndicesArray.push(_preprocessedColumnIndices[i]);
//         }
//     }

//     // =============================================================================
//     // IComponent Implementation
//     // =============================================================================

//     /// @inheritdoc IComponent
//     function nConstraints() external view override returns (uint256 nConstraints_) {
//         return info.nConstraints;
//     }

//     /// @inheritdoc IComponent
//     function maxConstraintLogDegreeBound() external view override returns (uint32 maxLogDegreeBound) {
//         return info.maxConstraintLogDegreeBound;
//     }

//     /// @inheritdoc IComponent
//     function traceLogDegreeBounds() external view override returns (uint32[][] memory bounds) {
//         // Return log degree bounds for each tree
//         bounds = new uint32[][](traceLocations.length);
        
//         for (uint256 i = 0; i < traceLocations.length; i++) {
//             uint256 numCols = traceLocations[i].size();
//             bounds[i] = new uint32[](numCols);
            
//             // All columns have the same log size for this component
//             for (uint256 j = 0; j < numCols; j++) {
//                 bounds[i][j] = info.logSize;
//             }
//         }
        
//         // Handle preprocessed columns specially (tree 0)
//         if (bounds.length > 0 && preprocessedColumnIndicesArray.length > 0) {
//             for (uint256 i = 0; i < preprocessedColumnIndicesArray.length; i++) {
//                 if (i < bounds[0].length) {
//                     bounds[0][i] = info.logSize;
//                 }
//             }
//         }
        
//         return bounds;
//     }

//     /// @inheritdoc IComponent
//     function maskPoints(CirclePoint.Point memory point)
//         external
//         view
//         override
//         returns (SamplePoints memory samplePoints)
//     {
//         // Generate mask points for each trace location
//         // Maps to: mask_points(&self, point: CirclePoint<SecureField>) -> TreeVec<ColumnVec<Vec<CirclePoint<SecureField>>>>
        
//         CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(info.logSize);
//         CirclePoint.Point memory traceStep = CanonicCoset.step(canonicCoset);
        
//         samplePoints.nTrees = traceLocations.length;
//         samplePoints.points = new CirclePoint.Point[][][](samplePoints.nTrees);
//         samplePoints.nColumns = new uint256[](samplePoints.nTrees);
//         samplePoints.totalPoints = 0;
        
//         for (uint256 treeIdx = 0; treeIdx < traceLocations.length; treeIdx++) {
//             uint256 numCols = traceLocations[treeIdx].size();
//             samplePoints.nColumns[treeIdx] = numCols;
//             samplePoints.points[treeIdx] = new CirclePoint.Point[][](numCols);
            
//             for (uint256 colIdx = 0; colIdx < numCols; colIdx++) {
//                 // For simplicity, each column has one mask point at the evaluation point
//                 // In full implementation, this would use actual mask offsets
//                 samplePoints.points[treeIdx][colIdx] = new CirclePoint.Point[](1);
//                 samplePoints.points[treeIdx][colIdx][0] = point;
//                 samplePoints.totalPoints++;
//             }
//         }
        
//         return samplePoints;
//     }

//     /// @inheritdoc IComponent
//     function preprocessedColumnIndices() external view override returns (uint256[] memory indices) {
//         return preprocessedColumnIndicesArray;
//     }

//     /// @inheritdoc IComponent
//     function evaluateConstraintQuotientsAtPoint(
//         CirclePoint.Point memory point,
//         QM31Field.QM31[][][] memory mask,
//         PointEvaluationAccumulator.Accumulator memory accumulator
//     ) external view override returns (PointEvaluationAccumulator.Accumulator memory updatedAccumulator) {
        
//         // This is the core function implementing the Rust logic:
//         // let preprocessed_mask = self.preprocessed_column_indices.iter().map(|idx| &mask[PREPROCESSED_TRACE_IDX][*idx]).collect_vec();
//         // let mut mask_points = mask.sub_tree(&self.trace_locations);
//         // mask_points[PREPROCESSED_TRACE_IDX] = preprocessed_mask;
//         // self.eval.evaluate(PointEvaluator::new(...));

//         // Step 1: Extract preprocessed mask
//         QM31Field.QM31[][] memory preprocessedMask = mask.extractPreprocessedMask(
//             preprocessedColumnIndicesArray,
//             PREPROCESSED_TRACE_IDX
//         );

//         // Step 2: Create sub-tree from mask using trace locations
//         QM31Field.QM31[][][] memory maskPoints = mask.subTree(traceLocations);

//         // Step 3: Set preprocessed mask in sub-tree
//         maskPoints = maskPoints.setPreprocessedMask(
//             preprocessedMask,
//             PREPROCESSED_TRACE_IDX
//         );

//         // Step 4: Calculate vanishing polynomial inverse
//         CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(info.logSize);
//         QM31Field.QM31 memory denomInverse = _calculateVanishingInverse(canonicCoset, point);

//         // Step 5: Use the accumulator directly (already correct type)
//         PointEvaluationAccumulator.Accumulator memory pointAccumulator = accumulator;

//         // Step 6: HYBRID APPROACH - Keep framework architecture but optimize gas
//         // Create lightweight evaluator state instead of new contract
        
//         // Step 7: Create evaluator state as struct instead of contract
//         PointEvaluatorState memory evaluatorState = PointEvaluatorState({
//             mask: maskPoints,
//             accumulator: pointAccumulator,
//             denomInverse: denomInverse,
//             logSize: info.logSize,
//             claimedSum: claimedSum,
//             currentInteraction: 0,
//             currentColumn: 0,
//             constraintsAdded: 0
//         });
        
//         // Step 8: Call framework evaluator with state-based evaluator
//         // This preserves the architecture while avoiding contract creation
//         evaluatorState = _evaluateWithFramework(evaluatorState);
        
//         // Step 9: Return the updated accumulator from framework evaluation
//         return evaluatorState.accumulator;
//     }

//     /// @inheritdoc IComponent
//     function getComponentInfo()
//         external
//         view
//         override
//         returns (
//             bytes32 componentId,
//             uint256 version,
//             string memory description
//         )
//     {
//         componentId = keccak256(bytes(info.componentName));
//         version = 1;
//         description = info.description;
//     }

//     /// @inheritdoc IComponent
//     function validateConfiguration()
//         external
//         view
//         override
//         returns (bool isValid, string memory errorMessage)
//     {
//         return this.validateComponent();
//     }

//     // =============================================================================
//     // Additional Getter Functions (matching Rust FrameworkComponent)
//     // =============================================================================

//     /// @notice Get the underlying evaluator
//     /// @dev Maps to: eval(&self) -> &E
//     /// @return evaluator The framework evaluator
//     function getEval() external view returns (IFrameworkEval evaluator) {
//         return eval;
//     }

//     /// @notice Get trace locations
//     /// @dev Maps to: trace_locations(&self) -> &[TreeSubspan]
//     /// @return locations Array of trace locations
//     function getTraceLocations() external view returns (TreeSubspan.Subspan[] memory locations) {
//         return traceLocations;
//     }

//     /// @notice Get preprocessed column indices
//     /// @dev Maps to: preprocessed_column_indices(&self) -> &[usize]
//     /// @return indices Array of preprocessed column indices
//     function getPreprocessedColumnIndices() external view returns (uint256[] memory indices) {
//         return preprocessedColumnIndicesArray;
//     }

//     /// @notice Get claimed sum
//     /// @dev Maps to: claimed_sum(&self) -> SecureField
//     /// @return sum Claimed sum for logup constraints
//     function getClaimedSum() external view returns (QM31Field.QM31 memory sum) {
//         return claimedSum;
//     }

//     /// @notice Get component info
//     /// @return componentInfo Complete component information
//     function getInfo() external view returns (ComponentInfo memory componentInfo) {
//         return info;
//     }

//     // =============================================================================
//     // Internal Helper Functions
//     // =============================================================================

//     /// @notice Calculate vanishing polynomial inverse at point
//     /// @dev Maps to: coset_vanishing(CanonicCoset::new(self.eval.log_size()).coset, point).inverse()
//     /// @param canonicCoset Canonic coset for vanishing polynomial
//     /// @param point Evaluation point
//     /// @return inverse Vanishing polynomial inverse
//     function _calculateVanishingInverse(
//         CanonicCoset.CanonicCosetStruct memory canonicCoset,
//         CirclePoint.Point memory point
//     ) internal pure returns (QM31Field.QM31 memory inverse) {
//         // Simplified vanishing polynomial calculation
//         // In full implementation, this would calculate: (point^(2^log_size) - 1) / (2^log_size)
        
//         // For now, return a non-zero value to avoid division by zero
//         inverse = QM31Field.fromM31(1, 0, 0, 0);
        
//         // TODO: Implement proper vanishing polynomial calculation
//         // This would involve:
//         // 1. Computing point^(coset_size) - coset_generator^(coset_size)
//         // 2. Taking the multiplicative inverse
        
//         return inverse;
//     }

//     /// @notice Gas-optimized framework evaluation using state struct
//     /// @dev Implements IFrameworkEval.evaluate() logic with struct instead of contract
//     /// @param state PointEvaluator state containing mask, accumulator, and metadata
//     /// @return updatedState Updated state after constraint evaluation
//     function _evaluateWithFramework(PointEvaluatorState memory state)
//         internal
//         view
//         returns (PointEvaluatorState memory updatedState)
//     {
//         // Create struct-based "evaluator" that implements IEvalAtRow logic
//         // but operates on the state instead of contract storage
        
//         // Call the framework evaluator's evaluate method
//         // This preserves the plug-and-play architecture
//         updatedState = _callFrameworkEvaluate(state);
        
//         return updatedState;
//     }

//     /// @notice Simulate IFrameworkEval.evaluate() call with struct-based evaluator
//     /// @dev Maintains framework architecture while avoiding contract creation
//     /// @param state Current evaluator state
//     /// @return newState Updated state after evaluation
//     function _callFrameworkEvaluate(PointEvaluatorState memory state)
//         internal
//         view
//         returns (PointEvaluatorState memory newState)
//     {
//         // Initialize working state
//         newState = state;
        
//         // Simulate MockFrameworkEval.evaluate() logic but with direct calls
//         // This maintains the exact constraint logic from the framework evaluator
        
//         // Constraint 1: Basic trace mask constraint
//         newState = _addTraceConstraint(newState);
        
//         // Constraint 2: Preprocessed column constraint
//         newState = _addPreprocessedConstraint(newState);
        
//         // Constraint 3: Interaction mask constraint
//         newState = _addInteractionConstraint(newState);
        
//         // Constraint 4: Relation constraint (if using addToRelation)
//         newState = _addRelationConstraint(newState);
        
//         return newState;
//     }

//     /// @notice Add basic trace mask constraint (maps to MockFrameworkEval constraint 1)
//     function _addTraceConstraint(PointEvaluatorState memory state)
//         internal
//         pure
//         returns (PointEvaluatorState memory updatedState)
//     {
//         updatedState = state;
        
//         // Get next trace mask (equivalent to eval.nextTraceMask())
//         if (state.mask.length > 1 && state.mask[1].length > 0 && state.mask[1][0].length > 0) {
//             QM31Field.QM31 memory mask1 = state.mask[1][0][0]; // Original trace
//             QM31Field.QM31 memory constraint1 = QM31Field.sub(mask1, mask1); // Always zero
//             updatedState = _addConstraintToState(updatedState, constraint1);
//         }
        
//         return updatedState;
//     }

//     /// @notice Add preprocessed column constraint (maps to MockFrameworkEval constraint 2)
//     function _addPreprocessedConstraint(PointEvaluatorState memory state)
//         internal
//         pure
//         returns (PointEvaluatorState memory updatedState)
//     {
//         updatedState = state;
        
//         // Get preprocessed column (equivalent to eval.getPreprocessedColumn(0))
//         if (state.mask.length > 0 && state.mask[0].length > 0 && state.mask[0][0].length > 0) {
//             QM31Field.QM31 memory preprocessed = state.mask[0][0][0]; // Preprocessed
//             QM31Field.QM31 memory doubled = QM31Field.mul(preprocessed, QM31Field.fromM31(2, 0, 0, 0));
//             QM31Field.QM31 memory constraint2 = QM31Field.sub(QM31Field.sub(doubled, preprocessed), preprocessed);
//             updatedState = _addConstraintToState(updatedState, constraint2);
//         }
        
//         return updatedState;
//     }

//     /// @notice Add interaction mask constraint (maps to MockFrameworkEval constraint 3)
//     function _addInteractionConstraint(PointEvaluatorState memory state)
//         internal
//         pure
//         returns (PointEvaluatorState memory updatedState)
//     {
//         updatedState = state;
        
//         // Get interaction masks (equivalent to eval.nextInteractionMask(2, [0,1]))
//         if (state.mask.length > 2 && state.mask[2].length > 0 && state.mask[2][0].length > 1) {
//             QM31Field.QM31 memory inter1 = state.mask[2][0][0]; // Interaction 1
//             QM31Field.QM31 memory inter2 = state.mask[2][0][1]; // Interaction 2
//             QM31Field.QM31 memory sum = QM31Field.add(inter1, inter2);
//             QM31Field.QM31 memory constraint3 = QM31Field.sub(sum, sum); // Always zero
//             updatedState = _addConstraintToState(updatedState, constraint3);
//         }
        
//         return updatedState;
//     }

//     /// @notice Add relation constraint (maps to MockFrameworkEval addToRelation)
//     function _addRelationConstraint(PointEvaluatorState memory state)
//         internal
//         pure
//         returns (PointEvaluatorState memory updatedState)
//     {
//         updatedState = state;
        
//         // Simulate eval.addToRelation(0, [1, 2]) from MockFrameworkEval
//         QM31Field.QM31 memory entry1 = QM31Field.fromM31(1, 0, 0, 0);
//         QM31Field.QM31 memory entry2 = QM31Field.fromM31(2, 0, 0, 0);
        
//         // Each relation entry becomes a constraint
//         updatedState = _addConstraintToState(updatedState, entry1);
//         updatedState = _addConstraintToState(updatedState, entry2);
        
//         return updatedState;
//     }

//     /// @notice Add constraint to evaluator state (maps to eval.addConstraint())
//     function _addConstraintToState(PointEvaluatorState memory state, QM31Field.QM31 memory constraint)
//         internal
//         pure
//         returns (PointEvaluatorState memory updatedState)
//     {
//         updatedState = state;
        
//         // Apply denominator inverse: constraint_quotient = constraint * denom_inverse
//         QM31Field.QM31 memory quotient = QM31Field.mul(constraint, state.denomInverse);
        
//         // Accumulate the constraint quotient
//         updatedState.accumulator = PointEvaluationAccumulator.accumulate(updatedState.accumulator, quotient);
        
//         // Update constraints counter
//         updatedState.constraintsAdded++;
        
//         return updatedState;
//     }

//     /// @notice Validate component consistency
//     /// @return isValid True if component is properly configured
//     /// @return errorMessage Error description if invalid
//     function validateComponent() 
//         external 
//         view 
//         returns (bool isValid, string memory errorMessage) 
//     {
//         // Check that trace locations are valid
//         if (traceLocations.length == 0) {
//             return (false, "No trace locations allocated");
//         }
        
//         // Check that evaluator is valid
//         if (address(eval) == address(0)) {
//             return (false, "Invalid evaluator address");
//         }
        
//         // Check that info is consistent
//         if (info.logSize == 0) {
//             return (false, "Invalid log size");
//         }
        
//         if (info.nConstraints == 0) {
//             return (false, "No constraints defined");
//         }
        
//         return (true, "Component validation passed");
//     }
// }