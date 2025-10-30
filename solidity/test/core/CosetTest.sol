// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/Coset.sol";
import "../../contracts/core/CanonicCoset.sol";
import "../../contracts/core/CirclePoint.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/fields/CM31Field.sol";

/// @title CosetTest
/// @notice Tests for Coset and CanonicCoset implementations
contract CosetTest is Test {
    using Coset for Coset.CosetStruct;
    using Coset for Coset.CirclePointIndex;
    using CanonicCoset for CanonicCoset.CanonicCosetStruct;
    using CirclePoint for CirclePoint.Point;

    function setUp() public {
        // Test setup
    }

    /// @notice Test basic coset creation and operations
    function testBasicCosetOperations() public {
        // Test subgroup creation
        Coset.CosetStruct memory subgroupCoset = Coset.subgroup(3); // Size 8
        
        assertEq(Coset.size(subgroupCoset), 8, "Subgroup size should be 8");
        assertEq(Coset.logSize(subgroupCoset), 3, "Log size should be 3");
        
        // Test first few points
        CirclePoint.Point memory point0 = Coset.at(subgroupCoset, 0);
        CirclePoint.Point memory point1 = Coset.at(subgroupCoset, 1);
        
        console.log("Subgroup coset created successfully");
        console.log("Point 0 x.first.real:", point0.x.first.real);
        console.log("Point 1 x.first.real:", point1.x.first.real);
    }

    /// @notice Test odds coset creation
    function testOddsCoset() public {
        // Create odds coset G_16 + <G_8>
        Coset.CosetStruct memory oddsCoset = Coset.odds(3); // log_size = 3
        
        assertEq(Coset.size(oddsCoset), 8, "Odds coset size should be 8");
        assertEq(Coset.logSize(oddsCoset), 3, "Odds coset log size should be 3");
        
        console.log("Odds coset created successfully");
        console.log("Initial index:", oddsCoset.initialIndex.value);
        console.log("Step size:", oddsCoset.stepSize.value);
    }

    /// @notice Test half-odds coset creation
    function testHalfOddsCoset() public {
        // Create half-odds coset G_32 + <G_8>
        Coset.CosetStruct memory halfOddsCoset = Coset.halfOdds(3); // log_size = 3
        
        assertEq(Coset.size(halfOddsCoset), 8, "Half-odds coset size should be 8");
        assertEq(Coset.logSize(halfOddsCoset), 3, "Half-odds coset log size should be 3");
        
        console.log("Half-odds coset created successfully");
    }

    /// @notice Test coset doubling operations
    function testCosetDoubling() public {
        // Create coset and double it
        Coset.CosetStruct memory originalCoset = Coset.subgroup(4); // Size 16
        Coset.CosetStruct memory doubledCoset = Coset.double(originalCoset);
        
        assertEq(Coset.size(doubledCoset), 8, "Doubled coset should have half the size");
        assertEq(Coset.logSize(doubledCoset), 3, "Doubled coset log size should decrease by 1");
        
        // Test repeated doubling
        Coset.CosetStruct memory repeatedDoubled = Coset.repeatedDouble(originalCoset, 2);
        assertEq(Coset.size(repeatedDoubled), 4, "Repeated doubling should work correctly");
        
        console.log("Coset doubling operations successful");
    }

    /// @notice Test coset shift operations
    function testCosetShift() public {
        Coset.CosetStruct memory originalCoset = Coset.subgroup(3);
        
        // Create a shift amount
        Coset.CirclePointIndex memory shiftAmount = Coset.subgroupGen(2);
        
        // Shift the coset
        Coset.CosetStruct memory shiftedCoset = Coset.shift(originalCoset, shiftAmount);
        
        // Original and shifted should have same size but different initial points
        assertEq(Coset.size(shiftedCoset), Coset.size(originalCoset), "Shifted coset should have same size");
        assertTrue(
            shiftedCoset.initialIndex.value != originalCoset.initialIndex.value,
            "Shifted coset should have different initial index"
        );
        
        console.log("Coset shift operations successful");
    }

    /// @notice Test coset conjugation
    function testCosetConjugation() public {
        Coset.CosetStruct memory originalCoset = Coset.odds(3);
        Coset.CosetStruct memory conjugatedCoset = Coset.conjugate(originalCoset);
        
        // Conjugated coset should have same size
        assertEq(Coset.size(conjugatedCoset), Coset.size(originalCoset), "Conjugated coset should have same size");
        
        // Double conjugation should give back original (modulo ordering)
        Coset.CosetStruct memory doubleConjugated = Coset.conjugate(conjugatedCoset);
        assertEq(Coset.size(doubleConjugated), Coset.size(originalCoset), "Double conjugation should preserve size");
        
        console.log("Coset conjugation operations successful");
    }

    /// @notice Test canonic coset creation and validation
    function testCanonicCosetCreation() public {
        // Create canonic coset
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(3);
        
        assertEq(CanonicCoset.size(canonicCoset), 8, "Canonic coset size should be 8");
        assertEq(CanonicCoset.logSize(canonicCoset), 3, "Canonic coset log size should be 3");
        
        // Validate the canonic coset
        (bool isValid, string memory errorMessage) = CanonicCoset.validate(canonicCoset);
        assertTrue(isValid, "Canonic coset should be valid");
        
        console.log("Canonic coset created and validated successfully");
        console.log("Validation message:", errorMessage);
    }

    /// @notice Test canonic coset half coset operation
    function testCanonicCosetHalfCoset() public {
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(4); // Size 16
        Coset.CosetStruct memory halfCoset = CanonicCoset.halfCoset(canonicCoset);
        
        assertEq(Coset.size(halfCoset), 8, "Half coset should have half the size");
        
        console.log("Canonic coset half coset operation successful");
    }

    /// @notice Test canonic coset point access
    function testCanonicCosetPointAccess() public {
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(3);
        
        // Test accessing points
        CirclePoint.Point memory point0 = CanonicCoset.at(canonicCoset, 0);
        CirclePoint.Point memory point1 = CanonicCoset.at(canonicCoset, 1);
        CirclePoint.Point memory lastPoint = CanonicCoset.at(canonicCoset, 7);
        
        console.log("Canonic coset point access successful");
        console.log("Point 0 x.first.real:", point0.x.first.real);
        console.log("Point 1 x.first.real:", point1.x.first.real);
        console.log("Last point x.first.real:", lastPoint.x.first.real);
        
        // Test index access
        Coset.CirclePointIndex memory index0 = CanonicCoset.indexAt(canonicCoset, 0);
        Coset.CirclePointIndex memory index1 = CanonicCoset.indexAt(canonicCoset, 1);
        
        assertTrue(index0.value != index1.value, "Different indices should have different values");
        
        console.log("Index 0:", index0.value);
        console.log("Index 1:", index1.value);
    }

    /// @notice Test canonic coset operations
    function testCanonicCosetOperations() public {
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(4);
        
        // Test doubling
        CanonicCoset.CanonicCosetStruct memory doubled = CanonicCoset.double(canonicCoset);
        assertEq(CanonicCoset.size(doubled), 8, "Doubled canonic coset should have half the size");
        
        // Test repeated doubling
        CanonicCoset.CanonicCosetStruct memory repeatedDoubled = CanonicCoset.repeatedDouble(canonicCoset, 2);
        assertEq(CanonicCoset.size(repeatedDoubled), 4, "Repeated doubling should work");
        
        // Test shift
        Coset.CirclePointIndex memory shiftAmount = Coset.subgroupGen(3);
        CanonicCoset.CanonicCosetStruct memory shifted = CanonicCoset.shift(canonicCoset, shiftAmount);
        assertEq(CanonicCoset.size(shifted), CanonicCoset.size(canonicCoset), "Shifted should have same size");
        
        // Test conjugation
        CanonicCoset.CanonicCosetStruct memory conjugated = CanonicCoset.conjugate(canonicCoset);
        assertEq(CanonicCoset.size(conjugated), CanonicCoset.size(canonicCoset), "Conjugated should have same size");
        
        console.log("All canonic coset operations successful");
    }

    /// @notice Test mask point generation with canonic coset
    function testMaskPointGeneration() public {
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(3);
        
        // Create base point
        CirclePoint.Point memory basePoint = CirclePoint.Point({
            x: QM31Field.QM31({
                first: CM31Field.CM31({real: 1000000000, imag: 2000000000}),
                second: CM31Field.CM31({real: 3000000000, imag: 400000000})
            }),
            y: QM31Field.QM31({
                first: CM31Field.CM31({real: 500000000, imag: 600000000}),
                second: CM31Field.CM31({real: 700000000, imag: 800000000})
            })
        });
        
        // Test single offset application
        CirclePoint.Point memory offsetPoint = CanonicCoset.applyOffset(canonicCoset, basePoint, 1);
        
        // Points should be different (unless offset is 0)
        bool pointsAreDifferent = (
            offsetPoint.x.first.real != basePoint.x.first.real ||
            offsetPoint.x.first.imag != basePoint.x.first.imag ||
            offsetPoint.y.first.real != basePoint.y.first.real ||
            offsetPoint.y.first.imag != basePoint.y.first.imag
        );
        
        console.log("Base point x.first.real:", basePoint.x.first.real);
        console.log("Offset point x.first.real:", offsetPoint.x.first.real);
        console.log("Points are different:", pointsAreDifferent);
        
        // Test multiple offsets
        int32[] memory offsets = new int32[](3);
        offsets[0] = 0;
        offsets[1] = 1;
        offsets[2] = -1;
        
        CirclePoint.Point[] memory maskPoints = CanonicCoset.generateMaskPoints(
            canonicCoset, 
            basePoint, 
            offsets
        );
        
        assertEq(maskPoints.length, 3, "Should generate 3 mask points");
        
        console.log("Mask point generation successful");
        console.log("Mask point 0 x.first.real:", maskPoints[0].x.first.real);
        console.log("Mask point 1 x.first.real:", maskPoints[1].x.first.real);
        console.log("Mask point 2 x.first.real:", maskPoints[2].x.first.real);
    }

    /// @notice Test error conditions
    function testErrorConditions() public {
        // Test invalid log size for canonic coset
        vm.expectRevert();
        CanonicCoset.newCanonicCoset(0);
        
        // Test index out of bounds
        Coset.CosetStruct memory smallCoset = Coset.subgroup(2); // Size 4
        vm.expectRevert();
        Coset.at(smallCoset, 4); // Index 4 is out of bounds
        
        // Test doubling coset of size 1
        Coset.CosetStruct memory singletonCoset = Coset.subgroup(0); // Size 1
        vm.expectRevert("Cannot double coset of size 1");
        Coset.double(singletonCoset);
        
        console.log("Error condition tests passed");
    }

    /// @notice Test coset equality and comparison
    function testCosetEquality() public {
        Coset.CosetStruct memory coset1 = Coset.subgroup(3);
        Coset.CosetStruct memory coset2 = Coset.subgroup(3);
        Coset.CosetStruct memory coset3 = Coset.odds(3);
        
        assertTrue(Coset.equal(coset1, coset2), "Identical cosets should be equal");
        assertFalse(Coset.equal(coset1, coset3), "Different cosets should not be equal");
        
        // Test doubling relationship
        Coset.CosetStruct memory doubled = Coset.double(coset1);
        assertTrue(Coset.isDoublingOf(doubled, coset1), "Doubled coset should be doubling of original");
        assertFalse(Coset.isDoublingOf(coset1, doubled), "Original should not be doubling of doubled");
        
        console.log("Coset equality tests passed");
    }

    /// @notice Test canonic coset equality
    function testCanonicCosetEquality() public {
        CanonicCoset.CanonicCosetStruct memory canonicCoset1 = CanonicCoset.newCanonicCoset(3);
        CanonicCoset.CanonicCosetStruct memory canonicCoset2 = CanonicCoset.newCanonicCoset(3);
        CanonicCoset.CanonicCosetStruct memory canonicCoset3 = CanonicCoset.newCanonicCoset(4);
        
        assertTrue(CanonicCoset.equal(canonicCoset1, canonicCoset2), "Identical canonic cosets should be equal");
        assertFalse(CanonicCoset.equal(canonicCoset1, canonicCoset3), "Different canonic cosets should not be equal");
        
        // Test doubling relationship
        CanonicCoset.CanonicCosetStruct memory doubled = CanonicCoset.double(canonicCoset3);
        assertTrue(CanonicCoset.isDoublingOf(doubled, canonicCoset3), "Doubled should be doubling of original");
        
        console.log("Canonic coset equality tests passed");
    }
}