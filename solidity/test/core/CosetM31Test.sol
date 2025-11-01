// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../../contracts/core/CosetM31.sol";
import "../../contracts/core/CanonicCosetM31.sol";
import "../../contracts/core/CirclePointM31.sol";
import "../../contracts/fields/M31Field.sol";

/// @title CosetM31Test
/// @notice Test contract for CosetM31 and CanonicCosetM31 libraries
contract CosetM31Test {
    using CosetM31 for CosetM31.CosetStruct;
    using CanonicCosetM31 for CanonicCosetM31.CanonicCosetStruct;
    using CirclePointM31 for CirclePointM31.Point;
    using M31Field for uint32;

    /// @notice Test basic CosetM31 functionality
    function testBasicCoset() external pure returns (bool) {
        // Create a simple subgroup coset
        CosetM31.CosetStruct memory coset = CosetM31.subgroup(3); // log_size = 3, size = 8
        
        // Check size
        uint256 cosetSize = CosetM31.size(coset);
        require(cosetSize == 8, "Coset size should be 8");
        
        // Check log size
        uint32 logSize = CosetM31.logSizeFunc(coset);
        require(logSize == 3, "Log size should be 3");
        
        return true;
    }

    /// @notice Test CanonicCosetM31 functionality
    function testCanonicCoset() external pure returns (bool) {
        // Create canonical coset
        CanonicCosetM31.CanonicCosetStruct memory canonicCoset = CanonicCosetM31.newCanonicCoset(3);
        
        // Check size
        uint256 size = CanonicCosetM31.size(canonicCoset);
        require(size == 8, "Canonic coset size should be 8");
        
        // Check log size
        uint32 logSize = CanonicCosetM31.logSize(canonicCoset);
        require(logSize == 3, "Canonic coset log size should be 3");
        
        // Get step point
        CirclePointM31.Point memory step = CanonicCosetM31.step(canonicCoset);
        
        // Step should not be identity (not (1,0))
        require(!(step.x == M31Field.one() && step.y == M31Field.zero()), 
                "Step point should not be identity");
        
        return true;
    }

    /// @notice Test odds coset functionality
    function testOddsCoset() external pure returns (bool) {
        // Create odds coset
        CosetM31.CosetStruct memory odds = CosetM31.odds(3);
        
        // Check that it's different from subgroup
        CosetM31.CosetStruct memory subgroup = CosetM31.subgroup(3);
        
        // Initial indices should be different
        require(odds.initialIndex.value != subgroup.initialIndex.value,
                "Odds and subgroup should have different initial indices");
        
        return true;
    }

    /// @notice Test index to point conversion
    function testIndexToPoint() external pure returns (bool) {
        // Test zero index -> identity point
        CosetM31.CirclePointIndex memory zeroIndex = CosetM31.zeroIndex();
        CirclePointM31.Point memory identity = CosetM31.indexToPoint(zeroIndex);
        
        require(identity.x == M31Field.one() && identity.y == M31Field.zero(),
                "Zero index should map to identity point (1,0)");
        
        // Test non-zero index
        CosetM31.CirclePointIndex memory nonZeroIndex = CosetM31.indexFromValue(1);
        CirclePointM31.Point memory point = CosetM31.indexToPoint(nonZeroIndex);
        
        // Should not be identity
        require(!(point.x == M31Field.one() && point.y == M31Field.zero()),
                "Non-zero index should not map to identity");
        
        return true;
    }

    /// @notice Test coset point access
    function testCosetAccess() external pure returns (bool) {
        CosetM31.CosetStruct memory coset = CosetM31.subgroup(2); // size = 4
        
        // Access points at different indices
        CirclePointM31.Point memory point0 = CosetM31.at(coset, 0);
        CirclePointM31.Point memory point1 = CosetM31.at(coset, 1);
        
        // Points should be different
        require(!(point0.x == point1.x && point0.y == point1.y),
                "Different indices should give different points");
        
        return true;
    }

    /// @notice Test that implementation matches expected Rust behavior
    function testRustCompatibility() external pure returns (bool) {
        // Test that CanonicCoset creates odds coset (Rust behavior)
        CanonicCosetM31.CanonicCosetStruct memory canonicCoset = CanonicCosetM31.newCanonicCoset(3);
        CosetM31.CosetStruct memory expectedOdds = CosetM31.odds(3);
        CosetM31.CosetStruct memory actualCoset = CanonicCosetM31.coset(canonicCoset);
        
        // Should have same initial index and step size
        require(actualCoset.initialIndex.value == expectedOdds.initialIndex.value,
                "Canonic coset should match odds coset initial index");
        require(actualCoset.stepSize.value == expectedOdds.stepSize.value,
                "Canonic coset should match odds coset step size");
        
        return true;
    }
}