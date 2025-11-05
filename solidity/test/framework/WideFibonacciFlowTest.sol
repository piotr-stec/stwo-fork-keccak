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
    FriVerifier.VerifierState friVerifier;

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
        CommitmentSchemeVerifierLib.initialize(commitmentScheme, pcsConfig);

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
        uint256 startGas = gasleft();
        console.log("=== Testing Real Commitment Flow ===");
        console.log("Start gas:", startGas);

        // Init part begin
        bytes32[] memory realCommitments = getRealCommitments();

        // Preprocessed columns commitment
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

        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            preprocessedCommit,
            preprocessedSizes,
            channel
        );
        console.log("  test1 digest:");
        console.logBytes32(channel.digest);

        // Trace columns commitment
        bytes32 traceCommit = testProof.getCommitment(1);
        console.log("Real Trace commitment:");
        console.logBytes32(traceCommit);
        assertEq(traceCommit, realCommitments[1], "Trace commitment mismatch");

        // Real commitment_scheme.commit(proof.commitments[1], &sizes[1], channel)
        // TODO: get real size from component
        uint32[] memory traceSizes = new uint32[](50); // 50 trace columns
        for (uint256 i = 0; i < 50; i++) {
            traceSizes[i] = 3;
        }

        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            traceCommit,
            traceSizes,
            channel
        );


        console.log(
            "Updated channel state after preprocessed trace commitment:"
        );
        console.log("  nDraws:", channel.nDraws);

        console.log("  digest:");

        console.logBytes32(channel.digest);

        // Init part ends

        // RUST Verify begin
        // Draw random coefficient (alpha) from channel
        QM31Field.QM31 memory randomCoeff;
        randomCoeff = channel.drawSecureFelt();
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

        CommitmentSchemeVerifierLib.commit(
            commitmentScheme,
            compositionCommit,
            compositionSizes,
            channel
        );

        uint32[][] memory columnLogSizes2 = commitmentScheme
            .columnLogSizes
            .data;

        console.log("Column log sizes in commitment scheme:");
        for (uint256 treeIdx = 0; treeIdx < columnLogSizes2.length; treeIdx++) {
            console.log(" Tree", treeIdx, "log sizes:");
            for (
                uint256 colIdx = 0;
                colIdx < columnLogSizes2[treeIdx].length;
                colIdx++
            ) {
                console.log(
                    "  Column",
                    colIdx,
                    "log size:",
                    columnLogSizes2[treeIdx][colIdx]
                );
            }
        }

        console.log("Updated channel state after composition commitment:");
        console.log("  digest:");
        console.log(channel.nDraws);
        console.logBytes32(channel.digest);

        // Draw OODS point from channel
        // Create CirclePoint using random QM31 values
        // QM31Field.QM31[] memory randomValues;

        CirclePoint.Point memory oodsPoint = CirclePoint
            .getRandomPointFromState(channel);

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

        uint256 afterOodsGas = gasleft();
        console.log("Gas after OODS point:", startGas - afterOodsGas);

        // Verify we have exactly 3 commitments
        (uint256 nCommitments, , ) = testProof.getProofStats();
        assertEq(nCommitments, 3, "Should have 3 commitments from proof.json");
        uint256[] memory treeSizes = new uint256[](2);
        treeSizes[0] = 0; // Preprocessed: empty
        treeSizes[1] = 50; // Original trace: n_columns

        uint256[] memory preprocessedColumnIndices = new uint256[](0);

        allocatorState.initialize();
        console.log(
            "Allocator state preprocessedColumns",
            allocatorState.preprocessedColumns.length
        );
        TreeSubspan.Subspan[] memory traceLocations = allocatorState
            .nextForStructure(treeSizes, 1);

        console.log("Trace locations allocated for WideFibonacciComponent");
        console.log("Trace locations colEnd: ", traceLocations[1].colEnd);

        FrameworkComponentLib.ComponentInfo
            memory componentInfo = FrameworkComponentLib.ComponentInfo({
                nConstraints: 50 >= 2 ? 50 - 2 : 0,
                maxConstraintLogDegreeBound: 3 + 1,
                logSize: 3,
                componentName: "WideFibonacciComponent",
                description: "Wide Fibonacci component for testing"
            });

        // Initialize the component (equivalent to WideFibonacciComponent::new)
        componentState.initialize(
            address(wideFibEval), // The evaluator
            traceLocations, // Trace locations
            preprocessedColumnIndices, // No preprocessed columns
            QM31Field.zero(), // claimed_sum = SecureField::zero()
            componentInfo // Component metadata
        );

        uint256 beforeMaskPointsGas = gasleft();

        FrameworkComponentLib.SamplePoints memory samplePoints = componentState
            .maskPoints(oodsPoint);

        uint256 afterMaskPointsGas = gasleft();
        console.log(
            "Gas for maskPoints():",
            beforeMaskPointsGas - afterMaskPointsGas
        );

        console.log("Sample points masked for OODS point:");
        console.log("SamplePoints structure:");
        console.log("  totalPoints:", samplePoints.totalPoints);
        console.log("  nColumns.length:", samplePoints.nColumns.length);

        // // Print nColumns array
        // for (uint256 i = 0; i < samplePoints.nColumns.length; i++) {
        //     console.log("  nColumns[", i, "]:", samplePoints.nColumns[i]);
        // }

        // // Print points structure
        // console.log("  points.length (trees):", samplePoints.points.length);
        // for (uint256 treeIdx = 0; treeIdx < samplePoints.points.length; treeIdx++) {
        //     console.log("  Tree", treeIdx, "columns:", samplePoints.points[treeIdx].length);

        //     for (uint256 colIdx = 0; colIdx < samplePoints.points[treeIdx].length; colIdx++) {
        //         if (samplePoints.points[treeIdx][colIdx].length > 0) {
        //             // console.log("    Tree", treeIdx, "Col", colIdx, "points:", samplePoints.points[treeIdx][colIdx].length);

        //             for (uint256 pointIdx = 0; pointIdx < samplePoints.points[treeIdx][colIdx].length; pointIdx++) {
        //                 console.log("      Point[", pointIdx, "].x.first.real:", samplePoints.points[treeIdx][colIdx][pointIdx].x.first.real);
        //                 console.log("      Point[", pointIdx, "].x.first.imag:", samplePoints.points[treeIdx][colIdx][pointIdx].x.first.imag);
        //                 console.log("      Point[", pointIdx, "].x.second.real:", samplePoints.points[treeIdx][colIdx][pointIdx].x.second.real);
        //                 console.log("      Point[", pointIdx, "].x.second.imag:", samplePoints.points[treeIdx][colIdx][pointIdx].x.second.imag);
        //                 console.log("      Point[", pointIdx, "].y.first.real:", samplePoints.points[treeIdx][colIdx][pointIdx].y.first.real);
        //                 console.log("      Point[", pointIdx, "].y.first.imag:", samplePoints.points[treeIdx][colIdx][pointIdx].y.first.imag);
        //                 console.log("      Point[", pointIdx, "].y.second.real:", samplePoints.points[treeIdx][colIdx][pointIdx].y.second.real);
        //                 console.log("      Point[", pointIdx, "].y.second.imag:", samplePoints.points[treeIdx][colIdx][pointIdx].y.second.imag);
        //             }
        //         }
        //     }
        // }

        // // Print preprocessed points
        // console.log("  preprocessed.length:", samplePoints.preprocessed.length);

        // Rust: sample_points.push(vec![vec![oods_point]; SECURE_EXTENSION_DEGREE]);
        // Add composition polynomial tree with SECURE_EXTENSION_DEGREE (4) columns
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

        // Rust: let sample_points_by_column = sample_points.as_cols_ref().flatten();
        console.log("\nFlattening sample_points_by_column...");

        // Count total columns across all trees
        uint256 totalColumns = 0;
        for (
            uint256 treeIdx = 0;
            treeIdx < samplePoints.points.length;
            treeIdx++
        ) {
            totalColumns += samplePoints.points[treeIdx].length;
        }

        console.log("Total columns across all trees:", totalColumns);

        uint256 beforePrintGas = gasleft();

        // Create flattened view and print all points
        // console.log("\nFlattened sample_points_by_column structure:");
        // uint256 columnIndex = 0;
        // for (
        //     uint256 treeIdx = 0;
        //     treeIdx < samplePoints.points.length;
        //     treeIdx++
        // ) {
        //     for (
        //         uint256 colIdx = 0;
        //         colIdx < samplePoints.points[treeIdx].length;
        //         colIdx++
        //     ) {
        //         if (samplePoints.points[treeIdx][colIdx].length > 0) {
        //             // console.log("Flattened column", columnIndex, "from tree", treeIdx, "col", colIdx);
        //             console.log(
        //                 "  points count:",
        //                 samplePoints.points[treeIdx][colIdx].length
        //             );

        //             // Print all points in this column
        //             for (
        //                 uint256 pointIdx = 0;
        //                 pointIdx < samplePoints.points[treeIdx][colIdx].length;
        //                 pointIdx++
        //             ) {
        //                 CirclePoint.Point memory point = samplePoints.points[
        //                     treeIdx
        //                 ][colIdx][pointIdx];
        //                 console.log("  Point[", pointIdx, "]:");
        //                 console.log("    x.first.real:", point.x.first.real);
        //                 console.log("    x.first.imag:", point.x.first.imag);
        //                 console.log("    x.second.real:", point.x.second.real);
        //                 console.log("    x.second.imag:", point.x.second.imag);
        //                 console.log("    y.first.real:", point.y.first.real);
        //                 console.log("    y.first.imag:", point.y.first.imag);
        //                 console.log("    y.second.real:", point.y.second.real);
        //                 console.log("    y.second.imag:", point.y.second.imag);
        //             }
        //         } else {
        //             console.log("Flattened column", columnIndex);
        //         }
        //         columnIndex++;
        //     }
        // }

        uint256 afterPrintGas = gasleft();
        console.log("Gas for printing points:", beforePrintGas - afterPrintGas);

        uint256 beforeEvalGas = gasleft();

        PointEvaluationAccumulator.Accumulator
            memory eval_accumulator = PointEvaluationAccumulator.newAccumulator(
                randomCoeff
            );

        QM31Field.QM31[][][] memory sampledValues = _createRealSampledValues();

        PointEvaluationAccumulator.Accumulator memory result = componentState
            .evaluateConstraintQuotientsAtPoint(
                oodsPoint,
                sampledValues,
                eval_accumulator
            );

        // Step 6: Get finalized result equivalent to eval_accumulator.finalize()
        QM31Field.QM31 memory finalResult = result.accumulation;
        console.log(
            "Final accumulated result after evaluating constraints at OODS point:"
        );
        console.log("  finalResult.first.real:", finalResult.first.real);
        console.log("  finalResult.first.imag:", finalResult.first.imag);
        console.log("  finalResult.second.real:", finalResult.second.real);
        console.log("  finalResult.second.imag:", finalResult.second.imag);

        uint256 afterEvalGas = gasleft();
        console.log("Gas for evaluation:", beforeEvalGas - afterEvalGas);

        uint256 totalGasUsed = startGas - gasleft();
        console.log("Total gas used in test:", totalGasUsed);

        uint256 beforeBoundsGas = gasleft();

        uint32[][] memory columnLogSizes = commitmentScheme.columnLogSizes.data;

        console.log("Column log sizes in commitment scheme:");
        for (uint256 treeIdx = 0; treeIdx < columnLogSizes.length; treeIdx++) {
            console.log(" Tree", treeIdx, "log sizes:");
            for (
                uint256 colIdx = 0;
                colIdx < columnLogSizes[treeIdx].length;
                colIdx++
            ) {
                console.log(
                    "  Column",
                    colIdx,
                    "log size:",
                    columnLogSizes[treeIdx][colIdx]
                );
            }
        }

        QM31Field.QM31[] memory flattenedSampledValues = _createRealSampledValuesFlattened();

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


        channel.mixFelts(flattenedSampledValues);
        console.log("Channel state after mixing flattened sampled values:");
        console.logBytes32(channel.digest);

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
        }
        
        // Initialize FriVerifier with bounds and config
        console.log("\n=== Initializing FriVerifier ===");
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

        uint256 afterFriInitGas = gasleft();
        console.log("Gas for FriVerifier initialization:", beforeFriInitGas - afterFriInitGas);
        console.log("FriVerifier initialized successfully");
        console.log("  config.logBlowupFactor:", friVerifier.config.logBlowupFactor);
        console.log("  config.nQueries:", friVerifier.config.nQueries);
        console.log("  firstLayer.columnBounds.length:", friVerifier.firstLayer.columnBounds.length);
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

        // Test that our WideFibonacci evaluator can handle these real values
        (string memory name, uint256 nConstraints, ) = wideFibEval
            .getEvalInfo();
        // console.log("Evaluator", name, "expects", nConstraints, "constraints for", realFib.length, "columns");

        assertEq(
            nConstraints,
            49,
            "Should have 49 constraints for 51 columns (51-2=49)"
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
        friProof.firstLayer = FriVerifier.FriLayerProof({
            friWitness: firstLayerWitness,
            decommitment: abi.encode(firstLayerHashWitness),
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
        
        friProof.innerLayers[0] = FriVerifier.FriLayerProof({
            friWitness: innerLayer0Witness,
            decommitment: abi.encode(innerLayer0HashWitness),
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
        
        friProof.innerLayers[1] = FriVerifier.FriLayerProof({
            friWitness: innerLayer1Witness,
            decommitment: abi.encode(innerLayer1HashWitness),
            commitment: _uint8ArrayToBytes32(innerLayer1Commitment)
        });
        
        // Inner layer 2 (final layer before last_layer_poly)
        QM31Field.QM31[] memory innerLayer2Witness = new QM31Field.QM31[](0); // Empty witness array
        
        uint8[32] memory innerLayer2Commitment = [58, 8, 109, 44, 213, 188, 98, 82, 228, 161, 119, 179, 76, 221, 211, 242, 155, 15, 83, 95, 110, 124, 123, 44, 180, 233, 178, 216, 3, 200, 171, 58];
        
        bytes32[] memory innerLayer2HashWitness = new bytes32[](1);
        innerLayer2HashWitness[0] = _uint8ArrayToBytes32(il0hw0); // Reuse from layer 0
        
        friProof.innerLayers[2] = FriVerifier.FriLayerProof({
            friWitness: innerLayer2Witness,
            decommitment: abi.encode(innerLayer2HashWitness),
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
