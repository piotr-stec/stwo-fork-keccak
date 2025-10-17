// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/fields/CM31FieldWrapper.sol";

/**
 * @title CM31FieldCompatibilityTest
 * @notice Cross-validation tests against Rust STWO implementation
 * @dev These tests ensure exact compatibility with the Rust CM31 implementation
 */
contract CM31FieldCompatibilityTest is Test {
    using CM31Field for CM31Field.CM31;

    CM31FieldWrapper wrapper;
    
    uint32 constant P = 2147483647; // 2^31 - 1

    function setUp() public {
        wrapper = new CM31FieldWrapper();
    }

    function test_RustCompatibility_BasicOps() public pure {
        // Test vectors from Rust implementation: cm31!(1, 2) + cm31!(4, 5) = cm31!(5, 7)
        CM31Field.CM31 memory cm0 = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory cm1 = CM31Field.fromM31(4, 5);
        CM31Field.CM31 memory sum = CM31Field.add(cm0, cm1);
        
        assertEq(sum.real, 5);
        assertEq(sum.imag, 7);
        
        // Test vectors from Rust: cm31!(1, 2) * cm31!(4, 5) = cm31!(P-6, 13)
        CM31Field.CM31 memory product = CM31Field.mul(cm0, cm1);
        assertEq(product.real, P - 6); // -6 ≡ P-6 (mod P)
        assertEq(product.imag, 13);
        
        // Test vectors from Rust: -cm31!(1, 2) = cm31!(P-1, P-2)
        CM31Field.CM31 memory negated = CM31Field.neg(cm0);
        assertEq(negated.real, P - 1);
        assertEq(negated.imag, P - 2);
        
        // Test vectors from Rust: cm31!(1, 2) - cm31!(4, 5) = cm31!(P-3, P-3)
        CM31Field.CM31 memory difference = CM31Field.sub(cm0, cm1);
        assertEq(difference.real, P - 3);
        assertEq(difference.imag, P - 3);
    }

    function test_RustCompatibility_MixedM31Operations() public pure {
        // Test mixed operations with M31 elements from Rust tests
        CM31Field.CM31 memory cm1 = CM31Field.fromM31(4, 5);
        uint32 m = 8;
        CM31Field.CM31 memory cm_from_m = CM31Field.fromReal(m);
        
        // Test cm1 + m == cm1 + cm (where cm = CM31::from(m))
        CM31Field.CM31 memory sum1 = CM31Field.addReal(cm1, m);
        CM31Field.CM31 memory sum2 = CM31Field.add(cm1, cm_from_m);
        assertTrue(CM31Field.eq(sum1, sum2));
        
        // Test cm1 * m == cm1 * cm
        CM31Field.CM31 memory mul1 = CM31Field.mulScalar(cm1, m);
        CM31Field.CM31 memory mul2 = CM31Field.mul(cm1, cm_from_m);
        assertTrue(CM31Field.eq(mul1, mul2));
        
        // Test cm1 - m == cm1 - cm
        CM31Field.CM31 memory sub1 = CM31Field.subReal(cm1, m);
        CM31Field.CM31 memory sub2 = CM31Field.sub(cm1, cm_from_m);
        assertTrue(CM31Field.eq(sub1, sub2));
        
        // Test cm1 / m == cm1 / cm
        CM31Field.CM31 memory div1 = CM31Field.divScalar(cm1, m);
        CM31Field.CM31 memory div2 = CM31Field.div(cm1, cm_from_m);
        assertTrue(CM31Field.eq(div1, div2));
    }

    function test_RustCompatibility_Division() public pure {
        // Test vectors from Rust: cm31!(P-6, 13) / cm31!(4, 5) = cm31!(1, 2)
        // This verifies that our multiplication and division are consistent
        CM31Field.CM31 memory numerator = CM31Field.fromM31(P - 6, 13);
        CM31Field.CM31 memory denominator = CM31Field.fromM31(4, 5);
        CM31Field.CM31 memory quotient = CM31Field.div(numerator, denominator);
        
        assertEq(quotient.real, 1);
        assertEq(quotient.imag, 2);
    }

    function test_RustCompatibility_Inversion() public pure {
        // Test inversion from Rust test: cm31!(1, 2).inverse()
        CM31Field.CM31 memory cm = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory inv = CM31Field.inverse(cm);
        
        // Verify cm * cm.inverse() = cm31!(1, 0) (which is one)
        CM31Field.CM31 memory product = CM31Field.mul(cm, inv);
        assertTrue(CM31Field.isOne(product));
        
        // The exact values should match Rust calculation:
        // 1/(1+2i) = (1-2i)/(1²+2²) = (1-2i)/5
        // So real = 1/5, imag = -2/5 in field arithmetic
        uint32 fiveInv = M31Field.inverse(5);
        uint32 expectedReal = M31Field.mul(1, fiveInv);
        uint32 expectedImag = M31Field.mul(M31Field.neg(2), fiveInv);
        
        assertEq(inv.real, expectedReal);
        assertEq(inv.imag, expectedImag);
    }

    function test_RustCompatibility_Constants() public pure {
        // Verify field constants match Rust implementation
        assertEq(CM31Field.P2, 4611686014132420609); // (2^31-1)^2
        
        // Test special elements
        CM31Field.CM31 memory zero = CM31Field.zero();
        assertEq(zero.real, 0);
        assertEq(zero.imag, 0);
        
        CM31Field.CM31 memory one = CM31Field.one();
        assertEq(one.real, 1);
        assertEq(one.imag, 0);
    }

    function test_RustCompatibility_ComplexConjugate() public pure {
        // Test complex conjugation matches Rust ComplexConjugate trait
        CM31Field.CM31 memory a = CM31Field.fromM31(3, 4);
        CM31Field.CM31 memory conj = CM31Field.conjugate(a);
        
        // conj(a + bi) = a - bi
        assertEq(conj.real, 3);
        assertEq(conj.imag, M31Field.neg(4));
        
        // Test that conjugation is involutive: conj(conj(z)) = z
        CM31Field.CM31 memory doubleConj = CM31Field.conjugate(conj);
        assertTrue(CM31Field.eq(a, doubleConj));
        
        // Test conjugation of real number (should be unchanged)
        CM31Field.CM31 memory real = CM31Field.fromReal(42);
        CM31Field.CM31 memory realConj = CM31Field.conjugate(real);
        assertTrue(CM31Field.eq(real, realConj));
    }

    function test_RustCompatibility_FieldAxioms() public pure {
        // Test that our implementation satisfies the same field axioms as Rust
        CM31Field.CM31 memory a = CM31Field.fromM31(7, 11);
        CM31Field.CM31 memory b = CM31Field.fromM31(13, 17);
        CM31Field.CM31 memory c = CM31Field.fromM31(19, 23);
        
        // Additive identity
        assertTrue(CM31Field.eq(CM31Field.add(a, CM31Field.zero()), a));
        
        // Multiplicative identity  
        assertTrue(CM31Field.eq(CM31Field.mul(a, CM31Field.one()), a));
        
        // Additive inverse
        assertTrue(CM31Field.isZero(CM31Field.add(a, CM31Field.neg(a))));
        
        // Multiplicative inverse (for non-zero elements)
        assertTrue(CM31Field.isOne(CM31Field.mul(a, CM31Field.inverse(a))));
        
        // Commutativity
        assertTrue(CM31Field.eq(CM31Field.add(a, b), CM31Field.add(b, a)));
        assertTrue(CM31Field.eq(CM31Field.mul(a, b), CM31Field.mul(b, a)));
        
        // Associativity
        assertTrue(CM31Field.eq(
            CM31Field.add(CM31Field.add(a, b), c),
            CM31Field.add(a, CM31Field.add(b, c))
        ));
        assertTrue(CM31Field.eq(
            CM31Field.mul(CM31Field.mul(a, b), c),
            CM31Field.mul(a, CM31Field.mul(b, c))
        ));
        
        // Distributivity
        assertTrue(CM31Field.eq(
            CM31Field.mul(a, CM31Field.add(b, c)),
            CM31Field.add(CM31Field.mul(a, b), CM31Field.mul(a, c))
        ));
    }

    function test_RustCompatibility_EdgeCases() public pure {
        // Test edge cases that might behave differently between implementations
        
        // Maximum values
        CM31Field.CM31 memory maxVal = CM31Field.fromM31(P - 1, P - 1);
        CM31Field.CM31 memory maxSum = CM31Field.add(maxVal, CM31Field.one());
        assertEq(maxSum.real, 0);  // (P-1) + 1 = 0 mod P
        assertEq(maxSum.imag, P - 1);  // imaginary part unchanged
        
        // Multiplication near boundary
        CM31Field.CM31 memory large1 = CM31Field.fromM31(P / 2, P / 3);
        CM31Field.CM31 memory large2 = CM31Field.fromM31(P / 5, P / 7);
        CM31Field.CM31 memory largeProduct = CM31Field.mul(large1, large2);
        
        // Result should be valid (reduced mod P)
        assertTrue(CM31Field.isValid(largeProduct));
        
        // Test that (P-1) * (P-1) behaves correctly
        CM31Field.CM31 memory minusOne = CM31Field.fromM31(P - 1, 0);
        CM31Field.CM31 memory minusOneSquared = CM31Field.mul(minusOne, minusOne);
        assertTrue(CM31Field.isOne(minusOneSquared)); // (-1)² = 1
    }

    function test_RustCompatibility_IrreduciblePolynomial() public pure {
        // Test that i² = -1 (the irreducible polynomial x² + 1)
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        CM31Field.CM31 memory iSquared = CM31Field.square(i);
        
        CM31Field.CM31 memory minusOne = CM31Field.fromM31(P - 1, 0);
        assertTrue(CM31Field.eq(iSquared, minusOne));
        
        // Test that i⁴ = 1
        CM31Field.CM31 memory iFourth = CM31Field.square(iSquared);
        assertTrue(CM31Field.isOne(iFourth));
        
        // Test powers of i: i⁰=1, i¹=i, i²=-1, i³=-i, i⁴=1, ...
        CM31Field.CM31 memory i0 = CM31Field.pow(i, 0);
        CM31Field.CM31 memory i1 = CM31Field.pow(i, 1);
        CM31Field.CM31 memory i2 = CM31Field.pow(i, 2);
        CM31Field.CM31 memory i3 = CM31Field.pow(i, 3);
        CM31Field.CM31 memory i4 = CM31Field.pow(i, 4);
        
        assertTrue(CM31Field.isOne(i0));
        assertTrue(CM31Field.eq(i1, i));
        assertTrue(CM31Field.eq(i2, minusOne));
        assertTrue(CM31Field.eq(i3, CM31Field.fromM31(0, P - 1))); // -i
        assertTrue(CM31Field.isOne(i4));
    }

    function test_RustCompatibility_TryInto() public pure {
        // Test conversion to M31 (like Rust's TryInto<M31>)
        
        // Should succeed for real numbers
        CM31Field.CM31 memory realNum = CM31Field.fromReal(42);
        (bool success, uint32 value) = CM31Field.tryToReal(realNum);
        assertTrue(success);
        assertEq(value, 42);
        
        // Should fail for complex numbers
        CM31Field.CM31 memory complexNum = CM31Field.fromM31(1, 2);
        (bool success2, uint32 value2) = CM31Field.tryToReal(complexNum);
        assertFalse(success2);
        assertEq(value2, 0);
        
        // Should succeed for zero
        (bool success3, uint32 value3) = CM31Field.tryToReal(CM31Field.zero());
        assertTrue(success3);
        assertEq(value3, 0);
    }

    function test_RustCompatibility_FromUnchecked() public pure {
        // Test fromU32Unchecked matches Rust's from_u32_unchecked behavior
        CM31Field.CM31 memory a = CM31Field.fromU32Unchecked(1, 2);
        assertEq(a.real, 1);
        assertEq(a.imag, 2);
        
        // Test with values >= P (should be reduced)
        CM31Field.CM31 memory b = CM31Field.fromU32Unchecked(P + 5, P + 7);
        assertEq(b.real, 5);
        assertEq(b.imag, 7);
        
        // Test at exact boundary
        CM31Field.CM31 memory c = CM31Field.fromU32Unchecked(P, P);
        assertEq(c.real, 0);
        assertEq(c.imag, 0);
    }

    // Property-based testing against known Rust behavior
    function testFuzz_RustCompatibility_FieldProperties(uint32 aReal, uint32 aImag, uint32 bReal, uint32 bImag) public pure {
        // Reduce to valid M31 elements
        aReal = aReal % P;
        aImag = aImag % P;
        bReal = bReal % P;
        bImag = bImag % P;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        
        // Test commutativity (should match Rust)
        assertTrue(CM31Field.eq(CM31Field.add(a, b), CM31Field.add(b, a)));
        assertTrue(CM31Field.eq(CM31Field.mul(a, b), CM31Field.mul(b, a)));
        
        // Test that conjugation preserves norm: |z|² = z * conj(z)
        CM31Field.CM31 memory conjA = CM31Field.conjugate(a);
        CM31Field.CM31 memory product = CM31Field.mul(a, conjA);
        assertEq(product.real, CM31Field.norm(a));
        assertEq(product.imag, 0); // Should be purely real
        
        // Test distributivity
        if (!CM31Field.isZero(a)) {
            CM31Field.CM31 memory sum = CM31Field.add(b, CM31Field.one());
            assertTrue(CM31Field.eq(
                CM31Field.mul(a, sum),
                CM31Field.add(CM31Field.mul(a, b), a)
            ));
        }
    }

    function test_RustCompatibility_NormMultiplicativity(uint32 aReal, uint32 aImag, uint32 bReal, uint32 bImag) public pure {
        // Test that |ab|² = |a|²|b|² (multiplicativity of norm)
        aReal = aReal % P;
        aImag = aImag % P;
        bReal = bReal % P;
        bImag = bImag % P;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        
        CM31Field.CM31 memory product = CM31Field.mul(a, b);
        uint32 productNorm = CM31Field.norm(product);
        uint32 expectedNorm = M31Field.mul(CM31Field.norm(a), CM31Field.norm(b));
        
        assertEq(productNorm, expectedNorm);
    }

    // Performance validation against Rust benchmarks
    function test_PerformanceBenchmark_RustComparison() public view {
        uint256 gasBefore;
        uint256 gasAfter;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(12345, 67890);
        CM31Field.CM31 memory b = CM31Field.fromM31(54321, 98765);
        
        // Benchmark addition (should be very fast)
        gasBefore = gasleft();
        CM31Field.add(a, b);
        gasAfter = gasleft();
        uint256 addGas = gasBefore - gasAfter;
        console.log("CM31 Addition gas:", addGas);
        
        // Benchmark multiplication (more expensive than M31)
        gasBefore = gasleft();
        CM31Field.mul(a, b);
        gasAfter = gasleft();
        uint256 mulGas = gasBefore - gasAfter;
        console.log("CM31 Multiplication gas:", mulGas);
        
        // Benchmark inversion (most expensive)
        gasBefore = gasleft();
        CM31Field.inverse(a);
        gasAfter = gasleft();
        uint256 invGas = gasBefore - gasAfter;
        console.log("CM31 Inversion gas:", invGas);
        
        // Benchmark conjugation (should be very fast)
        gasBefore = gasleft();
        CM31Field.conjugate(a);
        gasAfter = gasleft();
        uint256 conjGas = gasBefore - gasAfter;
        console.log("CM31 Conjugation gas:", conjGas);
        
        // Reasonable gas limits based on complexity (adjusted for memory struct overhead)
        assertTrue(addGas < 1000, "Addition should be under 1K gas");
        assertTrue(mulGas < 3000, "Multiplication should be under 3K gas");
        assertTrue(invGas < 25000, "Inversion should be under 25K gas");
        assertTrue(conjGas < 500, "Conjugation should be under 500 gas");
    }
}