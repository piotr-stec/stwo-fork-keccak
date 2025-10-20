// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/fields/M31Field.sol";

contract M31FieldDebugTest is Test {
    using M31Field for uint32;

    uint32 constant P = 2147483647; // 2^31 - 1

    function test_DebugEdgeCases() public view {
        // Debug each line from the edge cases test
        
        console.log("=== Maximum values ===");
        uint32 result1 = M31Field.add(P - 1, P - 1);
        console.log("add(P-1, P-1) = %d, expected = %d", result1, P - 2);
        
        uint32 result2 = M31Field.mul(P - 1, P - 1);
        console.log("mul(P-1, P-1) = %d, expected = 1", result2);
        
        console.log("=== Large multiplication ===");
        uint32 large1 = P / 2;
        uint32 large2 = P / 3;
        uint32 result3 = M31Field.mul(large1, large2);
        console.log("mul(P/2, P/3) = %d, P = %d", result3, P);
        
        console.log("=== Double and add patterns ===");
        uint32 result4 = M31Field.add(large1, large1);
        console.log("add(P/2, P/2) = %d, P-1 = %d", result4, P - 1);
        
        console.log("=== Powers of 2 ===");
        uint32 pow2_30 = 1073741824; // 2^30
        uint32 result5 = M31Field.add(pow2_30, pow2_30);
        console.log("add(2^30, 2^30) = %d, P-1 = %d", result5, P - 1);
        
        uint32 result6 = M31Field.mul(2, pow2_30);
        console.log("mul(2, 2^30) = %d, expected = ???", result6);
        
        // This is the failing assertion:
        console.log("FAILING: mul(2, 2^30) = %d, but test expects P-1 = %d", result6, P - 1);
    }
}