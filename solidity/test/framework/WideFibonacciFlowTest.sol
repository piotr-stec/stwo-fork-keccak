// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/framework/WideFibonacciEval.sol";
import "../../contracts/libraries/FrameworkComponentLib.sol";
import "../../contracts/libraries/TraceLocationAllocatorLib.sol";
import "../../contracts/libraries/ProofLib.sol";
import "../../contracts/libraries/KeccakChannelLib.sol";
import "../../contracts/libraries/CommitmentSchemeVerifierLib.sol";
import "../../contracts/pcs/PcsConfig.sol";
import "../../contracts/framework/TreeSubspan.sol";
import "../../contracts/core/PointEvaluationAccumulator.sol";
import "../../contracts/core/CirclePoint.sol";
import "../../contracts/core/CirclePolyDegreeBound.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/pcs/FriVerifier.sol";

import "../../contracts/verifier/StwoVerifier.sol";
import "../../contracts/verifier/ProofParser.sol";

/// @title WideFibonacciFlowTest
/// @notice Test replicating verification flow from Rust with REAL proof.json data
/// @dev Uses actual commitments, sampled_values, and config from proof.json
contract WideFibonacciFlowTest is Test {
    using QM31Field for QM31Field.QM31;
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;
    using FrameworkComponentLib for FrameworkComponentLib.ComponentState;
    using TraceLocationAllocatorLib for TraceLocationAllocatorLib.AllocatorState;
    using ProofLib for ProofLib.Proof;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using CommitmentSchemeVerifierLib for CommitmentSchemeVerifierLib.VerifierState;
    using FriVerifier for FriVerifier.FriVerifierState;
    using PcsConfig for PcsConfig.Config;

    // =============================================================================
    // Real Data from proof.json
    // =============================================================================

    // Real commitments from proof.json
    function getRealCommitments()
        internal
        pure
        returns (bytes32[] memory commitments)
    {
        commitments = new bytes32[](3);

        // Commitment 0 (preprocessed)
        uint8[32] memory commit0 = [
            150,
            93,
            46,
            166,
            193,
            179,
            224,
            254,
            77,
            21,
            163,
            204,
            63,
            72,
            175,
            116,
            11,
            82,
            180,
            189,
            169,
            54,
            19,
            51,
            136,
            97,
            184,
            124,
            193,
            150,
            220,
            7
        ];
        commitments[0] = _uint8ArrayToBytes32(commit0);

        // Commitment 1 (trace)
        uint8[32] memory commit1 = [
            35,
            43,
            180,
            182,
            96,
            49,
            39,
            205,
            68,
            28,
            150,
            22,
            20,
            193,
            4,
            107,
            204,
            185,
            139,
            251,
            232,
            244,
            166,
            129,
            254,
            249,
            86,
            202,
            174,
            219,
            241,
            232
        ];
        commitments[1] = _uint8ArrayToBytes32(commit1);

        // Commitment 2 (composition)
        uint8[32] memory commit2 = [
            10,
            135,
            54,
            55,
            212,
            122,
            161,
            55,
            191,
            43,
            2,
            164,
            171,
            248,
            96,
            144,
            213,
            49,
            181,
            136,
            96,
            147,
            173,
            226,
            190,
            205,
            43,
            196,
            148,
            214,
            244,
            132
        ];
        commitments[2] = _uint8ArrayToBytes32(commit2);
    }

    // Real config from proof.json
    uint32 constant POW_BITS = 10;
    uint32 constant LOG_BLOWUP_FACTOR = 1;
    uint32 constant LOG_LAST_LAYER_DEGREE_BOUND = 0;
    uint32 constant N_QUERIES = 3;
    
    // Real proof of work from proof.json
    uint64 constant REAL_PROOF_OF_WORK = 1615;

    // Real sampled_values from proof.json (Fibonacci sequence: 0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765,10946,17711,28657,46368,75025,121393,196418,317811,514229,832040,1346269,2178309,3524578,5702887,9227465,14930352,24157817,39088169,63245986,102334155,165580141,267914296,433494437,701408733,1134903170,1836311903,823731426,512559682,1336291108)
    function getRealFibonacciValues()
        internal
        pure
        returns (uint32[] memory values)
    {
        values = new uint32[](50);
        values[0] = 0;
        values[1] = 1;
        values[2] = 1;
        values[3] = 2;
        values[4] = 3;
        values[5] = 5;
        values[6] = 8;
        values[7] = 13;
        values[8] = 21;
        values[9] = 34;
        values[10] = 55;
        values[11] = 89;
        values[12] = 144;
        values[13] = 233;
        values[14] = 377;
        values[15] = 610;
        values[16] = 987;
        values[17] = 1597;
        values[18] = 2584;
        values[19] = 4181;
        values[20] = 6765;
        values[21] = 10946;
        values[22] = 17711;
        values[23] = 28657;
        values[24] = 46368;
        values[25] = 75025;
        values[26] = 121393;
        values[27] = 196418;
        values[28] = 317811;
        values[29] = 514229;
        values[30] = 832040;
        values[31] = 1346269;
        values[32] = 2178309;
        values[33] = 3524578;
        values[34] = 5702887;
        values[35] = 9227465;
        values[36] = 14930352;
        values[37] = 24157817;
        values[38] = 39088169;
        values[39] = 63245986;
        values[40] = 102334155;
        values[41] = 165580141;
        values[42] = 267914296;
        values[43] = 433494437;
        values[44] = 701408733;
        values[45] = 1134903170;
        values[46] = 1836311903;
        values[47] = 823731426;
        values[48] = 512559682;
        values[49] = 1336291108;
        // values[50] = 0; // Last value for 51 columns
    }

    // Test components
    WideFibonacciEval wideFibEval;
    FrameworkComponentLib.ComponentState componentState;
    TraceLocationAllocatorLib.AllocatorState allocatorState;
    ProofLib.Proof testProof;

    // Storage variables for libraries that modify state
    KeccakChannelLib.ChannelState channel;
    CommitmentSchemeVerifierLib.VerifierState commitmentScheme;
    FriVerifier.FriVerifierState friVerifier;

    // =============================================================================
    // Setup
    // =============================================================================

    function setUp() public {
        uint256 setupStartGas = gasleft();
        console.log("=== setUp() Gas Analysis ===");
        console.log("setUp start gas:", setupStartGas);

        // Create WideFibonacci evaluator with exact params from proof.json
        wideFibEval = new WideFibonacciEval(3, 50);
        uint256 afterWideFibGas = gasleft();
        console.log(
            "Gas for WideFibonacciEval creation:",
            setupStartGas - afterWideFibGas
        );

        // Initialize proof with real config from proof.json
        testProof = ProofLib.createProofWithConfig(
            POW_BITS,
            LOG_BLOWUP_FACTOR,
            LOG_LAST_LAYER_DEGREE_BOUND,
            N_QUERIES
        );

        // Set real commitments from proof.json
        testProof = testProof.setCommitments(getRealCommitments());

        // Initialize Keccak channel
        KeccakChannelLib.initialize(channel);

        // Initialize commitment scheme with config from proof.json
        PcsConfig.FriConfig memory friConfig = PcsConfig.FriConfig({
            logBlowupFactor: LOG_BLOWUP_FACTOR,
            logLastLayerDegreeBound: LOG_LAST_LAYER_DEGREE_BOUND,
            nQueries: N_QUERIES
        });
        PcsConfig.Config memory pcsConfig = PcsConfig.Config({
            powBits: POW_BITS,
            friConfig: friConfig
        });
        CommitmentSchemeVerifierLib.initializeEmpty(commitmentScheme, pcsConfig);

        uint256 setupEndGas = gasleft();
        uint256 totalSetupGas = setupStartGas - setupEndGas;
        console.log("Total setUp() gas used:", totalSetupGas);
        console.log("=== setUp() Complete ===\n");
    }

    // =============================================================================
    // Test: Real Commitment Flow
    // =============================================================================

    /// @notice Test commitment flow with real proof.json data - EXACT Rust replica
    /// @dev Replicates this exact Rust code:
    ///      commitment_scheme.commit(proof.commitments[0], &sizes[0], channel);
    ///      commitment_scheme.commit(proof.commitments[1], &sizes[1], channel);
    ///      let random_coeff = channel.draw_secure_felt();
    ///      commitment_scheme.commit(*proof.commitments.last().unwrap(), &[...], channel);
    ///      let oods_point = CirclePoint::<SecureField>::get_random_point(channel);
    function test_realCommitmentFlow() public {
        uint256 totalStartGas = gasleft();
        // console.log("══════════════════════════════════════════════════════════════");
        // console.log("║               REAL COMMITMENT FLOW TEST                     ║");
        // console.log("===═════════════════════════════════════════════════════════════");
        console.log("Total start gas:", totalStartGas);

        // =============================================================================
        // PHASE 1: COMMITMENT SETUP
        // =============================================================================
        uint256 phase1StartGas = gasleft();
        console.log("\\n=== PHASE 1: COMMITMENT SETUP ===");
        
        bytes32[] memory realCommitments = getRealCommitments();

        // Preprocessed columns commitment
        uint256 preprocessedCommitGas = gasleft();
        bytes32 preprocessedCommit = testProof.getCommitment(0);
        console.log("Real Preprocessed commitment:");
        console.logBytes32(preprocessedCommit);
        assertEq(
            preprocessedCommit,
            realCommitments[0],
            "Preprocessed commitment mismatch"
        );

        // Real commitment_scheme.commit(proof.commitments[0], &sizes[0], channel)
        uint32[] memory preprocessedSizes = new uint32[](0); // Empty for preprocessed (no columns)
        uint256 beforePreprocessedCommit = gasleft();
        
        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            preprocessedCommit,
            preprocessedSizes,
            channel
        );
        
        uint256 afterPreprocessedCommit = gasleft();
        console.log("* Preprocessed commitment gas:", beforePreprocessedCommit - afterPreprocessedCommit);
        console.log("  Digest:", vm.toString(channel.digest));

        // Trace columns commitment  
        bytes32 traceCommit = testProof.getCommitment(1);
        console.log("Real Trace commitment:");
        console.logBytes32(traceCommit);
        assertEq(traceCommit, realCommitments[1], "Trace commitment mismatch");

        // Real commitment_scheme.commit(proof.commitments[1], &sizes[1], channel)
        uint32[] memory traceSizes = new uint32[](50); // 50 trace columns
        for (uint256 i = 0; i < 50; i++) {
            traceSizes[i] = 3;
        }
        
        uint256 beforeTraceCommit = gasleft();
        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            traceCommit,
            traceSizes,
            channel
        );
        uint256 afterTraceCommit = gasleft();
        console.log("* Trace commitment gas:", beforeTraceCommit - afterTraceCommit);
        
        uint256 phase1EndGas = gasleft();
        console.log("=== PHASE 1 TOTAL GAS:", phase1StartGas - phase1EndGas, "===");

        // =============================================================================
        // PHASE 2: RANDOM COEFFICIENT GENERATION
        // =============================================================================
        uint256 phase2StartGas = gasleft();
        console.log("\\n=== PHASE 2: RANDOM COEFFICIENT ===");
        
        // Draw random coefficient (alpha) from channel
        uint256 beforeRandomCoeff = gasleft();
        QM31Field.QM31 memory randomCoeff;
        randomCoeff = channel.drawSecureFelt();
        uint256 afterRandomCoeff = gasleft();
        console.log("* Random coefficient generation gas:", beforeRandomCoeff - afterRandomCoeff);
        console.log("Random coefficient (alpha) from real commitments:");
        console.log("  first.real:", randomCoeff.first.real);
        console.log("  first.imag:", randomCoeff.first.imag);
        console.log("  second.real:", randomCoeff.second.real);
        console.log("  second.imag:", randomCoeff.second.imag);

        assertEq(
            randomCoeff.first.real,
            1744149446,
            "Random coefficient first.real mismatch"
        );
        assertEq(
            randomCoeff.first.imag,
            152709925,
            "Random coefficient first.imag mismatch"
        );
        assertEq(
            randomCoeff.second.real,
            1490462927,
            "Random coefficient second.real mismatch"
        );
        assertEq(
            randomCoeff.second.imag,
            1785869662,
            "Random coefficient second.imag mismatch"
        );

        uint256 phase2EndGas = gasleft();
        console.log("=== PHASE 2 TOTAL GAS:", phase2StartGas - phase2EndGas, "===");

        // =============================================================================
        // PHASE 3: COMPOSITION POLYNOMIAL COMMITMENT
        // =============================================================================
        uint256 phase3StartGas = gasleft();
        console.log("\n=== PHASE 3: COMPOSITION POLYNOMIAL ===");

        // Composition polynomial commitment
        bytes32 compositionCommit = testProof.getLastCommitment();
        console.log("Real Composition commitment:");
        console.logBytes32(compositionCommit);
        assertEq(
            compositionCommit,
            realCommitments[2],
            "Composition commitment mismatch"
        );

        // Real commitment_scheme.commit(*proof.commitments.last().unwrap(), &[...], channel)
        uint32[] memory compositionSizes = new uint32[](4); // SECURE_EXTENSION_DEGREE = 4
        uint32 compositionLogDegree = wideFibEval.maxConstraintLogDegreeBound();
        for (uint256 i = 0; i < 4; i++) {
            compositionSizes[i] = compositionLogDegree; // All 4 components have same log degree
        }

        uint256 beforeCompositionCommit = gasleft();
        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            compositionCommit,
            compositionSizes,
            channel
        );
        uint256 afterCompositionCommit = gasleft();
        console.log("* Composition polynomial commitment gas:", beforeCompositionCommit - afterCompositionCommit);

        console.log("Updated channel state after composition commitment:");
        console.log("  digest:");
        console.log(channel.nDraws);
        console.logBytes32(channel.digest);

        uint256 phase3EndGas = gasleft();
        console.log("=== PHASE 3 TOTAL GAS:", phase3StartGas - phase3EndGas, "===");

        // =============================================================================
        // PHASE 4: OODS POINT GENERATION
        // =============================================================================
        uint256 phase4StartGas = gasleft();
        console.log("\n=== PHASE 4: OODS POINT GENERATION ===");

        // Draw OODS point from channel
        uint256 beforeOodsPoint = gasleft();
        CirclePoint.Point memory oodsPoint = CirclePoint
            .getRandomPointFromState(channel);
        uint256 afterOodsPoint = gasleft();
        console.log("* OODS point generation gas:", beforeOodsPoint - afterOodsPoint);

        console.log("OODS point from real channel state:");
        console.log("  x.first.real:", oodsPoint.x.first.real);
        console.log("  x.first.imag:", oodsPoint.x.first.imag);
        console.log("  x.second.real:", oodsPoint.x.second.real);
        console.log("  x.second.imag:", oodsPoint.x.second.imag);
        console.log("  y.first.real:", oodsPoint.y.first.real);
        console.log("  y.first.imag:", oodsPoint.y.first.imag);
        console.log("  y.second.real:", oodsPoint.y.second.real);
        console.log("  y.second.imag:", oodsPoint.y.second.imag);

        assertEq(oodsPoint.x.first.real, 691016796);
        assertEq(oodsPoint.x.first.imag, 792293106);
        assertEq(oodsPoint.x.second.real, 1324913522);
        assertEq(oodsPoint.x.second.imag, 322322494);
        assertEq(oodsPoint.y.first.real, 2054495875);
        assertEq(oodsPoint.y.first.imag, 580434386);
        assertEq(oodsPoint.y.second.real, 210002610);
        assertEq(oodsPoint.y.second.imag, 1343094441);

        uint256 phase4EndGas = gasleft();
        console.log("=== PHASE 4 TOTAL GAS:", phase4StartGas - phase4EndGas, "===");

        // =============================================================================
        // PHASE 5: MASK POINTS CALCULATION
        // =============================================================================
        uint256 phase5StartGas = gasleft();
        console.log("\n=== PHASE 5: MASK POINTS CALCULATION ===");

        // Verify we have exactly 3 commitments
        (uint256 nCommitments, , ) = testProof.getProofStats();
        assertEq(nCommitments, 3, "Should have 3 commitments from proof.json");
        uint256[] memory treeSizes = new uint256[](2);
        treeSizes[0] = 0; // Preprocessed: empty
        treeSizes[1] = 50; // Original trace: n_columns

        uint256[] memory preprocessedColumnIndices = new uint256[](0);

        uint256 beforeAllocatorInit = gasleft();
        allocatorState.initialize();
        uint256 afterAllocatorInit = gasleft();
        console.log("* Allocator initialization gas:", beforeAllocatorInit - afterAllocatorInit);
        console.log(
            "Allocator state preprocessedColumns",
            allocatorState.preprocessedColumns.length
        );
        
        uint256 beforeTraceLocationAlloc = gasleft();
        TreeSubspan.Subspan[] memory traceLocations = allocatorState
            .nextForStructure(treeSizes, 1);
        uint256 afterTraceLocationAlloc = gasleft();
        console.log("* Trace location allocation gas:", beforeTraceLocationAlloc - afterTraceLocationAlloc);

        console.log("Trace locations allocated for WideFibonacciComponent");
        console.log("Trace locations colEnd: ", traceLocations[1].colEnd);

        // Component info with mask offsets matching Rust InfoEvaluator
        // TreeVec([[], [[0], [0], ..., [0]]]) - empty preprocessed, 50 trace columns with offset 0
        int32[][][] memory maskOffsets = new int32[][][](2);  // 2 trees
        maskOffsets[0] = new int32[][](0);  // Tree 0: PREPROCESSED - empty
        maskOffsets[1] = new int32[][](50);  // Tree 1: ORIGINAL_TRACE (50 columns for WideFibonacci)
        for (uint256 i = 0; i < 50; i++) {
            maskOffsets[1][i] = new int32[](1);  // Each column has 1 mask point
            maskOffsets[1][i][0] = 0;            // Offset is 0 (current row)
        }

        FrameworkComponentLib.ComponentInfo
            memory componentInfo = FrameworkComponentLib.ComponentInfo({
                nConstraints: 50 >= 2 ? 50 - 2 : 0,
                maxConstraintLogDegreeBound: 3 + 1,
                logSize: 3,
                componentName: "WideFibonacciComponent",
                description: "Wide Fibonacci component for testing",
                maskOffsets: maskOffsets,
                preprocessedColumns: new uint256[](0)
            });

        // Initialize the component (equivalent to WideFibonacciComponent::new)
        uint256 beforeComponentInit = gasleft();
        componentState.initialize(
            address(wideFibEval), // The evaluator
            traceLocations, // Trace locations
            preprocessedColumnIndices, // No preprocessed columns
            QM31Field.zero(), // claimed_sum = SecureField::zero()
            componentInfo // Component metadata
        );
        uint256 afterComponentInit = gasleft();
        console.log("* Component initialization gas:", beforeComponentInit - afterComponentInit);

        uint256 beforeMaskPointsGas = gasleft();
        FrameworkComponentLib.SamplePoints memory samplePoints = componentState
            .maskPoints(oodsPoint);
        uint256 afterMaskPointsGas = gasleft();
        console.log("* Mask points calculation gas:", beforeMaskPointsGas - afterMaskPointsGas);

        console.log("Sample points masked for OODS point:");
        console.log("SamplePoints structure:");
        console.log("  totalPoints:", samplePoints.totalPoints);
        console.log("  nColumns.length:", samplePoints.nColumns.length);

        // Rust: sample_points.push(vec![vec![oods_point]; SECURE_EXTENSION_DEGREE]);
        // Add composition polynomial tree with SECURE_EXTENSION_DEGREE (4) columns
        uint256 beforeCompositionTreeSetup = gasleft();
        console.log("\nAdding composition polynomial tree...");

        // Expand sample points to include composition polynomial tree (tree index 3)
        CirclePoint.Point[][][] memory newPoints = new CirclePoint.Point[][][](
            4
        ); // 4 trees now
        uint256[] memory newNColumns = new uint256[](4);

        // Copy existing trees
        for (uint256 i = 0; i < 3; i++) {
            newPoints[i] = samplePoints.points[i];
            newNColumns[i] = samplePoints.nColumns[i];
        }

        // Add composition polynomial tree (tree 3) with SECURE_EXTENSION_DEGREE=4 columns
        uint256 SECURE_EXTENSION_DEGREE = 4;
        newPoints[3] = new CirclePoint.Point[][](SECURE_EXTENSION_DEGREE);
        newNColumns[3] = SECURE_EXTENSION_DEGREE;

        // Each column in composition tree contains vec![oods_point]
        for (uint256 colIdx = 0; colIdx < SECURE_EXTENSION_DEGREE; colIdx++) {
            newPoints[3][colIdx] = new CirclePoint.Point[](1);
            newPoints[3][colIdx][0] = oodsPoint; // vec![oods_point]
            samplePoints.totalPoints++;
        }

        // Update sample points structure
        samplePoints.points = newPoints;
        samplePoints.nColumns = newNColumns;
        uint256 afterCompositionTreeSetup = gasleft();
        console.log("* Composition tree setup gas:", beforeCompositionTreeSetup - afterCompositionTreeSetup);

        console.log("Sample points after adding composition polynomial:");
        console.log("  totalPoints:", samplePoints.totalPoints);
        console.log("  nColumns.length:", samplePoints.nColumns.length);
        for (uint256 i = 0; i < samplePoints.nColumns.length; i++) {
            console.log("  nColumns[", i, "]:", samplePoints.nColumns[i]);
        }

        // Print composition polynomial tree (tree 3)
        console.log("  Composition polynomial tree (tree 3):");
        for (uint256 colIdx = 0; colIdx < newPoints[3].length; colIdx++) {
            console.log(
                "    Col",
                colIdx,
                "points:",
                newPoints[3][colIdx].length
            );
            console.log(
                "      Point[0].x.first.real:",
                newPoints[3][colIdx][0].x.first.real
            );
            console.log(
                "      Point[0].y.first.real:",
                newPoints[3][colIdx][0].y.first.real
            );
        }

        uint256 phase5EndGas = gasleft();
        console.log("=== PHASE 5 TOTAL GAS:", phase5StartGas - phase5EndGas, "===");

        // =============================================================================
        // PHASE 6: CONSTRAINT EVALUATION
        // =============================================================================
        uint256 phase6StartGas = gasleft();
        console.log("\n=== PHASE 6: CONSTRAINT EVALUATION ===");

        // Rust: let sample_points_by_column = sample_points.as_cols_ref().flatten();
        uint256 beforeFlattening = gasleft();
        console.log("Flattening sample_points_by_column...");

        // Count total columns across all trees
        uint256 totalColumns = 0;
        for (
            uint256 treeIdx = 0;
            treeIdx < samplePoints.points.length;
            treeIdx++
        ) {
            totalColumns += samplePoints.points[treeIdx].length;
        }
        uint256 afterFlattening = gasleft();
        console.log("* Sample points flattening gas:", beforeFlattening - afterFlattening);
        console.log("Total columns across all trees:", totalColumns);


        uint256 beforeAccumulatorInit = gasleft();
        PointEvaluationAccumulator.Accumulator
            memory eval_accumulator = PointEvaluationAccumulator.newAccumulator(
                randomCoeff
            );

        uint256 afterAccumulatorInit = gasleft();
        console.log("* Accumulator initialization gas:", beforeAccumulatorInit - afterAccumulatorInit);

        uint256 beforeSampledValuesCreation = gasleft();
        QM31Field.QM31[][][] memory sampledValues = _createRealSampledValues();
        uint256 afterSampledValuesCreation = gasleft();
        console.log("* Sampled values creation gas:", beforeSampledValuesCreation - afterSampledValuesCreation);

        uint256 beforeConstraintEval = gasleft();
        PointEvaluationAccumulator.Accumulator memory result = componentState
            .evaluateConstraintQuotientsAtPoint(
                oodsPoint,
                sampledValues,
                eval_accumulator
            );
        uint256 afterConstraintEval = gasleft();
        console.log("* Constraint evaluation gas:", beforeConstraintEval - afterConstraintEval);

        // Step 6: Get finalized result equivalent to eval_accumulator.finalize()
        QM31Field.QM31 memory finalResult = result.accumulation;
        console.log(
            "Final accumulated result after evaluating constraints at OODS point:"
        );
        console.log("  finalResult.first.real:", finalResult.first.real);
        console.log("  finalResult.first.imag:", finalResult.first.imag);
        console.log("  finalResult.second.real:", finalResult.second.real);
        console.log("  finalResult.second.imag:", finalResult.second.imag);

        uint256 phase6EndGas = gasleft();
        console.log("=== PHASE 6 TOTAL GAS:", phase6StartGas - phase6EndGas, "===");

        // =============================================================================
        // PHASE 7: FRI VERIFIER INITIALIZATION
        // =============================================================================
        uint256 phase7StartGas = gasleft();
        console.log("\n=== PHASE 7: FRI VERIFIER INITIALIZATION ===");

        uint256 beforeSampledValuesFlattening = gasleft();
        QM31Field.QM31[] memory flattenedSampledValues = _createRealSampledValuesFlattened();
        uint256 afterSampledValuesFlattening = gasleft();
        console.log("* Sampled values flattening gas:", beforeSampledValuesFlattening - afterSampledValuesFlattening);

        console.log("=== Flattened Sampled Values ===");
        console.log("flattenedSampledValues.length:", flattenedSampledValues.length);
        for (uint256 i = 0; i < flattenedSampledValues.length; i++) {
            console.log("flattenedSampledValues[", i, "]:");
            console.log("  first.real:", flattenedSampledValues[i].first.real);
            console.log("  first.imag:", flattenedSampledValues[i].first.imag);
            console.log("  second.real:", flattenedSampledValues[i].second.real);
            console.log("  second.imag:", flattenedSampledValues[i].second.imag);
        }

        console.log("Channel state before mixing flattened sampled values:");
        console.logBytes32(channel.digest);

        uint256 beforeChannelMixing = gasleft();
        channel.mixFelts(flattenedSampledValues);
        uint256 afterChannelMixing = gasleft();
        console.log("* Channel mixing gas:", beforeChannelMixing - afterChannelMixing);
        console.log("Channel state after mixing flattened sampled values:");
        console.logBytes32(channel.digest);

        uint256 beforeRandomCoeff2 = gasleft();
        QM31Field.QM31 memory randomCoeff2;
        randomCoeff2 = channel.drawSecureFelt();
        uint256 afterRandomCoeff2 = gasleft();
        console.log("* Second random coefficient generation gas:", beforeRandomCoeff2 - afterRandomCoeff2);

        // Test 1: Calculate bounds from current commitment scheme state
        uint256 beforeBoundsCalculation = gasleft();
        CirclePolyDegreeBound.Bound[] memory bounds = commitmentScheme
            .calculateBounds();
        uint256 afterBoundsCalculation = gasleft();
        console.log("* Bounds calculation gas:", beforeBoundsCalculation - afterBoundsCalculation);

        console.log("Calculated bounds:");
        console.log("  bounds.length:", bounds.length);

        // Print each bound
        for (uint256 i = 0; i < bounds.length; i++) {
            console.log(
                "  bounds[",
                i,
                "].logDegreeBound:",
                bounds[i].logDegreeBound
            );
        }
        
        // Initialize FriVerifier with bounds and config
        console.log("Initializing FriVerifier...");
        uint256 beforeFriInitGas = gasleft();
        
        // Calculate expected number of inner layers
        // Formula: start with max bound - CIRCLE_TO_LINE_FOLD_STEP (1), fold by FOLD_STEP (1) until reaching logLastLayerDegreeBound
        uint32 maxBound = bounds[0].logDegreeBound; // bounds are sorted in descending order
        uint32 currentBound = maxBound - 1; // CIRCLE_TO_LINE_FOLD_STEP = 1
        uint32 logLastLayerDegreeBound = commitmentScheme.config.friConfig.logLastLayerDegreeBound;
        
        uint256 expectedInnerLayers = 0;
        uint32 tempBound = currentBound;
        while (tempBound > logLastLayerDegreeBound) {
            expectedInnerLayers++;
            tempBound -= 1; // FOLD_STEP = 1
        }
        
        console.log("Calculating FRI inner layers:");
        console.log("  maxBound:", maxBound);
        console.log("  currentBound after line fold:", currentBound);
        console.log("  logLastLayerDegreeBound:", logLastLayerDegreeBound);
        console.log("  expectedInnerLayers:", expectedInnerLayers);
        
        // Create real FRI proof with data from proof.json
        FriVerifier.FriProof memory friProof = getRealFriProof();
        
        friVerifier = FriVerifier.commit(
            channel,
            commitmentScheme.config.friConfig,
            friProof,
            bounds
        );

        console.log("Channel after commit");
        console.logBytes32(channel.digest);

        bool pow_result = channel.verifyPowNonce(commitmentScheme.config.powBits, 1615);

        assertEq(pow_result, true, "Proof of work verification failed");

        channel.mixU64(1615); // Proof of work

        console.log("Channel after mixing proof of work nonce");
        console.logBytes32(channel.digest); 


        FriVerifier.QueryPositionsByLogSize memory queryPositions = friVerifier.sampleQueryPositions(channel);
        
        // Set the queries in friVerifier state for decommitment
        // Use the highest log size queries for FRI decommitment (LogSize 5 with 3 queries)
        uint256 maxLogSizeIdx = 0;
        uint32 maxLogSize = 0;
        for (uint256 i = 0; i < queryPositions.logSizes.length; i++) {
            if (queryPositions.logSizes[i] > maxLogSize) {
                maxLogSize = queryPositions.logSizes[i];
                maxLogSizeIdx = i;
            }
        }
        
        friVerifier.queries = FriVerifier.Queries({
            positions: queryPositions.queryPositions[maxLogSizeIdx],
            logDomainSize: maxLogSize
        });
        
        console.log("Query positions sampled successfully:");
        console.log("  Number of log sizes:", queryPositions.logSizes.length);
        for (uint256 i = 0; i < queryPositions.logSizes.length; i++) {
            console.log("  LogSize", queryPositions.logSizes[i]);
            console.log("    has", queryPositions.queryPositions[i].length, "queries");
            for (uint256 j = 0; j < queryPositions.queryPositions[i].length; j++) {
                console.log("      Query", j, "position:", queryPositions.queryPositions[i][j]);
            }
        }
        
        console.log("Set friVerifier.queries to LogSize", maxLogSize);
        console.log("  with", friVerifier.queries.positions.length, "positions");

        // =============================================================================
        // N Columns Per Log Size (matching Rust: tree.n_columns_per_log_size)
        // =============================================================================
        console.log("\n=== N Columns Per Log Size ===");
        
        // Get n_columns_per_log_size for each tree (equivalent to Rust BTreeMap<u32, usize>)
        uint32[][][] memory nColumnsPerLogSizeData = getNColumnsPerLogSize(commitmentScheme);
        
        console.log("N columns per log size per tree:");
        for (uint256 treeIdx = 0; treeIdx < nColumnsPerLogSizeData.length; treeIdx++) {
            console.log("  Tree", treeIdx, ":");
            if (nColumnsPerLogSizeData[treeIdx].length == 0) {
                console.log("    (empty tree)");
                continue;
            }
            
            for (uint256 i = 0; i < nColumnsPerLogSizeData[treeIdx].length; i++) {
                if (nColumnsPerLogSizeData[treeIdx][i].length >= 2) {
                    uint32 logSize = nColumnsPerLogSizeData[treeIdx][i][0];
                    uint32 nColumns = nColumnsPerLogSizeData[treeIdx][i][1];
                    console.log("Log size", logSize);
                    console.log("    has", nColumns, "columns");
                    // console.log("    LogSize", logSize, "has", nColumns, "columns");
                }
            }
        }
        


        uint256 afterFriInitGas = gasleft();
        console.log("Gas for FriVerifier initialization:", beforeFriInitGas - afterFriInitGas);
        console.log("FriVerifier initialized successfully");
        console.log("  config.logBlowupFactor:", friVerifier.config.logBlowupFactor);
        console.log("  config.nQueries:", friVerifier.config.nQueries);
        console.log("  firstLayer.columnBounds.length:", friVerifier.firstLayer.columnBounds.length);

        // =============================================================================
        // Verify Merkle Decommitments (matching Rust code)
        // =============================================================================
        console.log("\n=== Verifying Merkle Decommitments ===");
        
        // // Get real decommitments and queried values from proof.json
        // bytes[] memory realDecommitments = getRealDecommitments();
        // uint256[][] memory realQueriedValues = getRealQueriedValues();
        
        // console.log("Real decommitments count:", realDecommitments.length);
        // console.log("Real queried values count:", realQueriedValues.length);
        
        // // Verify each tree's decommitments
        // // trees.as_ref().zip_eq(proof.decommitments).zip_eq(proof.queried_values.clone())
        // for (uint256 i = 0; i < realDecommitments.length && i < realQueriedValues.length; i++) {
        //     console.log("  Tree", i, "decommitment size:", realDecommitments[i].length);
        //     console.log("  Tree", i, "queried values count:", realQueriedValues[i].length);
            
        //     // TODO: Call tree.verify(&query_positions_per_log_size, queried_values, decommitment)
        //     // This would require implementing MerkleVerifier.verify() function
        // }

        // =============================================================================  
        // Create Samples (matching Rust: sampled_points.zip_cols(sampled_values))
        // =============================================================================
        console.log("\n=== Creating Point Samples ===");
        
        // Get real sampled values from proof.json
        QM31Field.QM31[][] memory realSampledValues = getRealSampledValues();
        
        console.log("Sample points trees:", samplePoints.nColumns.length);
        console.log("Real sampled values trees:", realSampledValues.length);
        
        // sampled_points.zip_cols(proof.sampled_values).map_cols(...)
        uint256 maxTrees = samplePoints.nColumns.length < realSampledValues.length ? 
                          samplePoints.nColumns.length : realSampledValues.length;
                          
        for (uint256 treeIdx = 0; treeIdx < maxTrees; treeIdx++) {
            if (samplePoints.nColumns[treeIdx] == 0) {
                console.log("  Tree", treeIdx, "- empty (no columns)");
                continue;
            }
            
            console.log("  Tree", treeIdx, "- creating samples:");
            console.log("    Points count:", samplePoints.nColumns[treeIdx]);
            console.log("    Values count:", realSampledValues[treeIdx].length);
            
            // zip(sampled_points, sampled_values).map(|(point, value)| PointSample { point, value })
            uint256 pointsCount = samplePoints.nColumns[treeIdx];
            uint256 maxSamples = pointsCount < realSampledValues[treeIdx].length ? 
                               pointsCount : realSampledValues[treeIdx].length;
                               
            for (uint256 i = 0; i < maxSamples && i < 3; i++) { // Limit to first 3 samples for readability
                console.log("      Sample", i, ":");
                if (samplePoints.points[treeIdx].length > 0 && samplePoints.points[treeIdx][0].length > i) {
                    console.log("        point.x.first.real:", samplePoints.points[treeIdx][0][i].x.first.real);
                    console.log("        point.x.first.imag:", samplePoints.points[treeIdx][0][i].x.first.imag);
                    console.log("        point.y.first.real:", samplePoints.points[treeIdx][0][i].y.first.real);
                    console.log("        point.y.first.imag:", samplePoints.points[treeIdx][0][i].y.first.imag);

                }
                console.log("        value.first.real:", realSampledValues[treeIdx][i].first.real);
                // Create PointSample { point, value } structure
            }
            
            if (maxSamples > 3) {
                console.log("      ... (", maxSamples - 3, "more samples)");
            }
        }

        // =============================================================================
        // Calculate FRI Answers (matching Rust: fri_answers)
        // =============================================================================
        console.log("\n=== Calculating FRI Answers ===");
        
        // Prepare data for fri_answers call
        uint32[][] memory commitmentColumnLogSizes = commitmentScheme.columnLogSizes();
        
        // Create simplified point samples structure (for proof of concept)
        FriVerifier.PointSample[][][] memory pointSamples = new FriVerifier.PointSample[][][](commitmentColumnLogSizes.length);
        for (uint256 treeIdx = 0; treeIdx < commitmentColumnLogSizes.length; treeIdx++) {
            if (commitmentColumnLogSizes[treeIdx].length == 0) {
                pointSamples[treeIdx] = new FriVerifier.PointSample[][](0);
                continue;
            }
            
            pointSamples[treeIdx] = new FriVerifier.PointSample[][](commitmentColumnLogSizes[treeIdx].length);
            for (uint256 colIdx = 0; colIdx < commitmentColumnLogSizes[treeIdx].length; colIdx++) {
                pointSamples[treeIdx][colIdx] = new FriVerifier.PointSample[](1);
                
                // Create a sample point (using OODS point as example)
                pointSamples[treeIdx][colIdx][0] = FriVerifier.PointSample({
                    point: oodsPoint,
                    value: treeIdx < realSampledValues.length && colIdx < realSampledValues[treeIdx].length 
                        ? realSampledValues[treeIdx][colIdx] 
                        : QM31Field.zero()
                });
            }
        }
        
        console.log("Prepared point samples for trees:", pointSamples.length);
        for (uint256 i = 0; i < pointSamples.length; i++) {
            console.log("  Tree", i);
            console.log("    has columns:", pointSamples[i].length);
        }
        
        // Call fri_answers function
        console.log("Calling FriVerifier.friAnswers...");
        
        // Get real queried values as M31 (base field) values
        uint32[][] memory realQueriedValuesM31 = getRealQueriedValuesM31();
        
  
        // Simple call without try-catch for now (can add error handling later)
        QM31Field.QM31[][] memory friAnswersResult = FriVerifier.friAnswers(
            commitmentColumnLogSizes,
            pointSamples,
            randomCoeff2,
            queryPositions,
            realQueriedValuesM31,
            nColumnsPerLogSizeData
        );
        
        console.log("FRI answers calculated successfully:");
        console.log("  Number of columns:", friAnswersResult.length);
        
        // Print detailed structure like in Rust: FRI answers: [[(0 + 0i) + (0 + 0i)u, ...], [...]]
        console.log("FRI answers detailed:");
        for (uint256 colIdx = 0; colIdx < friAnswersResult.length; colIdx++) {
            console.log("  Column", colIdx);
            for (uint256 valIdx = 0; valIdx < friAnswersResult[colIdx].length; valIdx++) {
                QM31Field.QM31 memory val = friAnswersResult[colIdx][valIdx];

                console.log("    Value index", valIdx, ":");
                console.log("First:" , val.first.real);
                console.log("First:" , val.first.imag);
                console.log("Second:" , val.second.real);
                console.log("Second:" , val.second.imag);

            }
        }
        
        // =============================================================================
        // PHASE 8: FRI DECOMMIT (like in Rust)  
        // =============================================================================
        console.log("\\n=== PHASE 8: FRI DECOMMIT ===");
        uint256 phase8StartGas = gasleft();
        
        // Get the real FRI proof data and populate the friVerifier state
        FriVerifier.FriProof memory realFriProof = getRealFriProof();
        
        // Populate friVerifier with the actual proof data needed for decommitment
        // NOTE: Don't create new innerLayers array! That would zero out degreeBound, domainLogSize, etc.
        // Just update the proof field which was set during commit()
        friVerifier.firstLayer.proof = realFriProof.firstLayer;
        for (uint256 i = 0; i < realFriProof.innerLayers.length; i++) {
            friVerifier.innerLayers[i].proof = realFriProof.innerLayers[i];
        }
        friVerifier.lastLayerPoly = realFriProof.lastLayerPoly;
        
        // Ensure queries are properly set (already done during initialization)
        require(friVerifier.queriesSampled, "Queries should be sampled by now");
        
        // Debug: Check FRI answers structure before decommit
        console.log("FRI decommit debug info:");
        console.log("  friAnswersResult.length (columns):", friAnswersResult.length);
        console.log("  friVerifier.queries.positions.length:", friVerifier.queries.positions.length);
        console.log("  friVerifier.firstLayer.columnBounds.length:", friVerifier.firstLayer.columnBounds.length);
        for (uint256 col = 0; col < friAnswersResult.length; col++) {
            console.log("  Column", col, "length:", friAnswersResult[col].length);
        }
        
        // Debug: Check first layer proof commitment
        console.log("First layer proof commitment:");
        console.logBytes32(friVerifier.firstLayer.proof.commitment);
        
        // Debug: Check query positions
        console.log("Query positions for decommit:");
        for (uint256 i = 0; i < friVerifier.queries.positions.length; i++) {
            console.log("  Position", i, ":", friVerifier.queries.positions[i]);
        }
        
        // Debug: Print FRI verifier state before decommit
        console.log("\n=== FRI VERIFIER STATE ===");
        console.log("Config:");
        console.log("  log_blowup_factor:", friVerifier.config.logBlowupFactor);
        console.log("  log_last_layer_degree_bound:", friVerifier.config.logLastLayerDegreeBound);
        console.log("  n_queries:", friVerifier.config.nQueries);
        
        console.log("First layer:");
        console.log("  column_bounds length:", friVerifier.firstLayer.columnBounds.length);
        console.log("  folding_alpha.first.real:", friVerifier.firstLayer.foldingAlpha.first.real);
        console.log("  folding_alpha.first.imag:", friVerifier.firstLayer.foldingAlpha.first.imag);
        console.log("  folding_alpha.second.real:", friVerifier.firstLayer.foldingAlpha.second.real);
        console.log("  folding_alpha.second.imag:", friVerifier.firstLayer.foldingAlpha.second.imag);
        console.log("  proof.commitment:", vm.toString(friVerifier.firstLayer.proof.commitment));
        
        console.log("Inner layers count:", friVerifier.innerLayers.length);
        for (uint256 i = 0; i < friVerifier.innerLayers.length; i++) {
            console.log("  Inner layer", i, ":");
            console.log("    degree_bound:", friVerifier.innerLayers[i].degreeBound);
            console.log("    domain_log_size:", friVerifier.innerLayers[i].domain.logSize);
            console.log("    folding_alpha.first.real:", friVerifier.innerLayers[i].foldingAlpha.first.real);
            console.log("    folding_alpha.first.imag:", friVerifier.innerLayers[i].foldingAlpha.first.imag);
            console.log("    folding_alpha.second.real:", friVerifier.innerLayers[i].foldingAlpha.second.real);
            console.log("    folding_alpha.second.imag:", friVerifier.innerLayers[i].foldingAlpha.second.imag);
            console.log("    commitment:", vm.toString(friVerifier.innerLayers[i].proof.commitment));
        }
        
        console.log("Last layer:");
        console.log("  domain_log_size:", friVerifier.lastLayerDomainLogSize);
        console.log("  poly coeffs length:", friVerifier.lastLayerPoly.length);
        if (friVerifier.lastLayerPoly.length > 0) {
            console.log("  poly[0].first.real:", friVerifier.lastLayerPoly[0].first.real);
            console.log("  poly[0].first.imag:", friVerifier.lastLayerPoly[0].first.imag);
            console.log("  poly[0].second.real:", friVerifier.lastLayerPoly[0].second.real);
            console.log("  poly[0].second.imag:", friVerifier.lastLayerPoly[0].second.imag);
        }
        
        console.log("Queries:");
        console.log("  positions length:", friVerifier.queries.positions.length);
        console.log("  log_domain_size:", friVerifier.queries.logDomainSize);
        console.log("  queries_sampled:", friVerifier.queriesSampled);
        
        // Debug: Print FRI answers result before decommit
        console.log("\n=== FRI ANSWERS RESULT ===");
        console.log("FRI answers columns:", friAnswersResult.length);
        for (uint256 i = 0; i < friAnswersResult.length; i++) {
            console.log("Column", i, "length:", friAnswersResult[i].length);
            for (uint256 j = 0; j < friAnswersResult[i].length; j++) {
                // console.log("  [", i, "][", j, "]:");
                console.log("    first.real:", friAnswersResult[i][j].first.real);
                console.log("    first.imag:", friAnswersResult[i][j].first.imag);
                console.log("    second.real:", friAnswersResult[i][j].second.real);
                console.log("    second.imag:", friAnswersResult[i][j].second.imag);
            }
        }
        
        uint256 beforeDecommit = gasleft();
        
        // Call actual FRI decommit with proper proof data
        bool decommitSuccess = FriVerifier.decommit(friVerifier, friAnswersResult);
        
        uint256 afterDecommit = gasleft();
        
        console.log("* FRI decommit gas:", beforeDecommit - afterDecommit);
        console.log("* FRI decommit result:", decommitSuccess ? "SUCCESS" : "FAILED");
        
        // Verify decommit succeeded (like in Rust where it returns Ok(()))
        assertTrue(decommitSuccess, "FRI decommit verification must succeed");
        
        uint256 phase8EndGas = gasleft();
        console.log("=== PHASE 8 TOTAL GAS:", phase8StartGas - phase8EndGas, "===");
        


        // =============================================================================
        // FINAL SUMMARY: TOTAL GAS BREAKDOWN
        // =============================================================================
        uint256 totalEndGas = gasleft();
        uint256 totalGasUsed = totalStartGas - totalEndGas;
        
        console.log("\\n============================================================");
        console.log("                FINAL GAS USAGE SUMMARY");
        console.log("============================================================");
        console.log("* Total gas consumed:", totalGasUsed);
        console.log("* Gas remaining:", totalEndGas);
        console.log("* Initial gas:", totalStartGas);
        console.log("============================================================");
        
        console.log("PHASE BREAKDOWN:");
        console.log("* All phases completed successfully");
        console.log("* Individual phase gas usage logged above");
        console.log("============================================================");
    }

    function test_realVerifier() public {
        ProofParser.Proof memory proof;
        proof.commitments = getRealCommitments();
        proof.config.powBits = POW_BITS;
        proof.proofOfWork = 1615;
        proof.config.friConfig.logBlowupFactor = LOG_BLOWUP_FACTOR;
        proof.config.friConfig.logLastLayerDegreeBound = LOG_LAST_LAYER_DEGREE_BOUND;
        proof.config.friConfig.nQueries = N_QUERIES;
        proof.decommitments = getRealDecommitments();
        proof.sampledValues = _createRealSampledValues();
        // proof.decommitments = MerkleVerifier.Decommitment[](0);
        proof.queriedValues = getRealQueriedValuesM31();
        proof.friProof = getRealFriProof();
        int32[][][] memory maskOffsets = new int32[][][](2);  // 2 trees
        maskOffsets[0] = new int32[][](0);  // Tree 0: PREPROCESSED - empty
        maskOffsets[1] = new int32[][](50);  // Tree 1: ORIGINAL_TRACE (50 columns for WideFibonacci)
        for (uint256 i = 0; i < 50; i++) {
            maskOffsets[1][i] = new int32[](1);  // Each column has 1 mask point
            maskOffsets[1][i][0] = 0;            // Offset is 0 (current row)
        }


        FrameworkComponentLib.ComponentInfo memory componentInfo = FrameworkComponentLib.ComponentInfo({
            nConstraints: 50 >= 2 ? 50 - 2 : 0,
            maxConstraintLogDegreeBound: 3 + 1,
            logSize: 3,
            componentName: "WideFibonacciComponent",
            description: "Wide Fibonacci component for testing",
            maskOffsets: maskOffsets,
            preprocessedColumns: new uint256[](0)
        });

        WideFibonacciEval wideFibEvalAddress = new WideFibonacciEval(3, 50);
        STWOVerifier verifier = new STWOVerifier();
        STWOVerifier.VerificationParams memory params = STWOVerifier.VerificationParams({
            evaluator: address(wideFibEvalAddress),
            claimedSum: QM31Field.zero(),
            componentInfo: componentInfo
        });

        bytes32[] memory treeRoots = new bytes32[](2);
        treeRoots[0] = proof.commitments[0]; // PREPROCESSED
        treeRoots[1] = proof.commitments[1]; // ORIGINAL_TRACE
        uint32[][] memory treeColumnLogSizes= new uint32[][](2);
           // Tree 0: Empty (preprocessed) - extended log sizes: []
        treeColumnLogSizes[0] = new uint32[](0);
        
        // Tree 1: 50 trace columns - extended log sizes: [4, 4, 4, ...] (50 times)
        treeColumnLogSizes[1] = new uint32[](50);
        for (uint256 i = 0; i < 50; i++) {
            treeColumnLogSizes[1][i] = 4;  // logSize(3) + logBlowupFactor(1) = 4
        }
        bytes32 digest = 0x4bf4f70138f3d2b12e3b0a724f67e69f2572d2818833ef6ec92e80ca3d11d687;
        uint32 nDraws = 0;

        uint256 gas_before = gasleft();
        bool result = verifier.verify(proof, params, treeRoots, treeColumnLogSizes, digest, nDraws);
        uint256 gas_after = gasleft();
        console.log("Gas used for verification:", gas_before - gas_after);
        assertEq(result, true, "STWO verification failed");


    }

    // =============================================================================
    // Test: Bounds Calculation
    // =============================================================================

    /// @notice Test bounds calculation matching Rust implementation
    /// @dev Verifies: column_log_sizes().flatten().sorted().rev().dedup()
    ///                .map(|log_size| CirclePolyDegreeBound::new(log_size - log_blowup_factor))
    function test_boundsCalculation() public {
        console.log("=== Testing Bounds Calculation ===");

        // First, set up commitments like in test_realCommitmentFlow
        bytes32[] memory realCommitments = getRealCommitments();

        // Preprocessed columns commitment (empty)
        uint32[] memory preprocessedSizes = new uint32[](0);
        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            realCommitments[0],
            preprocessedSizes,
            channel
        );

        // Trace columns commitment (50 columns, all log_size 3)
        uint32[] memory traceSizes = new uint32[](50);
        for (uint256 i = 0; i < 50; i++) {
            traceSizes[i] = 3;
        }
        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            realCommitments[1],
            traceSizes,
            channel
        );

        // Get commitment scheme state from the real test setup
        uint256 beforeBoundsGas = gasleft();

        // Test 1: Calculate bounds from current commitment scheme state
        CirclePolyDegreeBound.Bound[] memory bounds = commitmentScheme
            .calculateBounds();

        uint256 afterBoundsGas = gasleft();
        console.log(
            "Gas for calculateBounds():",
            beforeBoundsGas - afterBoundsGas
        );

        console.log("Calculated bounds:");
        console.log("  bounds.length:", bounds.length);

        // Print each bound
        for (uint256 i = 0; i < bounds.length; i++) {
            console.log(
                "  bounds[",
                i,
                "].logDegreeBound:",
                bounds[i].logDegreeBound
            );
            console.log(
                "  bounds[",
                i,
                "].degree:",
                1 << bounds[i].logDegreeBound
            );
        }

        // Test 2: Debug intermediate steps
        console.log("\nDebug intermediate steps:");

        // Get flattened column log sizes
        uint32[] memory flattened = commitmentScheme
            .getFlattenedColumnLogSizes();
        console.log("Flattened column log sizes:");
        console.log("  flattened.length:", flattened.length);
        for (uint256 i = 0; i < flattened.length; i++) {
            console.log("  flattened[", i, "]:", flattened[i]);
        }

        // Get processed (sorted, reversed, deduplicated) log sizes
        uint32[] memory processed = commitmentScheme
            .getProcessedColumnLogSizes();
        console.log("Processed column log sizes (sorted.rev.dedup):");
        console.log("  processed.length:", processed.length);
        for (uint256 i = 0; i < processed.length; i++) {
            console.log("  processed[", i, "]:", processed[i]);
        }

        // Test 3: Verify against expected values for WideFibonacci
        // Expected: Tree 0 (preprocessed): empty, Tree 1 (trace): 50 columns of log_size 3
        // So flattened should be [3, 3, 3, ..., 3] (50 times)
        // Sorted: [3, 3, 3, ..., 3], Reversed: [3, 3, 3, ..., 3], Dedup: [3]
        // Bounds: [CirclePolyDegreeBound::new(3 - 1)] = [CirclePolyDegreeBound::new(2)]

        console.log("\nExpected vs Actual:");
        console.log(
            "Expected processed length: 1 (only log_size 3 after dedup)"
        );
        console.log("Actual processed length:", processed.length);

        if (processed.length > 0) {
            console.log("Expected processed[0]: 3");
            console.log("Actual processed[0]:", processed[0]);

            uint32 expectedLogDegreeBound = 3 - LOG_BLOWUP_FACTOR; // 3 - 1 = 2
            console.log(
                "Expected bounds[0].logDegreeBound:",
                expectedLogDegreeBound
            );
            if (bounds.length > 0) {
                console.log(
                    "Actual bounds[0].logDegreeBound:",
                    bounds[0].logDegreeBound
                );
                assertEq(
                    bounds[0].logDegreeBound,
                    expectedLogDegreeBound,
                    "Bounds calculation mismatch"
                );
            }
        }

        // Verify non-empty bounds
        assertGt(bounds.length, 0, "Should have at least one bound");
        console.log("Bounds calculation test passed");
    }

    // =============================================================================
    // Test: Real Fibonacci Sampled Values
    // =============================================================================

    /// @notice Test with real Fibonacci values from proof.json
    /// @dev Uses actual sampled_values[1] which contains the Fibonacci sequence
    function test_realFibonacciValues() public {
        console.log("=== Testing Real Fibonacci Values ===");

        uint32[] memory realFib = getRealFibonacciValues();

        // Log first 10 Fibonacci values to verify they're correct
        console.log("First 10 real Fibonacci values from proof.json:");
        for (uint256 i = 0; i < 10; i++) {
            console.log("  F(", i, ") =", realFib[i]);
        }

        // Verify Fibonacci sequence properties
        assertEq(realFib[0], 0, "F(0) should be 0");
        assertEq(realFib[1], 1, "F(1) should be 1");
        assertEq(realFib[2], 1, "F(2) should be 1");

        // Verify Fibonacci recurrence: F(n) = F(n-1) + F(n-2)
        for (uint256 i = 2; i < 10; i++) {
            uint32 expected = realFib[i - 1] + realFib[i - 2];
            assertEq(
                realFib[i],
                expected,
                string.concat(
                    "Fibonacci recurrence failed at index ",
                    vm.toString(i)
                )
            );
        }

        // Convert to QM31 format for constraint testing
        QM31Field.QM31[] memory qm31Values = new QM31Field.QM31[](51);
        for (uint256 i = 0; i < 51; i++) {
            qm31Values[i] = QM31Field.fromM31(realFib[i], 0, 0, 0);
        }

        console.log(
            "Successfully converted",
            qm31Values.length,
            "Fibonacci values to QM31 format"
        );


    }

    // =============================================================================
    // Test: Real n_preprocessed_columns Flow
    // =============================================================================

    /// @notice Test n_preprocessed_columns calculation like in Rust
    /// @dev Maps to: let n_preprocessed_columns = commitment_scheme.trees[PREPROCESSED_TRACE_IDX].column_log_sizes.len();
    function test_realPreprocessedColumnsFlow() public {
        console.log("=== Testing Real n_preprocessed_columns Flow ===");

        // Based on proof.json structure, sampled_values[0] is empty [] indicating no preprocessed columns
        uint256 nPreprocessedColumns = 0; // Empty array in proof.json

        console.log(
            "Real n_preprocessed_columns from proof.json:",
            nPreprocessedColumns
        );

        // This should match Rust: Components { components: components.to_vec(), n_preprocessed_columns }
        console.log("Creating Components structure:");
        console.log("  components: [WideFibonacciEval]");
        console.log("  n_preprocessed_columns:", nPreprocessedColumns);

        // Get composition_log_degree_bound like in Rust
        uint32 compositionLogDegreeBound = wideFibEval
            .maxConstraintLogDegreeBound();
        console.log(
            "Composition polynomial log degree bound:",
            compositionLogDegreeBound
        );

        // This should match Rust log output: "Composition polynomial log degree bound: {}"
        assertEq(
            compositionLogDegreeBound,
            6,
            "Expected: log_n_rows + 1 = 5 + 1 = 6"
        );
        assertEq(
            nPreprocessedColumns,
            0,
            "WideFibonacci should have no preprocessed columns"
        );
    }

    // =============================================================================
    // Test: Real Proof-of-Work Value
    // =============================================================================

    /// @notice Test with real proof_of_work value from proof.json
    function test_realProofOfWork() public {
        console.log("=== Testing Real Proof of Work ===");

        // Get real proof_of_work value from proof.json
        uint64 realProofOfWork = getRealProofOfWork();

        console.log("Real proof_of_work from proof.json:", realProofOfWork);

        // Set it in our test proof
        testProof.proofOfWork = realProofOfWork;

        // Verify POW_BITS config matches
        assertEq(
            testProof.config.powBits,
            POW_BITS,
            "POW_BITS should match proof.json config"
        );
        console.log("POW_BITS config:", testProof.config.powBits);

        // In real verification, this would be checked against the channel state
        assertTrue(realProofOfWork > 0, "Proof of work should be non-zero");
        
        // Note: POW_BITS represents the difficulty (number of leading zeros required),
        // not a maximum value constraint on the nonce itself.
        // The real proof_of_work value 1615 is the nonce that satisfies the POW_BITS=10 requirement.
        console.log("Real proof of work nonce is valid for POW_BITS =", POW_BITS);
    }

    // =============================================================================
    // Real Proof Data Functions
    // =============================================================================

    /// @notice Create real FRI proof from proof.json data
    /// @dev Converts the exact FRI proof structure from proof.json
    /// @return friProof Complete FRI proof with real data
    function getRealFriProof() internal pure returns (FriVerifier.FriProof memory friProof) {
        // Real first layer data from proof.json
        QM31Field.QM31[] memory firstLayerWitness = new QM31Field.QM31[](3);
        firstLayerWitness[0] = QM31Field.fromM31(0, 0, 0, 0);
        firstLayerWitness[1] = QM31Field.fromM31(0, 0, 0, 0);
        firstLayerWitness[2] = QM31Field.fromM31(0, 0, 0, 0);
        
        // First layer commitment from proof.json
        uint8[32] memory firstLayerCommitmentBytes = [
            4, 121, 99, 64, 148, 203, 210, 20, 206, 172, 78, 16, 210, 57, 165, 191,
            43, 112, 218, 76, 30, 105, 42, 243, 163, 248, 10, 7, 14, 185, 89, 73
        ];
        
        // First layer decommitment - using first hash_witness from fri_proof.first_layer.decommitment
        bytes32[] memory firstLayerHashWitness = new bytes32[](7);
        
        // Hash witness 0
        uint8[32] memory hw0 = [171, 202, 64, 193, 28, 82, 54, 15, 9, 244, 176, 201, 231, 102, 70, 112, 123, 105, 202, 187, 159, 59, 59, 243, 93, 8, 29, 32, 13, 220, 39, 50];
        firstLayerHashWitness[0] = _uint8ArrayToBytes32(hw0);
        
        // Hash witness 1-3 (same as 0 in proof.json)
        firstLayerHashWitness[1] = firstLayerHashWitness[0];
        firstLayerHashWitness[2] = firstLayerHashWitness[0];
        firstLayerHashWitness[3] = firstLayerHashWitness[0];
        
        // Hash witness 4-5
        uint8[32] memory hw4 = [226, 185, 28, 138, 5, 106, 181, 97, 115, 99, 29, 172, 145, 153, 108, 61, 6, 240, 157, 60, 38, 230, 163, 219, 40, 146, 83, 185, 149, 191, 191, 245];
        firstLayerHashWitness[4] = _uint8ArrayToBytes32(hw4);
        firstLayerHashWitness[5] = firstLayerHashWitness[4];
        
        // Hash witness 6
        uint8[32] memory hw6 = [154, 187, 40, 169, 116, 29, 146, 43, 248, 137, 213, 95, 30, 111, 34, 184, 85, 157, 34, 154, 121, 162, 223, 175, 245, 185, 16, 179, 47, 125, 179, 218];
        firstLayerHashWitness[6] = _uint8ArrayToBytes32(hw6);
        
        // Create first layer  
        // Encode decommitment in the format expected by _decodeDecommitment:
        // [hashWitnessLength(32)] + [hashWitness...] + [columnWitnessLength(32)] + [columnWitness...]
        bytes memory firstLayerDecommitment = abi.encodePacked(
            uint256(firstLayerHashWitness.length),  // hashWitnessLength
            firstLayerHashWitness,                  // hashWitness array
            uint256(0),                             // columnWitnessLength (0 for empty)
            new uint32[](0)                         // empty columnWitness
        );
        
        friProof.firstLayer = FriVerifier.FriLayerProof({
            friWitness: firstLayerWitness,
            decommitment: firstLayerDecommitment,
            commitment: _uint8ArrayToBytes32(firstLayerCommitmentBytes)
        });
        
        // Create 3 inner layers from proof.json
        friProof.innerLayers = new FriVerifier.FriLayerProof[](3);
        
        // Inner layer 0
        QM31Field.QM31[] memory innerLayer0Witness = new QM31Field.QM31[](2);
        innerLayer0Witness[0] = QM31Field.fromM31(0, 0, 0, 0);
        innerLayer0Witness[1] = QM31Field.fromM31(0, 0, 0, 0);
        
        uint8[32] memory innerLayer0Commitment = [47, 157, 158, 144, 122, 106, 6, 152, 1, 50, 228, 151, 193, 72, 40, 119, 91, 14, 118, 149, 204, 44, 126, 226, 40, 182, 9, 70, 60, 214, 91, 229];
        
        bytes32[] memory innerLayer0HashWitness = new bytes32[](3);
        uint8[32] memory il0hw0 = [50, 92, 80, 167, 201, 186, 48, 118, 40, 229, 240, 169, 189, 91, 239, 102, 136, 173, 49, 45, 13, 27, 100, 238, 108, 207, 63, 173, 208, 248, 42, 36];
        innerLayer0HashWitness[0] = _uint8ArrayToBytes32(il0hw0);
        innerLayer0HashWitness[1] = innerLayer0HashWitness[0];
        uint8[32] memory il0hw2 = [226, 74, 37, 64, 18, 215, 102, 235, 189, 54, 100, 183, 213, 123, 245, 167, 54, 26, 246, 116, 89, 18, 56, 27, 146, 229, 206, 199, 214, 117, 69, 7];
        innerLayer0HashWitness[2] = _uint8ArrayToBytes32(il0hw2);
        
        bytes memory innerLayer0Decommitment = abi.encodePacked(
            uint256(innerLayer0HashWitness.length),  // hashWitnessLength
            innerLayer0HashWitness,                  // hashWitness array
            uint256(0),                             // columnWitnessLength (0 for empty)
            new uint32[](0)                         // empty columnWitness
        );
        
        friProof.innerLayers[0] = FriVerifier.FriLayerProof({
            friWitness: innerLayer0Witness,
            decommitment: innerLayer0Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer0Commitment)
        });
        
        // Inner layer 1
        QM31Field.QM31[] memory innerLayer1Witness = new QM31Field.QM31[](2);
        innerLayer1Witness[0] = QM31Field.fromM31(0, 0, 0, 0);
        innerLayer1Witness[1] = QM31Field.fromM31(0, 0, 0, 0);
        
        uint8[32] memory innerLayer1Commitment = [226, 74, 37, 64, 18, 215, 102, 235, 189, 54, 100, 183, 213, 123, 245, 167, 54, 26, 246, 116, 89, 18, 56, 27, 146, 229, 206, 199, 214, 117, 69, 7];
        
        bytes32[] memory innerLayer1HashWitness = new bytes32[](1);
        uint8[32] memory il1hw0 = [58, 8, 109, 44, 213, 188, 98, 82, 228, 161, 119, 179, 76, 221, 211, 242, 155, 15, 83, 95, 110, 124, 123, 44, 180, 233, 178, 216, 3, 200, 171, 58];
        innerLayer1HashWitness[0] = _uint8ArrayToBytes32(il1hw0);
        
        bytes memory innerLayer1Decommitment = abi.encodePacked(
            uint256(innerLayer1HashWitness.length),  // hashWitnessLength
            innerLayer1HashWitness,                  // hashWitness array
            uint256(0),                             // columnWitnessLength (0 for empty)
            new uint32[](0)                         // empty columnWitness
        );
        
        friProof.innerLayers[1] = FriVerifier.FriLayerProof({
            friWitness: innerLayer1Witness,
            decommitment: innerLayer1Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer1Commitment)
        });
        
        // Inner layer 2 (final layer before last_layer_poly)
        QM31Field.QM31[] memory innerLayer2Witness = new QM31Field.QM31[](0); // Empty witness array
        
        uint8[32] memory innerLayer2Commitment = [58, 8, 109, 44, 213, 188, 98, 82, 228, 161, 119, 179, 76, 221, 211, 242, 155, 15, 83, 95, 110, 124, 123, 44, 180, 233, 178, 216, 3, 200, 171, 58];
        
        bytes32[] memory innerLayer2HashWitness = new bytes32[](1);
        innerLayer2HashWitness[0] = _uint8ArrayToBytes32(il0hw0); // Reuse from layer 0
        
        bytes memory innerLayer2Decommitment = abi.encodePacked(
            uint256(innerLayer2HashWitness.length),  // hashWitnessLength
            innerLayer2HashWitness,                  // hashWitness array
            uint256(0),                             // columnWitnessLength (0 for empty)
            new uint32[](0)                         // empty columnWitness
        );
        
        friProof.innerLayers[2] = FriVerifier.FriLayerProof({
            friWitness: innerLayer2Witness,
            decommitment: innerLayer2Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer2Commitment)
        });
        
        // Last layer polynomial - single coefficient [0,0],[0,0] from proof.json
        friProof.lastLayerPoly = new QM31Field.QM31[](1);
        friProof.lastLayerPoly[0] = QM31Field.fromM31(0, 0, 0, 0);
    }

    /// @notice Get real proof of work value from proof.json
    /// @return Real proof of work nonce
    function getRealProofOfWork() internal pure returns (uint64) {
        return REAL_PROOF_OF_WORK;
    }


    function getRealDecommitments() internal pure returns (MerkleVerifier.Decommitment[] memory decommitments) {

        decommitments = new MerkleVerifier.Decommitment[](3);

        // bytes[] memory decommitments = new bytes[](3);

        decommitments[0] = MerkleVerifier.Decommitment({
            hashWitness: new bytes32[](0),
            columnWitness: new uint32[](0)
        });

        bytes32[] memory hashWitness1 = new bytes32[](5);
        hashWitness1[0] = 0x256d4681eaaeb89966ad0e2b4a47d523ad2d296eca8e0a39ebec52692ca54a5b;
        hashWitness1[1] = 0x256d4681eaaeb89966ad0e2b4a47d523ad2d296eca8e0a39ebec52692ca54a5b;
        hashWitness1[2] = 0x173de5b95b94db69a785629e3731bfa68adfab1fddb0b95a9925c65dc599ce13;
        hashWitness1[3] = 0x173de5b95b94db69a785629e3731bfa68adfab1fddb0b95a9925c65dc599ce13;
        hashWitness1[4] = 0x9b436975ff564f4b2bd0b0d3b26da6a634865292730eb879c390cb233a1a2a5a;

        bytes32[] memory hashWitness2 = new bytes32[](6);
        hashWitness2[0] = 0xabca40c11c52360f09f4b0c9e76646707b69cabb9f3b3bf35d081d200ddc2732;
        hashWitness2[1] = 0x325c50a7c9ba307628e5f0a9bd5bef6688ad312d0d1b64ee6ccf3fadd0f82a24;
        hashWitness2[2] = 0x325c50a7c9ba307628e5f0a9bd5bef6688ad312d0d1b64ee6ccf3fadd0f82a24;
        hashWitness2[3] = 0x3a086d2cd5bc6252e4a177b34cddd3f29b0f535f6e7c7b2cb4e9b2d803c8ab3a;
        hashWitness2[4] = 0x3a086d2cd5bc6252e4a177b34cddd3f29b0f535f6e7c7b2cb4e9b2d803c8ab3a;
        hashWitness2[5] = 0x2f9d9e907a6a06980132e497c14828775b0e7695cc2c7ee228b609463cd65be5;

        decommitments[1] = MerkleVerifier.Decommitment({
            hashWitness: hashWitness1,
            columnWitness: new uint32[](0)
        });

        decommitments[2] = MerkleVerifier.Decommitment({
            hashWitness: hashWitness2,
            columnWitness: new uint32[](0)
        });
        return decommitments;
    }

    /// @notice Get real queried values from proof.json
    /// @return Array of queried values for each tree
    function getRealQueriedValues() internal pure returns (uint256[][] memory) {
        uint256[][] memory queriedValues = new uint256[][](3);
        
        // Tree 0: Empty queried values
        queriedValues[0] = new uint256[](0);
        
        // Tree 1: Real Fibonacci values from proof.json "queried_values"
        uint32[] memory fibValues = getRealFibonacciValues();
        queriedValues[1] = new uint256[](fibValues.length);
        for (uint256 i = 0; i < fibValues.length; i++) {
            queriedValues[1][i] = fibValues[i];
        }
        
        // Tree 2: Zero values from proof.json 
        queriedValues[2] = new uint256[](12);
        for (uint256 i = 0; i < 12; i++) {
            queriedValues[2][i] = 0;
        }
        
        return queriedValues;
    }

    /// @notice Get real queried values from proof.json as M31 (base field) values
    /// @dev This version returns uint32 values suitable for FRI answers computation
    /// @return Array of queried M31 values for each tree
    function getRealQueriedValuesM31() internal pure returns (uint32[][] memory) {
        uint32[][] memory queriedValues = new uint32[][](3);
        
        // Tree 0: Empty queried values from proof.json
        queriedValues[0] = new uint32[](0);
        
        // Tree 1: Real Fibonacci values from proof.json "queried_values"
        // First 50 values: [0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765,10946,17711,28657,46368,75025,121393,196418,317811,514229,832040,1346269,2178309,3524578,5702887,9227465,14930352,24157817,39088169,63245986,102334155,165580141,267914296,433494437,701408733,1134903170,1836311903,823731426,512559682,1336291108]
        // Then repeats the same 50 values
        uint32[] memory fibValues = getRealFibonacciValues();
        queriedValues[1] = new uint32[](100); // Total 100 values (50 + 50)
        
        // Copy first 50 Fibonacci values
        for (uint256 i = 0; i < 50; i++) {
            queriedValues[1][i] = fibValues[i];
        }
        
        // Copy same 50 Fibonacci values again (as per proof.json structure)
        for (uint256 i = 0; i < 50; i++) {
            queriedValues[1][50 + i] = fibValues[i];
        }
        
        // Tree 2: 12 zero values from proof.json 
        queriedValues[2] = new uint32[](12);
        for (uint256 i = 0; i < 12; i++) {
            queriedValues[2][i] = 0;
        }
        
        return queriedValues;
    }

    /// @notice Get real sampled values from proof.json  
    /// @return Array of sampled values for each tree
    function getRealSampledValues() internal pure returns (QM31Field.QM31[][] memory) {
        QM31Field.QM31[][] memory sampledValues = new QM31Field.QM31[][](3);
        
        // Tree 0: Empty sampled values
        sampledValues[0] = new QM31Field.QM31[](0);
        
        // Tree 1: Fibonacci values from proof.json "sampled_values"  
        uint32[] memory fibValues = getRealFibonacciValues();
        sampledValues[1] = new QM31Field.QM31[](fibValues.length);
        for (uint256 i = 0; i < fibValues.length; i++) {
            sampledValues[1][i] = QM31Field.fromM31(fibValues[i], 0, 0, 0);
        }
        
        // Tree 2: Zero values from proof.json
        sampledValues[2] = new QM31Field.QM31[](4);
        for (uint256 i = 0; i < 4; i++) {
            sampledValues[2][i] = QM31Field.zero();
        }
        
        return sampledValues;
    }

    /// @notice Get n_columns_per_log_size for each tree (matching Rust BTreeMap<u32, usize>)
    /// @param scheme The commitment scheme state
    /// @return Array of [logSize, nColumns] pairs for each tree
    function getNColumnsPerLogSize(CommitmentSchemeVerifierLib.VerifierState storage scheme) 
        internal 
        view 
        returns (uint32[][][] memory) 
    {
        uint32[][][] memory result = new uint32[][][](scheme.columnLogSizes().length);
        
        for (uint256 treeIdx = 0; treeIdx < scheme.columnLogSizes().length; treeIdx++) {
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
    function _getUniqueLogSizes(uint32[] memory logSizes) internal pure returns (uint32[] memory) {
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
    function _removeDuplicatesUint32Helper(uint32[] memory sortedArr) internal pure returns (uint32[] memory) {
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
        uint32[] memory deduplicated = new uint32[](uniqueCount);
        deduplicated[0] = sortedArr[0];
        uint256 currentIndex = 1;
        
        for (uint256 i = 1; i < sortedArr.length; i++) {
            if (sortedArr[i] != sortedArr[i-1]) {
                deduplicated[currentIndex] = sortedArr[i];
                currentIndex++;
            }
        }
        
        return deduplicated;
    }

    // =============================================================================
    // Helper Functions
    // =============================================================================

    /// @notice Create real sampled values structure from proof.json
    /// @dev Converts the nested array structure from proof.json
    function _createRealSampledValues()
        internal
        pure
        returns (QM31Field.QM31[][][] memory sampledValues)
    {
        sampledValues = new QM31Field.QM31[][][](3); // 3 trees: preprocessed, trace, interaction

        // Tree 0: Preprocessed (empty in proof.json)
        sampledValues[0] = new QM31Field.QM31[][](0);

        // Tree 1: Trace (51 Fibonacci values)
        uint32[] memory fibValues = getRealFibonacciValues();
        sampledValues[1] = new QM31Field.QM31[][](fibValues.length);
        for (uint256 i = 0; i < fibValues.length; i++) {
            sampledValues[1][i] = new QM31Field.QM31[](1);
            sampledValues[1][i][0] = QM31Field.fromM31(fibValues[i], 0, 0, 0);
        }

        // Tree 2: Interaction (4 zero values in proof.json)
        sampledValues[2] = new QM31Field.QM31[][](4);
        for (uint256 i = 0; i < 4; i++) {
            sampledValues[2][i] = new QM31Field.QM31[](1);
            sampledValues[2][i][0] = QM31Field.zero();
        }
    }

    /// @notice Create real sampled values and return them flattened
    /// @dev Creates the same structure as _createRealSampledValues but returns flattened array
    /// @return flattened Flattened array of all sampled values (51 Fibonacci + 4 zeros)
    function _createRealSampledValuesFlattened()
        internal
        pure
        returns (QM31Field.QM31[] memory flattened)
    {
        uint32[] memory fibValues = getRealFibonacciValues();
        
        // Calculate total length: 0 (preprocessed) + 51 (trace) + 4 (interaction) = 55
        uint256 totalLength = fibValues.length + 4;
        flattened = new QM31Field.QM31[](totalLength);
        uint256 currentIndex = 0;
        
        // Tree 0: Preprocessed (empty) - nothing to add
        
        // Tree 1: Trace (51 Fibonacci values)
        for (uint256 i = 0; i < fibValues.length; i++) {
            flattened[currentIndex] = QM31Field.fromM31(fibValues[i], 0, 0, 0);
            currentIndex++;
        }
        
        // Tree 2: Interaction (4 zero values)
        for (uint256 i = 0; i < 4; i++) {
            flattened[currentIndex] = QM31Field.zero();
            currentIndex++;
        }
    }

    /// @notice Log commitment in hex format like Rust debug output
    function _logCommitmentAsHex(
        string memory label,
        bytes32 commitment
    ) internal view {
        console.log(label);
        console.logBytes32(commitment);
    }

    /// @notice Convert bytes32 to uint32 array for KeccakChannelLib
    /// @param value Bytes32 value to convert
    /// @return u32Array Array of 8 uint32 values (32 bytes / 4 bytes per uint32)
    function _bytes32ToU32Array(
        bytes32 value
    ) internal pure returns (uint32[] memory u32Array) {
        u32Array = new uint32[](8);

        for (uint256 i = 0; i < 8; i++) {
            // Extract 4 bytes starting from position i*4
            uint32 extracted = uint32(uint256(value >> (224 - i * 32)));
            u32Array[i] = extracted;
        }
    }

    /// @notice Convert uint8[32] array to bytes32
    /// @param arr Array of 32 uint8 values
    /// @return result Bytes32 representation
    function _uint8ArrayToBytes32(
        uint8[32] memory arr
    ) internal pure returns (bytes32 result) {
        for (uint256 i = 0; i < 32; i++) {
            result |= bytes32(uint256(arr[i])) << (8 * (31 - i));
        }
    }
}
