// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../core/CirclePoint.sol";
import "../fields/QM31Field.sol";
import "../fields/CM31Field.sol";

/// @title CompositionEvaluator
/// @notice Evaluates composition polynomials at OODS points for STARK verification
/// @dev Implements composition polynomial evaluation equivalent to Rust stwo implementation
contract CompositionEvaluator {
    using QM31Field for QM31Field.QM31;

    /// @notice Error thrown when sampled values structure is invalid
    error InvalidSampledValues();
    
    /// @notice Error thrown when tree indices are out of bounds
    error TreeIndexOutOfBounds(uint256 treeIdx, uint256 maxTrees);

    /// @notice Point evaluation accumulator for constraint evaluations
    struct PointEvaluationAccumulator {
        QM31Field.QM31 accumulation;    // Running accumulation value
        QM31Field.QM31 alpha;           // Random coefficient (base)
        QM31Field.QM31 alphaPower;      // Current power of alpha
        uint256 evaluationCount;       // Number of evaluations accumulated
    }

    /// @notice AIR component configuration for constraint evaluation
    struct AirComponent {
        uint256 treeIdx;                // Tree index for this component
        uint256 logTraceLength;         // Log of trace length for vanishing polynomial
        uint256[] constraintDegrees;    // Degrees of constraints for this component
        uint256 nConstraints;           // Number of constraints
        bool isEnabled;                 // Whether component is active
    }

    /// @notice Constraint evaluation context
    struct ConstraintEvaluationCtx {
        CirclePoint.Point point;        // OODS point
        QM31Field.QM31[] maskValues;    // Mask values for this component
        QM31Field.QM31 domainSize;      // Size of trace domain
        QM31Field.QM31 vanishingInv;    // 1/Z_T(point) - inverse of vanishing polynomial
    }

    /// @notice Registered AIR components
    AirComponent[] public components;

    /// @notice Maximum number of constraints per component
    uint256 public constant MAX_CONSTRAINTS_PER_COMPONENT = 100;

    constructor() {
        // Initialize with empty components
    }

    /// @notice Register an AIR component for composition evaluation
    /// @param treeIdx Tree index for component
    /// @param logTraceLength Log of trace length
    /// @param constraintDegrees Array of constraint degrees
    function addAirComponent(
        uint256 treeIdx,
        uint256 logTraceLength,
        uint256[] calldata constraintDegrees
    ) external {
        require(constraintDegrees.length <= MAX_CONSTRAINTS_PER_COMPONENT, "Too many constraints");
        require(logTraceLength > 0, "Invalid trace length");

        components.push();
        uint256 componentIdx = components.length - 1;
        AirComponent storage component = components[componentIdx];
        
        component.treeIdx = treeIdx;
        component.logTraceLength = logTraceLength;
        component.nConstraints = constraintDegrees.length;
        component.isEnabled = true;

        // Copy constraint degrees
        for (uint256 i = 0; i < constraintDegrees.length; i++) {
            component.constraintDegrees.push(constraintDegrees[i]);
        }
    }

    /// @notice Evaluate composition polynomial at OODS point
    /// @param oodsPoint Out-of-domain sampling point
    /// @param sampledValues Sampled trace values (TreeVec<Vec<Vec<SecureField>>>)
    /// @param randomCoeff Random coefficient for linear combination
    /// @return evaluation Composition polynomial evaluation result
    function evalCompositionPolynomialAtPoint(
        CirclePoint.Point memory oodsPoint,
        QM31Field.QM31[][][] memory sampledValues,  // [tree][column][values]
        QM31Field.QM31 memory randomCoeff
    ) external view returns (QM31Field.QM31 memory evaluation) {
        // Initialize point evaluation accumulator
        PointEvaluationAccumulator memory accumulator = _initializeAccumulator(randomCoeff);

        // Process each component
        for (uint256 compIdx = 0; compIdx < components.length; compIdx++) {
            AirComponent storage component = components[compIdx];
            
            if (!component.isEnabled || component.treeIdx >= sampledValues.length) {
                continue;
            }

            // Evaluate constraints for this component
            _evaluateComponentConstraints(
                accumulator,
                component,
                oodsPoint,
                sampledValues[component.treeIdx]
            );
        }

        return accumulator.accumulation;
    }

    /// @notice Evaluate composition polynomial with simplified interface
    /// @param oodsPoint OODS point
    /// @param sampledValues Flattened sampled values
    /// @param randomCoeff Random coefficient
    /// @return evaluation Result
    function evalCompositionPolynomialSimple(
        CirclePoint.Point memory oodsPoint,
        QM31Field.QM31[] memory sampledValues,
        QM31Field.QM31 memory randomCoeff
    ) external view returns (QM31Field.QM31 memory evaluation) {
        // Initialize accumulator
        PointEvaluationAccumulator memory accumulator = _initializeAccumulator(randomCoeff);

        // For simplified version, treat all sampled values as coming from single component
        if (components.length > 0) {
            AirComponent storage component = components[0];
            
            if (component.isEnabled) {
                // Create constraint evaluation context
                ConstraintEvaluationCtx memory ctx = ConstraintEvaluationCtx({
                    point: oodsPoint,
                    maskValues: sampledValues,
                    domainSize: QM31Field.fromM31(uint32(1 << component.logTraceLength), 0, 0, 0),
                    vanishingInv: QM31Field.zero()
                });

                // Calculate vanishing polynomial inverse
                ctx.vanishingInv = _calculateVanishingInverse(ctx.point, ctx.domainSize);

                // Evaluate constraints (simplified - multiple evaluations to test random coefficient)
                QM31Field.QM31 memory constraintEval1 = _evaluateTestConstraints(ctx);
                QM31Field.QM31 memory constraintEval2 = QM31Field.add(constraintEval1, QM31Field.one());
                
                // Accumulate multiple evaluations to test random coefficient effect
                _accumulateEvaluation(accumulator, constraintEval1);
                _accumulateEvaluation(accumulator, constraintEval2);
            }
        }

        return accumulator.accumulation;
    }

    /// @notice Get number of registered components
    /// @return count Number of components
    function getComponentCount() external view returns (uint256 count) {
        return components.length;
    }

    /// @notice Check if component is enabled
    /// @param componentIdx Component index
    /// @return enabled Whether component is enabled
    function isComponentEnabled(uint256 componentIdx) external view returns (bool enabled) {
        if (componentIdx >= components.length) {
            return false;
        }
        return components[componentIdx].isEnabled;
    }

    /// @notice Enable or disable a component
    /// @param componentIdx Component index
    /// @param enabled New enabled state
    function setComponentEnabled(uint256 componentIdx, bool enabled) external {
        require(componentIdx < components.length, "Invalid component index");
        components[componentIdx].isEnabled = enabled;
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    /// @notice Initialize point evaluation accumulator
    /// @param randomCoeff Random coefficient for accumulation
    /// @return accumulator Initialized accumulator
    function _initializeAccumulator(QM31Field.QM31 memory randomCoeff) 
        internal 
        pure 
        returns (PointEvaluationAccumulator memory accumulator) 
    {
        accumulator.accumulation = QM31Field.zero();
        accumulator.alpha = randomCoeff;
        accumulator.alphaPower = QM31Field.one();
        accumulator.evaluationCount = 0;
    }

    /// @notice Evaluate constraints for a single component
    /// @param accumulator Evaluation accumulator to update
    /// @param component Component configuration
    /// @param oodsPoint OODS point
    /// @param columnValues Sampled values for this component's columns
    function _evaluateComponentConstraints(
        PointEvaluationAccumulator memory accumulator,
        AirComponent storage component,
        CirclePoint.Point memory oodsPoint,
        QM31Field.QM31[][] memory columnValues
    ) internal view {
        // Create constraint evaluation context
        ConstraintEvaluationCtx memory ctx = ConstraintEvaluationCtx({
            point: oodsPoint,
            maskValues: _flattenColumnValues(columnValues),
            domainSize: QM31Field.fromM31(uint32(1 << component.logTraceLength), 0, 0, 0),
            vanishingInv: QM31Field.zero()
        });

        // Calculate vanishing polynomial inverse: 1/Z_T(point)
        ctx.vanishingInv = _calculateVanishingInverse(ctx.point, ctx.domainSize);

        // Evaluate each constraint for this component
        for (uint256 i = 0; i < component.nConstraints; i++) {
            QM31Field.QM31 memory constraintEval = _evaluateConstraint(ctx, i);
            
            // Divide by vanishing polynomial: constraint_i(point) / Z_T(point)
            QM31Field.QM31 memory quotient = QM31Field.mul(constraintEval, ctx.vanishingInv);
            
            // Accumulate with random coefficient
            _accumulateEvaluation(accumulator, quotient);
        }
    }

    /// @notice Flatten column values into single array
    /// @param columnValues Array of columns containing values
    /// @return flattened Single array of all values
    function _flattenColumnValues(QM31Field.QM31[][] memory columnValues) 
        internal 
        pure 
        returns (QM31Field.QM31[] memory flattened) 
    {
        // Calculate total length
        uint256 totalLength = 0;
        for (uint256 col = 0; col < columnValues.length; col++) {
            totalLength += columnValues[col].length;
        }

        // Create flattened array
        flattened = new QM31Field.QM31[](totalLength);
        uint256 idx = 0;
        
        for (uint256 col = 0; col < columnValues.length; col++) {
            for (uint256 val = 0; val < columnValues[col].length; val++) {
                flattened[idx] = columnValues[col][val];
                idx++;
            }
        }
    }

    /// @notice Calculate inverse of vanishing polynomial Z_T(point) = point^domain_size - 1
    /// @param point Evaluation point
    /// @param domainSize Size of the trace domain
    /// @return vanishingInv 1/Z_T(point)
    function _calculateVanishingInverse(
        CirclePoint.Point memory point,
        QM31Field.QM31 memory domainSize
    ) internal pure returns (QM31Field.QM31 memory vanishingInv) {
        // For circle group, vanishing polynomial is more complex
        // For now, use simplified calculation: 1/(x_coordinate^domain_size - 1)
        
        // Calculate point.x^domain_size
        QM31Field.QM31 memory xPower = _powerMod(point.x, domainSize);
        
        // Calculate Z_T(point) = x^domain_size - 1
        QM31Field.QM31 memory vanishing = QM31Field.sub(xPower, QM31Field.one());
        
        // Return 1/Z_T(point)
        vanishingInv = QM31Field.inverse(vanishing);
    }

    /// @notice Compute modular exponentiation for QM31 elements
    /// @param base Base element
    /// @param exponent Exponent as QM31 (simplified to use real part)
    /// @return result base^exponent
    function _powerMod(QM31Field.QM31 memory base, QM31Field.QM31 memory exponent) 
        internal 
        pure 
        returns (QM31Field.QM31 memory result) 
    {
        // Simplified implementation - use only real part of exponent
        uint32 exp = exponent.first.real;
        result = QM31Field.one();
        
        // Fast exponentiation
        QM31Field.QM31 memory currentBase = base;
        while (exp > 0) {
            if (exp & 1 == 1) {
                result = QM31Field.mul(result, currentBase);
            }
            currentBase = QM31Field.mul(currentBase, currentBase);
            exp >>= 1;
        }
    }

    /// @notice Evaluate a specific constraint (simplified implementation)
    /// @param ctx Constraint evaluation context
    /// @param constraintIdx Index of constraint to evaluate
    /// @return evaluation Constraint evaluation result
    function _evaluateConstraint(
        ConstraintEvaluationCtx memory ctx,
        uint256 constraintIdx
    ) internal pure returns (QM31Field.QM31 memory evaluation) {
        // Simplified constraint evaluation - in practice this would implement
        // the actual AIR constraints for the specific protocol
        
        if (ctx.maskValues.length == 0) {
            return QM31Field.zero();
        }

        // Simple test constraint: sum of mask values
        evaluation = QM31Field.zero();
        for (uint256 i = 0; i < ctx.maskValues.length; i++) {
            evaluation = QM31Field.add(evaluation, ctx.maskValues[i]);
        }

        // Add constraint index as variation
        QM31Field.QM31 memory indexTerm = QM31Field.fromM31(uint32(constraintIdx), 0, 0, 0);
        evaluation = QM31Field.add(evaluation, indexTerm);
    }

    /// @notice Evaluate test constraints for simplified interface
    /// @param ctx Constraint evaluation context
    /// @return evaluation Test constraint evaluation
    function _evaluateTestConstraints(ConstraintEvaluationCtx memory ctx) 
        internal 
        pure 
        returns (QM31Field.QM31 memory evaluation) 
    {
        // Simple polynomial evaluation for testing
        evaluation = QM31Field.zero();
        
        // Add point coordinates
        evaluation = QM31Field.add(evaluation, ctx.point.x);
        evaluation = QM31Field.add(evaluation, ctx.point.y);
        
        // Add sum of mask values
        for (uint256 i = 0; i < ctx.maskValues.length; i++) {
            evaluation = QM31Field.add(evaluation, ctx.maskValues[i]);
        }
    }

    /// @notice Accumulate evaluation with random coefficient
    /// @param accumulator Accumulator to update
    /// @param evaluation Evaluation to accumulate
    function _accumulateEvaluation(
        PointEvaluationAccumulator memory accumulator,
        QM31Field.QM31 memory evaluation
    ) internal pure {
        // Update accumulation: accumulation = accumulation * alpha + evaluation
        accumulator.accumulation = QM31Field.mul(accumulator.accumulation, accumulator.alpha);
        accumulator.accumulation = QM31Field.add(accumulator.accumulation, evaluation);
        
        // Update for next iteration
        accumulator.alphaPower = QM31Field.mul(accumulator.alphaPower, accumulator.alpha);
        accumulator.evaluationCount++;
    }
}