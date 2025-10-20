// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/fields/CM31FieldWrapper.sol";
import "forge-std/console.sol";

/**
 * @title CM31FieldComplexTest
 * @notice Phase 2: Complex operations tests for CM31 complex field
 * @dev Tests multiplication, inversion, division, conjugation, norm, and scalar operations
 */
contract CM31FieldComplexTest is Test {
    using CM31Field for CM31Field.CM31;

    CM31FieldWrapper wrapper;

    // Constants from M31 field
    uint32 constant P = 2147483647; // 2^31 - 1

    function setUp() public {
        wrapper = new CM31FieldWrapper();
    }

    function test_MultiplicationCM() public pure {
        // Test vectors from Rust implementation analysis
        // cm31!(1, 2) * cm31!(4, 5) = cm31!(P-6, 13) where P-6 = 2147483641
        CM31Field.CM31 memory a = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory b = CM31Field.fromM31(4, 5);
        CM31Field.CM31 memory result = CM31Field.mul(a, b);

        // (1 + 2i) * (4 + 5i) = (1*4 - 2*5) + (1*5 + 2*4)i = (4 - 10) + (5 + 8)i = -6 + 13i
        assertEq(result.real, P - 6); // -6 ≡ P-6 (mod P)
        assertEq(result.imag, 13);

        // Test multiplication by zero
        CM31Field.CM31 memory zero = CM31Field.zero();
        CM31Field.CM31 memory c = CM31Field.fromM31(42, 17);
        CM31Field.CM31 memory result2 = CM31Field.mul(c, zero);
        assertTrue(CM31Field.isZero(result2));

        // Test multiplication by one
        CM31Field.CM31 memory one = CM31Field.one();
        CM31Field.CM31 memory result3 = CM31Field.mul(c, one);
        assertTrue(CM31Field.eq(c, result3));

        // Test multiplication by imaginary unit i
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        CM31Field.CM31 memory d = CM31Field.fromM31(3, 4);
        CM31Field.CM31 memory result4 = CM31Field.mul(d, i);
        // (3 + 4i) * i = 3i + 4i² = 3i + 4(-1) = -4 + 3i
        assertEq(result4.real, P - 4);
        assertEq(result4.imag, 3);

        // Test commutativity
        CM31Field.CM31 memory e = CM31Field.fromM31(7, 11);
        CM31Field.CM31 memory f = CM31Field.fromM31(13, 17);
        assertTrue(CM31Field.eq(CM31Field.mul(e, f), CM31Field.mul(f, e)));
    }

    function test_Square() public pure {
        // Test (1 + 2i)² = 1 + 4i + 4i² = 1 + 4i - 4 = -3 + 4i
        CM31Field.CM31 memory a = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory result = CM31Field.square(a);

        assertEq(result.real, P - 3); // -3 ≡ P-3 (mod P)
        assertEq(result.imag, 4);

        // Test i² = -1
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        CM31Field.CM31 memory iSquared = CM31Field.square(i);
        assertEq(iSquared.real, P - 1); // -1 ≡ P-1 (mod P)
        assertEq(iSquared.imag, 0);

        // Test (a + bi)² = a² - b² + 2abi
        CM31Field.CM31 memory b = CM31Field.fromM31(3, 5);
        CM31Field.CM31 memory squareResult = CM31Field.square(b);
        CM31Field.CM31 memory mulResult = CM31Field.mul(b, b);
        assertTrue(CM31Field.eq(squareResult, mulResult));
    }

    function test_Conjugation() public pure {
        // Basic conjugation test
        CM31Field.CM31 memory a = CM31Field.fromM31(3, 4);
        CM31Field.CM31 memory conj = CM31Field.conjugate(a);

        assertEq(conj.real, 3);
        assertEq(conj.imag, P - 4); // -4 ≡ P-4 (mod P)

        // Test conjugation of real number
        CM31Field.CM31 memory real = CM31Field.fromReal(42);
        CM31Field.CM31 memory realConj = CM31Field.conjugate(real);
        assertTrue(CM31Field.eq(real, realConj));

        // Test conjugation of purely imaginary number
        CM31Field.CM31 memory imaginary = CM31Field.fromM31(0, 7);
        CM31Field.CM31 memory imagConj = CM31Field.conjugate(imaginary);
        assertEq(imagConj.real, 0);
        assertEq(imagConj.imag, P - 7);

        // Test double conjugation: conj(conj(z)) = z
        CM31Field.CM31 memory b = CM31Field.fromM31(5, 8);
        CM31Field.CM31 memory doubleConj = CM31Field.conjugate(
            CM31Field.conjugate(b)
        );
        assertTrue(CM31Field.eq(b, doubleConj));

        // Test conjugation of zero and one
        assertTrue(
            CM31Field.eq(
                CM31Field.zero(),
                CM31Field.conjugate(CM31Field.zero())
            )
        );
        assertTrue(
            CM31Field.eq(CM31Field.one(), CM31Field.conjugate(CM31Field.one()))
        );
    }

    function test_Norm() public pure {
        // Test |3 + 4i|² = 9 + 16 = 25
        CM31Field.CM31 memory a = CM31Field.fromM31(3, 4);
        uint32 normA = CM31Field.norm(a);
        assertEq(normA, 25);

        // Test |0|² = 0
        CM31Field.CM31 memory zero = CM31Field.zero();
        assertEq(CM31Field.norm(zero), 0);

        // Test |1|² = 1
        CM31Field.CM31 memory one = CM31Field.one();
        assertEq(CM31Field.norm(one), 1);

        // Test |i|² = 1
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        assertEq(CM31Field.norm(i), 1);

        // Test norm property: |z * w|² = |z|² * |w|²
        CM31Field.CM31 memory b = CM31Field.fromM31(5, 12); // |b|² = 25 + 144 = 169
        CM31Field.CM31 memory c = CM31Field.fromM31(3, 4); // |c|² = 9 + 16 = 25

        uint32 normB = CM31Field.norm(b);
        uint32 normC = CM31Field.norm(c);
        uint32 normProduct = CM31Field.norm(CM31Field.mul(b, c));

        // |b * c|² should equal |b|² * |c|²
        assertEq(normProduct, M31Field.mul(normB, normC));

        // Test with larger values
        CM31Field.CM31 memory d = CM31Field.fromM31(1000, 2000);
        uint32 normD = CM31Field.norm(d);
        assertEq(
            normD,
            M31Field.add(M31Field.square(1000), M31Field.square(2000))
        );
    }

    function test_Inversion() public pure {
        // Test inversion of 1 + 2i
        // 1/(1 + 2i) = (1 - 2i)/(1² + 2²) = (1 - 2i)/5
        CM31Field.CM31 memory a = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory inv = CM31Field.inverse(a);

        // Verify a * a⁻¹ = 1
        CM31Field.CM31 memory product = CM31Field.mul(a, inv);
        assertTrue(CM31Field.isOne(product));

        // Test inversion of real number
        CM31Field.CM31 memory real = CM31Field.fromReal(5);
        CM31Field.CM31 memory realInv = CM31Field.inverse(real);
        assertEq(realInv.real, M31Field.inverse(5));
        assertEq(realInv.imag, 0);

        // Test inversion of imaginary unit i
        // 1/i = -i (since i * (-i) = -i² = -(-1) = 1)
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        CM31Field.CM31 memory iInv = CM31Field.inverse(i);
        assertEq(iInv.real, 0);
        assertEq(iInv.imag, P - 1); // -1 ≡ P-1 (mod P)

        // Verify i * i⁻¹ = 1
        CM31Field.CM31 memory iProduct = CM31Field.mul(i, iInv);
        assertTrue(CM31Field.isOne(iProduct));

        // Test more complex cases
        uint32[5] memory testReals = [uint32(3), 7, 13, 17, 19];
        uint32[5] memory testImags = [uint32(4), 11, 5, 2, 23];

        for (uint j = 0; j < testReals.length; j++) {
            CM31Field.CM31 memory testVal = CM31Field.fromM31(
                testReals[j],
                testImags[j]
            );
            CM31Field.CM31 memory testInv = CM31Field.inverse(testVal);
            CM31Field.CM31 memory testProduct = CM31Field.mul(testVal, testInv);
            assertTrue(CM31Field.isOne(testProduct));
        }
    }

    function test_InversionReverts() public {
        // Test that inversion of zero reverts
        vm.expectRevert("CM31Field: division by zero");
        wrapper.inverse(0, 0);
    }

    function test_Division() public pure {
        // Test a / b = a * b⁻¹
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory b = CM31Field.fromM31(3, 4);

        CM31Field.CM31 memory divResult = CM31Field.div(a, b);
        CM31Field.CM31 memory mulResult = CM31Field.mul(
            a,
            CM31Field.inverse(b)
        );

        assertTrue(CM31Field.eq(divResult, mulResult));

        // Test division by one
        CM31Field.CM31 memory one = CM31Field.one();
        CM31Field.CM31 memory c = CM31Field.fromM31(42, 17);
        CM31Field.CM31 memory divByOne = CM31Field.div(c, one);
        assertTrue(CM31Field.eq(c, divByOne));

        // Test a / a = 1 for non-zero a
        CM31Field.CM31 memory d = CM31Field.fromM31(13, 19);
        CM31Field.CM31 memory selfDiv = CM31Field.div(d, d);
        assertTrue(CM31Field.isOne(selfDiv));
    }

    function test_DivisionReverts() public {
        // Test that division by zero reverts
        vm.expectRevert("CM31Field: division by zero");
        wrapper.div(1, 2, 0, 0);
    }

    function test_ScalarOperations() public pure {
        // Test scalar multiplication
        CM31Field.CM31 memory a = CM31Field.fromM31(3, 4);
        uint32 scalar = 5;
        CM31Field.CM31 memory result = CM31Field.mulScalar(a, scalar);

        assertEq(result.real, 15);
        assertEq(result.imag, 20);

        // Test scalar multiplication by zero
        CM31Field.CM31 memory zeroResult = CM31Field.mulScalar(a, 0);
        assertTrue(CM31Field.isZero(zeroResult));

        // Test scalar multiplication by one
        CM31Field.CM31 memory oneResult = CM31Field.mulScalar(a, 1);
        assertTrue(CM31Field.eq(a, oneResult));

        // Test scalar division
        CM31Field.CM31 memory b = CM31Field.fromM31(15, 20);
        CM31Field.CM31 memory divResult = CM31Field.divScalar(b, 5);
        assertEq(divResult.real, 3);
        assertEq(divResult.imag, 4);

        // Test that scalar multiplication and division are inverses
        CM31Field.CM31 memory c = CM31Field.fromM31(7, 11);
        uint32 nonZeroScalar = 13;
        CM31Field.CM31 memory mulThenDiv = CM31Field.divScalar(
            CM31Field.mulScalar(c, nonZeroScalar),
            nonZeroScalar
        );
        assertTrue(CM31Field.eq(c, mulThenDiv));
    }

    function test_ScalarDivisionReverts() public {
        // Test that scalar division by zero reverts
        vm.expectRevert("M31Field: division by zero");
        wrapper.divScalar(1, 2, 0);
    }

    function test_Power() public pure {
        // Test power function
        CM31Field.CM31 memory base = CM31Field.fromM31(2, 3);

        // Test base^0 = 1
        CM31Field.CM31 memory pow0 = CM31Field.pow(base, 0);
        assertTrue(CM31Field.isOne(pow0));

        // Test base^1 = base
        CM31Field.CM31 memory pow1 = CM31Field.pow(base, 1);
        assertTrue(CM31Field.eq(base, pow1));

        // Test base^2 = base * base
        CM31Field.CM31 memory pow2 = CM31Field.pow(base, 2);
        CM31Field.CM31 memory squared = CM31Field.mul(base, base);
        assertTrue(CM31Field.eq(pow2, squared));

        // Test i^2 = -1
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        CM31Field.CM31 memory i2 = CM31Field.pow(i, 2);
        assertEq(i2.real, P - 1);
        assertEq(i2.imag, 0);

        // Test i^4 = 1
        CM31Field.CM31 memory i4 = CM31Field.pow(i, 4);
        assertTrue(CM31Field.isOne(i4));

        // Test 0^n = 0 for n > 0
        CM31Field.CM31 memory zero = CM31Field.zero();
        CM31Field.CM31 memory zeroPow = CM31Field.pow(zero, 5);
        assertTrue(CM31Field.isZero(zeroPow));
    }

    function test_BatchConjugate() public pure {
        // Test batch conjugation
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](3);
        elements[0] = CM31Field.fromM31(1, 2);
        elements[1] = CM31Field.fromM31(3, 4);
        elements[2] = CM31Field.fromM31(0, 5);

        CM31Field.CM31[] memory conjugates = CM31Field.batchConjugate(elements);

        assertEq(conjugates.length, 3);
        assertTrue(
            CM31Field.eq(conjugates[0], CM31Field.conjugate(elements[0]))
        );
        assertTrue(
            CM31Field.eq(conjugates[1], CM31Field.conjugate(elements[1]))
        );
        assertTrue(
            CM31Field.eq(conjugates[2], CM31Field.conjugate(elements[2]))
        );
    }

    // Fuzz testing for complex operations
    function testFuzz_Multiplication(
        uint32 aReal,
        uint32 aImag,
        uint32 bReal,
        uint32 bImag
    ) public pure {
        // Reduce inputs to valid M31 elements
        aReal = aReal % P;
        aImag = aImag % P;
        bReal = bReal % P;
        bImag = bImag % P;

        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);

        CM31Field.CM31 memory result = CM31Field.mul(a, b);

        // Verify result is valid
        assertTrue(CM31Field.isValid(result));

        // Verify commutativity
        assertTrue(CM31Field.eq(CM31Field.mul(a, b), CM31Field.mul(b, a)));
    }

    function testFuzz_Inversion(uint32 real, uint32 imag) public pure {
        real = real % P;
        imag = imag % P;

        // Skip zero to avoid division by zero
        if (real == 0 && imag == 0) return;

        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory inv = CM31Field.inverse(a);

        // Verify result is valid
        assertTrue(CM31Field.isValid(inv));

        // Verify a * a⁻¹ = 1
        CM31Field.CM31 memory product = CM31Field.mul(a, inv);
        assertTrue(CM31Field.isOne(product));
    }

    function testFuzz_Conjugation(uint32 real, uint32 imag) public pure {
        real = real % P;
        imag = imag % P;

        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory conj = CM31Field.conjugate(a);

        // Verify result is valid
        assertTrue(CM31Field.isValid(conj));

        // Verify conj(conj(a)) = a
        CM31Field.CM31 memory doubleConj = CM31Field.conjugate(conj);
        assertTrue(CM31Field.eq(a, doubleConj));

        // Verify |a|² = a * conj(a) is real
        CM31Field.CM31 memory normProduct = CM31Field.mul(a, conj);
        assertEq(normProduct.imag, 0);
        assertEq(normProduct.real, CM31Field.norm(a));
    }

    // Gas benchmarks for complex operations
    function test_GasBenchmark_ComplexOps() public view {
        uint256 gasBefore;
        uint256 gasAfter;

        CM31Field.CM31 memory a = CM31Field.fromM31(12345, 67890);
        CM31Field.CM31 memory b = CM31Field.fromM31(11111, 22222);

        // Multiplication
        gasBefore = gasleft();
        CM31Field.mul(a, b);
        gasAfter = gasleft();
        uint256 mulGas = gasBefore - gasAfter;
        console.log("Multiplication gas:", mulGas);
        assertTrue(mulGas < 1500, "Multiplication too expensive");

        // Inversion
        gasBefore = gasleft();
        CM31Field.inverse(a);
        gasAfter = gasleft();
        uint256 invGas = gasBefore - gasAfter;
        console.log("Inversion gas:", invGas);
        assertTrue(invGas < 20000, "Inversion too expensive");

        // Conjugation
        gasBefore = gasleft();
        CM31Field.conjugate(a);
        gasAfter = gasleft();
        uint256 conjGas = gasBefore - gasAfter;
        console.log("Conjugation gas:", conjGas);
        assertTrue(conjGas < 100, "Conjugation too expensive");

        // Norm
        gasBefore = gasleft();
        CM31Field.norm(a);
        gasAfter = gasleft();
        uint256 normGas = gasBefore - gasAfter;
        console.log("Norm gas:", normGas);
        assertTrue(normGas < 1000, "Norm too expensive");
    }
}
