// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../libraries/CommitmentSchemeVerifierLib.sol";
import "../libraries/KeccakChannelLib.sol";
import "../pcs/PcsConfig.sol";
import "./CirclePoint.sol";
import "../fields/QM31Field.sol";

/// @title STWOVerifier
/// @notice Main STWO verifier contract using library-based architecture for optimal gas efficiency
/// @dev Uses libraries to minimize deployment and initialization costs
contract STWOVerifier {
    using CommitmentSchemeVerifierLib for CommitmentSchemeVerifierLib.VerifierState;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using QM31Field for QM31Field.QM31;
    using CirclePoint for CirclePoint.Point;

    /// @notice Verifier state - stored once, reused for multiple verifications
    CommitmentSchemeVerifierLib.VerifierState private verifierState;
    
    /// @notice Channel state - cleared after each verification
    KeccakChannelLib.ChannelState private channelState;
    
    /// @notice Verification session tracking
    bool private verificationInProgress;

    /// @notice Events for monitoring
    event VerifierInitialized(PcsConfig.Config config);
    event VerificationSessionStarted();
    event VerificationSessionCompleted(bool success);
    event StateCleared();

    /// @notice Errors
    error VerificationAlreadyInProgress();
    error NoVerificationInProgress();
    error VerifierNotInitialized();

    /// @notice Initialize verifier with PCS configuration
    /// @param config PCS configuration (FRI + PoW parameters)
    function initialize(PcsConfig.Config memory config) external {
        verifierState.initialize(config);
        channelState.initialize();
        verificationInProgress = false;
        
        emit VerifierInitialized(config);
    }

    /// @notice Start new verification session
    /// @dev Clears previous state and prepares for new verification
    function startVerificationSession() external {
        if (verificationInProgress) {
            revert VerificationAlreadyInProgress();
        }
        
        // Clear previous verification state but keep configuration
        _clearVerificationState();
        verificationInProgress = true;
        
        emit VerificationSessionStarted();
    }

    /// @notice Add commitment tree to current verification session
    /// @param commitment Tree root hash
    /// @param logSizes Column log sizes for this tree
    function commit(bytes32 commitment, uint32[] calldata logSizes) external {
        if (!verificationInProgress) {
            revert NoVerificationInProgress();
        }
        
        verifierState.commit(commitment, logSizes, channelState);
    }

    /// @notice Verify commitment scheme proof and complete verification session
    /// @param samplePoints Circle points where polynomials are sampled
    /// @param proof Commitment scheme proof
    /// @return success True if verification succeeds
    function verifyAndComplete(
        CirclePoint.Point[] calldata samplePoints,
        CommitmentSchemeVerifierLib.Proof calldata proof
    ) external returns (bool success) {
        if (!verificationInProgress) {
            revert NoVerificationInProgress();
        }
        
        // Perform verification
        success = verifierState.verifyValues(samplePoints, proof, channelState);
        
        // End verification session
        verificationInProgress = false;
        
        // Clear verification state (but keep config for reuse)
        _clearVerificationState();
        
        emit VerificationSessionCompleted(success);
        return success;
    }

    /// @notice Emergency function to abort current verification session
    function abortVerificationSession() external {
        if (!verificationInProgress) {
            revert NoVerificationInProgress();
        }
        
        verificationInProgress = false;
        _clearVerificationState();
        
        emit VerificationSessionCompleted(false);
    }

    /// @notice One-shot verification function for convenience
    /// @param config PCS configuration
    /// @param commitments Array of commitment data
    /// @param samplePoints Circle points where polynomials are sampled
    /// @param proof Commitment scheme proof
    /// @return success True if verification succeeds
    function verifyProof(
        PcsConfig.Config memory config,
        CommitmentData[] calldata commitments,
        CirclePoint.Point[] calldata samplePoints,
        CommitmentSchemeVerifierLib.Proof calldata proof
    ) external returns (bool success) {
        // Initialize if needed
        if (verifierState.getTreeCount() == 0 || 
            !_configsEqual(verifierState.getConfig(), config)) {
            this.initialize(config);
        }
        
        // Start verification session
        this.startVerificationSession();
        
        // Add all commitments
        for (uint256 i = 0; i < commitments.length; i++) {
            this.commit(commitments[i].root, commitments[i].logSizes);
        }
        
        // Verify and complete
        return this.verifyAndComplete(samplePoints, proof);
    }

    /// @notice Clear verification state while preserving configuration
    function _clearVerificationState() private {
        // Clear commitment trees but keep config
        verifierState.clearState();
        
        // Reset channel state
        channelState.clearState();
        
        emit StateCleared();
    }

    /// @notice Compare two PCS configurations for equality
    /// @param config1 First configuration
    /// @param config2 Second configuration
    /// @return True if configurations are equal
    function _configsEqual(
        PcsConfig.Config memory config1, 
        PcsConfig.Config memory config2
    ) private pure returns (bool) {
        return config1.powBits == config2.powBits &&
               config1.friConfig.logBlowupFactor == config2.friConfig.logBlowupFactor &&
               config1.friConfig.logLastLayerDegreeBound == config2.friConfig.logLastLayerDegreeBound &&
               config1.friConfig.nQueries == config2.friConfig.nQueries;
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    /// @notice Get current verifier configuration
    /// @return Current PCS configuration
    function getConfig() external view returns (PcsConfig.Config memory) {
        return verifierState.getConfig();
    }

    /// @notice Get number of commitment trees in current session
    /// @return Number of trees
    function getTreeCount() external view returns (uint256) {
        return verifierState.getTreeCount();
    }

    /// @notice Get tree root by index
    /// @param index Tree index
    /// @return Tree root hash
    function getTreeRoot(uint256 index) external view returns (bytes32) {
        return verifierState.getTreeRoot(index);
    }

    /// @notice Get column log sizes for tree
    /// @param index Tree index
    /// @return Column log sizes
    function getColumnLogSizes(uint256 index) external view returns (uint32[] memory) {
        return verifierState.getColumnLogSizes(index);
    }

    /// @notice Get current channel digest
    /// @return Current channel digest
    function getChannelDigest() external view returns (bytes32) {
        return channelState.digest;
    }

    /// @notice Check if verification is currently in progress
    /// @return True if verification session is active
    function isVerificationInProgress() external view returns (bool) {
        return verificationInProgress;
    }

    /// @notice Get gas cost estimation for verification
    /// @param nCommitments Number of commitment trees
    /// @param nQueries Number of FRI queries
    /// @return Estimated gas cost
    function estimateVerificationGas(
        uint256 nCommitments, 
        uint256 nQueries
    ) external pure returns (uint256) {
        // Rough estimation based on operations
        uint256 baseGas = 50000; // Base verification overhead
        uint256 commitmentGas = nCommitments * 10000; // Per commitment
        uint256 queryGas = nQueries * 5000; // Per query
        
        return baseGas + commitmentGas + queryGas;
    }

    /// @notice Commitment data structure for batch operations
    struct CommitmentData {
        bytes32 root;
        uint32[] logSizes;
    }

}