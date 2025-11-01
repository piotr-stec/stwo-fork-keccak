// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../../contracts/pcs/PcsConfig.sol";
// import "../../contracts/core/CirclePoint.sol";
// import "../../contracts/fields/QM31Field.sol";
// import "../../contracts/libraries/CommitmentSchemeVerifierLib.sol";
// import "../../contracts/libraries/KeccakChannelLib.sol";

// /// @title CommitmentSchemeVerifierLibTestState
// /// @notice Tests for library-based CommitmentSchemeVerifier using direct libraries with storage
// contract CommitmentSchemeVerifierLibTestState is Test {
//     using CommitmentSchemeVerifierLib for CommitmentSchemeVerifierLib.VerifierState;
//     using KeccakChannelLib for KeccakChannelLib.ChannelState;
//     using QM31Field for QM31Field.QM31;
//     using CirclePoint for CirclePoint.Point;

//     // Storage variables for the test contract
//     CommitmentSchemeVerifierLib.VerifierState rustVerifierState;
//     KeccakChannelLib.ChannelState rustChannelState;

//     /// @notice Test commitment with specific Rust data and configuration using libraries
//     function testRustSpecificCommitmentLib() public {
//         // Rust config: PcsConfig { pow_bits: 10, fri_config: FriConfig::new(5, 4, 64) }
//         // FriConfig::new(log_last_layer_degree_bound, log_blowup_factor, n_queries)
//         PcsConfig.Config memory rustConfig = PcsConfig.Config({
//             powBits: 10,
//             friConfig: PcsConfig.FriConfig({
//                 logBlowupFactor: 4, // Second parameter: log_blowup_factor = 4 (16x blowup)
//                 logLastLayerDegreeBound: 5, // First parameter: log_last_layer_degree_bound = 5
//                 nQueries: 64 // Third parameter: n_queries = 64
//             })
//         });

//         // Initialize using library functions
//         rustVerifierState.initialize(rustConfig);
//         rustChannelState.initialize();

//         // Test data from Rust implementation
//         bytes32 commitment = 0x7f3fb23a36bd8b85697aadc79cd031fab8fe3b65a557d923e8fd5d1879d02e13;

//         // Trace 0: [8, 8, 8, 8]
//         uint32[] memory trace0LogSizes = new uint32[](4);
//         trace0LogSizes[0] = 8;
//         trace0LogSizes[1] = 8;
//         trace0LogSizes[2] = 8;
//         trace0LogSizes[3] = 8;

//         // Expected channel states from Rust
//         bytes32 expectedInitialDigest = bytes32(0);
//         bytes32 expectedAfterCommitDigest = 0x7b8cb803bdb2e8fc5e286da7e482d259702b4669015513390b4aa0d184d3a6c7;

//         // Verify initial channel state
//         assertEq(
//             rustChannelState.digest,
//             expectedInitialDigest,
//             "Initial channel digest should be zero"
//         );

//         // Perform commitment using library function
//         rustVerifierState.commit(
//             commitment,
//             trace0LogSizes,
//             rustChannelState
//         );

//         // Verify channel state after commitment matches Rust implementation
//         bytes32 actualAfterCommitDigest = rustChannelState.digest;
//         assertEq(
//             actualAfterCommitDigest,
//             expectedAfterCommitDigest,
//             "Channel digest after commitment should match Rust implementation"
//         );

//         // Verify verifier state using library functions
//         assertEq(
//             rustVerifierState.getTreeCount(),
//             1,
//             "Should have 1 tree after commitment"
//         );
//         assertEq(
//             rustVerifierState.getTreeRoot(0),
//             commitment,
//             "Tree root should match commitment"
//         );

//         // Verify extended log sizes (should be original + blowup factor of 4)
//         uint32[] memory extendedLogSizes = rustVerifierState.getColumnLogSizes(0);
//         assertEq(extendedLogSizes.length, 4, "Should have 4 columns");

//         // With blowup factor of 4, each log size should be incremented by 4
//         for (uint256 i = 0; i < 4; i++) {
//             assertEq(
//                 extendedLogSizes[i],
//                 12,
//                 "Extended log size should be 8 + 4 = 12"
//             );
//         }

//         // Second commitment
//         uint32[] memory traceLogSizesLast = new uint32[](4);
//         traceLogSizesLast[0] = 9;
//         traceLogSizesLast[1] = 9;
//         traceLogSizesLast[2] = 9;
//         traceLogSizesLast[3] = 9;

//         bytes32 expectedAfterCommitDigest2 = 0xf245fe4637c11bc8514b7d25b7630b79bfdfe835bdece5afd03af21803aa11b3;
//         bytes32 commitmentLast = 0xa00622a26198aed3782e389b01a0579eae15dfd3313b89767a14e6a5aa714bbe;

//         // Perform second commitment using library function
//         rustVerifierState.commit(
//             commitmentLast,
//             traceLogSizesLast,
//             rustChannelState
//         );

//         assertEq(
//             rustChannelState.digest,
//             expectedAfterCommitDigest2,
//             "Channel digest after second commitment should match Rust implementation"
//         );

//         // Test drawing from channel using library functions directly
//         QM31Field.QM31 memory t = rustChannelState.drawSecureFelt();
//         console.log("Drawn t from channel:");
//         console.log("  t.first.real:", t.first.real);
//         console.log("  t.first.imag:", t.first.imag);
//         console.log("  t.second.real:", t.second.real);
//         console.log("  t.second.imag:", t.second.imag);

//         QM31Field.QM31 memory tSquare = QM31Field.square(t);
//         console.log("Computed t^2:");
//         console.log("  tSquare.first.real:", tSquare.first.real);
//         console.log("  tSquare.first.imag:", tSquare.first.imag);
//         console.log("  tSquare.second.real:", tSquare.second.real);
//         console.log("  tSquare.second.imag:", tSquare.second.imag);
        
//         QM31Field.QM31 memory added = QM31Field.add(tSquare, QM31Field.one());
//         console.log("Computed (t^2 + 1):");
//         console.log("  added.first.real:", added.first.real);
//         console.log("  added.first.imag:", added.first.imag);
//         console.log("  added.second.real:", added.second.real);
//         console.log("  added.second.imag:", added.second.imag);

//         QM31Field.QM31 memory onePlusTSquaredInv = QM31Field.inverse(QM31Field.add(tSquare, QM31Field.one()));
//         console.log("Computed (1 + t^2)^-1:");
//         console.log("  onePlusTSquaredInv.first.real:", onePlusTSquaredInv.first.real);
//         console.log("  onePlusTSquaredInv.first.imag:", onePlusTSquaredInv.first.imag);
//         console.log("  onePlusTSquaredInv.second.real:", onePlusTSquaredInv.second.real);
//         console.log("  onePlusTSquaredInv.second.imag:", onePlusTSquaredInv.second.imag);

//         // x = (1 - t²) / (1 + t²)
//         QM31Field.QM31 memory x = QM31Field.mul(QM31Field.sub(QM31Field.one(), tSquare), onePlusTSquaredInv);
//         console.log("Computed x coordinate:");
//         console.log("  x.first.real:", x.first.real);
//         console.log("  x.first.imag:", x.first.imag);
//         console.log("  x.second.real:", x.second.real);
//         console.log("  x.second.imag:", x.second.imag);
        
//         // y = 2t / (1 + t²)  
//         QM31Field.QM31 memory y = QM31Field.mul(QM31Field.add(t, t), onePlusTSquaredInv);
//         console.log("Computed y coordinate:");
//         console.log("  y.first.real:", y.first.real);
//         console.log("  y.first.imag:", y.first.imag);
//         console.log("  y.second.real:", y.second.real);
//         console.log("  y.second.imag:", y.second.imag);

//         // Generate OODS point using library function directly on channel state
//         CirclePoint.Point memory oodsPoint = CirclePoint.getRandomPointFromState(rustChannelState);
//         console.log("Generated OODS point:");
//         console.log("  x.first.real:", oodsPoint.x.first.real);
//         console.log("  x.first.imag:", oodsPoint.x.first.imag);
//         console.log("  x.second.real:", oodsPoint.x.second.real);
//         console.log("  x.second.imag:", oodsPoint.x.second.imag);
//         console.log("  y.first.real:", oodsPoint.y.first.real);
//         console.log("  y.first.imag:", oodsPoint.y.first.imag);
//         console.log("  y.second.real:", oodsPoint.y.second.real);
//         console.log("  y.second.imag:", oodsPoint.y.second.imag);
//     }

//     /// @notice Test gas efficiency of library approach
//     function testGasEfficiencyLibrary() public {
//         PcsConfig.Config memory config = PcsConfig.defaultConfig();
        
//         // Test library approach
//         uint256 gasBefore = gasleft();
        
//         CommitmentSchemeVerifierLib.VerifierState storage verifierState = rustVerifierState;
//         KeccakChannelLib.ChannelState storage channelState = rustChannelState;
        
//         verifierState.initialize(config);
//         channelState.initialize();
        
//         bytes32 commitment = keccak256("test_commitment");
//         uint32[] memory logSizes = new uint32[](4);
//         logSizes[0] = 8;
//         logSizes[1] = 8;
//         logSizes[2] = 8;
//         logSizes[3] = 8;
        
//         verifierState.commit(commitment, logSizes, channelState);
        
//         uint256 libraryGasUsed = gasBefore - gasleft();
//         console.log("Library approach gas used:", libraryGasUsed);
        
//         // Verify functionality
//         assertEq(verifierState.getTreeCount(), 1, "Should have 1 tree");
//         assertEq(verifierState.getTreeRoot(0), commitment, "Root should match");
        
//         uint32[] memory extendedSizes = verifierState.getColumnLogSizes(0);
//         assertEq(extendedSizes.length, 4, "Should have 4 columns");
//         for (uint256 i = 0; i < 4; i++) {
//             assertEq(extendedSizes[i], 9, "Extended size should be 8 + 1 = 9");
//         }
        
//         // Test channel functionality
//         QM31Field.QM31 memory randomFelt = channelState.drawSecureFelt();
//         assertTrue(randomFelt.first.real != 0 || randomFelt.first.imag != 0, "Should generate non-zero random felt");
        
//         console.log("Library test completed successfully with", libraryGasUsed, "gas");
//     }

//     /// @notice Test direct channel state manipulation
//     function testChannelStateManipulation() public {
//         KeccakChannelLib.ChannelState storage channelState = rustChannelState;
//         channelState.initialize();
        
//         // Test initial state
//         assertEq(channelState.digest, bytes32(0), "Initial digest should be zero");
//         assertEq(channelState.nDraws, 0, "Initial draws should be zero");
        
//         // Test mixing
//         uint32[] memory data = new uint32[](4);
//         data[0] = 0x12345678;
//         data[1] = 0x9abcdef0;
//         data[2] = 0x11111111;
//         data[3] = 0x22222222;
        
//         channelState.mixU32s(data);
//         assertTrue(channelState.digest != bytes32(0), "Digest should change after mixing");
        
//         // Test drawing
//         uint32[] memory randomU32s = channelState.drawU32s();
//         assertEq(randomU32s.length, 8, "Should return 8 u32 values");
//         assertEq(channelState.nDraws, 1, "Draw count should increment");
        
//         // Test secure felt drawing
//         QM31Field.QM31 memory felt = channelState.drawSecureFelt();
//         assertTrue(felt.first.real < 2147483647, "Should be valid M31 element"); // 2^31 - 1
        
//         // Test state clearing
//         channelState.clearState();
//         assertEq(channelState.digest, bytes32(0), "Digest should be cleared");
//         assertEq(channelState.nDraws, 0, "Draws should be cleared");
//     }
// }