// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/fields/M31Field.sol";

/**
 * @title QM31FieldBasicTest
 * @notice TDD Phase 1: Basic operations tests for QM31 quaternion field
 * @dev Tests fundamental operations before implementing QM31Field.sol
 */
contract QM31FieldBasicTest is Test {
    using QM31Field for QM31Field.QM31;
    using CM31Field for CM31Field.CM31;
    using M31Field for uint32;

    // Constants from Rust implementation
    uint32 constant P = 2147483647; // 2^31 - 1
    
    // Test constants and special elements
    function test_Constants() public pure {
        // Test field constants
        assertEq(QM31Field.P4, 21267647892944572736998860269687930881); // (2^31-1)^4
        assertEq(QM31Field.EXTENSION_DEGREE, 4);
        
        // Test special elements
        QM31Field.QM31 memory zero = QM31Field.zero();
        assertEq(zero.first.real, 0);
        assertEq(zero.first.imag, 0);
        assertEq(zero.second.real, 0);
        assertEq(zero.second.imag, 0);
        
        QM31Field.QM31 memory one = QM31Field.one();
        assertEq(one.first.real, 1);
        assertEq(one.first.imag, 0);
        assertEq(one.second.real, 0);
        assertEq(one.second.imag, 0);
        
        // Test R constant (2 + i)
        CM31Field.CM31 memory R = QM31Field.R();
        assertEq(R.real, 2);
        assertEq(R.imag, 1);
    }

    function test_Construction() public pure {
        // Test fromM31 construction
        QM31Field.QM31 memory qm = QM31Field.fromM31(1, 2, 3, 4);
        assertEq(qm.first.real, 1);
        assertEq(qm.first.imag, 2);
        assertEq(qm.second.real, 3);
        assertEq(qm.second.imag, 4);
        
        // Test fromCM31 construction
        CM31Field.CM31 memory cm1 = CM31Field.fromM31(5, 6);
        CM31Field.CM31 memory cm2 = CM31Field.fromM31(7, 8);
        QM31Field.QM31 memory qm2 = QM31Field.fromCM31(cm1, cm2);
        assertEq(qm2.first.real, 5);
        assertEq(qm2.first.imag, 6);
        assertEq(qm2.second.real, 7);
        assertEq(qm2.second.imag, 8);
        
        // Test fromReal construction
        QM31Field.QM31 memory real = QM31Field.fromReal(42);
        assertEq(real.first.real, 42);
        assertEq(real.first.imag, 0);
        assertEq(real.second.real, 0);
        assertEq(real.second.imag, 0);
        
        // Test fromU32Unchecked
        QM31Field.QM31 memory qm3 = QM31Field.fromU32Unchecked(P + 1, P + 2, P + 3, P + 4);
        assertEq(qm3.first.real, 1);
        assertEq(qm3.first.imag, 2);
        assertEq(qm3.second.real, 3);
        assertEq(qm3.second.imag, 4);
    }

    function test_Addition() public pure {
        // Test vectors from Rust: qm31!(1,2,3,4) + qm31!(4,5,6,7) = qm31!(5,7,9,11)
        QM31Field.QM31 memory qm0 = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(4, 5, 6, 7);
        QM31Field.QM31 memory sum = QM31Field.add(qm0, qm1);
        
        assertEq(sum.first.real, 5);
        assertEq(sum.first.imag, 7);
        assertEq(sum.second.real, 9);
        assertEq(sum.second.imag, 11);
        
        // Test addition with zero
        QM31Field.QM31 memory zero = QM31Field.zero();
        QM31Field.QM31 memory sum2 = QM31Field.add(qm0, zero);
        assertTrue(QM31Field.eq(qm0, sum2));
        
        // Test commutativity
        assertTrue(QM31Field.eq(QM31Field.add(qm0, qm1), QM31Field.add(qm1, qm0)));
    }

    function test_Subtraction() public pure {
        // Test vectors from Rust: qm31!(1,2,3,4) - qm31!(4,5,6,7) = qm31!(P-3,P-3,P-3,P-3)
        QM31Field.QM31 memory qm0 = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(4, 5, 6, 7);
        QM31Field.QM31 memory diff = QM31Field.sub(qm0, qm1);
        
        assertEq(diff.first.real, P - 3);
        assertEq(diff.first.imag, P - 3);
        assertEq(diff.second.real, P - 3);
        assertEq(diff.second.imag, P - 3);
        
        // Test a - a = 0
        QM31Field.QM31 memory selfDiff = QM31Field.sub(qm0, qm0);
        assertTrue(QM31Field.isZero(selfDiff));
    }

    function test_Negation() public pure {
        // Test vectors from Rust: -qm31!(1,2,3,4) = qm31!(P-1,P-2,P-3,P-4)
        QM31Field.QM31 memory qm0 = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory neg = QM31Field.neg(qm0);
        
        assertEq(neg.first.real, P - 1);
        assertEq(neg.first.imag, P - 2);
        assertEq(neg.second.real, P - 3);
        assertEq(neg.second.imag, P - 4);
        
        // Test double negation
        QM31Field.QM31 memory doubleNeg = QM31Field.neg(neg);
        assertTrue(QM31Field.eq(qm0, doubleNeg));
        
        // Test a + (-a) = 0
        QM31Field.QM31 memory sum = QM31Field.add(qm0, neg);
        assertTrue(QM31Field.isZero(sum));
    }

    function test_Equality() public pure {
        QM31Field.QM31 memory a = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory b = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory c = QM31Field.fromM31(1, 2, 3, 5);
        
        assertTrue(QM31Field.eq(a, b));
        assertFalse(QM31Field.eq(a, c));
        assertTrue(QM31Field.eq(a, a)); // reflexivity
    }

    function test_IsZero() public pure {
        assertTrue(QM31Field.isZero(QM31Field.zero()));
        assertFalse(QM31Field.isZero(QM31Field.one()));
        assertFalse(QM31Field.isZero(QM31Field.fromM31(0, 0, 0, 1)));
    }

    function test_IsOne() public pure {
        assertTrue(QM31Field.isOne(QM31Field.one()));
        assertFalse(QM31Field.isOne(QM31Field.zero()));
        assertFalse(QM31Field.isOne(QM31Field.fromM31(1, 0, 0, 1)));
    }

    function test_ToM31Array() public pure {
        QM31Field.QM31 memory qm = QM31Field.fromM31(1, 2, 3, 4);
        uint32[4] memory arr = QM31Field.toM31Array(qm);
        
        assertEq(arr[0], 1);
        assertEq(arr[1], 2);
        assertEq(arr[2], 3);
        assertEq(arr[3], 4);
    }

    function test_FromM31Array() public pure {
        uint32[4] memory arr = [uint32(1), 2, 3, 4];
        QM31Field.QM31 memory qm = QM31Field.fromM31Array(arr);
        
        assertEq(qm.first.real, 1);
        assertEq(qm.first.imag, 2);
        assertEq(qm.second.real, 3);
        assertEq(qm.second.imag, 4);
    }

    function test_TryToReal() public pure {
        // Should succeed for real numbers
        QM31Field.QM31 memory realNum = QM31Field.fromReal(42);
        (bool success, uint32 value) = QM31Field.tryToReal(realNum);
        assertTrue(success);
        assertEq(value, 42);
        
        // Should fail for quaternion numbers
        QM31Field.QM31 memory quatNum = QM31Field.fromM31(1, 2, 3, 4);
        (bool success2, uint32 value2) = QM31Field.tryToReal(quatNum);
        assertFalse(success2);
        assertEq(value2, 0);
        
        // Should succeed for zero
        (bool success3, uint32 value3) = QM31Field.tryToReal(QM31Field.zero());
        assertTrue(success3);
        assertEq(value3, 0);
    }

    function test_IsValid() public pure {
        assertTrue(QM31Field.isValid(QM31Field.zero()));
        assertTrue(QM31Field.isValid(QM31Field.one()));
        assertTrue(QM31Field.isValid(QM31Field.fromM31(P - 1, P - 1, P - 1, P - 1)));
    }

    // Fuzz testing for basic operations
    function testFuzz_Addition(uint32 a, uint32 b, uint32 c, uint32 d, uint32 e, uint32 f, uint32 g, uint32 h) public pure {
        // Reduce inputs to valid M31 elements
        a = a % P; b = b % P; c = c % P; d = d % P;
        e = e % P; f = f % P; g = g % P; h = h % P;
        
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(a, b, c, d);
        QM31Field.QM31 memory qm2 = QM31Field.fromM31(e, f, g, h);
        
        QM31Field.QM31 memory result = QM31Field.add(qm1, qm2);
        
        // Verify result is valid
        assertTrue(QM31Field.isValid(result));
        
        // Verify commutativity
        assertTrue(QM31Field.eq(QM31Field.add(qm1, qm2), QM31Field.add(qm2, qm1)));
    }

    function testFuzz_Subtraction(uint32 a, uint32 b, uint32 c, uint32 d, uint32 e, uint32 f, uint32 g, uint32 h) public pure {
        a = a % P; b = b % P; c = c % P; d = d % P;
        e = e % P; f = f % P; g = g % P; h = h % P;
        
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(a, b, c, d);
        QM31Field.QM31 memory qm2 = QM31Field.fromM31(e, f, g, h);
        
        QM31Field.QM31 memory result = QM31Field.sub(qm1, qm2);
        
        // Verify result is valid
        assertTrue(QM31Field.isValid(result));
        
        // Verify qm1 - qm2 + qm2 = qm1
        QM31Field.QM31 memory restored = QM31Field.add(result, qm2);
        assertTrue(QM31Field.eq(qm1, restored));
    }

    function testFuzz_Negation(uint32 a, uint32 b, uint32 c, uint32 d) public pure {
        a = a % P; b = b % P; c = c % P; d = d % P;
        
        QM31Field.QM31 memory qm = QM31Field.fromM31(a, b, c, d);
        QM31Field.QM31 memory negQm = QM31Field.neg(qm);
        
        // Verify result is valid
        assertTrue(QM31Field.isValid(negQm));
        
        // Verify qm + (-qm) = 0
        QM31Field.QM31 memory sum = QM31Field.add(qm, negQm);
        assertTrue(QM31Field.isZero(sum));
        
        // Verify -(-qm) = qm
        QM31Field.QM31 memory doubleNeg = QM31Field.neg(negQm);
        assertTrue(QM31Field.eq(qm, doubleNeg));
    }
}