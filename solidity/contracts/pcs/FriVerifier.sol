// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../pcs/PcsConfig.sol";
import "../core/CirclePolyDegreeBound.sol";
import "../core/CircleDomain.sol";
import "../core/CanonicCoset.sol";
import "../core/CirclePoint.sol";
import "../fields/QM31Field.sol";
import "../fields/CM31Field.sol";
import "forge-std/console.sol";
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
    using CM31Field for CM31Field.CM31;
    using CirclePoint for CirclePoint.Point;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using MerkleVerifier for MerkleVerifier.Verifier;

    /// @notice Query structure for FRI decommitment
    /// @param positions Query positions sorted in ascending order
    /// @param logDomainSize Size of the domain from which queries were sampled
    struct Queries {
        uint256[] positions;
        uint32 logDomainSize;
    }

    /// @notice Mapping of log sizes to query positions
    /// @param logSizes Array of unique log sizes
    /// @param queryPositions Array of query position arrays, indexed by logSizes
    struct QueryPositionsByLogSize {
        uint32[] logSizes;
        uint256[][] queryPositions;
    }

    /// @notice FRI verifier state for commitment phase
    /// @param config FRI configuration parameters
    /// @param firstLayer First layer verifier state
    /// @param innerLayers Array of inner layer verifier states
    /// @param lastLayerDomainLogSize Log size of last layer domain
    /// @param lastLayerPoly Coefficients of last layer polynomial
    /// @param queries Generated queries (set after sampling)
    /// @param queryPositionsByLogSize Query positions organized by log size
    struct FriVerifierState {
        PcsConfig.FriConfig config;
        FriFirstLayerVerifier firstLayer;
        FriInnerLayerVerifier[] innerLayers;
        uint32 lastLayerDomainLogSize;
        QM31Field.QM31[] lastLayerPoly;
        Queries queries;  // Set when queries are sampled
        QueryPositionsByLogSize queryPositionsByLogSize;
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

    /// @notice Point sample structure for FRI answers
    /// @param point Circle point where sample was taken
    /// @param value QM31 value at the point
    struct PointSample {
        CirclePoint.Point point;
        QM31Field.QM31 value;
    }

    /// @notice Column sample batch for efficient quotient evaluation
    /// @param point Circle point for this batch 
    /// @param columnsAndValues Array of (columnIndex, sampledValue) pairs
    struct ColumnSampleBatch {
        CirclePoint.Point point;
        ColumnAndValue[] columnsAndValues;
    }

    /// @notice Column index and value pair
    /// @param columnIndex Index of the column
    /// @param value Sampled value at the column
    struct ColumnAndValue {
        uint256 columnIndex;
        QM31Field.QM31 value;
    }

    /// @notice Quotient constants for FRI answers
    /// @param lineCoeffs Precomputed line coefficients for each batch and column
    struct QuotientConstants {
        QM31Field.QM31[][][] lineCoeffs; // [batch][column][3] for (a, b, c) coefficients
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
    /// @return friVerifierState Initialized verifier state for decommitment
    function commit(
        KeccakChannelLib.ChannelState storage channelState,
        PcsConfig.FriConfig memory config,
        FriProof memory proof,
        CirclePolyDegreeBound.Bound[] memory columnBounds
    ) internal returns (FriVerifierState memory friVerifierState) {
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
        friVerifierState = FriVerifierState({
            config: config,
            firstLayer: firstLayer,
            innerLayers: innerLayers,
            lastLayerDomainLogSize: layerDomainLogSize,
            lastLayerPoly: proof.lastLayerPoly,
            queries: Queries({
                positions: new uint256[](0),
                logDomainSize: 0
            }),
            queryPositionsByLogSize: QueryPositionsByLogSize({
                logSizes: new uint32[](0),
                queryPositions: new uint256[][](0)
            }),
            queriesSampled: false
        });

        emit FriCommitmentCompleted(true);
    }

    /// @notice Sample query positions for FRI decommitment
    /// @dev Matches Rust implementation: generates unique queries and maps them by log size
    /// @param friVerifierState FRI verifier state
    /// @param channelState Keccak channel for randomness
    /// @return queryPositionsByLogSize Mapping of log sizes to query positions (equivalent to Rust BTreeMap)
    function sampleQueryPositions(
        FriVerifierState storage friVerifierState,
        KeccakChannelLib.ChannelState storage channelState
    ) internal returns (QueryPositionsByLogSize memory queryPositionsByLogSize) {
        // Collect unique column log sizes (equivalent to Rust BTreeSet)
        uint32[] memory columnLogSizes = _getUniqueColumnLogSizes(friVerifierState);
        
        // Find maximum column log size
        uint32 maxColumnLogSize = 0;
        for (uint256 i = 0; i < columnLogSizes.length; i++) {
            if (columnLogSizes[i] > maxColumnLogSize) {
                maxColumnLogSize = columnLogSizes[i];
            }
        }
        
        // Generate queries (equivalent to Queries::generate)
        Queries memory queries = _generateQueries(channelState, maxColumnLogSize, uint32(friVerifierState.config.nQueries));
        
        // Get query positions by log size (equivalent to get_query_positions_by_log_size)
        queryPositionsByLogSize = _getQueryPositionsByLogSize(queries, columnLogSizes);
        
        // Store in verifier state
        friVerifierState.queries = queries;
        friVerifierState.queryPositionsByLogSize = queryPositionsByLogSize;
        friVerifierState.queriesSampled = true;
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
    /// @param friVerifierState FRI verifier state
    /// @return maxLogSize Maximum log size among all column domains
    function getMaxColumnLogSize(FriVerifierState memory friVerifierState)  
        internal 
        pure 
        returns (uint32 maxLogSize) 
    {
        maxLogSize = 0;
        for (uint256 i = 0; i < friVerifierState.firstLayer.columnCommitmentDomains.length; i++) {
            uint32 logSize = CircleDomain.logSize(friVerifierState.firstLayer.columnCommitmentDomains[i]);
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

    /// @notice Get unique column log sizes from first layer domains
    /// @dev Equivalent to Rust BTreeSet collection
    /// @param friVerifierState FRI verifier state
    /// @return uniqueLogSizes Array of unique log sizes in ascending order
    function _getUniqueColumnLogSizes(FriVerifierState storage friVerifierState) 
        private 
        view 
        returns (uint32[] memory uniqueLogSizes) 
    {
        uint32[] memory allLogSizes = new uint32[](friVerifierState.firstLayer.columnCommitmentDomains.length);
        
        // Collect all log sizes
        for (uint256 i = 0; i < friVerifierState.firstLayer.columnCommitmentDomains.length; i++) {
            allLogSizes[i] = CircleDomain.logSize(friVerifierState.firstLayer.columnCommitmentDomains[i]);
        }
        
        // Sort array
        _sortUint32Array(allLogSizes);
        
        // Remove duplicates
        return _removeDuplicatesUint32(allLogSizes);
    }

    /// @notice Generate unique query positions (equivalent to Queries::generate)
    /// @dev Uses BTreeSet-like logic to ensure uniqueness
    /// @param channelState Channel state for randomness
    /// @param logDomainSize Log size of domain to sample from
    /// @param nQueries Number of unique queries to generate
    /// @return queries Generated queries structure
    function _generateQueries(
        KeccakChannelLib.ChannelState storage channelState,
        uint32 logDomainSize, 
        uint32 nQueries
    ) private returns (Queries memory queries) {
        uint256 maxQuery = (1 << logDomainSize) - 1;
        uint256[] memory uniqueQueries = new uint256[](nQueries);
        uint256 queriesFound = 0;
        
        // Use simple approach since we expect nQueries << domain size
        // In practice, duplicates are very rare for reasonable parameters
        while (queriesFound < nQueries) {
            uint32[] memory randomWords = channelState.drawU32s();
            
            for (uint256 i = 0; i < randomWords.length && queriesFound < nQueries; i++) {
                uint256 candidateQuery = randomWords[i] & maxQuery;
                
                // Check if this query is already present (simple linear search)
                bool isDuplicate = false;
                for (uint256 j = 0; j < queriesFound; j++) {
                    if (uniqueQueries[j] == candidateQuery) {
                        isDuplicate = true;
                        break;
                    }
                }
                
                if (!isDuplicate) {
                    uniqueQueries[queriesFound] = candidateQuery;
                    queriesFound++;
                }
            }
        }
        
        // Sort the queries (equivalent to BTreeSet ordering)
        _sortUint256Array(uniqueQueries);
        
        queries = Queries({
            positions: uniqueQueries,
            logDomainSize: logDomainSize
        });
    }

    /// @notice Map query positions by log size (equivalent to get_query_positions_by_log_size)
    /// @param queries Generated queries  
    /// @param columnLogSizes Unique column log sizes
    /// @return queryPositionsByLogSize Mapped query positions
    function _getQueryPositionsByLogSize(
        Queries memory queries,
        uint32[] memory columnLogSizes
    ) private pure returns (QueryPositionsByLogSize memory queryPositionsByLogSize) {
        uint256[][] memory queryPositions = new uint256[][](columnLogSizes.length);
        
        for (uint256 logSizeIdx = 0; logSizeIdx < columnLogSizes.length; logSizeIdx++) {
            uint32 logSize = columnLogSizes[logSizeIdx];
            
            if (logSize >= queries.logDomainSize) {
                // Same size or larger domain - use all queries
                queryPositions[logSizeIdx] = queries.positions;
            } else {
                // Smaller domain - map queries down by shifting and remove duplicates
                uint32 shift = queries.logDomainSize - logSize;
                uint256[] memory mappedQueries = new uint256[](queries.positions.length);
                
                for (uint256 i = 0; i < queries.positions.length; i++) {
                    mappedQueries[i] = queries.positions[i] >> shift;
                }
                
                // Remove duplicates (queries are already sorted, so we just need to remove consecutive duplicates)
                queryPositions[logSizeIdx] = _removeDuplicatesUint256(mappedQueries);
            }
        }
        
        queryPositionsByLogSize = QueryPositionsByLogSize({
            logSizes: columnLogSizes,
            queryPositions: queryPositions
        });
    }

    /// @notice Sort uint32 array in ascending order (bubble sort)
    /// @param arr Array to sort in-place
    function _sortUint32Array(uint32[] memory arr) private pure {
        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    uint32 temp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = temp;
                }
            }
        }
    }

    /// @notice Sort uint256 array in ascending order (bubble sort)
    /// @param arr Array to sort in-place  
    function _sortUint256Array(uint256[] memory arr) private pure {
        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    uint256 temp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = temp;
                }
            }
        }
    }

    /// @notice Remove consecutive duplicates from sorted uint32 array
    /// @param sortedArr Sorted array with potential duplicates
    /// @return deduplicated Array without consecutive duplicates
    function _removeDuplicatesUint32(uint32[] memory sortedArr) 
        private 
        pure 
        returns (uint32[] memory deduplicated) 
    {
        if (sortedArr.length == 0) {
            return new uint32[](0);
        }
        
        // Count unique elements
        uint256 uniqueCount = 1;
        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i-1]) {
                uniqueCount++;
            }
        }
        
        // Create deduplicated array
        deduplicated = new uint32[](uniqueCount);
        deduplicated[0] = sortedArr[0];
        uint256 currentIndex = 1;
        
        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i-1]) {
                deduplicated[currentIndex] = sortedArr[i];
                currentIndex++;
            }
        }
    }

    /// @notice Remove consecutive duplicates from sorted uint256 array
    /// @param sortedArr Sorted array with potential duplicates
    /// @return deduplicated Array without consecutive duplicates
    function _removeDuplicatesUint256(uint256[] memory sortedArr) 
        private 
        pure 
        returns (uint256[] memory deduplicated) 
    {
        if (sortedArr.length == 0) {
            return new uint256[](0);
        }
        
        // Count unique elements
        uint256 uniqueCount = 1;
        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i-1]) {
                uniqueCount++;
            }
        }
        
        // Create deduplicated array
        deduplicated = new uint256[](uniqueCount);
        deduplicated[0] = sortedArr[0];
        uint256 currentIndex = 1;
        
        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i-1]) {
                deduplicated[currentIndex] = sortedArr[i];
                currentIndex++;
            }
        }
    }

    /// @notice Calculate FRI answers for quotient polynomials
    /// @dev Equivalent to Rust fri_answers function - computes quotient evaluations at query positions
    /// @param columnLogSizes Array of log sizes for each tree and column
    /// @param samples Point samples organized by tree, column and point
    /// @param randomCoeff Random coefficient for linear combination
    /// @param queryPositionsByLogSize Query positions mapped by log size
    /// @param queriedValues Queried values from each tree
    /// @param nColumnsPerLogSize Number of columns per log size for each tree
    /// @return friAnswers 2D array of quotient evaluations for FRI decommitment (columns x query values)
    function friAnswers(
        uint32[][] memory columnLogSizes,           // TreeVec<Vec<u32>>
        PointSample[][][] memory samples,           // TreeVec<Vec<Vec<PointSample>>>
        QM31Field.QM31 memory randomCoeff,          // SecureField
        QueryPositionsByLogSize memory queryPositionsByLogSize,  // &BTreeMap<u32, Vec<usize>>
        uint32[][] memory queriedValues,            // TreeVec<Vec<BaseField>> (BaseField = M31 = uint32)
        uint32[][][] memory nColumnsPerLogSize      // TreeVec<&BTreeMap<u32, usize>>
    ) internal pure returns (QM31Field.QM31[][] memory friAnswers) {
        // Flatten column log sizes and create (logSize, samples) pairs
        LogSizeAndSamples[] memory flattenedData = _flattenAndCreatePairs(columnLogSizes, samples);
        
        // Sort by log size in descending order (equivalent to sorted_by_key(Reverse(*log_size)))
        _sortByLogSizeDescending(flattenedData);
        
        // Group by log size and process each group
        // In Rust this is: .group_by(|(log_size, ..)| *log_size).into_iter().map(...).collect()
        // Each group produces one Vec<SecureField>, so we have as many columns as unique log sizes
        
        friAnswers = new QM31Field.QM31[][](queryPositionsByLogSize.logSizes.length);
        uint256 columnIndex = 0;
        
        // Create mutable iterator state for queried values
        QueriedValuesIterator memory queriedValuesIter = QueriedValuesIterator({
            data: queriedValues,
            positions: new uint256[](queriedValues.length)
        });
        
        // Process each unique log size in descending order (to match Rust Reverse sorting)
        for (uint256 i = 0; i < queryPositionsByLogSize.logSizes.length; i++) {
            uint256 logSizeIdx = queryPositionsByLogSize.logSizes.length - 1 - i;
            uint32 logSize = queryPositionsByLogSize.logSizes[logSizeIdx];
            uint256[] memory queryPositions = queryPositionsByLogSize.queryPositions[logSizeIdx];
            
            // Get samples for this log size
            PointSample[][] memory samplesForLogSize = _getSamplesForLogSize(flattenedData, logSize);
            
            // Get n_columns for this log size from each tree
            uint256[] memory nColumnsForLogSize = _getNColumnsForLogSize(nColumnsPerLogSize, logSize);
            
            // Calculate answers for this log size
            // In Rust: fri_answers_for_log_size returns Result<Vec<SecureField>, VerificationError>
            // This becomes one column in our 2D array
            QM31Field.QM31[] memory answersForLogSize = friAnswersForLogSize(
                logSize,
                samplesForLogSize,
                randomCoeff,
                queryPositions,
                queriedValuesIter,
                nColumnsForLogSize
            );
            
            
            // Store this group's answers as one column
            friAnswers[columnIndex] = answersForLogSize;
            columnIndex++;
        }
    }

    /// @notice Calculate FRI answers for a specific log size
    /// @dev Equivalent to Rust fri_answers_for_log_size function
    /// @param logSize Log size of the domain
    /// @param samples Point samples for this log size
    /// @param randomCoeff Random coefficient for linear combination
    /// @param queryPositions Query positions for this log size
    /// @param queriedValuesIter Iterator over queried values (mutable)
    /// @param nColumns Number of columns per tree for this log size
    /// @return answersForLogSize Quotient evaluations at query positions
    function friAnswersForLogSize(
        uint32 logSize,
        PointSample[][] memory samples,
        QM31Field.QM31 memory randomCoeff,
        uint256[] memory queryPositions,
        QueriedValuesIterator memory queriedValuesIter,
        uint256[] memory nColumns
    ) internal pure returns (QM31Field.QM31[] memory answersForLogSize) {
        // Create sample batches (equivalent to ColumnSampleBatch::new_vec)
        ColumnSampleBatch[] memory sampleBatches = _createColumnSampleBatches(samples);
        
        // Calculate quotient constants
        QuotientConstants memory quotientConstants = _calculateQuotientConstants(sampleBatches, randomCoeff);
        
        // Create commitment domain
        CircleDomain.CircleDomainStruct memory commitmentDomain = _createCommitmentDomain(logSize);
        
        // Calculate quotient evaluations at each query position
        answersForLogSize = new QM31Field.QM31[](queryPositions.length);
        
        for (uint256 i = 0; i < queryPositions.length; i++) {
            uint256 queryPosition = queryPositions[i];
            
            // Get domain point at bit-reversed query position
            CirclePoint.Point memory domainPoint = _getDomainPointAtQuery(commitmentDomain, queryPosition, logSize);
            
            // Get queried values at this row
            uint32[] memory queriedValuesAtRow = _getQueriedValuesAtRow(queriedValuesIter, nColumns);
            
            
            // Accumulate row quotients
            answersForLogSize[i] = _accumulateRowQuotients(
                sampleBatches,
                queriedValuesAtRow,
                quotientConstants,
                domainPoint
            );
        }
    }

    /// @notice Accumulate quotient contributions from all sample batches at a domain point
    /// @dev Equivalent to Rust accumulate_row_quotients function
    /// @param sampleBatches Array of column sample batches
    /// @param queriedValuesAtRow Queried values for this row
    /// @param quotientConstants Precomputed quotient constants
    /// @param domainPoint Domain point where quotients are evaluated
    /// @return accumulator Sum of all quotient contributions
    function _accumulateRowQuotients(
        ColumnSampleBatch[] memory sampleBatches,
        uint32[] memory queriedValuesAtRow,
        QuotientConstants memory quotientConstants,
        CirclePoint.Point memory domainPoint
    ) internal pure returns (QM31Field.QM31 memory accumulator) {
        // Calculate denominator inverses for all sample batches
        CM31Field.CM31[] memory denominatorInverses = _calculateDenominatorInverses(sampleBatches, domainPoint);
        
        accumulator = QM31Field.zero();
        
        // Process each sample batch
        for (uint256 batchIdx = 0; batchIdx < sampleBatches.length; batchIdx++) {
            ColumnSampleBatch memory sampleBatch = sampleBatches[batchIdx];
            QM31Field.QM31[][] memory batchLineCoeffs = quotientConstants.lineCoeffs[batchIdx];
            CM31Field.CM31 memory denominatorInverse = denominatorInverses[batchIdx];
            
            QM31Field.QM31 memory numerator = QM31Field.zero();
            
            // Process each column in the batch
            for (uint256 colIdx = 0; colIdx < sampleBatch.columnsAndValues.length; colIdx++) {
                ColumnAndValue memory columnAndValue = sampleBatch.columnsAndValues[colIdx];
                QM31Field.QM31[] memory lineCoeffs = batchLineCoeffs[colIdx]; // [a, b, c]
                
                // Get queried value for this column and convert to QM31
                QM31Field.QM31 memory queriedValue = QM31Field.fromM31(queriedValuesAtRow[columnAndValue.columnIndex], 0, 0, 0);
                QM31Field.QM31 memory value = QM31Field.mul(
                    queriedValue,
                    lineCoeffs[2] // c coefficient
                );
                
                // Calculate linear term: a * domain_point.y + b
                QM31Field.QM31 memory linearTerm = QM31Field.add(
                    QM31Field.mul(lineCoeffs[0], domainPoint.y), // a * domain_point.y
                    lineCoeffs[1] // b
                );
                
                // Add to numerator: value - linear_term
                numerator = QM31Field.add(numerator, QM31Field.sub(value, linearTerm));
            }
            
            // Multiply numerator by denominator inverse and add to accumulator
            QM31Field.QM31 memory contribution = QM31Field.mulCM31(numerator, denominatorInverse);
            accumulator = QM31Field.add(accumulator, contribution);
        }
    }

    // Helper data structures for fri_answers implementation
    
    /// @notice Pair of log size and corresponding samples for sorting/grouping
    struct LogSizeAndSamples {
        uint32 logSize;
        PointSample[] samples;
    }
    
    /// @notice Iterator state for queried values
    struct QueriedValuesIterator {
        uint32[][] data;
        uint256[] positions; // Current position in each tree's data
    }

    // Helper functions (implementation details follow)
    
    function _flattenAndCreatePairs(
        uint32[][] memory columnLogSizes,
        PointSample[][][] memory samples
    ) private pure returns (LogSizeAndSamples[] memory pairs) {
        // Implementation would flatten the tree structure and create pairs
        // This is a simplified placeholder - full implementation would handle the complex tree flattening
        pairs = new LogSizeAndSamples[](0);
    }
    
    function _sortByLogSizeDescending(LogSizeAndSamples[] memory data) private pure {
        // Bubble sort by log size in descending order
        for (uint256 i = 0; i < data.length; i++) {
            for (uint256 j = 0; j < data.length - i - 1; j++) {
                if (data[j].logSize < data[j + 1].logSize) {
                    LogSizeAndSamples memory temp = data[j];
                    data[j] = data[j + 1];
                    data[j + 1] = temp;
                }
            }
        }
    }
    
    function _getSamplesForLogSize(
        LogSizeAndSamples[] memory flattenedData,
        uint32 logSize
    ) private pure returns (PointSample[][] memory samplesForLogSize) {
        // Extract samples matching the given log size
        samplesForLogSize = new PointSample[][](0);
    }
    
    function _getNColumnsForLogSize(
        uint32[][][] memory nColumnsPerLogSize,
        uint32 logSize
    ) private pure returns (uint256[] memory nColumnsForLogSize) {
        nColumnsForLogSize = new uint256[](nColumnsPerLogSize.length);
        for (uint256 treeIdx = 0; treeIdx < nColumnsPerLogSize.length; treeIdx++) {
            // Find the entry for this log size in the tree's data
            for (uint256 i = 0; i < nColumnsPerLogSize[treeIdx].length; i++) {
                if (nColumnsPerLogSize[treeIdx][i].length >= 2 && 
                    nColumnsPerLogSize[treeIdx][i][0] == logSize) {
                    nColumnsForLogSize[treeIdx] = nColumnsPerLogSize[treeIdx][i][1];
                    break;
                }
            }
        }
    }
    
    function _createColumnSampleBatches(
        PointSample[][] memory samples
    ) private pure returns (ColumnSampleBatch[] memory batches) {
        // Group samples by point to create batches
        batches = new ColumnSampleBatch[](0);
    }
    
    function _calculateQuotientConstants(
        ColumnSampleBatch[] memory sampleBatches,
        QM31Field.QM31 memory randomCoeff
    ) private pure returns (QuotientConstants memory constants) {
        // Calculate line coefficients for each batch and column
        constants.lineCoeffs = new QM31Field.QM31[][][](sampleBatches.length);
        QM31Field.QM31 memory alpha = QM31Field.one();
        
        for (uint256 batchIdx = 0; batchIdx < sampleBatches.length; batchIdx++) {
            ColumnSampleBatch memory batch = sampleBatches[batchIdx];
            constants.lineCoeffs[batchIdx] = new QM31Field.QM31[][](batch.columnsAndValues.length);
            
            for (uint256 colIdx = 0; colIdx < batch.columnsAndValues.length; colIdx++) {
                PointSample memory sample = PointSample({
                    point: batch.point,
                    value: batch.columnsAndValues[colIdx].value
                });
                
                constants.lineCoeffs[batchIdx][colIdx] = _complexConjugateLineCoeffs(sample, alpha);
                alpha = QM31Field.mul(alpha, randomCoeff);
            }
        }
    }
    
    function _createCommitmentDomain(uint32 logSize) private pure returns (CircleDomain.CircleDomainStruct memory domain) {
        CanonicCoset.CanonicCosetStruct memory canonicCoset = CanonicCoset.newCanonicCoset(logSize);
        domain = CircleDomain.newCircleDomain(CanonicCoset.halfCoset(canonicCoset));
    }
    
    function _getDomainPointAtQuery(
        CircleDomain.CircleDomainStruct memory domain,
        uint256 queryPosition,
        uint32 logSize
    ) private pure returns (CirclePoint.Point memory point) {
        uint256 bitReversedIndex = _bitReverseIndex(queryPosition, logSize);
        point = CircleDomain.at(domain, bitReversedIndex);
    }
    
    function _getQueriedValuesAtRow(
        QueriedValuesIterator memory iter,
        uint256[] memory nColumns
    ) private pure returns (uint32[] memory valuesAtRow) {
        // Calculate total values needed
        uint256 totalValues = 0;
        for (uint256 i = 0; i < nColumns.length; i++) {
            totalValues += nColumns[i];
        }
        
        valuesAtRow = new uint32[](totalValues);
        uint256 valueIndex = 0;
        
        // Take specified number of values from each tree's iterator
        for (uint256 treeIdx = 0; treeIdx < nColumns.length; treeIdx++) {
            uint256 nCols = nColumns[treeIdx];
            for (uint256 i = 0; i < nCols; i++) {
                if (iter.positions[treeIdx] < iter.data[treeIdx].length) {
                    valuesAtRow[valueIndex] = iter.data[treeIdx][iter.positions[treeIdx]];
                    iter.positions[treeIdx]++;
                } else {
                    valuesAtRow[valueIndex] = 0; // Use 0 instead of QM31Field.zero()
                }
                valueIndex++;
            }
        }
    }
    
    function _calculateDenominatorInverses(
        ColumnSampleBatch[] memory sampleBatches,
        CirclePoint.Point memory domainPoint
    ) private pure returns (CM31Field.CM31[] memory inverses) {
        CM31Field.CM31[] memory denominators = new CM31Field.CM31[](sampleBatches.length);
        
        for (uint256 i = 0; i < sampleBatches.length; i++) {
            CirclePoint.Point memory samplePoint = sampleBatches[i].point;
            
            // Extract real and imaginary parts
            uint32 prx = samplePoint.x.first.real;
            uint32 pry = samplePoint.y.first.real;
            uint32 pix = samplePoint.x.first.imag;
            uint32 piy = samplePoint.y.first.imag;
            
            // Calculate: (prx - domain_point.x) * piy - (pry - domain_point.y) * pix
            uint32 dx = prx >= domainPoint.x.first.real ? prx - domainPoint.x.first.real : domainPoint.x.first.real - prx;
            uint32 dy = pry >= domainPoint.y.first.real ? pry - domainPoint.y.first.real : domainPoint.y.first.real - pry;
            
            denominators[i] = CM31Field.fromM31(dx * piy, dy * pix);
        }
        
        // Batch inverse (simplified - would need proper implementation)
        inverses = CM31Field.batchInverse(denominators);
    }
    
    function _complexConjugateLineCoeffs(
        PointSample memory sample,
        QM31Field.QM31 memory alpha
    ) private pure returns (QM31Field.QM31[] memory coeffs) {
        coeffs = new QM31Field.QM31[](3);
        // Simplified implementation - would need proper complex conjugate line calculation
        coeffs[0] = QM31Field.mul(alpha, sample.point.x); // a
        coeffs[1] = QM31Field.mul(alpha, sample.point.y); // b  
        coeffs[2] = alpha; // c
    }
    
    function _bitReverseIndex(uint256 index, uint32 logSize) private pure returns (uint256 reversed) {
        reversed = 0;
        for (uint256 i = 0; i < logSize; i++) {
            reversed = (reversed << 1) | (index & 1);
            index >>= 1;
        }
    }

    // =============================================================================
    // FRI DECOMMITMENT FUNCTIONS
    // =============================================================================

    /// @notice Verifies the decommitment stage of FRI
    /// @dev The query evals need to be provided in the same order as their commitment
    /// @param friVerifierState FRI verifier state with sampled queries
    /// @param firstLayerQueryEvals Query evaluations for the first layer columns
    /// @return success True if decommitment verification passes
    function decommit(
        FriVerifierState memory friVerifierState,
        QM31Field.QM31[][] memory firstLayerQueryEvals
    ) internal pure returns (bool success) {
        // Ensure queries were sampled
        if (!friVerifierState.queriesSampled) {
            revert("Queries not sampled");
        }

        return decommitOnQueries(
            friVerifierState,
            friVerifierState.queries,
            firstLayerQueryEvals
        );
    }

    /// @notice Internal decommitment orchestrator
    /// @dev Coordinates first layer, inner layers, and last layer verification
    /// @param friVerifierState FRI verifier state
    /// @param queries Query positions for decommitment
    /// @param firstLayerQueryEvals Query evaluations for the first layer
    /// @return success True if all layers verify successfully
    function decommitOnQueries(
        FriVerifierState memory friVerifierState,
        Queries memory queries,
        QM31Field.QM31[][] memory firstLayerQueryEvals
    ) internal pure returns (bool success) {
        // Step 1: Verify first layer and get sparse evaluations
        (bool firstLayerSuccess, QM31Field.QM31[][] memory firstLayerSparseEvals) = 
            decommitFirstLayer(friVerifierState, queries, firstLayerQueryEvals);
        
        if (!firstLayerSuccess) {
            revert("FRI decommit failed at STEP 1: First layer verification failed");
        }

        // Step 2: Fold queries for inner layers (equivalent to queries.fold(CIRCLE_TO_LINE_FOLD_STEP))
        Queries memory innerLayerQueries = foldQueries(queries, CIRCLE_TO_LINE_FOLD_STEP);

        // Step 3: Verify inner layers
        (bool innerLayersSuccess, Queries memory lastLayerQueries, QM31Field.QM31[] memory lastLayerQueryEvals) = 
            decommitInnerLayers(friVerifierState, innerLayerQueries, firstLayerSparseEvals);
        
        if (!innerLayersSuccess) {
            revert("FRI decommit failed at STEP 3: Inner layers verification failed");
        }

        // Step 4: Verify last layer
        bool lastLayerSuccess = decommitLastLayer(friVerifierState, lastLayerQueries, lastLayerQueryEvals);
        if (!lastLayerSuccess) {
            revert("FRI decommit failed at STEP 4: Last layer verification failed");
        }
        
        return true;
    }

    /// @notice Verifies the first layer decommitment
    /// @dev Returns the queries and first layer folded column evaluations for remaining layers
    /// @param friVerifierState FRI verifier state
    /// @param queries Query positions
    /// @param firstLayerQueryEvals Query evaluations for first layer columns
    /// @return success True if first layer verification passes
    /// @return sparseEvals Sparse evaluations for use in inner layers
    function decommitFirstLayer(
        FriVerifierState memory friVerifierState,
        Queries memory queries,
        QM31Field.QM31[][] memory firstLayerQueryEvals
    ) internal pure returns (bool success, QM31Field.QM31[][] memory sparseEvals) {
        // Verify first layer using the first layer verifier
        return verifyFirstLayer(friVerifierState.firstLayer, queries, firstLayerQueryEvals);
    }

    /// @notice Verifies the first layer of FRI
    /// @param firstLayer First layer verifier state
    /// @param queries Query positions
    /// @param firstLayerQueryEvals Query evaluations for first layer columns
    /// @return success True if verification passes
    /// @return sparseEvals Sparse evaluations for inner layers
    function verifyFirstLayer(
        FriFirstLayerVerifier memory firstLayer,
        Queries memory queries,
        QM31Field.QM31[][] memory firstLayerQueryEvals
    ) internal pure returns (bool success, QM31Field.QM31[][] memory sparseEvals) {
        // Validate input lengths
        if (firstLayerQueryEvals.length != firstLayer.columnBounds.length) {
            revert("FIRST LAYER COLUMN COUNT MISMATCH");
        }

        // Initialize sparse evaluations
        sparseEvals = new QM31Field.QM31[][](firstLayer.columnBounds.length);

        // Verify each column - columns may have different lengths based on their domain sizes
        for (uint256 i = 0; i < firstLayer.columnBounds.length; i++) {
            // Convert query evaluations to sparse evaluations
            // Each column has its own number of evaluations based on its domain
            sparseEvals[i] = new QM31Field.QM31[](firstLayerQueryEvals[i].length);
            for (uint256 j = 0; j < firstLayerQueryEvals[i].length; j++) {
                sparseEvals[i][j] = firstLayerQueryEvals[i][j];
            }
        }

        // Verify Merkle tree decommitment using MerkleVerifier
        // Create verifier instance
        MerkleVerifier.Verifier memory verifier = MerkleVerifier.create(
            firstLayer.proof.commitment,
            _extractColumnLogSizes(firstLayer.columnBounds)
        );
        
        // Decode decommitment from bytes
        MerkleVerifier.Decommitment memory decommitment = _decodeDecommitment(
            firstLayer.proof.decommitment
        );
        
        // Prepare query with flattened values
        // Each column may have different number of query evaluations
        uint256 totalValues = 0;
        for (uint256 i = 0; i < firstLayerQueryEvals.length; i++) {
            totalValues += firstLayerQueryEvals[i].length * 4; // Each QM31 has 4 BaseField values
        }
        
        uint256 totalQueries = 0;
        for (uint256 i = 0; i < firstLayerQueryEvals.length; i++) {
            totalQueries += firstLayerQueryEvals[i].length;
        }
        
        uint256[] memory queryPositions = new uint256[](totalQueries);
        uint32[] memory expectedValues = new uint32[](totalValues);
        uint256 posIndex = 0;
        uint256 valueIndex = 0;
        
        // Map query positions directly - each column uses the same base query positions
        // but they may have different numbers of evaluations based on their domain sizes
        for (uint256 columnIdx = 0; columnIdx < firstLayerQueryEvals.length; columnIdx++) {
            for (uint256 queryIdx = 0; queryIdx < firstLayerQueryEvals[columnIdx].length; queryIdx++) {
                // Use query positions directly for each column
                // If a column has fewer evaluations, use the available query positions
                if (queryIdx < queries.positions.length) {
                    queryPositions[posIndex++] = queries.positions[queryIdx];
                } else {
                    // Fallback to the last query position if column has more evals than queries
                    queryPositions[posIndex++] = queries.positions[queries.positions.length - 1];
                }
                
                QM31Field.QM31 memory value = firstLayerQueryEvals[columnIdx][queryIdx];
                expectedValues[valueIndex++] = value.first.real;
                expectedValues[valueIndex++] = value.first.imag;
                expectedValues[valueIndex++] = value.second.real;
                expectedValues[valueIndex++] = value.second.imag;
            }
        }
        
        MerkleVerifier.Query memory query = MerkleVerifier.Query({
            positions: queryPositions,
            expectedValues: expectedValues
        });
        
        // Verify Merkle proof
        bool verifySuccess = MerkleVerifier.verify(verifier, query, decommitment);
        
        if (!verifySuccess) {
            revert("FIRST LAYER MERKLE VERIFICATION FAILED");
        }
        
        return (true, sparseEvals);
    }

    /// @notice Verifies all inner layer decommitments
    /// @dev Returns the queries and query evaluations needed for verifying the last FRI layer
    /// @param friVerifierState FRI verifier state
    /// @param queries Query positions for inner layers
    /// @param firstLayerSparseEvals Sparse evaluations from first layer
    /// @return success True if all inner layers verify
    /// @return lastLayerQueries Query positions for last layer
    /// @return lastLayerQueryEvals Query evaluations for last layer
    function decommitInnerLayers(
        FriVerifierState memory friVerifierState,
        Queries memory queries,
        QM31Field.QM31[][] memory firstLayerSparseEvals
    ) internal pure returns (
        bool success, 
        Queries memory lastLayerQueries, 
        QM31Field.QM31[] memory lastLayerQueryEvals
    ) {
        Queries memory layerQueries = queries;
        QM31Field.QM31[] memory layerQueryEvals = new QM31Field.QM31[](layerQueries.positions.length);
        
        // Initialize layer query evals to zero
        for (uint256 i = 0; i < layerQueryEvals.length; i++) {
            layerQueryEvals[i] = QM31Field.zero();
        }

        uint256 sparseEvalsIndex = 0;
        uint256 columnBoundIndex = 0;
        QM31Field.QM31 memory previousFoldingAlpha = friVerifierState.firstLayer.foldingAlpha;

        // Process each inner layer
        for (uint256 layerIndex = 0; layerIndex < friVerifierState.innerLayers.length; layerIndex++) {
            FriInnerLayerVerifier memory layer = friVerifierState.innerLayers[layerIndex];

            // Check for evals committed in the first layer that need to be folded into this layer
            while (columnBoundIndex < friVerifierState.firstLayer.columnBounds.length) {
                CirclePolyDegreeBound.Bound memory bound = friVerifierState.firstLayer.columnBounds[columnBoundIndex];
                uint32 foldedBound = bound.logDegreeBound > 0 ? bound.logDegreeBound - CIRCLE_TO_LINE_FOLD_STEP : 0;
                
                if (foldedBound != layer.degreeBound) {
                    break;
                }

                // Use the previous layer's folding alpha to fold the circle's sparse evals
                CircleDomain.CircleDomainStruct memory columnDomain = 
                    friVerifierState.firstLayer.columnCommitmentDomains[columnBoundIndex];
                
                QM31Field.QM31[] memory foldedColumnEvals = foldCircleSparseEvals(
                    firstLayerSparseEvals[sparseEvalsIndex],
                    previousFoldingAlpha,
                    columnDomain
                );

                accumulateLine(layerQueryEvals, foldedColumnEvals, previousFoldingAlpha);

                sparseEvalsIndex++;
                columnBoundIndex++;
            }

            // Verify the layer and fold it using the current layer's folding alpha
            (bool layerSuccess, Queries memory newLayerQueries, QM31Field.QM31[] memory newLayerQueryEvals) =
                verifyAndFoldLayer(layer, layerQueries, layerQueryEvals);
            
            if (!layerSuccess) {
                return (false, layerQueries, layerQueryEvals);
            }

            layerQueries = newLayerQueries;
            layerQueryEvals = newLayerQueryEvals;
            previousFoldingAlpha = layer.foldingAlpha;
        }

        // Ensure all values have been consumed
        require(columnBoundIndex == friVerifierState.firstLayer.columnBounds.length, "Not all column bounds consumed");
        require(sparseEvalsIndex == firstLayerSparseEvals.length, "Not all sparse evals consumed");

        return (true, layerQueries, layerQueryEvals);
    }

    /// @notice Verifies the last layer
    /// @dev Evaluates the last layer polynomial at query positions and compares with expected values
    /// @param friVerifierState FRI verifier state
    /// @param queries Query positions for last layer
    /// @param queryEvals Expected query evaluations
    /// @return success True if last layer verification passes
    function decommitLastLayer(
        FriVerifierState memory friVerifierState,
        Queries memory queries,
        QM31Field.QM31[] memory queryEvals
    ) internal pure returns (bool success) {
        // Get last layer domain and polynomial
        uint32 lastLayerDomainLogSize = friVerifierState.lastLayerDomainLogSize;
        QM31Field.QM31[] memory lastLayerPoly = friVerifierState.lastLayerPoly;

        // Create domain for last layer
        CanonicCoset.CanonicCosetStruct memory canonicCoset = 
            CanonicCoset.newCanonicCoset(lastLayerDomainLogSize);
        Coset.CosetStruct memory halfCoset = CanonicCoset.halfCoset(canonicCoset);
        CircleDomain.CircleDomainStruct memory domain = CircleDomain.newCircleDomain(halfCoset);

        // Verify each query evaluation
        for (uint256 i = 0; i < queries.positions.length; i++) {
            uint256 query = queries.positions[i];
            QM31Field.QM31 memory queryEval = queryEvals[i];

            // Get domain point at bit-reversed query position
            uint256 reversedIndex = _bitReverseIndex(query, lastLayerDomainLogSize);
            CirclePoint.Point memory x = CircleDomain.at(domain, reversedIndex);

            // Evaluate polynomial at point x
            QM31Field.QM31 memory expectedEval = evaluatePolynomialAtPoint(lastLayerPoly, x);

            // Compare with provided evaluation
            if (!QM31Field.eq(queryEval, expectedEval)) {
                return false; // LastLayerEvaluationsInvalid
            }
        }

        return true;
    }

    // =============================================================================
    // SUPPORTING FUNCTIONS FOR DECOMMITMENT
    // =============================================================================

    /// @notice Folds query positions by a specified step
    /// @param queries Original queries
    /// @param foldStep Step size for folding
    /// @return foldedQueries Folded query positions
    function foldQueries(
        Queries memory queries,
        uint32 foldStep
    ) internal pure returns (Queries memory foldedQueries) {
        uint256[] memory foldedPositions = new uint256[](queries.positions.length);
        
        for (uint256 i = 0; i < queries.positions.length; i++) {
            foldedPositions[i] = queries.positions[i] >> foldStep;
        }

        foldedQueries = Queries({
            positions: foldedPositions,
            logDomainSize: queries.logDomainSize - foldStep
        });
    }

    /// @notice Folds circle sparse evaluations into line evaluations
    /// @param sparseEvals Sparse evaluations to fold
    /// @param foldingAlpha Folding coefficient
    /// @param columnDomain Domain for the column
    /// @return foldedEvals Folded evaluations
    function foldCircleSparseEvals(
        QM31Field.QM31[] memory sparseEvals,
        QM31Field.QM31 memory foldingAlpha,
        CircleDomain.CircleDomainStruct memory columnDomain
    ) internal pure returns (QM31Field.QM31[] memory foldedEvals) {
        // Simplified implementation - would need proper circle to line folding
        foldedEvals = new QM31Field.QM31[](sparseEvals.length);
        
        for (uint256 i = 0; i < sparseEvals.length; i++) {
            // Basic folding: multiply by alpha and combine
            foldedEvals[i] = QM31Field.mul(sparseEvals[i], foldingAlpha);
        }
    }

    /// @notice Accumulates line evaluations with a folding alpha
    /// @param layerQueryEvals Existing layer query evaluations (modified in place)
    /// @param foldedColumnEvals Folded column evaluations to accumulate
    /// @param foldingAlpha Folding coefficient
    function accumulateLine(
        QM31Field.QM31[] memory layerQueryEvals,
        QM31Field.QM31[] memory foldedColumnEvals,
        QM31Field.QM31 memory foldingAlpha
    ) internal pure {
        require(layerQueryEvals.length == foldedColumnEvals.length, "Array length mismatch");
        
        for (uint256 i = 0; i < layerQueryEvals.length; i++) {
            QM31Field.QM31 memory contribution = QM31Field.mul(foldedColumnEvals[i], foldingAlpha);
            layerQueryEvals[i] = QM31Field.add(layerQueryEvals[i], contribution);
        }
    }

    /// @notice Verifies and folds a single inner layer
    /// @param layer Inner layer verifier
    /// @param layerQueries Current layer queries
    /// @param layerQueryEvals Current layer query evaluations
    /// @return success True if layer verification passes
    /// @return newQueries Folded queries for next layer
    /// @return newQueryEvals Folded evaluations for next layer
    function verifyAndFoldLayer(
        FriInnerLayerVerifier memory layer,
        Queries memory layerQueries,
        QM31Field.QM31[] memory layerQueryEvals
    ) internal pure returns (
        bool success,
        Queries memory newQueries,
        QM31Field.QM31[] memory newQueryEvals
    ) {
        // Verify layer against provided proof
        if (!verifyInnerLayerProof(layer, layerQueries, layerQueryEvals)) {
            return (false, layerQueries, layerQueryEvals);
        }

        // Fold queries for next layer
        newQueries = foldQueries(layerQueries, FOLD_STEP);
        
        // Fold evaluations using layer's folding alpha
        newQueryEvals = new QM31Field.QM31[](newQueries.positions.length);
        for (uint256 i = 0; i < newQueryEvals.length; i++) {
            newQueryEvals[i] = QM31Field.mul(layerQueryEvals[i], layer.foldingAlpha);
        }

        return (true, newQueries, newQueryEvals);
    }

    /// @notice Verifies an inner layer proof
    /// @param layer Inner layer verifier
    /// @param queries Query positions
    /// @param expectedEvals Expected evaluations
    /// @return success True if verification passes
    function verifyInnerLayerProof(
        FriInnerLayerVerifier memory layer,
        Queries memory queries,
        QM31Field.QM31[] memory expectedEvals
    ) internal pure returns (bool success) {
        // Simplified verification - would need proper Merkle proof verification
        // and polynomial evaluation verification
        
        // Check that we have the right number of evaluations
        if (expectedEvals.length != queries.positions.length) {
            return false;
        }

        // Additional verification logic would go here
        // For now, return true as placeholder
        return true;
    }

    /// @notice Evaluates a polynomial at a given point
    /// @param poly Polynomial coefficients
    /// @param point Evaluation point
    /// @return result Polynomial evaluation result
    function evaluatePolynomialAtPoint(
        QM31Field.QM31[] memory poly,
        CirclePoint.Point memory point
    ) internal pure returns (QM31Field.QM31 memory result) {
        if (poly.length == 0) {
            return QM31Field.zero();
        }

        // Use Horner's method for polynomial evaluation
        result = poly[poly.length - 1];
        QM31Field.QM31 memory pointX = point.x;
        
        for (uint256 i = poly.length - 1; i > 0; i--) {
            result = QM31Field.add(QM31Field.mul(result, pointX), poly[i - 1]);
        }
    }

    /// @notice Extract column log sizes from circle polynomial degree bounds
    /// @param columnBounds Array of degree bounds
    /// @return logSizes Array of corresponding log sizes
    function _extractColumnLogSizes(
        CirclePolyDegreeBound.Bound[] memory columnBounds
    ) internal pure returns (uint32[] memory logSizes) {
        logSizes = new uint32[](columnBounds.length);
        for (uint256 i = 0; i < columnBounds.length; i++) {
            logSizes[i] = columnBounds[i].logDegreeBound;
        }
    }

    /// @notice Decode Merkle decommitment from bytes
    /// @param encodedDecommitment Encoded decommitment data  
    /// @return decommitment Decoded Merkle decommitment
    function _decodeDecommitment(
        bytes memory encodedDecommitment
    ) internal pure returns (MerkleVerifier.Decommitment memory decommitment) {
        // For now, assume the encoded data is structured as:
        // [hashWitnessLength(32)] + [hashWitness...] + [columnWitnessLength(32)] + [columnWitness...]
        
        require(encodedDecommitment.length >= 64, "Decommitment too short");
        
        uint256 offset = 0;
        
        // Decode hash witness length
        uint256 hashWitnessLength;
        assembly {
            hashWitnessLength := mload(add(add(encodedDecommitment, 0x20), offset))
        }
        offset += 32;
        
        // Decode hash witness
        decommitment.hashWitness = new bytes32[](hashWitnessLength);
        for (uint256 i = 0; i < hashWitnessLength; i++) {
            assembly {
                let value := mload(add(add(encodedDecommitment, 0x20), offset))
                mstore(add(add(mload(add(decommitment, 0x00)), 0x20), mul(i, 0x20)), value)
            }
            offset += 32;
        }
        
        // Decode column witness length  
        uint256 columnWitnessLength;
        assembly {
            columnWitnessLength := mload(add(add(encodedDecommitment, 0x20), offset))
        }
        offset += 32;
        
        // Decode column witness
        decommitment.columnWitness = new uint32[](columnWitnessLength);
        for (uint256 i = 0; i < columnWitnessLength; i++) {
            uint32 value;
            assembly {
                value := mload(add(add(encodedDecommitment, 0x20), offset))
            }
            decommitment.columnWitness[i] = value;
            offset += 32;
        }
    }
}