// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./TreeVec.sol";
import "./PcsConfig.sol";
import "../vcs/MerkleVerifier.sol";
import "../core/CirclePoint.sol";
import "../fields/QM31Field.sol";
import "../channel/IChannel.sol";

/// @title CommitmentSchemeVerifier
/// @notice Verifies polynomial commitment scheme proofs using FRI and Merkle trees
/// @dev Main verifier for STWO commitment scheme with Keccak channel integration
contract CommitmentSchemeVerifier {
    using TreeVec for TreeVec.Bytes32TreeVec;
    using TreeVec for TreeVec.Uint32ArrayTreeVec;
    using PcsConfig for PcsConfig.Config;
    using MerkleVerifier for MerkleVerifier.Verifier;
    using QM31Field for QM31Field.QM31;
    using CirclePoint for CirclePoint.Point;

    /// @notice Verifier state containing trees and configuration
    /// @param trees TreeVec of Merkle verifiers for each commitment tree
    /// @param config PCS configuration (FRI + PoW parameters)
    struct VerifierState {
        TreeVec.Bytes32TreeVec treeRoots;           // Commitment tree roots
        TreeVec.Uint32ArrayTreeVec columnLogSizes;  // Column log sizes per tree
        PcsConfig.Config config;                    // PCS configuration
        uint256 nTrees;                             // Number of commitment trees
    }

    /// @notice Commitment scheme proof structure
    /// @param commitments Tree roots for each commitment
    /// @param sampledValues Sampled polynomial values at OODS point
    /// @param decommitments Merkle decommitment proofs
    /// @param queriedValues Values at FRI query positions
    /// @param proofOfWork Proof of work nonce
    /// @param friProof FRI verification proof (placeholder for now)
    struct Proof {
        bytes32[] commitments;           // TreeVec<Hash>
        QM31Field.QM31[] sampledValues;  // TreeVec<ColumnVec<Vec<SecureField>>>
        bytes[] decommitments;           // TreeVec<MerkleDecommitment> (encoded)
        uint32[] queriedValues;          // TreeVec<Vec<BaseField>>
        uint64 proofOfWork;              // Proof of work nonce
        bytes friProof;                  // FRI proof (to be implemented)
    }

    /// @notice Commitment scheme verification error types
    error InvalidCommitment(uint256 treeIndex, bytes32 expected, bytes32 actual);
    error InvalidProofStructure(string reason);
    error OodsNotMatching(QM31Field.QM31 expected, QM31Field.QM31 actual);
    error ProofOfWorkFailed(uint32 required, uint64 nonce);
    error FriVerificationFailed(string reason);
    error MerkleDecommitmentFailed(uint256 treeIndex);

    /// @notice Verifier state storage
    VerifierState private verifierState;

    /// @notice Events for debugging and monitoring
    event CommitmentAdded(uint256 indexed treeIndex, bytes32 indexed root);
    event VerificationStarted(bytes32 indexed proofHash);
    event VerificationCompleted(bool indexed success);

    /// @notice Initialize verifier with configuration
    /// @param config PCS configuration
    constructor(PcsConfig.Config memory config) {
        require(PcsConfig.isValidConfig(config), "Invalid PCS configuration");
        
        verifierState.config = config;
        verifierState.treeRoots = TreeVec.newBytes32();
        verifierState.columnLogSizes = TreeVec.newUint32Array();
        verifierState.nTrees = 0;
    }

    /// @notice Add commitment tree to verifier
    /// @param commitment Tree root hash
    /// @param logSizes Column log sizes for this tree
    /// @param channel Channel for Fiat-Shamir mixing
    function commit(
        bytes32 commitment,
        uint32[] calldata logSizes,
        IChannel channel
    ) external {
        // Mix commitment root into channel
        channel.mixRoot(channel.getDigest(), commitment);
        
        // Calculate extended log sizes with FRI blowup factor
        uint32[] memory extendedLogSizes = PcsConfig.getExtendedLogSizes(
            logSizes,
            verifierState.config.friConfig
        );
        
        // Add to verifier state
        verifierState.treeRoots = verifierState.treeRoots.push(commitment);
        verifierState.columnLogSizes = verifierState.columnLogSizes.push(extendedLogSizes);
        verifierState.nTrees++;
        
        emit CommitmentAdded(verifierState.nTrees - 1, commitment);
    }

    /// @notice Verify commitment scheme proof
    /// @param samplePoints Circle points where polynomials are sampled
    /// @param proof Commitment scheme proof
    /// @param channel Channel for Fiat-Shamir randomness
    /// @return True if verification succeeds
    function verifyValues(
        CirclePoint.Point[] calldata samplePoints,
        Proof calldata proof,
        IChannel channel
    ) external returns (bool) {
        bytes32 proofHash = keccak256(abi.encode(proof));
        emit VerificationStarted(proofHash);
        
        try this._verifyValuesInternal(samplePoints, proof, channel) returns (bool success) {
            emit VerificationCompleted(success);
            return success;
        } catch Error(string memory reason) {
            emit VerificationCompleted(false);
            revert(reason);
        }
    }

    /// @notice Internal verification logic (for error handling)
    /// @param proof Commitment scheme proof  
    /// @param channel Channel for Fiat-Shamir randomness
    /// @return True if verification succeeds
    function _verifyValuesInternal(
        CirclePoint.Point[] calldata, /* samplePoints */
        Proof calldata proof,
        IChannel channel
    ) external returns (bool) {
        // Step 1: Validate proof structure
        _validateProofStructure(proof);
        
        // Step 2: Mix sampled values into channel
        _mixSampledValues(proof.sampledValues, channel);
        
        // Step 3: Draw random coefficient for batching
        /* QM31Field.QM31 memory randomCoeff = */ channel.drawSecureFelt();
        
        // Step 4: Verify proof of work
        if (!channel.verifyPowNonce(verifierState.config.powBits, proof.proofOfWork)) {
            revert ProofOfWorkFailed(verifierState.config.powBits, proof.proofOfWork);
        }
        
        // Step 5: Mix proof of work nonce
        channel.mixU64(proof.proofOfWork);
        
        // Step 6: Sample FRI query positions (simplified for now)
        uint256[] memory queryPositions = _sampleQueryPositions(channel);
        
        // Step 7: Verify Merkle decommitments
        if (!_verifyMerkleDecommitments(queryPositions, proof)) {
            return false;
        }
        
        // Step 8: Verify FRI proof (placeholder)
        if (!_verifyFriProof(proof.friProof, queryPositions)) {
            revert FriVerificationFailed("FRI verification not implemented");
        }
        
        return true;
    }

    /// @notice Validate proof structure and consistency
    /// @param proof Proof to validate
    function _validateProofStructure(Proof calldata proof) internal view {
        if (proof.commitments.length != verifierState.nTrees) {
            revert InvalidProofStructure("Commitment count mismatch");
        }
        
        if (proof.sampledValues.length == 0) {
            revert InvalidProofStructure("Empty sampled values");
        }
        
        if (proof.decommitments.length != verifierState.nTrees) {
            revert InvalidProofStructure("Decommitment count mismatch");
        }
    }

    /// @notice Mix sampled values into channel
    /// @param sampledValues Values to mix
    /// @param channel Channel for mixing
    function _mixSampledValues(QM31Field.QM31[] calldata sampledValues, IChannel channel) internal {
        // Convert QM31 to bytes and mix
        for (uint256 i = 0; i < sampledValues.length; i++) {
            uint32[4] memory components = QM31Field.toM31Array(sampledValues[i]);
            uint32[] memory componentsArray = new uint32[](4);
            componentsArray[0] = components[0];
            componentsArray[1] = components[1];
            componentsArray[2] = components[2];
            componentsArray[3] = components[3];
            channel.mixU32s(componentsArray);
        }
    }

    /// @notice Sample FRI query positions from channel
    /// @param channel Channel for randomness
    /// @return Array of query positions
    function _sampleQueryPositions(IChannel channel) internal returns (uint256[] memory) {
        // Simplified query sampling - full implementation would use FRI verifier
        uint256 nQueries = verifierState.config.friConfig.nQueries;
        uint256[] memory positions = new uint256[](nQueries);
        
        for (uint256 i = 0; i < nQueries; i++) {
            // Draw random position (simplified)
            uint32[] memory randomU32s = channel.drawU32s();
            positions[i] = randomU32s[0] % (1 << 20); // Limit to reasonable range
        }
        
        return positions;
    }

    /// @notice Verify Merkle decommitments for all trees
    /// @param queryPositions Positions to verify
    /// @param proof Proof containing decommitments
    /// @return True if all decommitments are valid
    function _verifyMerkleDecommitments(
        uint256[] memory queryPositions,
        Proof calldata proof
    ) internal view returns (bool) {
        for (uint256 treeIndex = 0; treeIndex < verifierState.nTrees; treeIndex++) {
            if (!_verifyTreeDecommitment(treeIndex, queryPositions, proof)) {
                revert MerkleDecommitmentFailed(treeIndex);
            }
        }
        return true;
    }

    /// @notice Verify decommitment for single tree
    /// @param treeIndex Index of tree to verify
    /// @param queryPositions Positions to verify
    /// @param proof Proof containing decommitment
    /// @return True if decommitment is valid
    function _verifyTreeDecommitment(
        uint256 treeIndex,
        uint256[] memory queryPositions,
        Proof calldata proof
    ) internal view returns (bool) {
        // Get tree root and column configuration
        bytes32 treeRoot = verifierState.treeRoots.get(treeIndex);
        uint32[] memory columnLogSizes = verifierState.columnLogSizes.get(treeIndex);
        
        // Create Merkle verifier for this tree
        MerkleVerifier.Verifier memory merkleVerifier = MerkleVerifier.create(
            treeRoot,
            columnLogSizes
        );
        
        // Decode decommitment (simplified - would need proper decoding)
        MerkleVerifier.Decommitment memory decommitment = _decodeDecommitment(
            proof.decommitments[treeIndex]
        );
        
        // Create query from positions and expected values
        MerkleVerifier.Query memory query = MerkleVerifier.Query({
            positions: queryPositions,
            expectedValues: _getExpectedValues(queryPositions, proof.queriedValues)
        });
        
        // Verify using Merkle verifier
        return merkleVerifier.verify(query, decommitment);
    }

    /// @notice Verify FRI proof (placeholder implementation)
    /// @param friProof FRI proof data
    /// @param queryPositions Query positions
    /// @return True if FRI verification succeeds
    function _verifyFriProof(
        bytes calldata friProof,
        uint256[] memory queryPositions
    ) internal pure returns (bool) {
        // Placeholder - real implementation would verify FRI layers
        return friProof.length > 0 && queryPositions.length > 0;
    }

    /// @notice Convert hash to uint32 array for channel mixing
    /// @param hash Hash to convert
    /// @return Array of uint32 values
    function _hashToU32Array(bytes32 hash) internal pure returns (uint32[] memory) {
        uint32[] memory result = new uint32[](8);
        for (uint256 i = 0; i < 8; i++) {
            result[i] = uint32(bytes4(hash << (i * 32)));
        }
        return result;
    }

    /// @notice Decode Merkle decommitment from bytes (placeholder)
    /// @return Decoded decommitment
    function _decodeDecommitment(bytes calldata /* data */) internal pure returns (MerkleVerifier.Decommitment memory) {
        // Placeholder decoding - real implementation would properly decode
        return MerkleVerifier.Decommitment({
            hashWitness: new bytes32[](0),
            columnWitness: new uint32[](0)
        });
    }

    /// @notice Get expected values for query positions
    /// @param queryPositions Query positions
    /// @param queriedValues All queried values
    /// @return Expected values for positions
    function _getExpectedValues(
        uint256[] memory queryPositions,
        uint32[] calldata queriedValues
    ) internal pure returns (uint32[] memory) {
        uint32[] memory expected = new uint32[](queryPositions.length);
        for (uint256 i = 0; i < queryPositions.length && i < queriedValues.length; i++) {
            expected[i] = queriedValues[i];
        }
        return expected;
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    /// @notice Get verifier configuration
    /// @return Current PCS configuration
    function getConfig() external view returns (PcsConfig.Config memory) {
        return verifierState.config;
    }

    /// @notice Get number of commitment trees
    /// @return Number of trees
    function getTreeCount() external view returns (uint256) {
        return verifierState.nTrees;
    }

    /// @notice Get tree root by index
    /// @param index Tree index
    /// @return Tree root hash
    function getTreeRoot(uint256 index) external view returns (bytes32) {
        return verifierState.treeRoots.get(index);
    }

    /// @notice Get column log sizes for tree
    /// @param index Tree index
    /// @return Column log sizes
    function getColumnLogSizes(uint256 index) external view returns (uint32[] memory) {
        return verifierState.columnLogSizes.get(index);
    }
}