// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/fields/M31Field.sol";
import "../../contracts/fields/M31FieldWrapper.sol";

contract M31FieldTest is Test {
    using M31Field for uint32;
    
    M31FieldWrapper wrapper;

    // Constants from Rust implementation
    uint32 constant P = 2147483647; // 2^31 - 1
    uint32 constant MODULUS_BITS = 31;
    
    function setUp() public {
        wrapper = new M31FieldWrapper();
    }

    // Test vectors from Rust implementation
    function test_BasicConstants() public pure {
        assertEq(M31Field.MODULUS, P);
        assertEq(M31Field.MODULUS_BITS, MODULUS_BITS);
        assertEq(M31Field.zero(), 0);
        assertEq(M31Field.one(), 1);
    }

    function test_PartialReduce() public pure {
        // Test cases from Rust implementation
        assertEq(M31Field.partialReduce(0), 0);
        assertEq(M31Field.partialReduce(P - 1), P - 1);
        assertEq(M31Field.partialReduce(P), 0);
        assertEq(M31Field.partialReduce(2 * P - 19), P - 19);
        assertEq(M31Field.partialReduce(2 * P - 1), P - 1);
    }

    function test_Reduce() public pure {
        // Test cases from Rust implementation
        assertEq(M31Field.reduce(0), 0);
        assertEq(M31Field.reduce(P - 1), P - 1);
        assertEq(M31Field.reduce(P), 0);
        assertEq(M31Field.reduce(uint64(P) * uint64(P) - 19), P - 19);
        
        // Additional edge cases
        assertEq(M31Field.reduce(uint64(P) + 1), 1);
        assertEq(M31Field.reduce(uint64(P) * 2), 0);
    }

    function test_Addition() public pure {
        // Basic addition tests
        assertEq(M31Field.add(0, 0), 0);
        assertEq(M31Field.add(1, 0), 1);
        assertEq(M31Field.add(0, 1), 1);
        assertEq(M31Field.add(1, 1), 2);
        
        // Edge cases near modulus
        assertEq(M31Field.add(P - 1, 1), 0);
        assertEq(M31Field.add(P - 1, 2), 1);
        assertEq(M31Field.add(P / 2, P / 2), P - 1);
        
        // Commutativity
        assertEq(M31Field.add(123, 456), M31Field.add(456, 123));
    }

    function test_Subtraction() public pure {
        // Basic subtraction tests
        assertEq(M31Field.sub(0, 0), 0);
        assertEq(M31Field.sub(1, 0), 1);
        assertEq(M31Field.sub(1, 1), 0);
        assertEq(M31Field.sub(0, 1), P - 1);
        
        // Edge cases
        assertEq(M31Field.sub(P - 1, P - 1), 0);
        assertEq(M31Field.sub(0, P - 1), 1);
        
        // Inverse of addition
        uint32 a = 12345;
        uint32 b = 67890;
        assertEq(M31Field.sub(M31Field.add(a, b), b), a);
    }

    function test_Negation() public pure {
        assertEq(M31Field.neg(0), 0);
        assertEq(M31Field.neg(1), P - 1);
        assertEq(M31Field.neg(P - 1), 1);
        assertEq(M31Field.neg(P / 2), P - P / 2);
        
        // Double negation
        uint32 x = 12345;
        assertEq(M31Field.neg(M31Field.neg(x)), x);
        
        // Addition with negation
        assertEq(M31Field.add(x, M31Field.neg(x)), 0);
    }

    function test_Multiplication() public pure {
        // Basic multiplication tests
        assertEq(M31Field.mul(0, 0), 0);
        assertEq(M31Field.mul(1, 0), 0);
        assertEq(M31Field.mul(0, 1), 0);
        assertEq(M31Field.mul(1, 1), 1);
        assertEq(M31Field.mul(2, 3), 6);
        
        // Edge cases
        assertEq(M31Field.mul(P - 1, 1), P - 1);
        assertEq(M31Field.mul(P - 1, P - 1), 1);
        
        // Commutativity
        uint32 a = 12345;
        uint32 b = 67890;
        assertEq(M31Field.mul(a, b), M31Field.mul(b, a));
        
        // Large number test
        uint32 large = 1000000000;
        uint32 result = M31Field.mul(large, large);
        assertTrue(result < P);
    }

    function test_Inversion() public pure {
        // Test known inverses
        assertEq(M31Field.mul(1, M31Field.inverse(1)), 1);
        assertEq(M31Field.mul(2, M31Field.inverse(2)), 1);
        assertEq(M31Field.mul(P - 1, M31Field.inverse(P - 1)), 1);
        
        // Test with random values
        uint32[10] memory testValues = [
            uint32(3), 7, 13, 97, 1009, 10007, 100003, 1000003, 10000019, 100000007
        ];
        
        for (uint i = 0; i < testValues.length; i++) {
            uint32 x = testValues[i];
            if (x < P) {
                uint32 inv = M31Field.inverse(x);
                assertEq(M31Field.mul(x, inv), 1);
            }
        }
    }

    function test_InverseZeroReverts() public {
        vm.expectRevert("M31Field: division by zero");
        wrapper.inverse(0);
    }

    function test_FromI32() public pure {
        // Positive numbers
        assertEq(M31Field.fromI32(0), 0);
        assertEq(M31Field.fromI32(1), 1);
        assertEq(M31Field.fromI32(10), 10);
        
        // Negative numbers (test vectors from Rust)
        assertEq(M31Field.fromI32(-1), P - 1);
        assertEq(M31Field.fromI32(-10), P - 10);
        
        // Large numbers
        assertEq(M31Field.fromI32(int32(P - 1)), P - 1);
    }

    function test_FieldAxioms() public pure {
        uint32 a = 12345;
        uint32 b = 67890;
        uint32 c = 11111;
        
        // Additive identity
        assertEq(M31Field.add(a, 0), a);
        assertEq(M31Field.add(0, a), a);
        
        // Additive inverse
        assertEq(M31Field.add(a, M31Field.neg(a)), 0);
        
        // Multiplicative identity
        assertEq(M31Field.mul(a, 1), a);
        assertEq(M31Field.mul(1, a), a);
        
        // Multiplicative inverse (for non-zero)
        if (a != 0) {
            assertEq(M31Field.mul(a, M31Field.inverse(a)), 1);
        }
        
        // Associativity
        assertEq(
            M31Field.add(M31Field.add(a, b), c),
            M31Field.add(a, M31Field.add(b, c))
        );
        assertEq(
            M31Field.mul(M31Field.mul(a, b), c),
            M31Field.mul(a, M31Field.mul(b, c))
        );
        
        // Commutativity
        assertEq(M31Field.add(a, b), M31Field.add(b, a));
        assertEq(M31Field.mul(a, b), M31Field.mul(b, a));
        
        // Distributivity
        assertEq(
            M31Field.mul(a, M31Field.add(b, c)),
            M31Field.add(M31Field.mul(a, b), M31Field.mul(a, c))
        );
    }

    function test_BatchInverse() public pure {
        uint32[] memory elements = new uint32[](5);
        elements[0] = 2;
        elements[1] = 3;
        elements[2] = 5;
        elements[3] = 7;
        elements[4] = 11;
        
        uint32[] memory inverses = M31Field.batchInverse(elements);
        
        for (uint i = 0; i < elements.length; i++) {
            assertEq(M31Field.mul(elements[i], inverses[i]), 1);
        }
    }

    function test_BatchInverseWithZero() public {
        uint32[] memory elements = new uint32[](3);
        elements[0] = 2;
        elements[1] = 0; // This should cause revert
        elements[2] = 3;
        
        vm.expectRevert("M31Field: division by zero");
        wrapper.batchInverse(elements);
    }

    // Fuzz testing for arithmetic operations
    function testFuzz_Addition(uint32 a, uint32 b) public pure {
        a = a % P;
        b = b % P;
        
        uint32 result = M31Field.add(a, b);
        assertTrue(result < P);
        
        // Commutativity
        assertEq(result, M31Field.add(b, a));
    }

    function testFuzz_Multiplication(uint32 a, uint32 b) public pure {
        a = a % P;
        b = b % P;
        
        uint32 result = M31Field.mul(a, b);
        assertTrue(result < P);
        
        // Commutativity
        assertEq(result, M31Field.mul(b, a));
    }

    function testFuzz_MultiplicativeInverse(uint32 x) public pure {
        x = (x % (P - 1)) + 1; // Ensure x is in [1, P-1]
        
        uint32 inv = M31Field.inverse(x);
        assertEq(M31Field.mul(x, inv), 1);
    }

    // Gas benchmarks
    function test_GasBenchmark_BasicOps() public view {
        uint256 gasBefore;
        uint256 gasAfter;
        
        // Addition
        gasBefore = gasleft();
        M31Field.add(12345, 67890);
        gasAfter = gasleft();
        console.log("Addition gas:", gasBefore - gasAfter);
        
        // Multiplication
        gasBefore = gasleft();
        M31Field.mul(12345, 67890);
        gasAfter = gasleft();
        console.log("Multiplication gas:", gasBefore - gasAfter);
        
        // Inversion
        gasBefore = gasleft();
        M31Field.inverse(12345);
        gasAfter = gasleft();
        console.log("Inversion gas:", gasBefore - gasAfter);
    }
}