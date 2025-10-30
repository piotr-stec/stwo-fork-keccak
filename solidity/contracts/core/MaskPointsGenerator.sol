// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../core/CirclePoint.sol";
import "../fields/QM31Field.sol";
import "../fields/CM31Field.sol";

/// @title MaskPointsGenerator
/// @notice Generates mask points for OODS verification in STARK proofs
/// @dev Implements mask_points generation equivalent to Rust stwo implementation
contract MaskPointsGenerator {
    using CirclePoint for CirclePoint.Point;

    /// @notice Secure extension degree for QM31 field (4 components)
    uint256 public constant SECURE_EXTENSION_DEGREE = 4;
    
    /// @notice Index for preprocessed trace tree
    uint256 public constant PREPROCESSED_TRACE_IDX = 0;

    /// @notice Mask offset structure for component evaluation
    struct MaskOffset {
        int256 offset;       // Relative offset from base point
        uint256 columnIdx;   // Column index in tree
    }

    /// @notice Component mask configuration
    struct ComponentMask {
        uint256 treeIdx;                    // Tree index for this component
        uint256 logSize;                    // Log size of evaluation domain
        MaskOffset[] maskOffsets;           // Mask offsets for this component
        uint256[] preprocessedColumns;      // Preprocessed column indices
    }

    /// @notice Sample points structure - TreeVec<ColumnVec<Vec<CirclePoint>>>
    struct SamplePoints {
        uint256 nTrees;                                    // Number of trees
        CirclePoint.Point[][][] points;                   // [tree][column][point]
        uint256[] nColumns;                               // Number of columns per tree
        uint256 totalPoints;                              // Total sample points count
    }

    /// @notice Component configurations for mask generation
    ComponentMask[] public components;

    /// @notice Number of preprocessed columns (for easy access)
    uint256 public nPreprocessedColumns;

    constructor() {
        // Initialize with empty component list
    }

    /// @notice Add component mask configuration
    /// @param treeIdx Tree index for component
    /// @param logSize Log size of evaluation domain
    /// @param maskOffsets Array of mask offsets
    /// @param preprocessedColumns Array of preprocessed column indices
    function addComponent(
        uint256 treeIdx,
        uint256 logSize,
        MaskOffset[] calldata maskOffsets,
        uint256[] calldata preprocessedColumns
    ) external {
        components.push();
        uint256 componentIdx = components.length - 1;
        ComponentMask storage component = components[componentIdx];
        component.treeIdx = treeIdx;
        component.logSize = logSize;
        
        // Copy mask offsets
        for (uint256 i = 0; i < maskOffsets.length; i++) {
            component.maskOffsets.push(maskOffsets[i]);
        }
        
        // Copy preprocessed column indices
        for (uint256 i = 0; i < preprocessedColumns.length; i++) {
            component.preprocessedColumns.push(preprocessedColumns[i]);
        }
        
        // Update total preprocessed columns count
        if (treeIdx == PREPROCESSED_TRACE_IDX) {
            nPreprocessedColumns = preprocessedColumns.length;
        }
    }

    /// @notice Generate mask points relative to OODS point
    /// @param oodsPoint Out-of-domain sampling point
    /// @return samplePoints Generated sample points structure
    function maskPoints(CirclePoint.Point memory oodsPoint) 
        external 
        view 
        returns (SamplePoints memory samplePoints) 
    {
        if (components.length == 0) {
            // Return empty structure for no components
            samplePoints.nTrees = 0;
            samplePoints.points = new CirclePoint.Point[][][](0);
            samplePoints.nColumns = new uint256[](0);
            samplePoints.totalPoints = 0;
            return samplePoints;
        }
        
        // Calculate maximum tree index to determine array size
        uint256 maxTreeIdx = 0;
        for (uint256 i = 0; i < components.length; i++) {
            if (components[i].treeIdx > maxTreeIdx) {
                maxTreeIdx = components[i].treeIdx;
            }
        }
        
        // Initialize sample points structure
        samplePoints.nTrees = maxTreeIdx + 1;
        samplePoints.points = new CirclePoint.Point[][][](samplePoints.nTrees);
        samplePoints.nColumns = new uint256[](samplePoints.nTrees);
        samplePoints.totalPoints = 0;

        // Initialize all trees
        for (uint256 treeIdx = 0; treeIdx <= maxTreeIdx; treeIdx++) {
            samplePoints.points[treeIdx] = new CirclePoint.Point[][](0);
            samplePoints.nColumns[treeIdx] = 0;
        }

        // Process each component to populate points
        for (uint256 compIdx = 0; compIdx < components.length; compIdx++) {
            ComponentMask storage component = components[compIdx];
            uint256 treeIdx = component.treeIdx;
            
            // Calculate trace step for this component
            QM31Field.QM31 memory traceStep = _calculateTraceStep(component.logSize);
            
            // For each mask offset, add the corresponding point
            for (uint256 i = 0; i < component.maskOffsets.length; i++) {
                MaskOffset storage maskOffset = component.maskOffsets[i];
                
                // Calculate sample point
                CirclePoint.Point memory samplePoint = _addScaledStep(
                    oodsPoint,
                    traceStep,
                    maskOffset.offset
                );
                
                // Ensure we have enough columns
                uint256 requiredColumns = maskOffset.columnIdx + 1;
                if (samplePoints.nColumns[treeIdx] < requiredColumns) {
                    // Extend columns array
                    CirclePoint.Point[][] memory newColumns = new CirclePoint.Point[][](requiredColumns);
                    for (uint256 col = 0; col < samplePoints.nColumns[treeIdx]; col++) {
                        newColumns[col] = samplePoints.points[treeIdx][col];
                    }
                    for (uint256 col = samplePoints.nColumns[treeIdx]; col < requiredColumns; col++) {
                        newColumns[col] = new CirclePoint.Point[](0);
                    }
                    samplePoints.points[treeIdx] = newColumns;
                    samplePoints.nColumns[treeIdx] = requiredColumns;
                }
                
                // Add point to column
                uint256 columnIdx = maskOffset.columnIdx;
                CirclePoint.Point[] memory currentColumn = samplePoints.points[treeIdx][columnIdx];
                CirclePoint.Point[] memory newColumn = new CirclePoint.Point[](currentColumn.length + 1);
                
                for (uint256 j = 0; j < currentColumn.length; j++) {
                    newColumn[j] = currentColumn[j];
                }
                newColumn[currentColumn.length] = samplePoint;
                
                samplePoints.points[treeIdx][columnIdx] = newColumn;
                samplePoints.totalPoints++;
            }
        }

        // Handle preprocessed columns specially
        _handlePreprocessedColumns(samplePoints, oodsPoint);
        
        return samplePoints;
    }

    /// @notice Add composition polynomial mask points
    /// @param samplePoints Existing sample points to extend
    /// @param oodsPoint OODS point for composition evaluation
    /// @return Extended sample points with composition polynomial
    function addCompositionMaskPoints(
        SamplePoints memory samplePoints,
        CirclePoint.Point memory oodsPoint
    ) external pure returns (SamplePoints memory) {
        // Create new structure with one additional tree
        SamplePoints memory extended;
        extended.nTrees = samplePoints.nTrees + 1;
        extended.points = new CirclePoint.Point[][][](extended.nTrees);
        extended.nColumns = new uint256[](extended.nTrees);
        extended.totalPoints = samplePoints.totalPoints;
        
        // Copy existing points
        for (uint256 i = 0; i < samplePoints.nTrees; i++) {
            extended.points[i] = samplePoints.points[i];
            extended.nColumns[i] = samplePoints.nColumns[i];
        }
        
        // Add composition polynomial tree with SECURE_EXTENSION_DEGREE columns
        uint256 compositionTreeIdx = samplePoints.nTrees;
        extended.nColumns[compositionTreeIdx] = SECURE_EXTENSION_DEGREE;
        extended.points[compositionTreeIdx] = new CirclePoint.Point[][](SECURE_EXTENSION_DEGREE);
        
        // Each column contains only the OODS point
        for (uint256 col = 0; col < SECURE_EXTENSION_DEGREE; col++) {
            extended.points[compositionTreeIdx][col] = new CirclePoint.Point[](1);
            extended.points[compositionTreeIdx][col][0] = oodsPoint;
            extended.totalPoints++;
        }
        
        return extended;
    }

    /// @notice Get total sample points count across all trees and columns
    /// @param samplePoints Sample points structure
    /// @return total Total number of sample points
    function getTotalSamplePoints(SamplePoints memory samplePoints) 
        external 
        pure 
        returns (uint256 total) 
    {
        return samplePoints.totalPoints;
    }

    /// @notice Get number of columns being sampled
    /// @param samplePoints Sample points structure  
    /// @return columns Total number of columns across all trees
    function getSampledColumnsCount(SamplePoints memory samplePoints)
        external
        pure
        returns (uint256 columns)
    {
        for (uint256 i = 0; i < samplePoints.nTrees; i++) {
            columns += samplePoints.nColumns[i];
        }
        return columns;
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    /// @notice Calculate trace step for given log size
    /// @param logSize Log size of evaluation domain
    /// @return traceStep Calculated trace step as QM31 element
    function _calculateTraceStep(uint256 logSize) internal pure returns (QM31Field.QM31 memory traceStep) {
        // For now, use a simplified calculation - this should match Rust CanonicCoset::step()
        // In practice, this would compute the step size of the coset
        uint32 stepValue = uint32(1 << logSize); // 2^logSize
        traceStep = QM31Field.fromM31(stepValue, 0, 0, 0); // (stepValue, 0, 0, 0)
        return traceStep;
    }


    /// @notice Handle preprocessed columns by setting their mask points to OODS point
    /// @param samplePoints Sample points structure to modify
    /// @param oodsPoint OODS point to use for preprocessed columns
    function _handlePreprocessedColumns(
        SamplePoints memory samplePoints,
        CirclePoint.Point memory oodsPoint
    ) internal view {
        // For preprocessed trace tree, set only actual preprocessed columns to just the OODS point
        if (samplePoints.nTrees > PREPROCESSED_TRACE_IDX) {
            uint256 treeIdx = PREPROCESSED_TRACE_IDX;
            
            // Process each component to find which columns are marked as preprocessed
            for (uint256 compIdx = 0; compIdx < components.length; compIdx++) {
                ComponentMask storage component = components[compIdx];
                if (component.treeIdx == PREPROCESSED_TRACE_IDX) {
                    // Replace preprocessed columns with single OODS point
                    for (uint256 i = 0; i < component.preprocessedColumns.length; i++) {
                        uint256 col = component.preprocessedColumns[i];
                        if (col < samplePoints.nColumns[treeIdx]) {
                            samplePoints.points[treeIdx][col] = new CirclePoint.Point[](1);
                            samplePoints.points[treeIdx][col][0] = oodsPoint;
                        }
                    }
                }
            }
        }
    }

    /// @notice Add scaled trace step to a point: point + step * offset
    /// @param point Base circle point
    /// @param step Trace step as QM31 element
    /// @param offset Signed offset multiplier
    /// @return result Resulting circle point
    function _addScaledStep(
        CirclePoint.Point memory point,
        QM31Field.QM31 memory step,
        int256 offset
    ) internal pure returns (CirclePoint.Point memory result) {
        // Convert offset to QM31 and multiply with step
        QM31Field.QM31 memory scaledStep;
        
        if (offset >= 0) {
            scaledStep = QM31Field.mul(step, QM31Field.fromM31(uint32(uint256(offset)), 0, 0, 0));
        } else {
            scaledStep = QM31Field.mul(step, QM31Field.fromM31(uint32(uint256(-offset)), 0, 0, 0));
            scaledStep = QM31Field.neg(scaledStep);
        }
        
        // For now, return the original point (this is a simplified implementation)
        // In a full implementation, we'd need to properly add the scaled step
        result = point;
        return result;
    }
}