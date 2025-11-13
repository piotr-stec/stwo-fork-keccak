// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../pcs/TreeVec.sol";
import "../pcs/PcsConfig.sol";
import "../vcs/MerkleVerifier.sol";
import "../core/CirclePoint.sol";
import "../core/CirclePolyDegreeBound.sol";
import "../fields/QM31Field.sol";
import "../channel/IChannel.sol";
import "../utils/ArrayUtils.sol";
import "./KeccakChannelLib.sol";

/// @title CommitmentSchemeVerifierLib
/// @notice Library for verifying polynomial commitment scheme proofs using FRI and Merkle trees
/// @dev Stateless library for STWO commitment scheme with state stored in calling contract
library CommitmentSchemeVerifierLib {
    using TreeVec for TreeVec.Bytes32TreeVec;
    using TreeVec for TreeVec.Uint32ArrayTreeVec;
    using PcsConfig for PcsConfig.Config;
    using MerkleVerifier for MerkleVerifier.Verifier;
    using QM31Field for QM31Field.QM31;
    using CirclePoint for CirclePoint.Point;
    using CirclePolyDegreeBound for CirclePolyDegreeBound.Bound;
    using ArrayUtils for TreeVec.Uint32ArrayTreeVec;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;

    /// @notice Verifier state containing trees and configuration
    /// @param trees TreeVec of Merkle verifiers for each commitment tree
    /// @param config PCS configuration (FRI + PoW parameters)
    struct VerifierState {
        MerkleVerifier.Verifier merkleVerifier;    // Multi-tree Merkle verifier
        PcsConfig.Config config;                    // PCS configuration
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

    /// @notice Events for debugging and monitoring
    event CommitmentAdded(uint256 indexed treeIndex, bytes32 indexed root);
    event VerificationStarted(bytes32 indexed proofHash);
    event VerificationCompleted(bool indexed success);

    /// @notice Initialize verifier state with configuration and trees
    /// @param state Verifier state to initialize
    /// @param config PCS configuration
    /// @param treeRoots Array of Merkle tree roots (from proof commitments)
    /// @param treeColumnLogSizes Array of column log sizes arrays (one per tree)
    function initialize(
        VerifierState storage state, 
        PcsConfig.Config memory config,
        bytes32[] memory treeRoots,
        uint32[][] memory treeColumnLogSizes
    ) internal {
        require(PcsConfig.isValidConfig(config), "Invalid PCS configuration");
        require(treeRoots.length == treeColumnLogSizes.length, "Mismatched trees and column sizes");
        
        state.config = config;
        
        // Create Merkle verifier with all trees
        state.merkleVerifier = MerkleVerifier.newVerifier(treeRoots, treeColumnLogSizes);
    }
    
    /// @notice Initialize verifier state with configuration only (for incremental tree addition)
    /// @param state Verifier state to initialize
    /// @param config PCS configuration
    function initializeEmpty(VerifierState storage state, PcsConfig.Config memory config) internal {
        require(PcsConfig.isValidConfig(config), "Invalid PCS configuration");
        
        state.config = config;
        // Initialize empty merkle verifier (trees will be added via commit)
        delete state.merkleVerifier;
    }

    /// @notice Clear verifier state after verification
    /// @param state Verifier state to clear
    function clearState(VerifierState storage state) internal {
        // Clear merkle verifier
        delete state.merkleVerifier;
        // Keep config for reuse
    }

    /// @notice Add commitment tree to verifier
    /// @param state Verifier state
    /// @param commitment Tree root hash
    /// @param logSizes Column log sizes for this tree
    /// @param channelState Channel state for Fiat-Shamir mixing
    function commit(
        VerifierState storage state,
        bytes32 commitment,
        uint32[] memory logSizes,
        KeccakChannelLib.ChannelState storage channelState
    ) internal {
        // Mix commitment root into channel
        channelState.mixRoot(channelState.digest, commitment);
        
        // Calculate extended log sizes (add blowup factor)
        uint32[] memory extendedLogSizes = new uint32[](logSizes.length);
        for (uint256 i = 0; i < logSizes.length; i++) {
            extendedLogSizes[i] = logSizes[i] + state.config.friConfig.logBlowupFactor;
        }
        
        // Create new tree and add to verifier
        MerkleVerifier.MerkleTree memory newTree = MerkleVerifier.createMerkleTree(
            commitment,
            extendedLogSizes
        );
        
        // Add tree to verifier (expand trees array)
        uint256 currentLength = state.merkleVerifier.trees.length;
        MerkleVerifier.MerkleTree[] memory newTrees = new MerkleVerifier.MerkleTree[](currentLength + 1);
        for (uint256 i = 0; i < currentLength; i++) {
            newTrees[i] = state.merkleVerifier.trees[i];
        }
        newTrees[currentLength] = newTree;
        state.merkleVerifier.trees = newTrees;
        
    }

    /// @notice Verify commitment scheme proof
    /// @param state Verifier state
    /// @param samplePoints Circle points where polynomials are sampled
    /// @param proof Commitment scheme proof
    /// @param channelState Channel state for Fiat-Shamir randomness
    /// @return True if verification succeeds
    function verifyValues(
        VerifierState storage state,
        CirclePoint.Point[] calldata samplePoints,
        Proof calldata proof,
        KeccakChannelLib.ChannelState storage channelState
    ) internal returns (bool) {
        bytes32 proofHash = keccak256(abi.encode(proof));
        emit VerificationStarted(proofHash);
        
        // Step 1: Validate proof structure
        _validateProofStructure(state, proof);
        
        // Step 2: Mix sampled values into channel
        _mixSampledValues(proof.sampledValues, channelState);
        
        // Step 3: Draw random coefficient for batching
        /* QM31Field.QM31 memory randomCoeff = */ channelState.drawSecureFelt();
        
        // Step 4: Verify proof of work
        if (!channelState.verifyPowNonce(state.config.powBits, proof.proofOfWork)) {
            revert ProofOfWorkFailed(state.config.powBits, proof.proofOfWork);
        }
        
        // Step 5: Mix proof of work nonce
        channelState.mixU64(proof.proofOfWork);
        
        // Step 6: Sample FRI query positions (simplified for now)
        uint256[] memory queryPositions = _sampleQueryPositions(state, channelState);
        
        // // Step 7: Verify Merkle decommitments
        // if (!_verifyMerkleDecommitments(state, queryPositions, proof)) {
        //     emit VerificationCompleted(false);
        //     return false;
        // }
        
        // Step 8: Verify FRI proof (placeholder)
        if (!_verifyFriProof(proof.friProof, queryPositions)) {
            revert FriVerificationFailed("FRI verification not implemented");
        }
        
        emit VerificationCompleted(true);
        return true;
    }

    /// @notice Validate proof structure and consistency
    /// @param state Verifier state
    /// @param proof Proof to validate
    function _validateProofStructure(VerifierState storage state, Proof calldata proof) private view {
        if (proof.commitments.length != state.merkleVerifier.trees.length) {
            revert InvalidProofStructure("Commitment count mismatch");
        }
        
        if (proof.sampledValues.length == 0) {
            revert InvalidProofStructure("Empty sampled values");
        }
        
        if (proof.decommitments.length != state.merkleVerifier.trees.length) {
            revert InvalidProofStructure("Decommitment count mismatch");
        }
    }

    /// @notice Mix sampled values into channel
    /// @param sampledValues Values to mix
    /// @param channelState Channel state for mixing
    function _mixSampledValues(
        QM31Field.QM31[] calldata sampledValues, 
        KeccakChannelLib.ChannelState storage channelState
    ) private {
        // Convert QM31 to bytes and mix
        for (uint256 i = 0; i < sampledValues.length; i++) {
            uint32[4] memory components = QM31Field.toM31Array(sampledValues[i]);
            uint32[] memory componentsArray = new uint32[](4);
            componentsArray[0] = components[0];
            componentsArray[1] = components[1];
            componentsArray[2] = components[2];
            componentsArray[3] = components[3];
            channelState.mixU32s(componentsArray);
        }
    }

    /// @notice Sample FRI query positions from channel
    /// @param state Verifier state
    /// @param channelState Channel state for randomness
    /// @return Array of query positions
    function _sampleQueryPositions(
        VerifierState storage state,
        KeccakChannelLib.ChannelState storage channelState
    ) private returns (uint256[] memory) {
        // Simplified query sampling - full implementation would use FRI verifier
        uint256 nQueries = state.config.friConfig.nQueries;
        uint256[] memory positions = new uint256[](nQueries);
        
        for (uint256 i = 0; i < nQueries; i++) {
            // Draw random position (simplified)
            uint32[] memory randomU32s = channelState.drawU32s();
            positions[i] = randomU32s[0] % (1 << 20); // Limit to reasonable range
        }
        
        return positions;
    }

    // /// @notice Verify Merkle decommitments for all trees
    // /// @param state Verifier state
    // /// @param queryPositions Positions to verify
    // /// @param proof Proof containing decommitments
    // /// @return True if all decommitments are valid
    // function _verifyMerkleDecommitments(
    //     VerifierState storage state,
    //     uint256[] memory queryPositions,
    //     Proof calldata proof
    // ) private view returns (bool) {
    //     for (uint256 treeIndex = 0; treeIndex < state.nTrees; treeIndex++) {
    //         if (!_verifyTreeDecommitment(state, treeIndex, queryPositions, proof)) {
    //             revert MerkleDecommitmentFailed(treeIndex);
    //         }
    //     }
    //     return true;
    // }

    // /// @notice Verify decommitment for single tree
    // /// @param state Verifier state
    // /// @param treeIndex Index of tree to verify
    // /// @param queryPositions Positions to verify
    // /// @param proof Proof containing decommitment
    // /// @return True if decommitment is valid
    // function _verifyTreeDecommitment(
    //     VerifierState storage state,
    //     uint256 treeIndex,
    //     uint256[] memory queryPositions,
    //     Proof calldata proof
    // ) private view returns (bool) {
    //     // Get tree root and column configuration
    //     bytes32 treeRoot = state.treeRoots.get(treeIndex);
    //     uint32[] memory columnLogSizes = state.columnLogSizes.get(treeIndex);
        
    //     // Create Merkle verifier for this tree
    //     MerkleVerifier.Verifier memory merkleVerifier = MerkleVerifier.create(
    //         treeRoot,
    //         columnLogSizes
    //     );
        
    //     // Decode decommitment (simplified - would need proper decoding)
    //     MerkleVerifier.Decommitment memory decommitment = _decodeDecommitment(
    //         proof.decommitments[treeIndex]
    //     );
        
    //     // Prepare queries per log size format (matches new MerkleVerifier)
    //     MerkleVerifier.QueriesPerLogSize[] memory queriesPerLogSize = _prepareQueriesPerLogSize(
    //         queryPositions, 
    //         columnLogSizes
    //     );
        
    //     // Get expected values for verification
    //     uint32[] memory expectedValues = _getExpectedValues(queryPositions, proof.queriedValues);
        
    //     // Verify using new Merkle verifier API
    //     try MerkleVerifier.verify(
    //         merkleVerifier,
    //         queriesPerLogSize,
    //         expectedValues,
    //         decommitment
    //     ) {
    //         return true;
    //     } catch {
    //         return false;
    //     }
    // }

    /// @notice Verify FRI proof (placeholder implementation)
    /// @param friProof FRI proof data
    /// @param queryPositions Query positions
    /// @return True if FRI verification succeeds
    function _verifyFriProof(
        bytes calldata friProof,
        uint256[] memory queryPositions
    ) private pure returns (bool) {
        // Placeholder - real implementation would verify FRI layers
        return friProof.length > 0 && queryPositions.length > 0;
    }

    /// @notice Decode Merkle decommitment from bytes (placeholder)
    /// @return Decoded decommitment
    function _decodeDecommitment(bytes calldata /* data */) private pure returns (MerkleVerifier.Decommitment memory) {
        // Placeholder decoding - real implementation would properly decode
        return MerkleVerifier.Decommitment({
            hashWitness: new bytes32[](0),
            columnWitness: new uint32[](0)
        });
    }

    /// @notice Prepare queries per log size format
    /// @param queryPositions Query positions
    /// @param columnLogSizes Column log sizes for organization
    /// @return Organized queries per log size
    function _prepareQueriesPerLogSize(
        uint256[] memory queryPositions,
        uint32[] memory columnLogSizes
    ) private pure returns (MerkleVerifier.QueriesPerLogSize[] memory) {
        if (columnLogSizes.length == 0) {
            return new MerkleVerifier.QueriesPerLogSize[](0);
        }
        
        // For simplicity, use the first (largest) log size
        // In full implementation, would organize by different log sizes
        MerkleVerifier.QueriesPerLogSize[] memory queries = new MerkleVerifier.QueriesPerLogSize[](1);
        queries[0] = MerkleVerifier.QueriesPerLogSize({
            logSize: columnLogSizes[0],
            queries: queryPositions
        });
        
        return queries;
    }

    /// @notice Get expected values for query positions
    /// @param queryPositions Query positions
    /// @param queriedValues All queried values
    /// @return Expected values for positions
    function _getExpectedValues(
        uint256[] memory queryPositions,
        uint32[] calldata queriedValues
    ) private pure returns (uint32[] memory) {
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
    /// @param state Verifier state
    /// @return Current PCS configuration
    function getConfig(VerifierState storage state) internal view returns (PcsConfig.Config memory) {
        return state.config;
    }

    /// @notice Get number of commitment trees
    /// @param state Verifier state
    /// @return Number of trees
    function getTreeCount(VerifierState storage state) internal view returns (uint256) {
        return state.merkleVerifier.trees.length;
    }

    /// @notice Get tree root by index
    /// @param state Verifier state
    /// @param index Tree index
    /// @return Tree root hash
    function getTreeRoot(VerifierState storage state, uint256 index) internal view returns (bytes32) {
        require(index < state.merkleVerifier.trees.length, "Tree index out of bounds");
        return state.merkleVerifier.trees[index].root;
    }

    /// @notice Get column log sizes for tree
    /// @param state Verifier state
    /// @param index Tree index
    /// @return Column log sizes
    function getColumnLogSizes(VerifierState storage state, uint256 index) internal view returns (uint32[] memory) {
        require(index < state.merkleVerifier.trees.length, "Tree index out of bounds");
        return state.merkleVerifier.trees[index].columnLogSizes;
    }

    /// @notice Get column log sizes for all trees (matches Rust column_log_sizes)
    /// @dev Maps to Rust: self.trees.as_ref().map(|tree| tree.column_log_sizes.clone())
    /// @param state Verifier state
    /// @return Array of column log sizes arrays (one per tree)
    function columnLogSizes(VerifierState storage state) internal view returns (uint32[][] memory) {
        uint32[][] memory result = new uint32[][](state.merkleVerifier.trees.length);
        for (uint256 i = 0; i < state.merkleVerifier.trees.length; i++) {
            result[i] = state.merkleVerifier.trees[i].columnLogSizes;
        }
        return result;
    }

    // =============================================================================
    // Bounds Calculation for FRI Verification
    // =============================================================================

    /// @notice Calculate degree bounds for FRI verification
    /// @dev Maps to Rust: self.column_log_sizes().flatten().sorted().rev().dedup()
    ///                    .map(|log_size| CirclePolyDegreeBound::new(log_size - self.config.fri_config.log_blowup_factor))
    /// @param state Verifier state containing column log sizes and config
    /// @return bounds Array of CirclePolyDegreeBound for FRI verification
    function calculateBounds(VerifierState storage state) 
        internal 
        view 
        returns (CirclePolyDegreeBound.Bound[] memory bounds) 
    {
        // Flatten all column log sizes from all trees
        uint32[] memory flattenedLogSizes = _flattenColumnLogSizes(state);
        
        // Sort, reverse, and deduplicate
        uint32[] memory processedLogSizes = _sortReverseDedup(flattenedLogSizes);
        
        // Map to CirclePolyDegreeBound
        uint32 logBlowupFactor = state.config.friConfig.logBlowupFactor;
        bounds = new CirclePolyDegreeBound.Bound[](processedLogSizes.length);
        
        for (uint256 i = 0; i < processedLogSizes.length; i++) {
            uint32 adjustedLogSize = processedLogSizes[i] - logBlowupFactor;
            bounds[i] = CirclePolyDegreeBound.create(adjustedLogSize);
        }
    }

    /// @notice Get flattened column log sizes for debugging
    /// @param state Verifier state
    /// @return flattened Flattened array of all column log sizes
    function getFlattenedColumnLogSizes(VerifierState storage state) 
        internal 
        view 
        returns (uint32[] memory flattened) 
    {
        return _flattenColumnLogSizes(state);
    }

    /// @notice Get processed column log sizes (sorted, reversed, deduplicated)
    /// @param state Verifier state  
    /// @return processed Processed array ready for bounds calculation
    function getProcessedColumnLogSizes(VerifierState storage state)
        internal
        view
        returns (uint32[] memory processed)
    {
        uint32[] memory flattened = _flattenColumnLogSizes(state);
        return _sortReverseDedup(flattened);
    }

    /// @notice Calculate bounds with explicit log blowup factor (for testing)
    /// @param state Verifier state
    /// @param logBlowupFactor Override log blowup factor
    /// @return bounds Array of CirclePolyDegreeBound
    function calculateBoundsWithBlowup(
        VerifierState storage state, 
        uint32 logBlowupFactor
    ) 
        internal 
        view 
        returns (CirclePolyDegreeBound.Bound[] memory bounds) 
    {
        uint32[] memory flattened = _flattenColumnLogSizes(state);
        uint32[] memory processedLogSizes = _sortReverseDedup(flattened);
        bounds = new CirclePolyDegreeBound.Bound[](processedLogSizes.length);
        
        for (uint256 i = 0; i < processedLogSizes.length; i++) {
            uint32 adjustedLogSize = processedLogSizes[i] - logBlowupFactor;
            bounds[i] = CirclePolyDegreeBound.create(adjustedLogSize);
        }
    }
    
    /// @notice Helper: Flatten column log sizes from all trees
    function _flattenColumnLogSizes(VerifierState storage state) 
        private 
        view 
        returns (uint32[] memory flattened) 
    {
        // Count total columns
        uint256 totalColumns = 0;
        for (uint256 i = 0; i < state.merkleVerifier.trees.length; i++) {
            totalColumns += state.merkleVerifier.trees[i].columnLogSizes.length;
        }
        
        // Flatten
        flattened = new uint32[](totalColumns);
        uint256 idx = 0;
        for (uint256 i = 0; i < state.merkleVerifier.trees.length; i++) {
            uint32[] memory treeColumns = state.merkleVerifier.trees[i].columnLogSizes;
            for (uint256 j = 0; j < treeColumns.length; j++) {
                flattened[idx++] = treeColumns[j];
            }
        }
    }
    
    /// @notice Helper: Sort, reverse, and deduplicate
    function _sortReverseDedup(uint32[] memory arr) 
        private 
        pure 
        returns (uint32[] memory result) 
    {
        if (arr.length == 0) return new uint32[](0);
        
        // Sort ascending (bubble sort - simple for small arrays)
        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = i + 1; j < arr.length; j++) {
                if (arr[i] < arr[j]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                }
            }
        }
        
        // Now arr is sorted descending (reversed)
        // Deduplicate
        uint32[] memory temp = new uint32[](arr.length);
        temp[0] = arr[0];
        uint256 uniqueCount = 1;
        
        for (uint256 i = 1; i < arr.length; i++) {
            if (arr[i] != arr[i-1]) {
                temp[uniqueCount++] = arr[i];
            }
        }
        
        // Copy to result
        result = new uint32[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            result[i] = temp[i];
        }
    }
}