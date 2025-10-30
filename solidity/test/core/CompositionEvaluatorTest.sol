// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/CompositionEvaluator.sol";
import "../../contracts/core/CirclePoint.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/libraries/KeccakChannelLib.sol";

/// @title CompositionEvaluatorTest
/// @notice TDD tests for CompositionEvaluator contract
contract CompositionEvaluatorTest is Test {
    using QM31Field for QM31Field.QM31;
    using CirclePoint for CirclePoint.Point;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;

    CompositionEvaluator evaluator;
    CirclePoint.Point oodsPoint;
    QM31Field.QM31 randomCoeff;
    KeccakChannelLib.ChannelState channelState;

    function setUp() public {
        evaluator = new CompositionEvaluator();
        
        // Create test OODS point
        oodsPoint = CirclePoint.Point({
            x: QM31Field.QM31({
                first: CM31Field.CM31({real: 1000000000, imag: 2000000000}),
                second: CM31Field.CM31({real: 3000000000, imag: 400000000})
            }),
            y: QM31Field.QM31({
                first: CM31Field.CM31({real: 500000000, imag: 600000000}),
                second: CM31Field.CM31({real: 700000000, imag: 800000000})
            })
        });

        // Create test random coefficient
        randomCoeff = QM31Field.QM31({
            first: CM31Field.CM31({real: 12345, imag: 67890}),
            second: CM31Field.CM31({real: 11111, imag: 22222})
        });
    }

    /// @notice Test component addition
    function testAddAirComponent() public {
        uint256[] memory constraintDegrees = new uint256[](3);
        constraintDegrees[0] = 1;
        constraintDegrees[1] = 2;
        constraintDegrees[2] = 3;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        assertEq(evaluator.getComponentCount(), 1, "Should have 1 component");
        assertTrue(evaluator.isComponentEnabled(0), "Component should be enabled");
    }

    /// @notice Test component enable/disable
    function testComponentEnableDisable() public {
        uint256[] memory constraintDegrees = new uint256[](1);
        constraintDegrees[0] = 1;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        assertTrue(evaluator.isComponentEnabled(0), "Component should start enabled");

        evaluator.setComponentEnabled(0, false);
        assertFalse(evaluator.isComponentEnabled(0), "Component should be disabled");

        evaluator.setComponentEnabled(0, true);
        assertTrue(evaluator.isComponentEnabled(0), "Component should be re-enabled");
    }

    /// @notice Test composition polynomial evaluation with no components
    function testEvalCompositionPolynomialNoComponents() public {
        QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](0);

        QM31Field.QM31 memory result = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            randomCoeff
        );

        // Should return zero for no components
        assertEq(result.first.real, 0, "Result should be zero with no components");
    }

    /// @notice Test composition polynomial evaluation with single component
    function testEvalCompositionPolynomialSingleComponent() public {
        // Add a component
        uint256[] memory constraintDegrees = new uint256[](2);
        constraintDegrees[0] = 1;
        constraintDegrees[1] = 2;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        // Create test sampled values
        QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](3);
        sampledValues[0] = QM31Field.fromM31(100, 200, 300, 400);
        sampledValues[1] = QM31Field.fromM31(500, 600, 700, 800);
        sampledValues[2] = QM31Field.fromM31(900, 1000, 1100, 1200);

        QM31Field.QM31 memory result = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            randomCoeff
        );

        // Should return non-zero result
        assertTrue(
            result.first.real != 0 || result.first.imag != 0 || 
            result.second.real != 0 || result.second.imag != 0,
            "Result should be non-zero with valid component and sampled values"
        );

        console.log("Composition evaluation result:");
        console.log("  first.real:", result.first.real);
        console.log("  first.imag:", result.first.imag);
        console.log("  second.real:", result.second.real);
        console.log("  second.imag:", result.second.imag);
    }

    /// @notice Test full 3D sampled values evaluation
    function testEvalCompositionPolynomial3D() public {
        // Add multiple components
        uint256[] memory constraintDegrees1 = new uint256[](1);
        constraintDegrees1[0] = 1;
        uint256[] memory constraintDegrees2 = new uint256[](2);
        constraintDegrees2[0] = 1;
        constraintDegrees2[1] = 2;

        evaluator.addAirComponent(0, 8, constraintDegrees1);
        evaluator.addAirComponent(1, 10, constraintDegrees2);

        // Create 3D sampled values structure: [tree][column][values]
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](2);
        
        // Tree 0: 2 columns with different number of values
        sampledValues[0] = new QM31Field.QM31[][](2);
        sampledValues[0][0] = new QM31Field.QM31[](2);
        sampledValues[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
        sampledValues[0][0][1] = QM31Field.fromM31(150, 250, 350, 450);
        sampledValues[0][1] = new QM31Field.QM31[](1);
        sampledValues[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);

        // Tree 1: 1 column with 3 values
        sampledValues[1] = new QM31Field.QM31[][](1);
        sampledValues[1][0] = new QM31Field.QM31[](3);
        sampledValues[1][0][0] = QM31Field.fromM31(900, 1000, 1100, 1200);
        sampledValues[1][0][1] = QM31Field.fromM31(1300, 1400, 1500, 1600);
        sampledValues[1][0][2] = QM31Field.fromM31(1700, 1800, 1900, 2000);

        QM31Field.QM31 memory result = evaluator.evalCompositionPolynomialAtPoint(
            oodsPoint,
            sampledValues,
            randomCoeff
        );

        // Should return non-zero result
        assertTrue(
            result.first.real != 0 || result.first.imag != 0 || 
            result.second.real != 0 || result.second.imag != 0,
            "Result should be non-zero with multiple components"
        );

        console.log("3D evaluation result:");
        console.log("  first.real:", result.first.real);
        console.log("  first.imag:", result.first.imag);
        console.log("  second.real:", result.second.real);
        console.log("  second.imag:", result.second.imag);
    }

    /// @notice Test deterministic evaluation
    function testDeterministicEvaluation() public {
        uint256[] memory constraintDegrees = new uint256[](1);
        constraintDegrees[0] = 1;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](2);
        sampledValues[0] = QM31Field.fromM31(1111, 2222, 3333, 4444);
        sampledValues[1] = QM31Field.fromM31(5555, 6666, 7777, 8888);

        // Evaluate multiple times with same inputs
        QM31Field.QM31 memory result1 = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            randomCoeff
        );

        QM31Field.QM31 memory result2 = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            randomCoeff
        );

        // Results should be identical
        assertEq(result1.first.real, result2.first.real, "Results should be deterministic - first.real");
        assertEq(result1.first.imag, result2.first.imag, "Results should be deterministic - first.imag");
        assertEq(result1.second.real, result2.second.real, "Results should be deterministic - second.real");
        assertEq(result1.second.imag, result2.second.imag, "Results should be deterministic - second.imag");
    }

    /// @notice Test different random coefficients produce different results
    function testDifferentRandomCoefficients() public {
        uint256[] memory constraintDegrees = new uint256[](1);
        constraintDegrees[0] = 1;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](2);
        sampledValues[0] = QM31Field.fromM31(1111, 2222, 3333, 4444);
        sampledValues[1] = QM31Field.fromM31(5555, 6666, 7777, 8888);

        QM31Field.QM31 memory randomCoeff2 = QM31Field.fromM31(99999, 88888, 77777, 66666);

        QM31Field.QM31 memory result1 = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            randomCoeff
        );

        QM31Field.QM31 memory result2 = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            randomCoeff2
        );

        console.log("Random coeff 1 - first.real:", randomCoeff.first.real);
        console.log("Random coeff 2 - first.real:", randomCoeff2.first.real);
        console.log("Result 1 - first.real:", result1.first.real);
        console.log("Result 2 - first.real:", result2.first.real);

        // Results should be different
        bool isDifferent = (
            result1.first.real != result2.first.real ||
            result1.first.imag != result2.first.imag ||
            result1.second.real != result2.second.real ||
            result1.second.imag != result2.second.imag
        );

        assertTrue(isDifferent, "Different random coefficients should produce different results");
    }

    /// @notice Test edge cases
    function testEdgeCases() public {
        uint256[] memory constraintDegrees = new uint256[](1);
        constraintDegrees[0] = 1;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        // Test with empty sampled values
        QM31Field.QM31[] memory emptySampledValues = new QM31Field.QM31[](0);
        QM31Field.QM31 memory emptyResult = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            emptySampledValues,
            randomCoeff
        );

        console.log("Empty sampled values result:");
        console.log("  first.real:", emptyResult.first.real);

        // Test with zero OODS point
        CirclePoint.Point memory zeroPoint = CirclePoint.Point({
            x: QM31Field.zero(),
            y: QM31Field.zero()
        });

        QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](1);
        sampledValues[0] = QM31Field.fromM31(1000, 2000, 3000, 4000);

        QM31Field.QM31 memory zeroPointResult = evaluator.evalCompositionPolynomialSimple(
            zeroPoint,
            sampledValues,
            randomCoeff
        );

        console.log("Zero point result:");
        console.log("  first.real:", zeroPointResult.first.real);

        // Test with zero random coefficient
        QM31Field.QM31 memory zeroCoeff = QM31Field.zero();
        QM31Field.QM31 memory zeroCoeffResult = evaluator.evalCompositionPolynomialSimple(
            oodsPoint,
            sampledValues,
            zeroCoeff
        );

        console.log("Zero coefficient result:");
        console.log("  first.real:", zeroCoeffResult.first.real);
    }

    /// @notice Test with realistic OODS point from channel
    function testWithRealisticOODSPoint() public {
        // Initialize channel state (using storage variable)
        channelState.initialize();
        
        // Set up channel state
        bytes32 commitment = 0x7f3fb23a36bd8b85697aadc79cd031fab8fe3b65a557d923e8fd5d1879d02e13;
        uint32[] memory commitmentU32s = new uint32[](8);
        for (uint256 i = 0; i < 8; i++) {
            commitmentU32s[i] = uint32(uint256(commitment) >> (8 * (28 - i * 4)));
        }
        channelState.mixU32s(commitmentU32s);
        
        // Generate realistic OODS point and random coefficient
        CirclePoint.Point memory realisticOODS = CirclePoint.getRandomPointFromState(channelState);
        QM31Field.QM31 memory realisticRandomCoeff = channelState.drawSecureFelt();

        // Add component and test
        uint256[] memory constraintDegrees = new uint256[](2);
        constraintDegrees[0] = 1;
        constraintDegrees[1] = 2;

        evaluator.addAirComponent(0, 8, constraintDegrees);

        QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](4);
        sampledValues[0] = QM31Field.fromM31(1111, 2222, 3333, 4444);
        sampledValues[1] = QM31Field.fromM31(5555, 6666, 7777, 8888);
        sampledValues[2] = QM31Field.fromM31(9999, 1010, 1111, 1212);
        sampledValues[3] = QM31Field.fromM31(1313, 1414, 1515, 1616);

        QM31Field.QM31 memory result = evaluator.evalCompositionPolynomialSimple(
            realisticOODS,
            sampledValues,
            realisticRandomCoeff
        );

        console.log("Realistic evaluation result:");
        console.log("  first.real:", result.first.real);
        console.log("  first.imag:", result.first.imag);
        console.log("  second.real:", result.second.real);
        console.log("  second.imag:", result.second.imag);

        // Should work without reverting
        assertTrue(true, "Realistic evaluation should complete successfully");
    }

    /// @notice Test error conditions
    function testErrorConditions() public {
        uint256[] memory constraintDegrees = new uint256[](1);
        constraintDegrees[0] = 1;

        // Test invalid component index
        vm.expectRevert("Invalid component index");
        evaluator.setComponentEnabled(999, false);

        // Test too many constraints
        uint256[] memory tooManyConstraints = new uint256[](150);
        vm.expectRevert("Too many constraints");
        evaluator.addAirComponent(0, 8, tooManyConstraints);

        // Test invalid trace length
        vm.expectRevert("Invalid trace length");
        evaluator.addAirComponent(0, 0, constraintDegrees);

        // Test out of bounds component check
        assertFalse(evaluator.isComponentEnabled(999), "Non-existent component should be disabled");
    }

    /// @notice Test component count and management
    function testComponentManagement() public {
        assertEq(evaluator.getComponentCount(), 0, "Should start with 0 components");

        uint256[] memory constraintDegrees1 = new uint256[](1);
        constraintDegrees1[0] = 1;
        uint256[] memory constraintDegrees2 = new uint256[](2);
        constraintDegrees2[0] = 1;
        constraintDegrees2[1] = 2;

        evaluator.addAirComponent(0, 8, constraintDegrees1);
        assertEq(evaluator.getComponentCount(), 1, "Should have 1 component");

        evaluator.addAirComponent(1, 10, constraintDegrees2);
        assertEq(evaluator.getComponentCount(), 2, "Should have 2 components");

        assertTrue(evaluator.isComponentEnabled(0), "Component 0 should be enabled");
        assertTrue(evaluator.isComponentEnabled(1), "Component 1 should be enabled");
    }
}