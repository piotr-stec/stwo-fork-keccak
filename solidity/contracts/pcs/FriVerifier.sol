// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../pcs/PcsConfig.sol";
import "../core/CirclePolyDegreeBound.sol";
import "../core/CircleDomain.sol";
import "../core/CanonicCoset.sol";
import "../fields/QM31Field.sol";
import "../channel/IChannel.sol";
import "../libraries/KeccakChannelLib.sol";
import "../vcs/MerkleVerifier.sol";

/// @title FriVerifier
/// @notice Library for FRI (Fast Reed-Solomon Interactive) proximity proof verification
/// @dev Implements the verifier side of FRI protocol using Keccak-based Merkle channel
library FriVerifier {
    using PcsConfig for PcsConfig.FriConfig;
    using CirclePolyDegreeBound for CirclePolyDegreeBound.Bound;
    using QM31Field for QM31Field.QM31;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using MerkleVerifier for MerkleVerifier.Verifier;

    /// @notice FRI verifier state for commitment phase
    /// @param config FRI configuration parameters
    /// @param firstLayer First layer verifier state
    /// @param innerLayers Array of inner layer verifier states
    /// @param lastLayerDomainLogSize Log size of last layer domain
    /// @param lastLayerPoly Coefficients of last layer polynomial
    /// @param queries Query positions for decommitment (set after sampling)
    struct VerifierState {
        PcsConfig.FriConfig config;
        FriFirstLayerVerifier firstLayer;
        FriInnerLayerVerifier[] innerLayers;
        uint32 lastLayerDomainLogSize;
        QM31Field.QM31[] lastLayerPoly;
        uint256[] queries;  // Set when queries are sampled
        bool queriesSampled;
    }

    /// @notice First layer verifier containing column degree bounds and domains
    /// @param columnBounds Circle polynomial degree bounds in descending order
    /// @param columnCommitmentDomains Commitment domains for each column
    /// @param foldingAlpha Random folding coefficient from channel
    /// @param proof First layer proof data
    struct FriFirstLayerVerifier {
        CirclePolyDegreeBound.Bound[] columnBounds;
        CircleDomain.CircleDomainStruct[] columnCommitmentDomains;
        QM31Field.QM31 foldingAlpha;
        FriLayerProof proof;
    }

    /// @notice Inner layer verifier for FRI intermediate layers
    /// @param degreeBound Degree bound for this layer
    /// @param domainLogSize Log size of layer domain  
    /// @param foldingAlpha Random folding coefficient from channel
    /// @param layerIndex Index of this layer (for error reporting)
    /// @param proof Layer proof data
    struct FriInnerLayerVerifier {
        uint32 degreeBound;
        uint32 domainLogSize;
        QM31Field.QM31 foldingAlpha;
        uint256 layerIndex;
        FriLayerProof proof;
    }

    /// @notice Proof for individual FRI layer
    /// @param friWitness Values needed by verifier that cannot be deduced
    /// @param decommitment Merkle decommitment proof  
    /// @param commitment Merkle tree root commitment
    struct FriLayerProof {
        QM31Field.QM31[] friWitness;
        bytes decommitment;  // Encoded MerkleDecommitment
        bytes32 commitment;
    }

    /// @notice Complete FRI proof structure
    /// @param firstLayer First layer proof
    /// @param innerLayers Array of inner layer proofs
    /// @param lastLayerPoly Last layer polynomial coefficients
    struct FriProof {
        FriLayerProof firstLayer;
        FriLayerProof[] innerLayers;
        QM31Field.QM31[] lastLayerPoly;
    }

    /// @notice FRI verification error types
    error InvalidNumFriLayers();
    error FirstLayerEvaluationsInvalid();
    error FirstLayerCommitmentInvalid();
    error InnerLayerEvaluationsInvalid(uint256 layerIndex);
    error InnerLayerCommitmentInvalid(uint256 layerIndex);
    error LastLayerDegreeInvalid();
    error LastLayerEvaluationsInvalid();
    error ColumnBoundsNotSorted();
    error EmptyColumnBounds();

    /// @notice Events for debugging and monitoring
    event FriCommitmentStarted(uint256 indexed numLayers);
    event FriLayerCommitted(uint256 indexed layerIndex, bytes32 indexed commitment);
    event FriCommitmentCompleted(bool indexed success);

    /// @notice FRI constants
    uint32 public constant FOLD_STEP = 1;
    uint32 public constant CIRCLE_TO_LINE_FOLD_STEP = 1;

    /// @notice Verify the commitment stage of FRI
    /// @dev Verifies FRI commitments and prepares verifier state for decommitment
    /// @param channelState Keccak channel state for Fiat-Shamir
    /// @param config FRI configuration parameters
    /// @param proof Complete FRI proof
    /// @param columnBounds Circle polynomial degree bounds in descending order
    /// @return verifierState Initialized verifier state for decommitment
    function commit(
        KeccakChannelLib.ChannelState storage channelState,
        PcsConfig.FriConfig memory config,
        FriProof memory proof,
        CirclePolyDegreeBound.Bound[] memory columnBounds
    ) internal returns (VerifierState memory verifierState) {
        emit FriCommitmentStarted(proof.innerLayers.length + 1);

        // Validate inputs
        if (columnBounds.length == 0) {
            revert EmptyColumnBounds();
        }
        
        // Verify column bounds are sorted in descending order
        for (uint256 i = 1; i < columnBounds.length; i++) {
            if (columnBounds[i-1].logDegreeBound < columnBounds[i].logDegreeBound) {
                revert ColumnBoundsNotSorted();
            }
        }

        // Mix first layer commitment into channel
        channelState.mixRoot(channelState.digest, proof.firstLayer.commitment);
        emit FriLayerCommitted(0, proof.firstLayer.commitment);

        // Calculate column commitment domains
        CircleDomain.CircleDomainStruct[] memory columnCommitmentDomains = 
            new CircleDomain.CircleDomainStruct[](columnBounds.length);
        
        for (uint256 i = 0; i < columnBounds.length; i++) {
            uint32 commitmentDomainLogSize = 
                columnBounds[i].logDegreeBound + config.logBlowupFactor;
            CanonicCoset.CanonicCosetStruct memory canonicCoset = 
                CanonicCoset.newCanonicCoset(commitmentDomainLogSize);
            Coset.CosetStruct memory halfCoset = CanonicCoset.halfCoset(canonicCoset);
            columnCommitmentDomains[i] = CircleDomain.newCircleDomain(halfCoset);
        }

        // Create first layer verifier
        FriFirstLayerVerifier memory firstLayer = FriFirstLayerVerifier({
            columnBounds: columnBounds,
            columnCommitmentDomains: columnCommitmentDomains,
            foldingAlpha: channelState.drawSecureFelt(),
            proof: proof.firstLayer
        });

        // Process inner layers
        FriInnerLayerVerifier[] memory innerLayers = 
            new FriInnerLayerVerifier[](proof.innerLayers.length);

        // Start with max column bound folded to line
        uint32 layerBound = columnBounds[0].logDegreeBound - CIRCLE_TO_LINE_FOLD_STEP;
        uint32 layerDomainLogSize = layerBound + config.logBlowupFactor;

        for (uint256 i = 0; i < proof.innerLayers.length; i++) {
            // Mix layer commitment into channel
            channelState.mixRoot(channelState.digest, proof.innerLayers[i].commitment);
            emit FriLayerCommitted(i + 1, proof.innerLayers[i].commitment);

            // Create inner layer verifier
            innerLayers[i] = FriInnerLayerVerifier({
                degreeBound: layerBound,
                domainLogSize: layerDomainLogSize,
                foldingAlpha: channelState.drawSecureFelt(),
                layerIndex: i,
                proof: proof.innerLayers[i]
            });

            // Fold for next layer
            if (layerBound < FOLD_STEP) {
                revert InvalidNumFriLayers();
            }
            layerBound -= FOLD_STEP;
            layerDomainLogSize = layerBound + config.logBlowupFactor;
        }

        // Verify final layer bound matches config
        if (layerBound != config.logLastLayerDegreeBound) {
            revert InvalidNumFriLayers();
        }

        // Verify last layer polynomial degree
        uint256 maxLastLayerSize = 1 << config.logLastLayerDegreeBound;
        if (proof.lastLayerPoly.length > maxLastLayerSize) {
            revert LastLayerDegreeInvalid();
        }

        // Mix last layer polynomial into channel
        _mixQM31Array(channelState, proof.lastLayerPoly);

        // Initialize verifier state
        verifierState = VerifierState({
            config: config,
            firstLayer: firstLayer,
            innerLayers: innerLayers,
            lastLayerDomainLogSize: layerDomainLogSize,
            lastLayerPoly: proof.lastLayerPoly,
            queries: new uint256[](0),
            queriesSampled: false
        });

        emit FriCommitmentCompleted(true);
    }

    /// @notice Sample query positions for FRI decommitment
    /// @dev Uses channel randomness to sample query positions
    /// @param verifierState FRI verifier state
    /// @param channelState Keccak channel for randomness
    function sampleQueryPositions(
        VerifierState storage verifierState,
        KeccakChannelLib.ChannelState storage channelState
    ) internal {
        // Find maximum column log size
        uint32 maxColumnLogSize = 0;
        for (uint256 i = 0; i < verifierState.firstLayer.columnCommitmentDomains.length; i++) {
            uint32 logSize = CircleDomain.logSize(verifierState.firstLayer.columnCommitmentDomains[i]);
            if (logSize > maxColumnLogSize) {
                maxColumnLogSize = logSize;
            }
        }

        // Sample queries on maximum domain
        uint256[] memory queries = new uint256[](verifierState.config.nQueries);
        for (uint256 i = 0; i < verifierState.config.nQueries; i++) {
            uint32[] memory randomU32s = channelState.drawU32s();
            queries[i] = randomU32s[0] % (1 << maxColumnLogSize);
        }

        // Store queries in verifier state
        verifierState.queries = queries;
        verifierState.queriesSampled = true;

        // Note: In full implementation, would return query positions mapped by log size
        // For now, simplified to store in verifier state
    }

    /// @notice Mix QM31 array into channel
    /// @dev Helper function to mix polynomial coefficients
    /// @param channelState Channel state for mixing
    /// @param values Array of QM31 values to mix
    function _mixQM31Array(
        KeccakChannelLib.ChannelState storage channelState,
        QM31Field.QM31[] memory values
    ) private {
        for (uint256 i = 0; i < values.length; i++) {
            uint32[4] memory components = QM31Field.toM31Array(values[i]);
            uint32[] memory componentsArray = new uint32[](4);
            componentsArray[0] = components[0];
            componentsArray[1] = components[1];
            componentsArray[2] = components[2];
            componentsArray[3] = components[3];
            channelState.mixU32s(componentsArray);
        }
    }

    /// @notice Get maximum column log size from first layer domains
    /// @param verifierState FRI verifier state
    /// @return maxLogSize Maximum log size among all column domains
    function getMaxColumnLogSize(VerifierState memory verifierState) 
        internal 
        pure 
        returns (uint32 maxLogSize) 
    {
        maxLogSize = 0;
        for (uint256 i = 0; i < verifierState.firstLayer.columnCommitmentDomains.length; i++) {
            uint32 logSize = CircleDomain.logSize(verifierState.firstLayer.columnCommitmentDomains[i]);
            if (logSize > maxLogSize) {
                maxLogSize = logSize;
            }
        }
    }

    /// @notice Get number of expected inner layers based on degree bounds and config
    /// @param maxColumnBound Maximum column degree bound
    /// @param config FRI configuration
    /// @return expectedLayers Number of expected inner layers
    function getExpectedInnerLayers(
        CirclePolyDegreeBound.Bound memory maxColumnBound,
        PcsConfig.FriConfig memory config
    ) internal pure returns (uint256 expectedLayers) {
        uint32 currentBound = maxColumnBound.logDegreeBound - CIRCLE_TO_LINE_FOLD_STEP;
        expectedLayers = 0;
        
        while (currentBound > config.logLastLayerDegreeBound) {
            if (currentBound < FOLD_STEP) break;
            currentBound -= FOLD_STEP;
            expectedLayers++;
        }
    }

    /// @notice Validate FRI configuration parameters
    /// @param config FRI configuration to validate
    /// @return valid True if configuration is valid
    function validateConfig(PcsConfig.FriConfig memory config) 
        internal 
        pure 
        returns (bool valid) 
    {
        // Validate blowup factor range (1 to 16)
        if (config.logBlowupFactor < 1 || config.logBlowupFactor > 16) {
            return false;
        }
        
        // Validate last layer degree bound (0 to 10)
        if (config.logLastLayerDegreeBound > 10) {
            return false;
        }
        
        // Validate non-zero queries
        if (config.nQueries == 0) {
            return false;
        }
        
        return true;
    }

    /// @notice Calculate security level in bits
    /// @param config FRI configuration
    /// @return securityBits Estimated security level
    function getSecurityBits(PcsConfig.FriConfig memory config) 
        internal 
        pure 
        returns (uint32 securityBits) 
    {
        return config.logBlowupFactor * uint32(config.nQueries);
    }
}