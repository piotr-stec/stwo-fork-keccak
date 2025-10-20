// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/fields/M31Field.sol";

/**
 * @title M31FieldSimpleTest  
 * @notice Simple tests to verify basic functionality and generate test vectors
 */
contract M31FieldSimpleTest is Test {
    using M31Field for uint32;

    uint32 constant P = 2147483647; // 2^31 - 1

    function test_BasicOperations() public view {
        // Test actual values to understand what's happening
        uint32 a = 1234567890;
        uint32 b = 987654321;
        
        uint32 sum = M31Field.add(a, b);
        console.log("Add result:", sum);
        console.log("Expected (if < P):", a + b);
        console.log("Expected (if >= P):", (a + b) - P);
        
        uint32 product = M31Field.mul(a, b);
        console.log("Mul result:", product);
        console.log("Product u64:", uint64(a) * uint64(b));
        console.log("Product % P:", uint64(a) * uint64(b) % uint64(P));
        
        uint32 inv7 = M31Field.inverse(7);
        console.log("Inverse of 7:", inv7);
        console.log("7 * inv(7):", M31Field.mul(7, inv7));
        
        int32 negOne = -1;
        uint32 fromNegOne = M31Field.fromI32(negOne);
        console.log("From -1:", fromNegOne);
        console.log("Should be P-1:", P - 1);
    }
    
    function test_InverseValues() public view {
        console.log("Inverse of 1:", M31Field.inverse(1));
        console.log("Inverse of 2:", M31Field.inverse(2));
        console.log("Inverse of 3:", M31Field.inverse(3));
        console.log("Inverse of 7:", M31Field.inverse(7));
        console.log("Inverse of P-1:", M31Field.inverse(P - 1));
    }
    
    function test_EdgeCasesMath() public view {
        console.log("P/2:", P / 2);
        console.log("P/2 + P/2:", M31Field.add(P / 2, P / 2));
        console.log("Should be P-1:", P - 1);
        
        console.log("(P-1) * (P-1):", M31Field.mul(P - 1, P - 1));
        console.log("Should be 1");
        
        uint32 pow2_30 = 1073741824;
        console.log("2^30: %d", pow2_30);
        console.log("2*2^30: %d", M31Field.mul(2, pow2_30));
        console.log("Should be P-1: %d", P - 1);
        
        // Check specific failing cases
        console.log("sqrt(P) = 46341");
        console.log("46341 * 46341:", M31Field.mul(46341, 46341));
        console.log("Expected: should be close to P");
        
        console.log("P/2 = %d", P/2);
        console.log("P/2 + P/2 = %d", M31Field.add(P/2, P/2));
        console.log("P-1 = %d", P-1);
    }
}