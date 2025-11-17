// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "../framework/IFrameworkEval.sol";
import "../libraries/FrameworkComponentLib.sol";
import "../libraries/TraceLocationAllocatorLib.sol";
import "../libraries/KeccakChannelLib.sol";
import "../libraries/CommitmentSchemeVerifierLib.sol";
import "../pcs/PcsConfig.sol";
import "../pcs/FriVerifier.sol";
import "../framework/TreeSubspan.sol";
import "../core/PointEvaluationAccumulator.sol";
import "../core/CirclePoint.sol";
import "../fields/QM31Field.sol";
import "../vcs/MerkleVerifier.sol";
import "./ProofParser.sol";

/// @title STWOVerifier
/// @notice Generic STARK verifier for any AIR implementation
/// @dev Main entry point for proof verification matching Rust implementation
contract STWOVerifier {
    using QM31Field for QM31Field.QM31;
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;
    using FrameworkComponentLib for FrameworkComponentLib.ComponentState;
    using TraceLocationAllocatorLib for TraceLocationAllocatorLib.AllocatorState;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using CommitmentSchemeVerifierLib for CommitmentSchemeVerifierLib.VerifierState;
    using FriVerifier for FriVerifier.FriVerifierState;
    using PcsConfig for PcsConfig.Config;

    // =============================================================================
    // State Variables (used during verification)
    // =============================================================================

    /// @notice Channel state for Fiat-Shamir transform
    /// @dev Temporary state used during each verification
    KeccakChannelLib.ChannelState private _channel;

    /// @notice Commitment scheme verifier state
    /// @dev Temporary state used during each verification
    CommitmentSchemeVerifierLib.VerifierState private _commitmentScheme;

    /// @notice Trace location allocator state
    /// @dev Temporary state used during each verification
    TraceLocationAllocatorLib.AllocatorState private _allocator;

    /// @notice Component state for framework evaluation
    /// @dev Temporary state used during each verification
    FrameworkComponentLib.ComponentState private _componentState;

    /// @notice FRI verifier state
    /// @dev Temporary state used during FRI verification (part of PCS)
    FriVerifier.FriVerifierState private _friVerifier;

    // =============================================================================
    // Verification Parameters Structure
    // =============================================================================

    /// @notice Parameters needed for verification
    /// @dev Passed during verify() call, not stored in contract
    struct VerificationParams {
        address evaluator; // Address of IFrameworkEval implementation
        uint32 nColumns; // Number of trace columns
        QM31Field.QM31 claimedSum; // Claimed sum for logup constraints
        FrameworkComponentLib.ComponentInfo componentInfo; // Precomputed component info
    }

    // =============================================================================
    // Main Verification Function
    // =============================================================================

    /// @notice Verify a STARK proof
    /// @dev Main entry point - follows the exact flow from test_realCommitmentFlow
    /// @param proof Complete proof structure from proof.json
    /// @param params Verification parameters (evaluator address, nColumns)
    /// @return bool True if proof is valid, false otherwise
    function verify(
        ProofParser.Proof calldata proof,
        VerificationParams calldata params,
        bytes32[] memory treeRoots,
        uint32[][] memory treeColumnLogSizes,
        bytes32 digest,
        uint32 nDraws
    ) external returns (bool) {
        require(params.evaluator != address(0), "Invalid evaluator address");

        // Get evaluator and verify interface
        IFrameworkEval evaluator = IFrameworkEval(params.evaluator);
        uint32 logSize = evaluator.logSize();

        // Initialize channel and commitment scheme (resets state for each verification)
        // NOTE: digest and nDraws should already include preprocessed and trace commitments
        KeccakChannelLib.initializeWith(_channel, digest, nDraws);
        CommitmentSchemeVerifierLib.initialize(
            _commitmentScheme,
            proof.config,
            treeRoots,
            treeColumnLogSizes
        );

        // =============================================================================
        // PHASE 2: Draw Random Coefficient (Interaction Phase)
        // =============================================================================

        QM31Field.QM31 memory randomCoeff = _channel.drawSecureFelt();

        // =============================================================================
        // PHASE 3: Composition Polynomial Commitment
        // =============================================================================

        uint32[] memory compositionSizes = new uint32[](4); // SECURE_EXTENSION_DEGREE
        uint32 compositionLogDegree = evaluator.maxConstraintLogDegreeBound();
        for (uint256 i = 0; i < 4; i++) {
            compositionSizes[i] = compositionLogDegree;
        }
        CommitmentSchemeVerifierLib.commit(
            _commitmentScheme,
            proof.commitments[proof.commitments.length - 1], // Last commitment is composition
            compositionSizes,
            _channel
        );

        // =============================================================================
        // PHASE 4: Draw OODS Point
        // =============================================================================

        CirclePoint.Point memory oodsPoint = CirclePoint
            .getRandomPointFromState(_channel);

        // =============================================================================
        // PHASE 5: Compute Mask Points and Sample Points
        // =============================================================================

        FrameworkComponentLib.SamplePoints
            memory samplePoints = _computeSamplePoints(
                oodsPoint,
                proof.commitments.length - 1, // Exclude composition commitment (it's added internally)
                params
            );

        uint256 totalColumns = 0;
        for (
            uint256 treeIdx = 0;
            treeIdx < samplePoints.points.length;
            treeIdx++
        ) {
            totalColumns += samplePoints.points[treeIdx].length;
        }

        // =============================================================================
        // PHASE 6: Verify OODS Values (Out-of-Domain Sampling)
        // =============================================================================

        // Extract composition OODS evaluation from proof
        (
            QM31Field.QM31 memory compositionOodsEval,
            bool extractSuccess
        ) = ProofParser.extractCompositionOodsEval(proof);
        require(extractSuccess, "Failed to extract composition OODS eval");

        bool oodsValid = _verifyOods(
            _componentState,
            proof.sampledValues,
            oodsPoint,
            randomCoeff,
            compositionOodsEval
        );
        if (!oodsValid) {
            return false;
        }

        // Mix felts and generate random coeff
        QM31Field.QM31[] memory flattenedSampledValues = ProofParser
            .flattenCols(proof.sampledValues);
        _channel.mixFelts(flattenedSampledValues);

        QM31Field.QM31 memory randomCoeff2;
        randomCoeff2 = _channel.drawSecureFelt();

        // Generate bounds for FRI from commitment scheme
        CirclePolyDegreeBound.Bound[] memory bounds = _commitmentScheme
            .calculateBounds();

        _friVerifier = FriVerifier.commit(
            _channel,
            _commitmentScheme.config.friConfig,
            proof.friProof,
            bounds
        );
        // =============================================================================
        // PHASE 7: Verify Proof of Work
        // =============================================================================

        bool powValid = _verifyProofOfWork(
            proof.proofOfWork,
            proof.config.powBits
        );
        require(powValid, "Proof of work verification failed");
        if (!powValid) {
            return false;
        }

        // mix pow nonce into channel
        _channel.mixU64(proof.proofOfWork);

        // =============================================================================
        // Create PointSamples for FRI verification
        // =============================================================================

        // Rust: let samples = sampled_points.zip_cols(proof.sampled_values).map_cols(...)
        FriVerifier.PointSample[][][]
            memory pointSamples = _zipSamplePointsWithValues(
                samplePoints,
                proof.sampledValues
            );

        // =============================================================================
        // PHASE 8: FRI Decommitment (PCS Verification)
        // =============================================================================

        bool friValid = _verifyFri(
            proof.friProof,
            proof.config.friConfig,
            pointSamples,
            proof.decommitments,
            proof.queriedValues,
            randomCoeff2
        );
        if (!friValid) {
            return false;
        }

        return true;
    }
    // =============================================================================
    // Internal Helper Functions
    // =============================================================================

    /// @notice Compute sample points for OODS evaluation
    /// @dev Follows maskPoints logic from FrameworkComponentLib
    function _computeSamplePoints(
        CirclePoint.Point memory oodsPoint,
        uint256 nTrees,
        VerificationParams calldata params
    ) internal returns (FrameworkComponentLib.SamplePoints memory) {
        // Get evaluator
        IFrameworkEval evaluator = IFrameworkEval(params.evaluator);
        uint32 logSize = evaluator.logSize();

        // Initialize allocator (reset for this verification)
        _allocator.initialize();

        // Create component matching Rust FrameworkComponent::new()
        // This evaluates InfoEvaluator to get mask offsets and then allocates trace locations
        (
            TreeSubspan.Subspan[] memory traceLocations,
            uint256[] memory preprocessedColumnIndices,
            FrameworkComponentLib.ComponentInfo memory componentInfo
        ) = _componentState.createComponent(
                _allocator,
                params.evaluator,
                params.claimedSum,
                params.componentInfo
            );

        // Compute mask points
        FrameworkComponentLib.SamplePoints memory samplePoints = _componentState
            .maskPoints(oodsPoint);

        // Add composition polynomial tree (SECURE_EXTENSION_DEGREE = 4 columns)
        CirclePoint.Point[][][] memory newPoints = new CirclePoint.Point[][][](
            nTrees + 1
        );
        uint256[] memory newNColumns = new uint256[](nTrees + 1);

        // Copy existing trees
        for (uint256 i = 0; i < samplePoints.points.length; i++) {
            newPoints[i] = samplePoints.points[i];
            newNColumns[i] = samplePoints.nColumns[i];
        }

        // Add composition tree
        uint256 compositionTreeIdx = nTrees;
        uint256 SECURE_EXTENSION_DEGREE = 4;
        newPoints[compositionTreeIdx] = new CirclePoint.Point[][](
            SECURE_EXTENSION_DEGREE
        );
        newNColumns[compositionTreeIdx] = SECURE_EXTENSION_DEGREE;

        for (uint256 colIdx = 0; colIdx < SECURE_EXTENSION_DEGREE; colIdx++) {
            newPoints[compositionTreeIdx][colIdx] = new CirclePoint.Point[](1);
            newPoints[compositionTreeIdx][colIdx][0] = oodsPoint;
            samplePoints.totalPoints++;
        }

        samplePoints.points = newPoints;
        samplePoints.nColumns = newNColumns;

        return samplePoints;
    }

    /// @notice Get n_columns_per_log_size for each tree (matching Rust BTreeMap<u32, usize>)
    /// @param scheme The commitment scheme state
    /// @return Array of [logSize, nColumns] pairs for each tree
    function getNColumnsPerLogSize(
        CommitmentSchemeVerifierLib.VerifierState storage scheme
    ) internal view returns (uint32[][][] memory) {
        uint32[][][] memory result = new uint32[][][](
            scheme.columnLogSizes().length
        );

        for (
            uint256 treeIdx = 0;
            treeIdx < scheme.columnLogSizes().length;
            treeIdx++
        ) {
            uint32[] memory columnLogSizes = scheme.columnLogSizes()[treeIdx];

            if (columnLogSizes.length == 0) {
                result[treeIdx] = new uint32[][](0);
                continue;
            }

            // Count unique log sizes and their occurrences (equivalent to BTreeMap)
            // First, find unique log sizes
            uint32[] memory uniqueLogSizes = _getUniqueLogSizes(columnLogSizes);

            // Create result array for this tree
            result[treeIdx] = new uint32[][](uniqueLogSizes.length);

            // For each unique log size, count occurrences
            for (uint256 i = 0; i < uniqueLogSizes.length; i++) {
                uint32 logSize = uniqueLogSizes[i];
                uint32 count = 0;

                // Count how many columns have this log size
                for (uint256 j = 0; j < columnLogSizes.length; j++) {
                    if (columnLogSizes[j] == logSize) {
                        count++;
                    }
                }

                // Store [logSize, count] pair
                result[treeIdx][i] = new uint32[](2);
                result[treeIdx][i][0] = logSize;
                result[treeIdx][i][1] = count;
            }
        }

        return result;
    }

    /// @notice Get unique log sizes from array (helper for getNColumnsPerLogSize)
    /// @param logSizes Array of log sizes (may contain duplicates)
    /// @return Array of unique log sizes in ascending order
    function _getUniqueLogSizes(
        uint32[] memory logSizes
    ) internal pure returns (uint32[] memory) {
        if (logSizes.length == 0) {
            return new uint32[](0);
        }

        // Sort the array first
        uint32[] memory sorted = new uint32[](logSizes.length);
        for (uint256 i = 0; i < logSizes.length; i++) {
            sorted[i] = logSizes[i];
        }
        _sortUint32ArrayHelper(sorted);

        // Remove duplicates
        return _removeDuplicatesUint32Helper(sorted);
    }

    /// @notice Sort uint32 array helper
    function _sortUint32ArrayHelper(uint32[] memory arr) internal pure {
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

    /// @notice Remove consecutive duplicates helper
    function _removeDuplicatesUint32Helper(
        uint32[] memory sortedArr
    ) internal pure returns (uint32[] memory) {
        if (sortedArr.length == 0) {
            return new uint32[](0);
        }

        // Count unique elements
        uint256 uniqueCount = 1;
        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i - 1]) {
                uniqueCount++;
            }
        }

        // Create deduplicated array
        uint32[] memory deduplicated = new uint32[](uniqueCount);
        deduplicated[0] = sortedArr[0];
        uint256 currentIndex = 1;

        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i - 1]) {
                deduplicated[currentIndex] = sortedArr[i];
                currentIndex++;
            }
        }

        return deduplicated;
    }

    /// @notice Zip sample points with sampled values to create PointSample structure
    /// @dev Rust: sampled_points.zip_cols(proof.sampled_values).map_cols(...)
    /// Creates PointSample[tree][column][sample_index] from points and values
    /// @param samplePoints Sample points structure (tree -> column -> point)
    /// @param sampledValues Sampled values from proof (tree -> column -> value)
    /// @return samples Array of PointSample structures [tree][column][sample]
    function _zipSamplePointsWithValues(
        FrameworkComponentLib.SamplePoints memory samplePoints,
        QM31Field.QM31[][][] memory sampledValues
    ) internal pure returns (FriVerifier.PointSample[][][] memory samples) {
        require(
            samplePoints.points.length == sampledValues.length,
            "Tree count mismatch"
        );

        samples = new FriVerifier.PointSample[][][](samplePoints.points.length);

        // For each tree
        for (
            uint256 treeIdx = 0;
            treeIdx < samplePoints.points.length;
            treeIdx++
        ) {
            require(
                samplePoints.points[treeIdx].length ==
                    sampledValues[treeIdx].length,
                "Column count mismatch"
            );

            samples[treeIdx] = new FriVerifier.PointSample[][](
                samplePoints.points[treeIdx].length
            );

            // For each column
            for (
                uint256 colIdx = 0;
                colIdx < samplePoints.points[treeIdx].length;
                colIdx++
            ) {
                CirclePoint.Point[] memory columnPoints = samplePoints.points[
                    treeIdx
                ][colIdx];
                QM31Field.QM31[] memory columnValues = sampledValues[treeIdx][
                    colIdx
                ];

                require(
                    columnPoints.length == columnValues.length,
                    "Sample count mismatch"
                );

                samples[treeIdx][colIdx] = new FriVerifier.PointSample[](
                    columnPoints.length
                );

                // Zip points with values: zip(sampled_points, sampled_values).map(|(point, value)| PointSample { point, value })
                for (
                    uint256 sampleIdx = 0;
                    sampleIdx < columnPoints.length;
                    sampleIdx++
                ) {
                    samples[treeIdx][colIdx][sampleIdx] = FriVerifier
                        .PointSample({
                            point: columnPoints[sampleIdx],
                            value: columnValues[sampleIdx]
                        });
                }
            }
        }

        return samples;
    }

    /// @notice Verify OODS (out-of-domain sampling) values
    /// @dev Checks that claimed evaluations match the constraint polynomial
    function _verifyOods(
        FrameworkComponentLib.ComponentState storage componentState,
        QM31Field.QM31[][][] memory sampledValues,
        CirclePoint.Point memory oodsPoint,
        QM31Field.QM31 memory randomCoeff,
        QM31Field.QM31 memory compositionPodsEval
    ) internal returns (bool) {
        // 1. Initialize point evaluation accumulator
        PointEvaluationAccumulator.Accumulator
            memory eval_accumulator = PointEvaluationAccumulator.newAccumulator(
                randomCoeff
            );
        // 2. Accumulate sampled values with random coefficient
        PointEvaluationAccumulator.Accumulator memory result = componentState
            .evaluateConstraintQuotientsAtPoint(
                oodsPoint,
                sampledValues,
                eval_accumulator
            );
        QM31Field.QM31 memory finalResult = result.accumulation;

        // 3. Verify constraint evaluations
        require(
            QM31Field.eq(finalResult, compositionPodsEval),
            "OODS values do not match"
        );
        return true;
    }

    /// @notice Verify proof of work
    /// @dev Checks that the PoW nonce produces a valid hash
    event PoWVerification(uint64 nonce, uint32 powBits, bool result);

    function _verifyProofOfWork(
        uint64 nonce,
        uint32 powBits
    ) internal returns (bool) {
        bool powResult = _channel.verifyPowNonce(powBits, nonce);
        emit PoWVerification(nonce, powBits, powResult);
        return powResult;
    }

    /// @notice Verify FRI proof
    /// @dev Main FRI decommitment verification
    function _verifyFri(
        FriVerifier.FriProof memory friProof,
        PcsConfig.FriConfig memory friConfig,
        FriVerifier.PointSample[][][] memory pointSamples,
        MerkleVerifier.Decommitment[] memory decommitments,
        uint32[][] memory queriedValues,
        QM31Field.QM31 memory randomCoeff
    ) internal returns (bool) {
        // Get FRI query positions (equivalent to fri_verifier.sample_query_positions(channel))
        FriVerifier.QueryPositionsByLogSize memory queryPositions = _friVerifier
            .sampleQueryPositions(_channel);

        // Verify merkle decommitments (equivalent to Rust tree verification loop)
        // self.trees.as_ref().zip_eq(proof.decommitments).zip_eq(proof.queried_values.clone())
        //     .map(|((tree, decommitment), queried_values)| tree.verify(...))
        bool merkleVerificationSuccess = _verifyMerkleDecommitments(
            decommitments,
            queriedValues,
            queryPositions
        );

        if (!merkleVerificationSuccess) {
            return false;
        }

        // Answer FRI queries (equivalent to fri_answers call)
        uint32[][][] memory nColumnsPerLogSizeData = getNColumnsPerLogSize(
            _commitmentScheme
        );
        uint32[][] memory commitmentColumnLogSizes = _commitmentScheme
            .columnLogSizes();

        QM31Field.QM31[][] memory friAnswersResult = FriVerifier.friAnswers(
            commitmentColumnLogSizes,
            pointSamples,
            randomCoeff,
            queryPositions,
            queriedValues,
            nColumnsPerLogSizeData
        );

        // FRI decommit verification
        bool decommitSuccess = FriVerifier.decommit(
            _friVerifier,
            friAnswersResult
        );

        return decommitSuccess;
    }

    /// @notice External wrapper for MerkleVerifier.verify to enable try/catch
    /// @dev External function required for try/catch pattern in Solidity
    function _verifyTreeDecommitment(
        MerkleVerifier.MerkleTree memory tree,
        MerkleVerifier.QueriesPerLogSize[] memory queriesPerLogSize,
        uint32[] memory queriedValues,
        MerkleVerifier.Decommitment memory decommitment
    ) internal pure {
        MerkleVerifier.verify(
            tree,
            queriesPerLogSize,
            queriedValues,
            decommitment
        );
    }

    /// @notice Verify Merkle tree decommitments for all trees
    /// @dev Equivalent to Rust: self.trees.as_ref().zip_eq(proof.decommitments).zip_eq(proof.queried_values.clone())
    ///      .map(|((tree, decommitment), queried_values)| tree.verify(&query_positions_per_log_size, queried_values, decommitment))
    /// @param decommitments Array of Merkle decommitments (one per tree)
    /// @param queriedValues Array of queried values (one per tree)
    /// @param queryPositions Query positions organized by log size
    /// @return success True if all tree verifications pass
    function _verifyMerkleDecommitments(
        MerkleVerifier.Decommitment[] memory decommitments,
        uint32[][] memory queriedValues,
        FriVerifier.QueryPositionsByLogSize memory queryPositions
    ) internal view returns (bool success) {
        // Get trees from commitment scheme (equivalent to self.trees.as_ref())
        uint32[][] memory treesColumnLogSizes = _commitmentScheme
            .columnLogSizes();

        // Verify length consistency (equivalent to zip_eq checks in Rust)
        require(
            decommitments.length == treesColumnLogSizes.length,
            "Decommitments count mismatch"
        );
        require(
            queriedValues.length == treesColumnLogSizes.length,
            "Queried values count mismatch"
        );

        // Verify each tree: tree.verify(&query_positions_per_log_size, queried_values, decommitment)
        for (
            uint256 treeIdx = 0;
            treeIdx < treesColumnLogSizes.length;
            treeIdx++
        ) {
            // Create MerkleTree structure (equivalent to tree in Rust)
            uint32[] memory columnLogSizes = treesColumnLogSizes[treeIdx];
            (
                uint32[] memory logSizes,
                uint256[] memory nColumnsPerLogSize
            ) = _getTreeLogSizeInfo(columnLogSizes);

            MerkleVerifier.MerkleTree memory tree = MerkleVerifier.MerkleTree({
                root: _commitmentScheme.getTreeRoot(treeIdx),
                columnLogSizes: columnLogSizes,
                logSizes: logSizes,
                nColumnsPerLogSize: nColumnsPerLogSize
            });

            // Convert FriVerifier.QueryPositionsByLogSize to MerkleVerifier.QueriesPerLogSize
            MerkleVerifier.QueriesPerLogSize[]
                memory queriesPerLogSize = _convertQueryPositions(
                    queryPositions
                );

            // Verify this tree's decommitment (throws on failure, so we use try/catch)
            _verifyTreeDecommitment(
                tree,
                queriesPerLogSize,
                queriedValues[treeIdx],
                decommitments[treeIdx]
            );
        }

        return true;
    }

    /// @notice Convert FriVerifier.QueryPositionsByLogSize to MerkleVerifier.QueriesPerLogSize format
    /// @param queryPositions Query positions from FRI verifier
    /// @return queriesPerLogSize Array in MerkleVerifier format
    function _convertQueryPositions(
        FriVerifier.QueryPositionsByLogSize memory queryPositions
    )
        internal
        pure
        returns (MerkleVerifier.QueriesPerLogSize[] memory queriesPerLogSize)
    {
        queriesPerLogSize = new MerkleVerifier.QueriesPerLogSize[](
            queryPositions.logSizes.length
        );

        for (uint256 i = 0; i < queryPositions.logSizes.length; i++) {
            queriesPerLogSize[i] = MerkleVerifier.QueriesPerLogSize({
                logSize: queryPositions.logSizes[i],
                queries: queryPositions.queryPositions[i]
            });
        }
    }

    /// @notice Get log size information for a single tree (helper for MerkleTree construction)
    /// @param columnLogSizes Array of column log sizes for one tree
    /// @return logSizes Unique log sizes in ascending order
    /// @return nColumnsPerLogSize Count of columns per each unique log size
    function _getTreeLogSizeInfo(
        uint32[] memory columnLogSizes
    )
        internal
        pure
        returns (uint32[] memory logSizes, uint256[] memory nColumnsPerLogSize)
    {
        // Get unique log sizes (reuse existing helper function)
        logSizes = _getUniqueLogSizes(columnLogSizes);

        // Count columns per log size
        nColumnsPerLogSize = new uint256[](logSizes.length);
        for (uint256 i = 0; i < logSizes.length; i++) {
            uint32 currentLogSize = logSizes[i];
            uint256 count = 0;

            for (uint256 j = 0; j < columnLogSizes.length; j++) {
                if (columnLogSizes[j] == currentLogSize) {
                    count++;
                }
            }

            nColumnsPerLogSize[i] = count;
        }
    }
}
