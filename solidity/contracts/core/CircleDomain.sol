// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./Coset.sol";
import "./CirclePoint.sol";
import "../fields/QM31Field.sol";

/// @title CircleDomain
/// @notice A valid domain for circle polynomial interpolation and evaluation
/// @dev Valid domains are a disjoint union of two conjugate cosets: +-C + <G_n>
/// @dev The ordering defined on this domain is C + iG_n, and then -C - iG_n
library CircleDomain {
    using Coset for Coset.CosetStruct;
    using Coset for Coset.CirclePointIndex;
    using CirclePoint for CirclePoint.Point;

    /// @notice Maximum log size for circle domain
    uint32 public constant MAX_CIRCLE_DOMAIN_LOG_SIZE = Coset.M31_CIRCLE_LOG_ORDER - 1;

    /// @notice Circle domain structure representing +-C + <G_n>
    /// @param halfCoset The coset C that defines the domain +-C + <G_n>
    struct CircleDomainStruct {
        Coset.CosetStruct halfCoset;
    }

    /// @notice Error thrown when log size exceeds maximum
    error LogSizeTooLarge(uint32 logSizeParam, uint32 maxLogSize);

    /// @notice Error thrown when index is out of bounds
    error IndexOutOfBounds(uint256 index, uint256 maxIndex);

    // =============================================================================
    // Constructor Functions
    // =============================================================================

    /// @notice Create a new circle domain from a half coset
    /// @dev Given a coset C + <G_n>, constructs the circle domain +-C + <G_n>
    /// @param halfCoset The coset that defines half of the domain
    /// @return domain New circle domain structure
    function newCircleDomain(Coset.CosetStruct memory halfCoset)
        internal
        pure
        returns (CircleDomainStruct memory domain)
    {
        if (Coset.logSize(halfCoset) >= MAX_CIRCLE_DOMAIN_LOG_SIZE) {
            revert LogSizeTooLarge(Coset.logSize(halfCoset), MAX_CIRCLE_DOMAIN_LOG_SIZE);
        }

        domain = CircleDomainStruct({
            halfCoset: halfCoset
        });
    }

    // =============================================================================
    // Access Functions
    // =============================================================================

    /// @notice Get the half coset that defines the domain
    /// @param domain Circle domain to access
    /// @return halfCoset The half coset structure
    function halfCoset(CircleDomainStruct memory domain)
        internal
        pure
        returns (Coset.CosetStruct memory halfCoset)
    {
        halfCoset = domain.halfCoset;
    }

    /// @notice Get the size of the circle domain
    /// @param domain Circle domain to measure
    /// @return domainSize Number of points in domain (2 * half coset size)
    function size(CircleDomainStruct memory domain)
        internal
        pure
        returns (uint256 domainSize)
    {
        domainSize = 1 << logSize(domain);
    }

    /// @notice Get the log size of the circle domain
    /// @param domain Circle domain to measure
    /// @return domainLogSize Log2 of domain size
    function logSize(CircleDomainStruct memory domain)
        internal
        pure
        returns (uint32 domainLogSize)
    {
        domainLogSize = Coset.logSize(domain.halfCoset) + 1;
    }

    // =============================================================================
    // Point Access Functions
    // =============================================================================

    /// @notice Get circle point at specific index in domain
    /// @dev For i < half_coset_size: returns half_coset[i]
    /// @dev For i >= half_coset_size: returns -half_coset[i - half_coset_size]
    /// @param domain Circle domain to access
    /// @param index Index within domain
    /// @return point Point at index
    function at(CircleDomainStruct memory domain, uint256 index)
        internal
        pure
        returns (CirclePoint.Point memory point)
    {
        Coset.CirclePointIndex memory pointIndex = indexAt(domain, index);
        point = Coset.indexToPoint(pointIndex);
    }

    /// @notice Get circle point index at specific position in domain
    /// @param domain Circle domain to access
    /// @param index Index within domain
    /// @return pointIndex Index of point at position
    function indexAt(CircleDomainStruct memory domain, uint256 index)
        internal
        pure
        returns (Coset.CirclePointIndex memory pointIndex)
    {
        uint256 halfCosetSize = Coset.size(domain.halfCoset);
        
        if (index >= size(domain)) {
            revert IndexOutOfBounds(index, size(domain) - 1);
        }

        if (index < halfCosetSize) {
            // First half: return half_coset[index]
            pointIndex = Coset.indexAt(domain.halfCoset, index);
        } else {
            // Second half: return -half_coset[index - half_coset_size]
            Coset.CirclePointIndex memory halfCosetIndex = Coset.indexAt(
                domain.halfCoset, 
                index - halfCosetSize
            );
            pointIndex = Coset.negIndex(halfCosetIndex);
        }
    }

    // =============================================================================
    // Domain Properties
    // =============================================================================

    /// @notice Check if the domain is canonic
    /// @dev Canonic domains are domains with elements that are the entire set of points
    /// @dev defined by G_2n + <G_n> where G_n and G_2n are obtained by repeatedly
    /// @dev doubling the circle generator
    /// @param domain Circle domain to check
    /// @return isCanonic True if domain is canonic
    function isCanonic(CircleDomainStruct memory domain)
        internal
        pure
        returns (bool isCanonic)
    {
        // Check if half_coset.initial_index * 4 == half_coset.step_size
        Coset.CirclePointIndex memory initialTimes4 = Coset.mulIndex(
            domain.halfCoset.initialIndex,
            4
        );
        isCanonic = (initialTimes4.value == domain.halfCoset.stepSize.value);
    }

    // =============================================================================
    // Domain Operations
    // =============================================================================

    /// @notice Shift circle domain by adding offset
    /// @param domain Circle domain to shift
    /// @param shiftSize Amount to shift by
    /// @return shifted Shifted circle domain
    function shift(CircleDomainStruct memory domain, Coset.CirclePointIndex memory shiftSize)
        internal
        pure
        returns (CircleDomainStruct memory shifted)
    {
        Coset.CosetStruct memory shiftedHalfCoset = Coset.shift(domain.halfCoset, shiftSize);
        shifted = CircleDomainStruct({
            halfCoset: shiftedHalfCoset
        });
    }

    /// @notice Split a circle domain into smaller domains with offsets
    /// @param domain Circle domain to split
    /// @param logParts Log2 of number of parts to split into
    /// @return subdomain The smaller domain
    /// @return shifts Array of shift indices for each part
    function split(CircleDomainStruct memory domain, uint32 logParts)
        internal
        pure
        returns (CircleDomainStruct memory subdomain, Coset.CirclePointIndex[] memory shifts)
    {
        require(logParts <= Coset.logSize(domain.halfCoset), "logParts too large");

        // Create subdomain with reduced log size
        Coset.CosetStruct memory newHalfCoset = Coset.newCoset(
            domain.halfCoset.initialIndex,
            Coset.logSize(domain.halfCoset) - logParts
        );
        subdomain = CircleDomainStruct({
            halfCoset: newHalfCoset
        });

        // Generate shift indices
        uint256 numShifts = 1 << logParts;
        shifts = new Coset.CirclePointIndex[](numShifts);
        for (uint256 i = 0; i < numShifts; i++) {
            shifts[i] = Coset.mulIndex(domain.halfCoset.stepSize, i);
        }
    }

    // =============================================================================
    // Utility Functions
    // =============================================================================

    /// @notice Get all points in circle domain as array
    /// @dev Returns first the half coset, then its conjugate
    /// @param domain Circle domain to enumerate
    /// @return points Array of all points in domain
    function toArray(CircleDomainStruct memory domain)
        internal
        pure
        returns (CirclePoint.Point[] memory points)
    {
        uint256 domainSize = size(domain);
        points = new CirclePoint.Point[](domainSize);

        for (uint256 i = 0; i < domainSize; i++) {
            points[i] = at(domain, i);
        }
    }

    /// @notice Check if two circle domains are equal
    /// @param a First circle domain
    /// @param b Second circle domain
    /// @return isEqual True if domains are equal
    function equal(CircleDomainStruct memory a, CircleDomainStruct memory b)
        internal
        pure
        returns (bool isEqual)
    {
        isEqual = Coset.equal(a.halfCoset, b.halfCoset);
    }

    // =============================================================================
    // Validation Functions
    // =============================================================================

    /// @notice Validate that circle domain is properly formed
    /// @param domain Circle domain to validate
    /// @return isValid True if domain is valid
    /// @return errorMessage Error description if invalid
    function validate(CircleDomainStruct memory domain)
        internal
        pure
        returns (bool isValid, string memory errorMessage)
    {
        // Check log size is reasonable
        if (Coset.logSize(domain.halfCoset) == 0) {
            return (false, "Half coset log size cannot be zero");
        }
        
        if (Coset.logSize(domain.halfCoset) >= MAX_CIRCLE_DOMAIN_LOG_SIZE) {
            return (false, "Half coset log size exceeds maximum circle domain size");
        }

        // Validate the underlying half coset
        // Additional validation could be added here

        return (true, "Valid circle domain");
    }

    // =============================================================================
    // Iterator Helpers (for future extension)
    // =============================================================================

    /// @notice Get conjugate of the half coset
    /// @param domain Circle domain to access
    /// @return conjugateCoset Conjugate of the half coset
    function getConjugateHalfCoset(CircleDomainStruct memory domain)
        internal
        pure
        returns (Coset.CosetStruct memory conjugateCoset)
    {
        conjugateCoset = Coset.conjugate(domain.halfCoset);
    }

    /// @notice Check if index is in first half (half coset) or second half (conjugate)
    /// @param domain Circle domain to check
    /// @param index Index to check
    /// @return inFirstHalf True if index is in first half
    function isIndexInFirstHalf(CircleDomainStruct memory domain, uint256 index)
        internal
        pure
        returns (bool inFirstHalf)
    {
        uint256 halfCosetSize = Coset.size(domain.halfCoset);
        inFirstHalf = index < halfCosetSize;
    }
}