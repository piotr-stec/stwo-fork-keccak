// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/CM31Field.sol";
import "../../contracts/fields/CM31FieldWrapper.sol";

/**
 * @title CM31FieldBasicTest
 * @notice Phase 1: Basic operations tests for CM31 complex field
 * @dev Tests fundamental operations: construction, addition, subtraction, negation, equality
 */
contract CM31FieldBasicTest is Test {
    using CM31Field for CM31Field.CM31;

    CM31FieldWrapper wrapper;
    
    // Constants from M31 field
    uint32 constant P = 2147483647; // 2^31 - 1

    function setUp() public {
        wrapper = new CM31FieldWrapper();
    }

    function test_Constants() public pure {
        // Test field constants
        assertEq(CM31Field.P2, 4611686014132420609); // (2^31-1)^2
        
        // Test special elements
        CM31Field.CM31 memory zero = CM31Field.zero();
        assertEq(zero.real, 0);
        assertEq(zero.imag, 0);
        
        CM31Field.CM31 memory one = CM31Field.one();
        assertEq(one.real, 1);
        assertEq(one.imag, 0);
        
        CM31Field.CM31 memory i = CM31Field.imaginaryUnit();
        assertEq(i.real, 0);
        assertEq(i.imag, 1);
    }

    function test_Construction() public pure {
        // Test fromM31
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        assertEq(a.real, 5);
        assertEq(a.imag, 7);
        
        // Test fromReal
        CM31Field.CM31 memory b = CM31Field.fromReal(42);
        assertEq(b.real, 42);
        assertEq(b.imag, 0);
        
        // Test fromU32Unchecked with modular reduction
        CM31Field.CM31 memory c = CM31Field.fromU32Unchecked(P + 5, P + 7);
        assertEq(c.real, 5);
        assertEq(c.imag, 7);
        
        // Test array conversion
        uint32[2] memory arr = [uint32(3), uint32(4)];
        CM31Field.CM31 memory d = CM31Field.fromArray(arr);
        assertEq(d.real, 3);
        assertEq(d.imag, 4);
        
        uint32[2] memory backToArr = CM31Field.toArray(d);
        assertEq(backToArr[0], 3);
        assertEq(backToArr[1], 4);
    }

    function test_Addition() public pure {
        // Basic addition
        CM31Field.CM31 memory a = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory b = CM31Field.fromM31(3, 4);
        CM31Field.CM31 memory result = CM31Field.add(a, b);
        
        assertEq(result.real, 4);
        assertEq(result.imag, 6);
        
        // Addition with zero
        CM31Field.CM31 memory zero = CM31Field.zero();
        CM31Field.CM31 memory c = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory result2 = CM31Field.add(c, zero);
        
        assertEq(result2.real, 5);
        assertEq(result2.imag, 7);
        
        // Commutative property
        CM31Field.CM31 memory d = CM31Field.fromM31(10, 20);
        CM31Field.CM31 memory e = CM31Field.fromM31(30, 40);
        
        assertTrue(CM31Field.eq(CM31Field.add(d, e), CM31Field.add(e, d)));
        
        // Edge case: addition near modulus boundary
        CM31Field.CM31 memory f = CM31Field.fromM31(P - 1, P - 2);
        CM31Field.CM31 memory g = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory result3 = CM31Field.add(f, g);
        
        assertEq(result3.real, 0); // (P-1) + 1 = 0 mod P
        assertEq(result3.imag, 0); // (P-2) + 2 = 0 mod P
    }

    function test_AdditionWithReal() public pure {
        // Test addReal function
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory result = CM31Field.addReal(a, 3);
        
        assertEq(result.real, 8);
        assertEq(result.imag, 7); // imaginary part unchanged
    }

    function test_Subtraction() public pure {
        // Basic subtraction
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory b = CM31Field.fromM31(3, 4);
        CM31Field.CM31 memory result = CM31Field.sub(a, b);
        
        assertEq(result.real, 2);
        assertEq(result.imag, 3);
        
        // Subtraction resulting in negative (modular arithmetic)
        CM31Field.CM31 memory c = CM31Field.fromM31(3, 4);
        CM31Field.CM31 memory d = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory result2 = CM31Field.sub(c, d);
        
        assertEq(result2.real, P - 2); // 3 - 5 = -2 ≡ P-2 (mod P)
        assertEq(result2.imag, P - 3); // 4 - 7 = -3 ≡ P-3 (mod P)
        
        // Subtraction from zero
        CM31Field.CM31 memory zero = CM31Field.zero();
        CM31Field.CM31 memory e = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory result3 = CM31Field.sub(zero, e);
        
        assertEq(result3.real, P - 1);
        assertEq(result3.imag, P - 2);
    }

    function test_SubtractionWithReal() public pure {
        // Test subReal function
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory result = CM31Field.subReal(a, 3);
        
        assertEq(result.real, 2);
        assertEq(result.imag, 7); // imaginary part unchanged
        
        // Test underflow
        CM31Field.CM31 memory b = CM31Field.fromM31(1, 2);
        CM31Field.CM31 memory result2 = CM31Field.subReal(b, 3);
        
        assertEq(result2.real, P - 2); // 1 - 3 = -2 ≡ P-2 (mod P)
        assertEq(result2.imag, 2);
    }

    function test_Negation() public pure {
        // Basic negation
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory result = CM31Field.neg(a);
        
        assertEq(result.real, P - 5);
        assertEq(result.imag, P - 7);
        
        // Negation of zero
        CM31Field.CM31 memory zero = CM31Field.zero();
        CM31Field.CM31 memory negZero = CM31Field.neg(zero);
        
        assertTrue(CM31Field.isZero(negZero));
        
        // Double negation
        CM31Field.CM31 memory b = CM31Field.fromM31(123, 456);
        CM31Field.CM31 memory doubleNeg = CM31Field.neg(CM31Field.neg(b));
        
        assertTrue(CM31Field.eq(b, doubleNeg));
        
        // Verify a + (-a) = 0
        CM31Field.CM31 memory c = CM31Field.fromM31(42, 17);
        CM31Field.CM31 memory negC = CM31Field.neg(c);
        CM31Field.CM31 memory sum = CM31Field.add(c, negC);
        
        assertTrue(CM31Field.isZero(sum));
    }

    function test_Equality() public pure {
        // Basic equality
        CM31Field.CM31 memory a = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory b = CM31Field.fromM31(5, 7);
        CM31Field.CM31 memory c = CM31Field.fromM31(5, 8);
        CM31Field.CM31 memory d = CM31Field.fromM31(6, 7);
        
        assertTrue(CM31Field.eq(a, b));
        assertFalse(CM31Field.eq(a, c));
        assertFalse(CM31Field.eq(a, d));
        
        // Reflexivity
        assertTrue(CM31Field.eq(a, a));
        
        // Symmetry
        assertTrue(CM31Field.eq(a, b) == CM31Field.eq(b, a));
    }

    function test_IsZero() public pure {
        assertTrue(CM31Field.isZero(CM31Field.zero()));
        assertFalse(CM31Field.isZero(CM31Field.one()));
        assertFalse(CM31Field.isZero(CM31Field.imaginaryUnit()));
        assertFalse(CM31Field.isZero(CM31Field.fromM31(1, 0)));
        assertFalse(CM31Field.isZero(CM31Field.fromM31(0, 1)));
        assertFalse(CM31Field.isZero(CM31Field.fromM31(1, 1)));
    }

    function test_IsOne() public pure {
        assertTrue(CM31Field.isOne(CM31Field.one()));
        assertFalse(CM31Field.isOne(CM31Field.zero()));
        assertFalse(CM31Field.isOne(CM31Field.imaginaryUnit()));
        assertFalse(CM31Field.isOne(CM31Field.fromM31(1, 1)));
        assertFalse(CM31Field.isOne(CM31Field.fromM31(2, 0)));
    }

    function test_IsReal() public pure {
        assertTrue(CM31Field.isReal(CM31Field.zero()));
        assertTrue(CM31Field.isReal(CM31Field.one()));
        assertTrue(CM31Field.isReal(CM31Field.fromReal(42)));
        assertFalse(CM31Field.isReal(CM31Field.imaginaryUnit()));
        assertFalse(CM31Field.isReal(CM31Field.fromM31(1, 1)));
        assertTrue(CM31Field.isReal(CM31Field.fromM31(123, 0)));
    }

    function test_IsPurelyImaginary() public pure {
        assertTrue(CM31Field.isPurelyImaginary(CM31Field.zero()));
        assertFalse(CM31Field.isPurelyImaginary(CM31Field.one()));
        assertTrue(CM31Field.isPurelyImaginary(CM31Field.imaginaryUnit()));
        assertFalse(CM31Field.isPurelyImaginary(CM31Field.fromM31(1, 1)));
        assertTrue(CM31Field.isPurelyImaginary(CM31Field.fromM31(0, 123)));
    }

    function test_IsValid() public pure {
        assertTrue(CM31Field.isValid(CM31Field.zero()));
        assertTrue(CM31Field.isValid(CM31Field.one()));
        assertTrue(CM31Field.isValid(CM31Field.fromM31(P - 1, P - 1)));
        
        // Test with values at boundary
        CM31Field.CM31 memory validAtBoundary = CM31Field.fromU32Unchecked(P - 1, P - 1);
        assertTrue(CM31Field.isValid(validAtBoundary));
    }

    function test_TryToReal() public pure {
        // Test successful conversion
        CM31Field.CM31 memory realNum = CM31Field.fromReal(42);
        (bool success, uint32 value) = CM31Field.tryToReal(realNum);
        assertTrue(success);
        assertEq(value, 42);
        
        // Test failed conversion
        CM31Field.CM31 memory complexNum = CM31Field.fromM31(1, 2);
        (bool success2, uint32 value2) = CM31Field.tryToReal(complexNum);
        assertFalse(success2);
        assertEq(value2, 0);
        
        // Test zero
        CM31Field.CM31 memory zero = CM31Field.zero();
        (bool success3, uint32 value3) = CM31Field.tryToReal(zero);
        assertTrue(success3);
        assertEq(value3, 0);
    }

    // Fuzz testing for basic operations
    function testFuzz_Addition(uint32 aReal, uint32 aImag, uint32 bReal, uint32 bImag) public pure {
        // Reduce inputs to valid M31 elements
        aReal = aReal % P;
        aImag = aImag % P;
        bReal = bReal % P;
        bImag = bImag % P;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        
        CM31Field.CM31 memory result = CM31Field.add(a, b);
        
        // Verify result is valid
        assertTrue(CM31Field.isValid(result));
        
        // Verify commutativity
        assertTrue(CM31Field.eq(CM31Field.add(a, b), CM31Field.add(b, a)));
    }

    function testFuzz_Subtraction(uint32 aReal, uint32 aImag, uint32 bReal, uint32 bImag) public pure {
        // Reduce inputs to valid M31 elements
        aReal = aReal % P;
        aImag = aImag % P;
        bReal = bReal % P;
        bImag = bImag % P;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        
        CM31Field.CM31 memory result = CM31Field.sub(a, b);
        
        // Verify result is valid
        assertTrue(CM31Field.isValid(result));
        
        // Verify a - b + b = a
        CM31Field.CM31 memory restored = CM31Field.add(result, b);
        assertTrue(CM31Field.eq(a, restored));
    }

    function testFuzz_Negation(uint32 real, uint32 imag) public pure {
        real = real % P;
        imag = imag % P;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory negA = CM31Field.neg(a);
        
        // Verify result is valid
        assertTrue(CM31Field.isValid(negA));
        
        // Verify a + (-a) = 0
        CM31Field.CM31 memory sum = CM31Field.add(a, negA);
        assertTrue(CM31Field.isZero(sum));
        
        // Verify -(-a) = a
        CM31Field.CM31 memory doubleNeg = CM31Field.neg(negA);
        assertTrue(CM31Field.eq(a, doubleNeg));
    }

    // Gas benchmarks for basic operations
    function test_GasBenchmark_BasicOps() public view {
        uint256 gasBefore;
        uint256 gasAfter;
        
        CM31Field.CM31 memory a = CM31Field.fromM31(12345, 67890);
        CM31Field.CM31 memory b = CM31Field.fromM31(11111, 22222);
        
        // Addition
        gasBefore = gasleft();
        CM31Field.add(a, b);
        gasAfter = gasleft();
        uint256 addGas = gasBefore - gasAfter;
        console.log("Addition gas:", addGas);
        assertTrue(addGas < 200, "Addition too expensive");
        
        // Subtraction
        gasBefore = gasleft();
        CM31Field.sub(a, b);
        gasAfter = gasleft();
        uint256 subGas = gasBefore - gasAfter;
        console.log("Subtraction gas:", subGas);
        assertTrue(subGas < 200, "Subtraction too expensive");
        
        // Negation
        gasBefore = gasleft();
        CM31Field.neg(a);
        gasAfter = gasleft();
        uint256 negGas = gasBefore - gasAfter;
        console.log("Negation gas:", negGas);
        assertTrue(negGas < 150, "Negation too expensive");
    }
}