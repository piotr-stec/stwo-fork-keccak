// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../fields/M31Field.sol";

/// @title MerkleVerifier
/// @notice Verifies Merkle tree decommitments for vector commitment schemes
/// @dev Handles verification of multiple columns with different log sizes
library MerkleVerifier {
    using M31Field for uint32;

    /// @notice Merkle tree verifier state
    /// @param root Merkle tree root hash
    /// @param columnLogSizes Log sizes for each column
    struct Verifier {
        bytes32 root;
        uint32[] columnLogSizes;
    }

    /// @notice Merkle decommitment proof
    /// @param hashWitness Hash values along Merkle path
    /// @param columnWitness Column values at queried positions  
    struct Decommitment {
        bytes32[] hashWitness;
        uint32[] columnWitness;
    }

    /// @notice Query specification for Merkle verification
    /// @param positions Positions to query in the tree
    /// @param expectedValues Expected values at queried positions
    struct Query {
        uint256[] positions;
        uint32[] expectedValues;
    }

    /// @notice Error thrown when Merkle verification fails
    error MerkleVerificationFailed(bytes32 expected, bytes32 actual);
    
    /// @notice Error thrown when decommitment data is malformed
    error InvalidDecommitment(string reason);
    
    /// @notice Error thrown when query parameters are invalid
    error InvalidQuery(string reason);

    /// @notice Create new Merkle verifier
    /// @param root Merkle tree root
    /// @param columnLogSizes Log sizes for columns
    /// @return verifier New verifier instance
    function create(
        bytes32 root,
        uint32[] memory columnLogSizes
    ) internal pure returns (Verifier memory verifier) {
        verifier.root = root;
        verifier.columnLogSizes = columnLogSizes;
    }

    /// @notice Verify Merkle decommitment
    /// @param verifier Merkle verifier state
    /// @param query Query specification
    /// @param decommitment Decommitment proof
    /// @return True if verification succeeds
    function verify(
        Verifier memory verifier,
        Query memory query,
        Decommitment memory decommitment
    ) internal pure returns (bool) {
        // Validate input parameters - each position should have 4 field values (QM31)
        if (query.positions.length * 4 != query.expectedValues.length) {
            revert InvalidQuery("Position and value lengths mismatch");
        }
        
        if (decommitment.hashWitness.length == 0) {
            revert InvalidDecommitment("Empty hash witness");
        }

        // Verify each queried position (each position has 4 QM31 field values)
        for (uint256 i = 0; i < query.positions.length; i++) {
            // Extract 4 field values for this position
            uint32[4] memory positionValues = [
                query.expectedValues[i * 4],
                query.expectedValues[i * 4 + 1], 
                query.expectedValues[i * 4 + 2],
                query.expectedValues[i * 4 + 3]
            ];
            
            if (!_verifyPositionWithValues(
                verifier,
                query.positions[i],
                positionValues,
                decommitment,
                i
            )) {
                return false;
            }
        }

        return true;
    }

    /// @notice Verify single position in Merkle tree with QM31 values
    /// @param verifier Merkle verifier state
    /// @param position Position to verify
    /// @param expectedValues Expected QM31 values (4 field elements) at position
    /// @param decommitment Decommitment proof
    /// @return True if position verification succeeds
    function _verifyPositionWithValues(
        Verifier memory verifier,
        uint256 position,
        uint32[4] memory expectedValues,
        Decommitment memory decommitment,
        uint256 /* queryIndex */
    ) internal pure returns (bool) {
        // Find column log size for this position
        uint32 logSize = _getLogSizeForPosition(verifier, position);
        
        // Calculate tree height
        uint32 height = logSize;
        
        // Start with leaf hash (hash all 4 QM31 field values)
        bytes32 currentHash = _hashLeafQM31(expectedValues);
        
        // Climb up the tree using witness hashes
        uint256 currentPos = position;
        uint256 witnessIndex = 0;
        
        for (uint32 level = 0; level < height; level++) {
            if (witnessIndex >= decommitment.hashWitness.length) {
                revert InvalidDecommitment("Insufficient hash witness");
            }
            
            bytes32 siblingHash = decommitment.hashWitness[witnessIndex++];
            
            // Determine if current node is left or right child
            if (currentPos % 2 == 0) {
                // Current is left child
                currentHash = _hashNode(currentHash, siblingHash);
            } else {
                // Current is right child  
                currentHash = _hashNode(siblingHash, currentHash);
            }
            
            currentPos = currentPos / 2;
        }
        
        // Final hash should match root
        if (currentHash != verifier.root) {
            // Debug: Log the mismatch
            revert MerkleVerificationFailed(verifier.root, currentHash);
        }
        return true;
    }

    /// @notice Verify single position in Merkle tree (legacy single value)
    /// @param verifier Merkle verifier state
    /// @param position Position to verify
    /// @param expectedValue Expected value at position
    /// @param decommitment Decommitment proof
    /// @return True if position verification succeeds
    function _verifyPosition(
        Verifier memory verifier,
        uint256 position,
        uint32 expectedValue,
        Decommitment memory decommitment,
        uint256 /* queryIndex */
    ) internal pure returns (bool) {
        // Find column log size for this position
        uint32 logSize = _getLogSizeForPosition(verifier, position);
        
        // Calculate tree height
        uint32 height = logSize;
        
        // Start with leaf hash
        bytes32 currentHash = _hashLeaf(expectedValue);
        
        // Climb up the tree using witness hashes
        uint256 currentPos = position;
        uint256 witnessIndex = 0;
        
        for (uint32 level = 0; level < height; level++) {
            if (witnessIndex >= decommitment.hashWitness.length) {
                revert InvalidDecommitment("Insufficient hash witness");
            }
            
            bytes32 siblingHash = decommitment.hashWitness[witnessIndex++];
            
            // Determine if current node is left or right child
            if (currentPos % 2 == 0) {
                // Current is left child
                currentHash = _hashNode(currentHash, siblingHash);
            } else {
                // Current is right child  
                currentHash = _hashNode(siblingHash, currentHash);
            }
            
            currentPos = currentPos / 2;
        }
        
        // Final hash should match root
        return currentHash == verifier.root;
    }

    /// @notice Get log size for given position
    /// @param verifier Merkle verifier state
    /// @return Log size for the column containing this position
    function _getLogSizeForPosition(
        Verifier memory verifier,
        uint256 /* position */
    ) internal pure returns (uint32) {
        // For now, assume all columns have same log size
        // In full implementation, would need column layout mapping
        require(verifier.columnLogSizes.length > 0, "No columns configured");
        return verifier.columnLogSizes[0];
    }

    /// @notice Hash leaf node with QM31 values (4 field elements)
    /// @param values QM31 field values [first.real, first.imag, second.real, second.imag]
    /// @return Hash of leaf
    function _hashLeafQM31(uint32[4] memory values) internal pure returns (bytes32) {
        // Use Keccak hash with leaf prefix for domain separation
        return keccak256(abi.encodePacked(
            "leaf",
            bytes16(0), // Padding
            values[0], values[1], values[2], values[3]
        ));
    }

    /// @notice Hash leaf node (column value)
    /// @param value Column value (M31 field element)
    /// @return Hash of leaf
    function _hashLeaf(uint32 value) internal pure returns (bytes32) {
        // Use Keccak hash with leaf prefix for domain separation
        return keccak256(abi.encodePacked(
            "leaf",
            bytes28(0), // Padding to 32 bytes
            value
        ));
    }

    /// @notice Hash internal node
    /// @param leftChild Left child hash
    /// @param rightChild Right child hash
    /// @return Hash of internal node
    function _hashNode(bytes32 leftChild, bytes32 rightChild) internal pure returns (bytes32) {
        // Use Keccak hash with node prefix for domain separation
        return keccak256(abi.encodePacked(
            "node",
            bytes28(0), // Padding to 32 bytes
            leftChild,
            rightChild
        ));
    }

    /// @notice Batch verify multiple queries
    /// @param verifier Merkle verifier state
    /// @param queries Array of queries to verify
    /// @param decommitments Array of decommitment proofs
    /// @return True if all verifications succeed
    function batchVerify(
        Verifier memory verifier,
        Query[] memory queries,
        Decommitment[] memory decommitments
    ) internal pure returns (bool) {
        if (queries.length != decommitments.length) {
            revert InvalidQuery("Query and decommitment count mismatch");
        }
        
        for (uint256 i = 0; i < queries.length; i++) {
            if (!verify(verifier, queries[i], decommitments[i])) {
                return false;
            }
        }
        
        return true;
    }

    /// @notice Get tree height for given log size
    /// @param logSize Log size of the tree
    /// @return Tree height
    function getTreeHeight(uint32 logSize) internal pure returns (uint32) {
        return logSize;
    }

    /// @notice Calculate expected witness length for verification
    /// @param logSize Log size of the tree
    /// @param nQueries Number of queries
    /// @return Expected witness length
    function expectedWitnessLength(uint32 logSize, uint256 nQueries) internal pure returns (uint256) {
        // Each query needs `logSize` sibling hashes
        return nQueries * logSize;
    }

    /// @notice Validate verifier configuration
    /// @param verifier Verifier to validate
    /// @return True if verifier is properly configured
    function isValid(Verifier memory verifier) internal pure returns (bool) {
        // Must have valid root
        if (verifier.root == bytes32(0)) {
            return false;
        }
        
        // Must have at least one column
        if (verifier.columnLogSizes.length == 0) {
            return false;
        }
        
        // All log sizes must be reasonable (0-32)
        for (uint256 i = 0; i < verifier.columnLogSizes.length; i++) {
            if (verifier.columnLogSizes[i] > 32) {
                return false;
            }
        }
        
        return true;
    }
}