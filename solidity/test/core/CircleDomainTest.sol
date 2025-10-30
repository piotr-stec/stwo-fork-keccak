// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/CircleDomain.sol";
import "../../contracts/core/CanonicCoset.sol";
import "../../contracts/core/Coset.sol";
import "../../contracts/core/CirclePoint.sol";

/// @title CircleDomainTest
/// @notice Test CircleDomain implementation and integration with CanonicCoset
contract CircleDomainTest is Test {
    using CircleDomain for CircleDomain.CircleDomainStruct;
    using CanonicCoset for CanonicCoset.CanonicCosetStruct;
    using Coset for Coset.CosetStruct;
    using CirclePoint for CirclePoint.Point;

    /// @notice Test basic CircleDomain creation and properties
    function testCircleDomainBasic() public {
        console.log("=== Basic CircleDomain Test ===");
        
        // Create a basic coset for testing
        uint32 logSize = 3; // Size 8 coset
        Coset.CosetStruct memory testCoset = Coset.subgroup(logSize);
        
        console.log("Created coset with log size:", logSize);
        console.log("Coset size:", Coset.size(testCoset));
        
        // Create circle domain from half coset
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(testCoset);
        
        // Test domain properties
        uint32 domainLogSize = CircleDomain.logSize(domain);
        uint256 domainSize = CircleDomain.size(domain);
        
        console.log("Domain log size:", domainLogSize);
        console.log("Domain size:", domainSize);
        
        // Verify properties
        assertEq(domainLogSize, logSize + 1, "Domain log size should be half coset log size + 1");
        assertEq(domainSize, 1 << domainLogSize, "Domain size should be 2^logSize");
        assertEq(domainSize, 2 * Coset.size(testCoset), "Domain size should be 2x half coset size");
        
        console.log("SUCCESS: Basic domain properties verified");
    }

    /// @notice Test CircleDomain point access
    function testCircleDomainPointAccess() public {
        console.log("=== CircleDomain Point Access Test ===");
        
        // Create a small domain for testing
        uint32 logSize = 2; // Size 4 half coset -> Size 8 domain
        Coset.CosetStruct memory halfCoset = Coset.subgroup(logSize);
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(halfCoset);
        
        uint256 domainSize = CircleDomain.size(domain);
        uint256 halfCosetSize = Coset.size(halfCoset);
        
        console.log("Half coset size:", halfCosetSize);
        console.log("Domain size:", domainSize);
        
        // Test point access
        for (uint256 i = 0; i < domainSize; i++) {
            CirclePoint.Point memory point = CircleDomain.at(domain, i);
            Coset.CirclePointIndex memory pointIndex = CircleDomain.indexAt(domain, i);
            
            console.log("Point %d: x.real=%d, index=%d", i, point.x.first.real, pointIndex.value);
            
            // Verify index bounds
            assertTrue(i < domainSize, "Index should be within domain bounds");
            
            // Check if point is in first or second half
            bool inFirstHalf = CircleDomain.isIndexInFirstHalf(domain, i);
            if (i < halfCosetSize) {
                assertTrue(inFirstHalf, "Points in first half should be marked as such");
            } else {
                assertFalse(inFirstHalf, "Points in second half should not be in first half");
            }
        }
        
        console.log("SUCCESS: Point access test passed");
    }

    /// @notice Test CircleDomain created from CanonicCoset
    function testCanonicCosetToCircleDomain() public {
        console.log("=== CanonicCoset to CircleDomain Test ===");
        
        // Create canonic coset
        uint32 logSize = 4; // Size 16
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(logSize);
        
        console.log("Created canonic coset with log size:", logSize);
        console.log("Canonic coset size:", CanonicCoset.size(canonicCoset));
        
        // Get half coset for circle domain
        Coset.CosetStruct memory halfCoset = CanonicCoset.halfCoset(canonicCoset);
        console.log("Half coset log size:", Coset.logSize(halfCoset));
        console.log("Half coset size:", Coset.size(halfCoset));
        
        // Create circle domain
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(halfCoset);
        
        // Verify sizes match expected relationships
        uint256 domainSize = CircleDomain.size(domain);
        uint256 canonicCosetSize = CanonicCoset.size(canonicCoset);
        
        console.log("Circle domain size:", domainSize);
        console.log("Expected relationship: domain size should equal canonic coset size");
        
        assertEq(domainSize, canonicCosetSize, "Circle domain size should equal canonic coset size");
        
        // Test canonicity
        bool isDomainCanonic = CircleDomain.isCanonic(domain);
        console.log("Is domain canonic:", isDomainCanonic);
        
        console.log("SUCCESS: CanonicCoset integration test passed");
    }

    /// @notice Test CircleDomain operations
    function testCircleDomainOperations() public {
        console.log("=== CircleDomain Operations Test ===");
        
        // Create base domain
        uint32 logSize = 3;
        Coset.CosetStruct memory halfCoset = Coset.subgroup(logSize);
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(halfCoset);
        
        console.log("Original domain size:", CircleDomain.size(domain));
        
        // Test shift operation
        Coset.CirclePointIndex memory shiftAmount = Coset.CirclePointIndex({value: 123});
        CircleDomain.CircleDomainStruct memory shiftedDomain = CircleDomain.shift(domain, shiftAmount);
        
        // Verify shifted domain has same size
        assertEq(CircleDomain.size(shiftedDomain), CircleDomain.size(domain), "Shifted domain should have same size");
        console.log("Shift operation: sizes match");
        
        // Test split operation
        uint32 logParts = 1; // Split into 2 parts
        (CircleDomain.CircleDomainStruct memory subdomain, Coset.CirclePointIndex[] memory shifts) = 
            CircleDomain.split(domain, logParts);
        
        uint256 expectedSubdomainSize = CircleDomain.size(domain) / (1 << logParts);
        assertEq(CircleDomain.size(subdomain), expectedSubdomainSize, "Subdomain should be smaller");
        assertEq(shifts.length, 1 << logParts, "Should have correct number of shifts");
        
        console.log("Subdomain size:", CircleDomain.size(subdomain));
        console.log("Number of shifts:", shifts.length);
        console.log("Split operation: verified");
        
        console.log("SUCCESS: Domain operations test passed");
    }

    /// @notice Test CircleDomain validation
    function testCircleDomainValidation() public {
        console.log("=== CircleDomain Validation Test ===");
        
        // Test valid domain
        uint32 validLogSize = 5;
        Coset.CosetStruct memory validHalfCoset = Coset.subgroup(validLogSize);
        CircleDomain.CircleDomainStruct memory validDomain = CircleDomain.newCircleDomain(validHalfCoset);
        
        (bool isValid, string memory errorMessage) = CircleDomain.validate(validDomain);
        assertTrue(isValid, "Valid domain should pass validation");
        console.log("Valid domain validation passed");
        
        // Test domain conversion to array
        CirclePoint.Point[] memory domainPoints = CircleDomain.toArray(validDomain);
        uint256 expectedSize = CircleDomain.size(validDomain);
        assertEq(domainPoints.length, expectedSize, "Array should contain all domain points");
        console.log("Domain array conversion: %d points", domainPoints.length);
        
        // Test domain equality
        CircleDomain.CircleDomainStruct memory sameDomain = CircleDomain.newCircleDomain(validHalfCoset);
        assertTrue(CircleDomain.equal(validDomain, sameDomain), "Identical domains should be equal");
        
        Coset.CosetStruct memory differentHalfCoset = Coset.subgroup(validLogSize + 1);
        CircleDomain.CircleDomainStruct memory differentDomain = CircleDomain.newCircleDomain(differentHalfCoset);
        assertFalse(CircleDomain.equal(validDomain, differentDomain), "Different domains should not be equal");
        
        console.log("Domain equality tests passed");
        console.log("SUCCESS: Validation tests passed");
    }

    /// @notice Test error conditions
    function testCircleDomainErrors() public {
        console.log("=== CircleDomain Error Conditions Test ===");
        
        // Test index out of bounds
        uint32 logSize = 2;
        Coset.CosetStruct memory halfCoset = Coset.subgroup(logSize);
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(halfCoset);
        
        uint256 domainSize = CircleDomain.size(domain);
        console.log("Domain size for error testing:", domainSize);
        
        // Test valid index access
        CirclePoint.Point memory validPoint = CircleDomain.at(domain, domainSize - 1);
        console.log("Valid access at max index successful");
        
        // Test invalid index access
        vm.expectRevert(abi.encodeWithSelector(
            CircleDomain.IndexOutOfBounds.selector,
            domainSize,
            domainSize - 1
        ));
        CircleDomain.at(domain, domainSize);
        console.log("Out of bounds access correctly reverted");
        
        // Test log size too large (approach the limit)
        uint32 maxLogSize = CircleDomain.MAX_CIRCLE_DOMAIN_LOG_SIZE - 1;
        Coset.CosetStruct memory maxHalfCoset = Coset.subgroup(maxLogSize);
        CircleDomain.CircleDomainStruct memory maxDomain = CircleDomain.newCircleDomain(maxHalfCoset);
        console.log("Max size domain created successfully with log size:", maxLogSize);
        
        console.log("SUCCESS: Error condition tests passed");
    }

    /// @notice Comprehensive integration test
    function testCircleDomainIntegration() public {
        console.log("=== CircleDomain Integration Test ===");
        
        // Create a canonic coset and convert it through the full pipeline
        uint32 logSize = 3;
        
        // Step 1: Create canonic coset
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(logSize);
        console.log("1. Created canonic coset");
        
        // Step 2: Get half coset for circle domain
        Coset.CosetStruct memory halfCoset = CanonicCoset.circleDomain(canonicCoset);
        console.log("2. Extracted half coset for domain");
        
        // Step 3: Create circle domain
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(halfCoset);
        console.log("3. Created circle domain");
        
        // Step 4: Verify all components work together
        uint256 canonicSize = CanonicCoset.size(canonicCoset);
        uint256 domainSize = CircleDomain.size(domain);
        uint256 halfCosetSize = Coset.size(halfCoset);
        
        console.log("Canonic coset size:", canonicSize);
        console.log("Circle domain size:", domainSize);
        console.log("Half coset size:", halfCosetSize);
        
        // Verify size relationships
        assertEq(domainSize, canonicSize, "Domain size should equal canonic coset size");
        assertEq(domainSize, 2 * halfCosetSize, "Domain should be twice the half coset size");
        
        // Step 5: Test point access across the pipeline
        for (uint256 i = 0; i < domainSize && i < 4; i++) {
            CirclePoint.Point memory domainPoint = CircleDomain.at(domain, i);
            console.log("Domain point %d: x.real=%d", i, domainPoint.x.first.real);
        }
        
        // Step 6: Test canonicity
        bool isDomainCanonic = CircleDomain.isCanonic(domain);
        console.log("Domain is canonic:", isDomainCanonic);
        
        console.log("SUCCESS: Complete integration test passed");
    }
}