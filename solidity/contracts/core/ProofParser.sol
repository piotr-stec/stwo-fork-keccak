// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../fields/QM31Field.sol";
import "../fields/CM31Field.sol";

/// @title ProofParser
/// @notice Parses and extracts data from STARK proofs for verification
/// @dev Implements proof structure parsing equivalent to Rust stwo implementation
contract ProofParser {
    using QM31Field for QM31Field.QM31;

    /// @notice Verification errors that can occur during proof parsing
    enum VerificationError {
        None,
        InvalidStructure,
        OodsNotMatching,
        MerkleError,
        FriError,
        ProofOfWork
    }

    /// @notice Secure extension degree for QM31 field (4 components)
    uint256 public constant SECURE_EXTENSION_DEGREE = 4;

    /// @notice Merkle witness for commitment verification
    struct MerkleWitness {
        bytes32[] siblings;     // Sibling hashes in Merkle tree
        uint256[] indices;      // Path indices to leaf
        bytes32 root;          // Merkle tree root
        bytes32 leaf;          // Leaf value being verified
    }

    /// @notice FRI proof components
    struct FriProof {
        bytes32[] layerCommitments;    // FRI layer commitments
        bytes32[] lastLayerPoly;       // Last layer polynomial coefficients
        bytes32[] queries;             // FRI query responses
        uint256 nQueries;              // Number of queries
    }

    /// @notice STARK proof structure
    struct StarkProof {
        QM31Field.QM31[][][] sampledValues;    // TreeVec<ColumnVec<Vec<SecureField>>>
        MerkleWitness[] witnesses;             // Merkle decommitment witnesses
        FriProof friProof;                     // FRI proximity proof
        bytes32 commitment;                    // Main commitment
        uint256 nTrees;                        // Number of commitment trees
        uint256[] nColumns;                    // Number of columns per tree
        bool isValid;                          // Whether proof structure is valid
    }

    /// @notice Extracted composition OODS evaluation
    struct CompositionOods {
        QM31Field.QM31 evaluation;    // Composition polynomial OODS evaluation
        bool isValid;                  // Whether extraction was successful
        VerificationError error;       // Error code if extraction failed
    }

    /// @notice Error thrown when proof structure is invalid
    error InvalidProofStructure(string reason);
    
    /// @notice Error thrown when sampled values structure is malformed
    error InvalidSampledValues(string reason);

    /// @notice Error thrown when tree indices are out of bounds
    error TreeIndexOutOfBounds(uint256 treeIdx, uint256 maxTrees);

    constructor() {
        // Initialize parser
    }

    /// @notice Extract composition OODS evaluation from proof
    /// @param proof STARK proof containing sampled values
    /// @return result Extracted composition OODS evaluation and status
    function extractCompositionOodsEval(StarkProof memory proof) 
        external 
        pure 
        returns (CompositionOods memory result) 
    {
        // Validate proof structure
        if (!proof.isValid) {
            result.isValid = false;
            result.error = VerificationError.InvalidStructure;
            return result;
        }

        // Check that we have at least one tree
        if (proof.nTrees == 0 || proof.sampledValues.length == 0) {
            result.isValid = false;
            result.error = VerificationError.InvalidStructure;
            return result;
        }

        // Get composition mask (last tree in sampled values)
        uint256 compositionTreeIdx = proof.nTrees - 1;
        QM31Field.QM31[][] memory compositionMask = proof.sampledValues[compositionTreeIdx];

        // Validate composition mask structure
        if (compositionMask.length != SECURE_EXTENSION_DEGREE) {
            result.isValid = false;
            result.error = VerificationError.InvalidStructure;
            return result;
        }

        // Extract coordinate evaluations from composition mask
        QM31Field.QM31[] memory coordinateEvals = new QM31Field.QM31[](SECURE_EXTENSION_DEGREE);
        
        for (uint256 col = 0; col < SECURE_EXTENSION_DEGREE; col++) {
            // Each composition column should have exactly one evaluation
            if (compositionMask[col].length != 1) {
                result.isValid = false;
                result.error = VerificationError.InvalidStructure;
                return result;
            }
            coordinateEvals[col] = compositionMask[col][0];
        }

        // Reconstruct SecureField from partial evaluations
        result.evaluation = _fromPartialEvals(coordinateEvals);
        result.isValid = true;
        result.error = VerificationError.None;
    }

    /// @notice Parse proof from raw bytes (simplified interface)
    /// @param proofData Raw proof bytes
    /// @return proof Parsed STARK proof structure
    function parseProof(bytes memory proofData) 
        external 
        pure 
        returns (StarkProof memory proof) 
    {
        // This is a simplified parser - in practice would decode from bytes
        // For testing, we'll create a minimal valid structure
        
        if (proofData.length < 32) {
            proof.isValid = false;
            return proof;
        }

        // Initialize basic structure
        proof.nTrees = 1;
        proof.nColumns = new uint256[](1);
        proof.nColumns[0] = SECURE_EXTENSION_DEGREE;
        proof.sampledValues = new QM31Field.QM31[][][](1);
        proof.sampledValues[0] = new QM31Field.QM31[][](SECURE_EXTENSION_DEGREE);
        
        // Create composition mask with one evaluation per column
        for (uint256 col = 0; col < SECURE_EXTENSION_DEGREE; col++) {
            proof.sampledValues[0][col] = new QM31Field.QM31[](1);
            proof.sampledValues[0][col][0] = QM31Field.fromM31(
                uint32(100 + col), 
                uint32(200 + col), 
                uint32(300 + col), 
                uint32(400 + col)
            );
        }

        // Extract first 32 bytes as commitment
        bytes32 commitment;
        assembly {
            commitment := mload(add(proofData, 32))
        }
        proof.commitment = commitment;
        proof.isValid = true;
    }

    /// @notice Create proof structure from sampled values (for testing)
    /// @param sampledValues Pre-structured sampled values
    /// @return proof STARK proof structure
    function createProofFromSampledValues(QM31Field.QM31[][][] memory sampledValues)
        external
        pure
        returns (StarkProof memory proof)
    {
        proof.sampledValues = sampledValues;
        proof.nTrees = sampledValues.length;
        proof.nColumns = new uint256[](proof.nTrees);
        
        for (uint256 tree = 0; tree < proof.nTrees; tree++) {
            proof.nColumns[tree] = sampledValues[tree].length;
        }
        
        proof.commitment = keccak256(abi.encodePacked("test_commitment"));
        proof.isValid = true;
    }

    /// @notice Validate proof structure integrity
    /// @param proof STARK proof to validate
    /// @return isValid Whether proof structure is valid
    /// @return error Error code if validation failed
    function validateProofStructure(StarkProof memory proof) 
        external 
        pure 
        returns (bool isValid, VerificationError error) 
    {
        // Check basic structure
        if (proof.nTrees == 0) {
            return (false, VerificationError.InvalidStructure);
        }

        if (proof.sampledValues.length != proof.nTrees) {
            return (false, VerificationError.InvalidStructure);
        }

        if (proof.nColumns.length != proof.nTrees) {
            return (false, VerificationError.InvalidStructure);
        }

        // Validate each tree
        for (uint256 tree = 0; tree < proof.nTrees; tree++) {
            if (proof.sampledValues[tree].length != proof.nColumns[tree]) {
                return (false, VerificationError.InvalidStructure);
            }
            
            // Check that each column has valid structure
            for (uint256 col = 0; col < proof.nColumns[tree]; col++) {
                // Columns can have any number of samples, but must exist
                if (proof.sampledValues[tree][col].length == 0) {
                    return (false, VerificationError.InvalidStructure);
                }
            }
        }

        // Validate composition tree (last tree) has correct structure
        if (proof.nTrees > 0) {
            uint256 compositionTreeIdx = proof.nTrees - 1;
            if (proof.nColumns[compositionTreeIdx] != SECURE_EXTENSION_DEGREE) {
                return (false, VerificationError.InvalidStructure);
            }

            // Each composition column should have exactly one sample
            for (uint256 col = 0; col < SECURE_EXTENSION_DEGREE; col++) {
                if (proof.sampledValues[compositionTreeIdx][col].length != 1) {
                    return (false, VerificationError.InvalidStructure);
                }
            }
        }

        return (true, VerificationError.None);
    }

    /// @notice Get sampled values for specific tree and column
    /// @param proof STARK proof
    /// @param treeIdx Tree index
    /// @param columnIdx Column index
    /// @return values Sampled values for the specified tree/column
    function getSampledValues(
        StarkProof memory proof,
        uint256 treeIdx,
        uint256 columnIdx
    ) external pure returns (QM31Field.QM31[] memory values) {
        if (treeIdx >= proof.nTrees) {
            revert TreeIndexOutOfBounds(treeIdx, proof.nTrees);
        }

        if (columnIdx >= proof.nColumns[treeIdx]) {
            revert("Column index out of bounds");
        }

        return proof.sampledValues[treeIdx][columnIdx];
    }

    /// @notice Get number of trees in proof
    /// @param proof STARK proof
    /// @return count Number of trees
    function getTreeCount(StarkProof memory proof) external pure returns (uint256 count) {
        return proof.nTrees;
    }

    /// @notice Get number of columns in specific tree
    /// @param proof STARK proof
    /// @param treeIdx Tree index
    /// @return count Number of columns
    function getColumnCount(StarkProof memory proof, uint256 treeIdx) 
        external 
        pure 
        returns (uint256 count) 
    {
        if (treeIdx >= proof.nTrees) {
            revert TreeIndexOutOfBounds(treeIdx, proof.nTrees);
        }
        return proof.nColumns[treeIdx];
    }

    /// @notice Check if proof has composition tree
    /// @param proof STARK proof
    /// @return hasComposition Whether proof has valid composition tree
    function hasCompositionTree(StarkProof memory proof) external pure returns (bool hasComposition) {
        if (proof.nTrees == 0) {
            return false;
        }

        uint256 lastTreeIdx = proof.nTrees - 1;
        return proof.nColumns[lastTreeIdx] == SECURE_EXTENSION_DEGREE;
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    /// @notice Reconstruct SecureField from partial evaluations
    /// @param coordinateEvals Array of 4 coordinate evaluations  
    /// @return result Reconstructed SecureField element
    function _fromPartialEvals(QM31Field.QM31[] memory coordinateEvals) 
        internal 
        pure 
        returns (QM31Field.QM31 memory result) 
    {
        require(coordinateEvals.length == SECURE_EXTENSION_DEGREE, "Invalid coordinate evaluations length");

        // For QM31 field, each coordinate evaluation should be a single M31 element
        // The 4 coordinates represent the 4 M31 components of the QM31 field
        // Extract the real part of the first component from each coordinate evaluation
        uint32[4] memory m31Components;
        for (uint256 i = 0; i < SECURE_EXTENSION_DEGREE; i++) {
            m31Components[i] = coordinateEvals[i].first.real;
        }
        
        // Reconstruct QM31 from the 4 M31 components
        result = QM31Field.fromM31Array(m31Components);
    }

    /// @notice Convert verification error to string
    /// @param error Verification error enum
    /// @return errorString Human-readable error description
    function _errorToString(VerificationError error) internal pure returns (string memory errorString) {
        if (error == VerificationError.None) return "None";
        if (error == VerificationError.InvalidStructure) return "InvalidStructure";
        if (error == VerificationError.OodsNotMatching) return "OodsNotMatching";
        if (error == VerificationError.MerkleError) return "MerkleError";
        if (error == VerificationError.FriError) return "FriError";
        if (error == VerificationError.ProofOfWork) return "ProofOfWork";
        return "Unknown";
    }
}