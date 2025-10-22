// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/core/CirclePoint.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/channel/KeccakChannel.sol";

/// @title CirclePointTest
/// @notice TDD tests for CirclePoint library, comparing results with Rust implementation
contract CirclePointTest is Test {
    using CirclePoint for CirclePoint.Point;
    using QM31Field for QM31Field.QM31;
    
    // Deploy channel once for all tests
    KeccakChannel channel;
    
    function setUp() public {
        channel = new KeccakChannel();
    }

    /// @notice Test the zero element (identity) of circle group
    function testZero() public pure {
        CirclePoint.Point memory zeroPoint = CirclePoint.zero();
        
        // Identity element should be (1, 0)
        QM31Field.QM31 memory expectedX = QM31Field.one();
        QM31Field.QM31 memory expectedY = QM31Field.zero();
        
        assertEq(QM31Field.eq(zeroPoint.x, expectedX), true, "Zero point x should be 1");
        assertEq(QM31Field.eq(zeroPoint.y, expectedY), true, "Zero point y should be 0");
        
        // Should be on circle
        assertEq(CirclePoint.isOnCircle(zeroPoint), true, "Zero point should be on circle");
    }

    /// @notice Test point addition with identity
    function testAdditionWithIdentity() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        // Create test point (example coordinates)
        QM31Field.QM31 memory testX = QM31Field.fromReal(1000);
        QM31Field.QM31 memory testY = QM31Field.fromReal(500);
        CirclePoint.Point memory testPoint = CirclePoint.Point({x: testX, y: testY});
        
        // Adding identity should not change the point
        CirclePoint.Point memory result1 = CirclePoint.add(testPoint, zero);
        CirclePoint.Point memory result2 = CirclePoint.add(zero, testPoint);
        
        assertEq(QM31Field.eq(result1.x, testPoint.x), true, "Adding identity should preserve x");
        assertEq(QM31Field.eq(result1.y, testPoint.y), true, "Adding identity should preserve y");
        assertEq(QM31Field.eq(result2.x, testPoint.x), true, "Identity addition is commutative (x)");
        assertEq(QM31Field.eq(result2.y, testPoint.y), true, "Identity addition is commutative (y)");
    }

    /// @notice Test point doubling
    function testDoubling() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        // Doubling identity should give identity
        CirclePoint.Point memory doubledZero = CirclePoint.double(zero);
        assertEq(QM31Field.eq(doubledZero.x, zero.x), true, "Doubling identity x");
        assertEq(QM31Field.eq(doubledZero.y, zero.y), true, "Doubling identity y");
        
        // Test doubleX function with identity
        QM31Field.QM31 memory one = QM31Field.one();
        QM31Field.QM31 memory doubledX = CirclePoint.doubleX(one);
        // doubleX(1) = 2(1)² - 1 = 2 - 1 = 1
        assertEq(QM31Field.eq(doubledX, one), true, "doubleX(1) should be 1");
    }

    /// @notice Test conjugation
    function testConjugation() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        // Conjugate of (1, 0) should be (1, 0)
        CirclePoint.Point memory conjZero = CirclePoint.conjugate(zero);
        assertEq(QM31Field.eq(conjZero.x, zero.x), true, "Conjugate of zero x");
        assertEq(QM31Field.eq(conjZero.y, zero.y), true, "Conjugate of zero y");
        
        // Create point with non-zero y
        QM31Field.QM31 memory x = QM31Field.fromReal(123);
        QM31Field.QM31 memory y = QM31Field.fromReal(456);
        CirclePoint.Point memory point = CirclePoint.Point({x: x, y: y});
        
        CirclePoint.Point memory conjPoint = CirclePoint.conjugate(point);
        assertEq(QM31Field.eq(conjPoint.x, x), true, "Conjugate preserves x");
        assertEq(QM31Field.eq(conjPoint.y, QM31Field.neg(y)), true, "Conjugate negates y");
    }

    /// @notice Test negation (which is conjugation)
    function testNegation() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        // Negation of identity should be identity
        CirclePoint.Point memory negZero = CirclePoint.neg(zero);
        assertEq(QM31Field.eq(negZero.x, zero.x), true, "Negation of zero x");
        assertEq(QM31Field.eq(negZero.y, zero.y), true, "Negation of zero y");
        
        // Test that negation works as expected
        QM31Field.QM31 memory x = QM31Field.fromReal(789);
        QM31Field.QM31 memory y = QM31Field.fromReal(321);
        CirclePoint.Point memory point = CirclePoint.Point({x: x, y: y});
        
        CirclePoint.Point memory negPoint = CirclePoint.neg(point);
        
        // For circle group, negation is conjugation
        assertEq(QM31Field.eq(negPoint.x, point.x), true, "Negation preserves x");
        assertEq(QM31Field.eq(negPoint.y, QM31Field.neg(point.y)), true, "Negation negates y");
    }

    /// @notice Test subtraction
    function testSubtraction() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        QM31Field.QM31 memory x = QM31Field.fromReal(100);
        QM31Field.QM31 memory y = QM31Field.fromReal(200);
        CirclePoint.Point memory point = CirclePoint.Point({x: x, y: y});
        
        // p - 0 should be p  
        CirclePoint.Point memory pointMinusZero = CirclePoint.sub(point, zero);
        assertEq(QM31Field.eq(pointMinusZero.x, point.x), true, "p - 0 = p (x)");
        assertEq(QM31Field.eq(pointMinusZero.y, point.y), true, "p - 0 = p (y)");
        
        // 0 - p should be -p
        CirclePoint.Point memory zeroMinusPoint = CirclePoint.sub(zero, point);
        CirclePoint.Point memory negPoint = CirclePoint.neg(point);
        assertEq(QM31Field.eq(zeroMinusPoint.x, negPoint.x), true, "0 - p = -p (x)");
        assertEq(QM31Field.eq(zeroMinusPoint.y, negPoint.y), true, "0 - p = -p (y)");
    }

    /// @notice Test scalar multiplication
    function testScalarMultiplication() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        // 0 * point = zero
        QM31Field.QM31 memory x = QM31Field.fromReal(500);
        QM31Field.QM31 memory y = QM31Field.fromReal(300);
        CirclePoint.Point memory point = CirclePoint.Point({x: x, y: y});
        
        CirclePoint.Point memory zeroMul = CirclePoint.mul(point, 0);
        assertEq(QM31Field.eq(zeroMul.x, zero.x), true, "0 * p = 0 (x)");
        assertEq(QM31Field.eq(zeroMul.y, zero.y), true, "0 * p = 0 (y)");
        
        // 1 * point = point
        CirclePoint.Point memory oneMul = CirclePoint.mul(point, 1);
        assertEq(QM31Field.eq(oneMul.x, point.x), true, "1 * p = p (x)");
        assertEq(QM31Field.eq(oneMul.y, point.y), true, "1 * p = p (y)");
        
        // 2 * point = point + point
        CirclePoint.Point memory twoMul = CirclePoint.mul(point, 2);
        CirclePoint.Point memory doubleAdd = CirclePoint.add(point, point);
        assertEq(QM31Field.eq(twoMul.x, doubleAdd.x), true, "2 * p = p + p (x)");
        assertEq(QM31Field.eq(twoMul.y, doubleAdd.y), true, "2 * p = p + p (y)");
    }

    /// @notice Test isOnCircle validation
    function testIsOnCircle() public pure {
        // Identity should be on circle
        CirclePoint.Point memory zero = CirclePoint.zero();
        assertEq(CirclePoint.isOnCircle(zero), true, "Identity should be on circle");
        
        // Create a point that should be on circle: (1, 0) is on circle
        CirclePoint.Point memory pointOnCircle = CirclePoint.Point({
            x: QM31Field.one(),
            y: QM31Field.zero()
        });
        assertEq(CirclePoint.isOnCircle(pointOnCircle), true, "Point (1,0) should be on circle");
        
        // Create a point that's definitely not on circle
        CirclePoint.Point memory pointNotOnCircle = CirclePoint.Point({
            x: QM31Field.fromReal(2),  // 2² + 3² = 4 + 9 = 13 ≠ 1
            y: QM31Field.fromReal(3)
        });
        assertEq(CirclePoint.isOnCircle(pointNotOnCircle), false, "Point (2,3) should not be on circle");
    }

    /// @notice Test repeated doubling
    function testRepeatedDoubling() public pure {
        CirclePoint.Point memory zero = CirclePoint.zero();
        
        // Repeated doubling of identity should remain identity
        CirclePoint.Point memory result = CirclePoint.repeatedDouble(zero, 5);
        assertEq(QM31Field.eq(result.x, zero.x), true, "Repeated doubling of identity (x)");
        assertEq(QM31Field.eq(result.y, zero.y), true, "Repeated doubling of identity (y)");
        
        // Test that repeated doubling equals manual doubling
        QM31Field.QM31 memory x = QM31Field.fromReal(42);
        QM31Field.QM31 memory y = QM31Field.fromReal(17);
        CirclePoint.Point memory point = CirclePoint.Point({x: x, y: y});
        
        CirclePoint.Point memory repeated3 = CirclePoint.repeatedDouble(point, 3);
        CirclePoint.Point memory manual3 = CirclePoint.double(CirclePoint.double(CirclePoint.double(point)));
        
        assertEq(QM31Field.eq(repeated3.x, manual3.x), true, "Repeated doubling matches manual (x)");
        assertEq(QM31Field.eq(repeated3.y, manual3.y), true, "Repeated doubling matches manual (y)");
    }

    /// @notice Test getRandomPoint function
    function testGetRandomPoint() public {
        // Use pre-deployed channel from setUp()
        
        // Initialize channel with known seed for reproducible test
        channel.updateDigest(keccak256("test_seed_for_circle_point"));
        
        // Generate random point
        CirclePoint.Point memory randomPoint = CirclePoint.getRandomPoint(IChannel(address(channel)));
        
        // The random point should be on the circle
        assertEq(CirclePoint.isOnCircle(randomPoint), true, "Random point should be on circle");
        
        // Generate another point - should be different (with very high probability)
        channel.updateDigest(keccak256("different_seed"));
        CirclePoint.Point memory randomPoint2 = CirclePoint.getRandomPoint(IChannel(address(channel)));
        
        assertEq(CirclePoint.isOnCircle(randomPoint2), true, "Second random point should be on circle");
        
        // Points should be different (check x coordinates)
        bool areEqual = QM31Field.eq(randomPoint.x, randomPoint2.x) && QM31Field.eq(randomPoint.y, randomPoint2.y);
        assertEq(areEqual, false, "Different seeds should produce different points");
    }

    /// @notice Test deployment cost specifically
    function testDeploymentCost() public {
        KeccakChannel newChannel = new KeccakChannel();
        // Just deployment, nothing else
        assertTrue(address(newChannel) != address(0), "Channel should be deployed");
    }

    /// @notice Test compatibility with known Rust values
    /// @dev This test uses hardcoded values that should match Rust implementation
    function testRustCompatibility() public pure {
        // Test known case: doubleX with specific input
        // In Rust: CirclePoint::double_x(M31::from(12345))
        QM31Field.QM31 memory input = QM31Field.fromReal(12345);
        QM31Field.QM31 memory result = CirclePoint.doubleX(input);
        
        // Expected: 2 * 12345² - 1 = 2 * 152399025 - 1 = 304798049
        // But in M31 field (mod 2^31 - 1)
        uint256 expected = (2 * 12345 * 12345 - 1) % (2**31 - 1);
        QM31Field.QM31 memory expectedQM31 = QM31Field.fromReal(uint32(expected));
        
        assertEq(QM31Field.eq(result, expectedQM31), true, "doubleX should match Rust calculation");
    }

    /// @notice Test field extension operations
    function testFieldExtension() public pure {
        CirclePoint.Point memory point = CirclePoint.Point({
            x: QM31Field.fromReal(100),
            y: QM31Field.fromReal(200)
        });
        
        // Test intoEF (should be identity since already in extension field)
        CirclePoint.Point memory extendedPoint = CirclePoint.intoEF(point);
        assertEq(QM31Field.eq(extendedPoint.x, point.x), true, "intoEF preserves x");
        assertEq(QM31Field.eq(extendedPoint.y, point.y), true, "intoEF preserves y");
    }
}