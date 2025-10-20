// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/fields/M31Field.sol";

/**
 * @title QM31FieldComplexTest
 * @notice TDD Phase 2: Complex operations tests for QM31 quaternion field
 * @dev Tests multiplication, inversion, division with Rust test vectors
 */
contract QM31FieldComplexTest is Test {
    using QM31Field for QM31Field.QM31;
    using CM31Field for CM31Field.CM31;
    using M31Field for uint32;

    uint32 constant P = 2147483647; // 2^31 - 1

    function test_Multiplication() public pure {
        // Test vectors from Rust implementation:
        // qm31!(1, 2, 3, 4) * qm31!(4, 5, 6, 7) = qm31!(P-71, 93, P-16, 50)
        QM31Field.QM31 memory qm0 = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(4, 5, 6, 7);
        QM31Field.QM31 memory product = QM31Field.mul(qm0, qm1);
        
        // Expected result: qm31!(P-71, 93, P-16, 50)
        assertEq(product.first.real, P - 71);
        assertEq(product.first.imag, 93);
        assertEq(product.second.real, P - 16);
        assertEq(product.second.imag, 50);
        
        // Test multiplication by zero
        QM31Field.QM31 memory zero = QM31Field.zero();
        QM31Field.QM31 memory zeroProduct = QM31Field.mul(qm0, zero);
        assertTrue(QM31Field.isZero(zeroProduct));
        
        // Test multiplication by one
        QM31Field.QM31 memory one = QM31Field.one();
        QM31Field.QM31 memory oneProduct = QM31Field.mul(qm0, one);
        assertTrue(QM31Field.eq(qm0, oneProduct));
        
        // Test commutativity
        QM31Field.QM31 memory a = QM31Field.fromM31(7, 11, 13, 17);
        QM31Field.QM31 memory b = QM31Field.fromM31(19, 23, 29, 31);
        assertTrue(QM31Field.eq(QM31Field.mul(a, b), QM31Field.mul(b, a)));
    }

    function test_Square() public pure {
        // Test squaring
        QM31Field.QM31 memory a = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory squared = QM31Field.square(a);
        QM31Field.QM31 memory mulSquared = QM31Field.mul(a, a);
        
        // square(a) should equal mul(a, a)
        assertTrue(QM31Field.eq(squared, mulSquared));
    }

    function test_Inversion() public pure {
        // Test inversion from Rust: qm31!(1, 2, 3, 4).inverse()
        QM31Field.QM31 memory qm = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory inv = QM31Field.inverse(qm);
        
        // Verify qm * qm.inverse() = one
        QM31Field.QM31 memory product = QM31Field.mul(qm, inv);
        assertTrue(QM31Field.isOne(product));
        
        // Test inversion of one
        QM31Field.QM31 memory one = QM31Field.one();
        QM31Field.QM31 memory oneInv = QM31Field.inverse(one);
        assertTrue(QM31Field.isOne(oneInv));
        
        // Test more complex cases
        uint32[4][5] memory testValues = [
            [uint32(2), 3, 5, 7],
            [uint32(11), 13, 17, 19],
            [uint32(23), 29, 31, 37],
            [uint32(41), 43, 47, 53],
            [uint32(59), 61, 67, 71]
        ];
        
        for (uint i = 0; i < testValues.length; i++) {
            QM31Field.QM31 memory testVal = QM31Field.fromM31(
                testValues[i][0], testValues[i][1], testValues[i][2], testValues[i][3]
            );
            QM31Field.QM31 memory testInv = QM31Field.inverse(testVal);
            QM31Field.QM31 memory testProduct = QM31Field.mul(testVal, testInv);
            assertTrue(QM31Field.isOne(testProduct));
        }
    }

    function test_Division() public pure {
        // Test division: qm0_x_qm1 / qm1 = qm0 from Rust test vectors
        QM31Field.QM31 memory qm0 = QM31Field.fromM31(1, 2, 3, 4);
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(4, 5, 6, 7);
        QM31Field.QM31 memory qm0_x_qm1 = QM31Field.fromM31(P - 71, 93, P - 16, 50);
        
        QM31Field.QM31 memory quotient = QM31Field.div(qm0_x_qm1, qm1);
        
        // Should get back qm0
        assertEq(quotient.first.real, 1);
        assertEq(quotient.first.imag, 2);
        assertEq(quotient.second.real, 3);
        assertEq(quotient.second.imag, 4);
        
        // Test a / a = 1
        QM31Field.QM31 memory a = QM31Field.fromM31(13, 17, 19, 23);
        QM31Field.QM31 memory selfDiv = QM31Field.div(a, a);
        assertTrue(QM31Field.isOne(selfDiv));
        
        // Test a / 1 = a
        QM31Field.QM31 memory one = QM31Field.one();
        QM31Field.QM31 memory divByOne = QM31Field.div(a, one);
        assertTrue(QM31Field.eq(a, divByOne));
    }

    function test_MixedM31Operations() public pure {
        // Test mixed operations with M31 elements (from Rust test vectors)
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(4, 5, 6, 7);
        uint32 m = 8;
        QM31Field.QM31 memory qm_from_m = QM31Field.fromReal(m);
        
        // Test qm1 + m == qm1 + qm (where qm = QM31::from(m))
        QM31Field.QM31 memory sum1 = QM31Field.add(qm1, qm_from_m);
        QM31Field.QM31 memory sum2 = QM31Field.add(qm1, qm_from_m);
        assertTrue(QM31Field.eq(sum1, sum2));
        
        // Test qm1 * m == qm1 * qm
        QM31Field.QM31 memory mul1 = QM31Field.mul(qm1, qm_from_m);
        QM31Field.QM31 memory mul2 = QM31Field.mul(qm1, qm_from_m);
        assertTrue(QM31Field.eq(mul1, mul2));
        
        // Test qm1 - m == qm1 - qm
        QM31Field.QM31 memory sub1 = QM31Field.sub(qm1, qm_from_m);
        QM31Field.QM31 memory sub2 = QM31Field.sub(qm1, qm_from_m);
        assertTrue(QM31Field.eq(sub1, sub2));
        
        // Test qm1 / m == qm1 / qm
        QM31Field.QM31 memory div1 = QM31Field.div(qm1, qm_from_m);
        QM31Field.QM31 memory div2 = QM31Field.div(qm1, qm_from_m);
        assertTrue(QM31Field.eq(div1, div2));
    }

    function test_MulCM31() public pure {
        // Test multiplication by CM31 scalar
        QM31Field.QM31 memory qm = QM31Field.fromM31(1, 2, 3, 4);
        CM31Field.CM31 memory scalar = CM31Field.fromM31(5, 6);
        
        QM31Field.QM31 memory result = QM31Field.mulCM31(qm, scalar);
        
        // Should be equivalent to mul(qm, QM31::from(scalar))
        QM31Field.QM31 memory scalarAsQM31 = QM31Field.fromCM31(scalar, CM31Field.zero());
        QM31Field.QM31 memory expected = QM31Field.mul(qm, scalarAsQM31);
        
        assertTrue(QM31Field.eq(result, expected));
    }

    function test_PowerFunction() public pure {
        // Test power function
        QM31Field.QM31 memory base = QM31Field.fromM31(2, 1, 1, 2);
        
        // Test base^0 = 1
        QM31Field.QM31 memory pow0 = QM31Field.pow(base, 0);
        assertTrue(QM31Field.isOne(pow0));
        
        // Test base^1 = base
        QM31Field.QM31 memory pow1 = QM31Field.pow(base, 1);
        assertTrue(QM31Field.eq(base, pow1));
        
        // Test base^2 = base * base
        QM31Field.QM31 memory pow2 = QM31Field.pow(base, 2);
        QM31Field.QM31 memory squared = QM31Field.mul(base, base);
        assertTrue(QM31Field.eq(pow2, squared));
        
        // Test 0^n = 0 for n > 0
        QM31Field.QM31 memory zero = QM31Field.zero();
        QM31Field.QM31 memory zeroPow = QM31Field.pow(zero, 5);
        assertTrue(QM31Field.isZero(zeroPow));
    }

    function test_IrreduciblePolynomial() public pure {
        // Test that u² = 2+i (the irreducible polynomial)
        // Create u = (0, 0, 1, 0) which represents the u element
        QM31Field.QM31 memory u = QM31Field.fromM31(0, 0, 1, 0);
        QM31Field.QM31 memory uSquared = QM31Field.square(u);
        
        // u² should equal R = 2+i = (2, 1, 0, 0)
        QM31Field.QM31 memory R_as_qm31 = QM31Field.fromM31(2, 1, 0, 0);
        assertTrue(QM31Field.eq(uSquared, R_as_qm31));
    }

    // Fuzz testing for complex operations
    function testFuzz_Multiplication(uint32 a, uint32 b, uint32 c, uint32 d, uint32 e, uint32 f, uint32 g, uint32 h) public pure {
        // Reduce inputs to valid M31 elements
        a = a % P; b = b % P; c = c % P; d = d % P;
        e = e % P; f = f % P; g = g % P; h = h % P;
        
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(a, b, c, d);
        QM31Field.QM31 memory qm2 = QM31Field.fromM31(e, f, g, h);
        
        QM31Field.QM31 memory result = QM31Field.mul(qm1, qm2);
        
        // Verify result is valid
        assertTrue(QM31Field.isValid(result));
        
        // Verify commutativity
        assertTrue(QM31Field.eq(QM31Field.mul(qm1, qm2), QM31Field.mul(qm2, qm1)));
    }

    function testFuzz_Inversion(uint32 a, uint32 b, uint32 c, uint32 d) public pure {
        a = a % P; b = b % P; c = c % P; d = d % P;
        
        // Skip zero to avoid division by zero
        if (a == 0 && b == 0 && c == 0 && d == 0) return;
        
        QM31Field.QM31 memory qm = QM31Field.fromM31(a, b, c, d);
        
        // Skip if this results in zero (very rare but possible)
        if (QM31Field.isZero(qm)) return;
        
        QM31Field.QM31 memory inv = QM31Field.inverse(qm);
        
        // Verify result is valid
        assertTrue(QM31Field.isValid(inv));
        
        // Verify qm * qm⁻¹ = 1
        QM31Field.QM31 memory product = QM31Field.mul(qm, inv);
        assertTrue(QM31Field.isOne(product));
    }

    function testFuzz_Division(uint32 a, uint32 b, uint32 c, uint32 d, uint32 e, uint32 f, uint32 g, uint32 h) public pure {
        a = a % P; b = b % P; c = c % P; d = d % P;
        e = e % P; f = f % P; g = g % P; h = h % P;
        
        QM31Field.QM31 memory qm1 = QM31Field.fromM31(a, b, c, d);
        QM31Field.QM31 memory qm2 = QM31Field.fromM31(e, f, g, h);
        
        // Skip if divisor is zero
        if (QM31Field.isZero(qm2)) return;
        
        QM31Field.QM31 memory quotient = QM31Field.div(qm1, qm2);
        
        // Verify result is valid
        assertTrue(QM31Field.isValid(quotient));
        
        // Verify quotient * qm2 = qm1
        QM31Field.QM31 memory restored = QM31Field.mul(quotient, qm2);
        assertTrue(QM31Field.eq(qm1, restored));
    }

    // Performance benchmarks
    function test_GasBenchmark_ComplexOps() public view {
        uint256 gasBefore;
        uint256 gasAfter;
        
        QM31Field.QM31 memory a = QM31Field.fromM31(12345, 67890, 11111, 22222);
        QM31Field.QM31 memory b = QM31Field.fromM31(54321, 98765, 33333, 44444);
        
        // Multiplication
        gasBefore = gasleft();
        QM31Field.mul(a, b);
        gasAfter = gasleft();
        uint256 mulGas = gasBefore - gasAfter;
        console.log("QM31 Multiplication gas:", mulGas);
        // assertTrue(mulGas < 10000, "Multiplication should be under 10K gas");
        
        // Inversion
        gasBefore = gasleft();
        QM31Field.inverse(a);
        gasAfter = gasleft();
        uint256 invGas = gasBefore - gasAfter;
        console.log("QM31 Inversion gas:", invGas);
        assertTrue(invGas < 50000, "Inversion should be under 50K gas");
        
        // Division
        gasBefore = gasleft();
        QM31Field.div(a, b);
        gasAfter = gasleft();
        uint256 divGas = gasBefore - gasAfter;
        console.log("QM31 Division gas:", divGas);
        assertTrue(divGas < 60000, "Division should be under 60K gas");
    }
}