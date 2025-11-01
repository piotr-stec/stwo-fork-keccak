// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../fields/QM31Field.sol";

/// @title ProofLib
/// @notice Library for storing and handling STARK proof structure from proof.json
/// @dev Direct mapping of Rust proof structure to Solidity
library ProofLib {
    using QM31Field for QM31Field.QM31;

    // =============================================================================
    // Configuration Structures
    // =============================================================================

    /// @notice FRI configuration matching proof.json
    struct FriConfig {
        uint32 logBlowupFactor;     // log_blowup_factor
        uint32 logLastLayerDegreeBound; // log_last_layer_degree_bound
        uint32 nQueries;            // n_queries
    }

    /// @notice Proof configuration
    struct ProofConfig {
        uint32 powBits;             // pow_bits
        FriConfig friConfig;        // fri_config
    }

    // =============================================================================
    // Decommitment Structures
    // =============================================================================

    /// @notice Decommitment structure for Merkle tree proofs
    struct Decommitment {
        bytes32[] hashWitness;      // hash_witness - Merkle authentication path
        uint256[] columnWitness;    // column_witness - Column data witness
    }

    // =============================================================================
    // FRI Proof Structures
    // =============================================================================

    /// @notice FRI layer structure
    struct FriLayer {
        QM31Field.QM31[] friWitness;    // fri_witness
        Decommitment decommitment;      // decommitment
        bytes32 commitment;             // commitment hash
    }

    /// @notice Last layer polynomial for FRI
    struct LastLayerPoly {
        QM31Field.QM31[] coeffs;        // coeffs
        uint32 logSize;                 // log_size
    }

    /// @notice Complete FRI proof structure
    struct FriProof {
        FriLayer firstLayer;            // first_layer
        FriLayer[] innerLayers;         // inner_layers
        LastLayerPoly lastLayerPoly;    // last_layer_poly
    }

    // =============================================================================
    // Main Proof Structure
    // =============================================================================

    /// @notice Complete STARK proof structure matching proof.json
    struct Proof {
        ProofConfig config;                     // Configuration
        bytes32[] commitments;                  // Commitment hashes (preprocessed, trace, composition)
        QM31Field.QM31[][][] sampledValues;    // sampled_values - Tree[Column[Values]]
        Decommitment[] decommitments;          // decommitments for each tree
        uint256[][] queriedValues;            // queried_values for each tree
        uint256 proofOfWork;                   // proof_of_work nonce
        FriProof friProof;                     // fri_proof
    }

    // =============================================================================
    // Constants matching Rust implementation
    // =============================================================================

    uint256 public constant PREPROCESSED_TRACE_IDX = 0;
    uint256 public constant ORIGINAL_TRACE_IDX = 1;
    uint256 public constant INTERACTION_TRACE_IDX = 2;
    uint256 public constant SECURE_EXTENSION_DEGREE = 4;

    // =============================================================================
    // Proof Creation and Manipulation Functions
    // =============================================================================

    /// @notice Create empty proof structure
    /// @return proof Empty proof with default values
    function createEmptyProof() internal pure returns (Proof memory proof) {
        proof.config.powBits = 0;
        proof.config.friConfig.logBlowupFactor = 0;
        proof.config.friConfig.logLastLayerDegreeBound = 0;
        proof.config.friConfig.nQueries = 0;
        
        // Initialize empty arrays
        proof.commitments = new bytes32[](0);
        proof.decommitments = new Decommitment[](0);
        proof.queriedValues = new uint256[][](0);
        proof.proofOfWork = 0;
        
        return proof;
    }

    /// @notice Create proof with basic configuration
    /// @param powBits Proof of work bits
    /// @param logBlowupFactor FRI log blowup factor
    /// @param logLastLayerDegreeBound FRI log last layer degree bound
    /// @param nQueries Number of FRI queries
    /// @return proof Configured proof structure
    function createProofWithConfig(
        uint32 powBits,
        uint32 logBlowupFactor,
        uint32 logLastLayerDegreeBound,
        uint32 nQueries
    ) internal pure returns (Proof memory proof) {
        proof = createEmptyProof();
        
        proof.config.powBits = powBits;
        proof.config.friConfig.logBlowupFactor = logBlowupFactor;
        proof.config.friConfig.logLastLayerDegreeBound = logLastLayerDegreeBound;
        proof.config.friConfig.nQueries = nQueries;
        
        return proof;
    }

    /// @notice Set commitments for proof
    /// @param proof The proof structure to modify
    /// @param commitmentHashes Array of commitment hashes
    /// @return updatedProof Proof with commitments set
    function setCommitments(
        Proof memory proof,
        bytes32[] memory commitmentHashes
    ) internal pure returns (Proof memory updatedProof) {
        proof.commitments = commitmentHashes;
        return proof;
    }

    /// @notice Add sampled values for a specific tree
    /// @param proof The proof structure to modify
    /// @param treeIdx Tree index (0=preprocessed, 1=trace, 2=interaction)
    /// @param values Sampled values for the tree
    /// @return updatedProof Proof with sampled values added
    function setSampledValues(
        Proof memory proof,
        uint256 treeIdx,
        QM31Field.QM31[][] memory values
    ) internal pure returns (Proof memory updatedProof) {
        // Ensure sampledValues array is large enough
        if (proof.sampledValues.length <= treeIdx) {
            QM31Field.QM31[][][] memory newSampledValues = new QM31Field.QM31[][][](treeIdx + 1);
            for (uint256 i = 0; i < proof.sampledValues.length; i++) {
                newSampledValues[i] = proof.sampledValues[i];
            }
            proof.sampledValues = newSampledValues;
        }
        
        proof.sampledValues[treeIdx] = values;
        return proof;
    }

    /// @notice Extract composition OODS evaluation from proof
    /// @dev Maps to: proof.extract_composition_oods_eval()
    /// @param proof The proof structure
    /// @return success True if extraction successful
    /// @return compositionOodsEval The extracted composition OODS evaluation
    function extractCompositionOodsEval(Proof memory proof)
        internal
        pure
        returns (bool success, QM31Field.QM31 memory compositionOodsEval)
    {
        // The composition OODS eval is typically in the last tree's sampled values
        if (proof.sampledValues.length == 0) {
            return (false, QM31Field.zero());
        }
        
        uint256 lastTreeIdx = proof.sampledValues.length - 1;
        QM31Field.QM31[][] memory lastTreeValues = proof.sampledValues[lastTreeIdx];
        
        if (lastTreeValues.length == 0 || lastTreeValues[0].length == 0) {
            return (false, QM31Field.zero());
        }
        
        // Return the first value from the composition polynomial evaluation
        compositionOodsEval = lastTreeValues[0][0];
        return (true, compositionOodsEval);
    }

    /// @notice Get commitment for specific tree
    /// @param proof The proof structure
    /// @param treeIdx Tree index
    /// @return commitment The commitment hash for the tree
    function getCommitment(Proof memory proof, uint256 treeIdx)
        internal
        pure
        returns (bytes32 commitment)
    {
        require(treeIdx < proof.commitments.length, "Invalid tree index");
        return proof.commitments[treeIdx];
    }

    /// @notice Get the last commitment (composition polynomial)
    /// @param proof The proof structure
    /// @return commitment The last commitment hash
    function getLastCommitment(Proof memory proof)
        internal
        pure
        returns (bytes32 commitment)
    {
        require(proof.commitments.length > 0, "No commitments available");
        return proof.commitments[proof.commitments.length - 1];
    }

    // =============================================================================
    // Helper Functions for Verification Flow
    // =============================================================================

    /// @notice Create commitment array from raw bytes
    /// @param rawCommitments Array of 32-byte arrays representing commitments
    /// @return commitments Array of bytes32 commitments
    function createCommitments(bytes32[] memory rawCommitments)
        internal
        pure
        returns (bytes32[] memory commitments)
    {
        return rawCommitments;
    }

    /// @notice Convert raw bytes to commitment hash
    /// @param rawBytes 32 bytes representing a commitment
    /// @return commitment The commitment as bytes32
    function bytesToCommitment(uint8[32] memory rawBytes)
        internal
        pure
        returns (bytes32 commitment)
    {
        assembly {
            commitment := mload(add(rawBytes, 32))
        }
    }

    /// @notice Validate proof structure
    /// @param proof The proof to validate
    /// @return isValid True if proof structure is valid
    /// @return errorMessage Error description if invalid
    function validateProof(Proof memory proof)
        internal
        pure
        returns (bool isValid, string memory errorMessage)
    {
        if (proof.commitments.length == 0) {
            return (false, "No commitments in proof");
        }
        
        if (proof.config.friConfig.nQueries == 0) {
            return (false, "Invalid FRI query count");
        }
        
        if (proof.sampledValues.length == 0) {
            return (false, "No sampled values in proof");
        }
        
        return (true, "Proof validation passed");
    }

    /// @notice Get proof statistics for debugging
    /// @param proof The proof structure
    /// @return nCommitments Number of commitments
    /// @return nSampledTrees Number of trees with sampled values
    /// @return nDecommitments Number of decommitments
    function getProofStats(Proof memory proof)
        internal
        pure
        returns (
            uint256 nCommitments,
            uint256 nSampledTrees,
            uint256 nDecommitments
        )
    {
        nCommitments = proof.commitments.length;
        nSampledTrees = proof.sampledValues.length;
        nDecommitments = proof.decommitments.length;
    }
}