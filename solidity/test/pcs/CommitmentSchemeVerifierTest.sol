// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../../contracts/pcs/CommitmentSchemeVerifier.sol";
// import "../../contracts/pcs/PcsConfig.sol";
// import "../../contracts/core/CirclePoint.sol";
// import "../../contracts/fields/QM31Field.sol";
// import "../../contracts/channel/KeccakChannel.sol";

// /// @title CommitmentSchemeVerifierTest
// /// @notice TDD tests for CommitmentSchemeVerifier contract
// contract CommitmentSchemeVerifierTest is Test {
//     using PcsConfig for PcsConfig.Config;
//     using QM31Field for QM31Field.QM31;
//     using CirclePoint for CirclePoint.Point;

//     CommitmentSchemeVerifier verifier;
//     KeccakChannel channel;
//     PcsConfig.Config defaultConfig;

//     function setUp() public {
//         defaultConfig = PcsConfig.defaultConfig();
//         verifier = new CommitmentSchemeVerifier(defaultConfig);
//         channel = new KeccakChannel();
//     }

//     /// @notice Test verifier initialization and configuration
//     function testVerifierInitialization() public view {
//         // Test that verifier is properly initialized
//         PcsConfig.Config memory config = verifier.getConfig();

//         assertEq(
//             config.powBits,
//             defaultConfig.powBits,
//             "PoW bits should match"
//         );
//         assertEq(
//             config.friConfig.logBlowupFactor,
//             defaultConfig.friConfig.logBlowupFactor,
//             "Blowup factor should match"
//         );
//         assertEq(
//             config.friConfig.nQueries,
//             defaultConfig.friConfig.nQueries,
//             "Query count should match"
//         );

//         // Test initial state
//         assertEq(verifier.getTreeCount(), 0, "Should start with no trees");
//     }

//     /// @notice Test invalid configuration rejection
//     function testInvalidConfigurationRejection() public {
//         PcsConfig.Config memory invalidConfig = PcsConfig.Config({
//             powBits: 40, // Invalid - too high
//             friConfig: PcsConfig.defaultFriConfig()
//         });

//         vm.expectRevert("Invalid PCS configuration");
//         new CommitmentSchemeVerifier(invalidConfig);
//     }

//     /// @notice Test commitment addition
//     function testCommitmentAddition() public {
//         bytes32 commitment1 = keccak256("commitment1");
//         bytes32 commitment2 = keccak256("commitment2");

//         uint32[] memory logSizes1 = new uint32[](2);
//         logSizes1[0] = 10;
//         logSizes1[1] = 12;

//         uint32[] memory logSizes2 = new uint32[](1);
//         logSizes2[0] = 8;

//         // Add first commitment
//         verifier.commit(commitment1, logSizes1, IChannel(address(channel)));

//         assertEq(
//             verifier.getTreeCount(),
//             1,
//             "Should have 1 tree after first commit"
//         );
//         assertEq(
//             verifier.getTreeRoot(0),
//             commitment1,
//             "First tree root should match"
//         );

//         // Check extended log sizes (with blowup factor)
//         uint32[] memory retrievedSizes1 = verifier.getColumnLogSizes(0);
//         assertEq(retrievedSizes1.length, 2, "Should have 2 columns");
//         assertEq(retrievedSizes1[0], 11, "First column: 10 + 1 (blowup) = 11");
//         assertEq(retrievedSizes1[1], 13, "Second column: 12 + 1 (blowup) = 13");

//         // Add second commitment
//         verifier.commit(commitment2, logSizes2, IChannel(address(channel)));

//         assertEq(
//             verifier.getTreeCount(),
//             2,
//             "Should have 2 trees after second commit"
//         );
//         assertEq(
//             verifier.getTreeRoot(1),
//             commitment2,
//             "Second tree root should match"
//         );

//         uint32[] memory retrievedSizes2 = verifier.getColumnLogSizes(1);
//         assertEq(retrievedSizes2.length, 1, "Should have 1 column");
//         assertEq(retrievedSizes2[0], 9, "Column: 8 + 1 (blowup) = 9");
//     }

//     /// @notice Test commitment addition events
//     function testCommitmentEvents() public {
//         bytes32 commitment = keccak256("test_commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;

//         // Expect event emission
//         vm.expectEmit(true, true, false, false);
//         emit CommitmentAdded(0, commitment);

//         verifier.commit(commitment, logSizes, IChannel(address(channel)));
//     }

//     /// @notice Test out of bounds access
//     function testOutOfBoundsAccess() public {
//         // Try to access tree that doesn't exist
//         vm.expectRevert();
//         verifier.getTreeRoot(0);

//         vm.expectRevert();
//         verifier.getColumnLogSizes(0);

//         // Add one tree and try to access second
//         bytes32 commitment = keccak256("commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;

//         verifier.commit(commitment, logSizes, IChannel(address(channel)));

//         vm.expectRevert();
//         verifier.getTreeRoot(1);

//         vm.expectRevert();
//         verifier.getColumnLogSizes(1);
//     }

//     /// @notice Test proof structure validation
//     function testProofStructureValidation() public {
//         // Add one commitment tree
//         bytes32 commitment = keccak256("commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;
//         verifier.commit(commitment, logSizes, IChannel(address(channel)));

//         // Create invalid proof with wrong number of commitments
//         CommitmentSchemeVerifier.Proof
//             memory invalidProof = CommitmentSchemeVerifier.Proof({
//                 commitments: new bytes32[](0), // Wrong count - should be 1
//                 sampledValues: new QM31Field.QM31[](1),
//                 decommitments: new bytes[](1),
//                 queriedValues: new uint32[](10),
//                 proofOfWork: 12345,
//                 friProof: ""
//             });

//         CirclePoint.Point[] memory samplePoints = new CirclePoint.Point[](1);
//         samplePoints[0] = CirclePoint.zero();

//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 CommitmentSchemeVerifier.InvalidProofStructure.selector,
//                 "Commitment count mismatch"
//             )
//         );
//         verifier.verifyValues(
//             samplePoints,
//             invalidProof,
//             IChannel(address(channel))
//         );
//     }

//     /// @notice Test empty sampled values validation
//     function testEmptySampledValuesValidation() public {
//         bytes32 commitment = keccak256("commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;
//         verifier.commit(commitment, logSizes, IChannel(address(channel)));

//         CommitmentSchemeVerifier.Proof
//             memory invalidProof = CommitmentSchemeVerifier.Proof({
//                 commitments: new bytes32[](1),
//                 sampledValues: new QM31Field.QM31[](0), // Empty - invalid
//                 decommitments: new bytes[](1),
//                 queriedValues: new uint32[](10),
//                 proofOfWork: 12345,
//                 friProof: ""
//             });

//         CirclePoint.Point[] memory samplePoints = new CirclePoint.Point[](1);
//         samplePoints[0] = CirclePoint.zero();

//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 CommitmentSchemeVerifier.InvalidProofStructure.selector,
//                 "Empty sampled values"
//             )
//         );
//         verifier.verifyValues(
//             samplePoints,
//             invalidProof,
//             IChannel(address(channel))
//         );
//     }

//     /// @notice Test proof of work verification
//     function testProofOfWorkVerification() public {
//         bytes32 commitment = keccak256("commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;
//         verifier.commit(commitment, logSizes, IChannel(address(channel)));

//         // Create proof with valid structure but invalid PoW
//         CommitmentSchemeVerifier.Proof
//             memory proofWithInvalidPoW = CommitmentSchemeVerifier.Proof({
//                 commitments: new bytes32[](1),
//                 sampledValues: new QM31Field.QM31[](1),
//                 decommitments: new bytes[](1),
//                 queriedValues: new uint32[](10),
//                 proofOfWork: 0, // Invalid PoW - won't satisfy requirement
//                 friProof: "dummy"
//             });

//         CirclePoint.Point[] memory samplePoints = new CirclePoint.Point[](1);
//         samplePoints[0] = CirclePoint.zero();

//         // Should fail on PoW verification
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 CommitmentSchemeVerifier.ProofOfWorkFailed.selector,
//                 defaultConfig.powBits,
//                 uint64(0)
//             )
//         );
//         verifier.verifyValues(
//             samplePoints,
//             proofWithInvalidPoW,
//             IChannel(address(channel))
//         );
//     }

//     /// @notice Test multiple tree commitments
//     function testMultipleTreeCommitments() public {
//         bytes32[] memory commitments = new bytes32[](3);
//         commitments[0] = keccak256("tree1");
//         commitments[1] = keccak256("tree2");
//         commitments[2] = keccak256("tree3");

//         // Add commitments with different configurations
//         uint32[] memory logSizes1 = new uint32[](2);
//         logSizes1[0] = 8;
//         logSizes1[1] = 10;

//         uint32[] memory logSizes2 = new uint32[](1);
//         logSizes2[0] = 12;

//         uint32[] memory logSizes3 = new uint32[](3);
//         logSizes3[0] = 6;
//         logSizes3[1] = 7;
//         logSizes3[2] = 8;

//         verifier.commit(commitments[0], logSizes1, IChannel(address(channel)));
//         verifier.commit(commitments[1], logSizes2, IChannel(address(channel)));
//         verifier.commit(commitments[2], logSizes3, IChannel(address(channel)));

//         // Verify all trees are stored correctly
//         assertEq(verifier.getTreeCount(), 3, "Should have 3 trees");

//         for (uint256 i = 0; i < 3; i++) {
//             assertEq(
//                 verifier.getTreeRoot(i),
//                 commitments[i],
//                 "Tree root should match"
//             );
//         }

//         // Verify extended log sizes
//         uint32[] memory retrieved1 = verifier.getColumnLogSizes(0);
//         assertEq(retrieved1.length, 2, "Tree 1 should have 2 columns");
//         assertEq(retrieved1[0], 9, "Tree 1 column 0: 8 + 1 = 9");
//         assertEq(retrieved1[1], 11, "Tree 1 column 1: 10 + 1 = 11");

//         uint32[] memory retrieved2 = verifier.getColumnLogSizes(1);
//         assertEq(retrieved2.length, 1, "Tree 2 should have 1 column");
//         assertEq(retrieved2[0], 13, "Tree 2 column 0: 12 + 1 = 13");

//         uint32[] memory retrieved3 = verifier.getColumnLogSizes(2);
//         assertEq(retrieved3.length, 3, "Tree 3 should have 3 columns");
//         assertEq(retrieved3[0], 7, "Tree 3 column 0: 6 + 1 = 7");
//         assertEq(retrieved3[1], 8, "Tree 3 column 1: 7 + 1 = 8");
//         assertEq(retrieved3[2], 9, "Tree 3 column 2: 8 + 1 = 9");
//     }

//     /// @notice Test with different PCS configurations
//     function testDifferentConfigurations() public {
//         // Test with secure configuration
//         PcsConfig.Config memory secureConfig = PcsConfig.secureConfig();
//         CommitmentSchemeVerifier secureVerifier = new CommitmentSchemeVerifier(
//             secureConfig
//         );

//         PcsConfig.Config memory retrievedConfig = secureVerifier.getConfig();
//         assertEq(
//             retrievedConfig.powBits,
//             26,
//             "Secure config should have 26 PoW bits"
//         );

//         // Test with custom configuration
//         PcsConfig.Config memory customConfig = PcsConfig.Config({
//             powBits: 15,
//             friConfig: PcsConfig.FriConfig({
//                 logBlowupFactor: 2, // 4x blowup
//                 logLastLayerDegreeBound: 1,
//                 nQueries: 60
//             })
//         });

//         CommitmentSchemeVerifier customVerifier = new CommitmentSchemeVerifier(
//             customConfig
//         );

//         // Test commitment with higher blowup factor
//         bytes32 commitment = keccak256("custom_commitment");
//         uint32[] memory logSizes = new uint32[](2);
//         logSizes[0] = 8;
//         logSizes[1] = 10;

//         customVerifier.commit(commitment, logSizes, IChannel(address(channel)));

//         uint32[] memory extendedSizes = customVerifier.getColumnLogSizes(0);
//         assertEq(extendedSizes[0], 10, "With 2x blowup: 8 + 2 = 10");
//         assertEq(extendedSizes[1], 12, "With 2x blowup: 10 + 2 = 12");
//     }

//     /// @notice Test channel interaction and mixing
//     function testChannelInteraction() public {
//         // Initialize channel with known state
//         channel.updateDigest(keccak256("initial_state"));

//         bytes32 commitment = keccak256("test_commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;

//         // Commit should mix the commitment into channel
//         bytes32 digestBefore = channel.getDigest();
//         verifier.commit(commitment, logSizes, IChannel(address(channel)));
//         bytes32 digestAfter = channel.getDigest();

//         // Digest should change after commitment mixing
//         assertTrue(
//             digestBefore != digestAfter,
//             "Channel digest should change after commit"
//         );
//     }

//     /// @notice Test error handling in verification flow
//     function testVerificationErrorHandling() public {
//         bytes32 commitment = keccak256("commitment");
//         uint32[] memory logSizes = new uint32[](1);
//         logSizes[0] = 10;
//         verifier.commit(commitment, logSizes, IChannel(address(channel)));

//         // Test with malformed proof structure
//         CommitmentSchemeVerifier.Proof
//             memory malformedProof = CommitmentSchemeVerifier.Proof({
//                 commitments: new bytes32[](2), // Wrong count
//                 sampledValues: new QM31Field.QM31[](1),
//                 decommitments: new bytes[](1),
//                 queriedValues: new uint32[](10),
//                 proofOfWork: 12345,
//                 friProof: ""
//             });

//         CirclePoint.Point[] memory samplePoints = new CirclePoint.Point[](1);
//         samplePoints[0] = CirclePoint.zero();

//         // Should revert with InvalidProofStructure error
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 CommitmentSchemeVerifier.InvalidProofStructure.selector,
//                 "Commitment count mismatch"
//             )
//         );
//         verifier.verifyValues(
//             samplePoints,
//             malformedProof,
//             IChannel(address(channel))
//         );
//     }

//     /// @notice Test real-world commitment scenario
//     function testRealWorldScenario() public {
//         // Simulate polynomial commitment scheme with multiple trees
//         // representing trace, permutation, and composition polynomials

//         bytes32 traceCommitment = keccak256("trace_polynomial_root");
//         bytes32 permutationCommitment = keccak256(
//             "permutation_polynomial_root"
//         );
//         bytes32 compositionCommitment = keccak256(
//             "composition_polynomial_root"
//         );

//         // Trace: 2^16 elements in 4 columns
//         uint32[] memory traceSizes = new uint32[](4);
//         traceSizes[0] = 16;
//         traceSizes[1] = 16;
//         traceSizes[2] = 16;
//         traceSizes[3] = 16;

//         // Permutation: 2^14 elements in 2 columns
//         uint32[] memory permutationSizes = new uint32[](2);
//         permutationSizes[0] = 14;
//         permutationSizes[1] = 14;

//         // Composition: 2^18 elements in 1 column
//         uint32[] memory compositionSizes = new uint32[](1);
//         compositionSizes[0] = 18;

//         // Commit all trees
//         verifier.commit(
//             traceCommitment,
//             traceSizes,
//             IChannel(address(channel))
//         );
//         verifier.commit(
//             permutationCommitment,
//             permutationSizes,
//             IChannel(address(channel))
//         );
//         verifier.commit(
//             compositionCommitment,
//             compositionSizes,
//             IChannel(address(channel))
//         );

//         // Verify setup
//         assertEq(
//             verifier.getTreeCount(),
//             3,
//             "Should have 3 polynomial commitment trees"
//         );

//         // Check extended sizes with blowup factor
//         uint32[] memory extendedTrace = verifier.getColumnLogSizes(0);
//         uint32[] memory extendedPermutation = verifier.getColumnLogSizes(1);
//         uint32[] memory extendedComposition = verifier.getColumnLogSizes(2);

//         // All should be extended by blowup factor (default = 1)
//         for (uint256 i = 0; i < extendedTrace.length; i++) {
//             assertEq(extendedTrace[i], 17, "Trace columns: 16 + 1 = 17");
//         }

//         for (uint256 i = 0; i < extendedPermutation.length; i++) {
//             assertEq(
//                 extendedPermutation[i],
//                 15,
//                 "Permutation columns: 14 + 1 = 15"
//             );
//         }

//         assertEq(extendedComposition[0], 19, "Composition column: 18 + 1 = 19");
//     }

//     /// @notice Test commitment with specific Rust data and configuration
//     function testRustSpecificCommitment() public {
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

//         CommitmentSchemeVerifier rustVerifier = new CommitmentSchemeVerifier(
//             rustConfig
//         );
//         KeccakChannel rustChannel = new KeccakChannel();

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
//             rustChannel.getDigest(),
//             expectedInitialDigest,
//             "Initial channel digest should be zero"
//         );

//         // Perform commitment
//         rustVerifier.commit(
//             commitment,
//             trace0LogSizes,
//             IChannel(address(rustChannel))
//         );

//         // Verify channel state after commitment matches Rust implementation
//         bytes32 actualAfterCommitDigest = rustChannel.getDigest();
//         assertEq(
//             actualAfterCommitDigest,
//             expectedAfterCommitDigest,
//             "Channel digest after commitment should match Rust implementation"
//         );

//         // Verify verifier state
//         assertEq(
//             rustVerifier.getTreeCount(),
//             1,
//             "Should have 1 tree after commitment"
//         );
//         assertEq(
//             rustVerifier.getTreeRoot(0),
//             commitment,
//             "Tree root should match commitment"
//         );

//         // Verify extended log sizes (should be original + blowup factor of 4)
//         uint32[] memory extendedLogSizes = rustVerifier.getColumnLogSizes(0);
//         assertEq(extendedLogSizes.length, 4, "Should have 4 columns");

//         // With blowup factor of 4, each log size should be incremented by 4
//         for (uint256 i = 0; i < 4; i++) {
//             assertEq(
//                 extendedLogSizes[i],
//                 12,
//                 "Extended log size should be 8 + 4 = 12"
//             );
//         }



//         uint32[] memory traceLogSizesLast = new uint32[](4);
//         traceLogSizesLast[0] = 9;
//         traceLogSizesLast[1] = 9;
//         traceLogSizesLast[2] = 9;
//         traceLogSizesLast[3] = 9;

//         bytes32 expectedAfterCommitDigest2 = 0xf245fe4637c11bc8514b7d25b7630b79bfdfe835bdece5afd03af21803aa11b3;

//         bytes32 commitmentLast = 0xa00622a26198aed3782e389b01a0579eae15dfd3313b89767a14e6a5aa714bbe;

//         // Perform commitment
//         rustVerifier.commit(
//             commitmentLast,
//             traceLogSizesLast,
//             IChannel(address(rustChannel))
//         );

//         assertEq(
//             rustChannel.getDigest(),
//             expectedAfterCommitDigest2,
//             "Channel digest after second commitment should match Rust implementation"
//         );

//         // QM31Field.QM31 memory t = rustChannel.drawSecureFelt();
//         // console.log("Drawn t from channel:");
//         // console.log("  t.first.real:", t.first.real);
//         // console.log("  t.first.imag:", t.first.imag);
//         // console.log("  t.second.real:", t.second.real);
//         // console.log("  t.second.imag:", t.second.imag);

//         // QM31Field.QM31 memory tSquare = QM31Field.square(t);
//         // console.log("Computed t^2:");
//         // console.log("  tSquare.first.real:", tSquare.first.real);
//         // console.log("  tSquare.first.imag:", tSquare.first.imag);
//         // console.log("  tSquare.second.real:", tSquare.second.real);
//         // console.log("  tSquare.second.imag:", tSquare.second.imag);
//         // QM31Field.QM31 memory added = QM31Field.add(tSquare, QM31Field.one());
//         // console.log("Computed (t^2 + 1):");
//         // console.log("  added.first.real:", added.first.real);
//         // console.log("  added.first.imag:", added.first.imag);
//         // console.log("  added.second.real:", added.second.real);
//         // console.log("  added.second.imag:", added.second.imag);

//         // QM31Field.QM31 memory onePlusTSquaredInv = QM31Field.inverse(QM31Field.add(tSquare, QM31Field.one()));
//         // console.log("Computed (1 + t^2)^-1:");
//         // console.log("  onePlusTSquaredInv.first.real:", onePlusTSquaredInv.first.real);
//         // console.log("  onePlusTSquaredInv.first.imag:", onePlusTSquaredInv.first.imag);
//         // console.log("  onePlusTSquaredInv.second.real:", onePlusTSquaredInv.second.real);
//         // console.log("  onePlusTSquaredInv.second.imag:", onePlusTSquaredInv.second.imag);

//         //         // x = (1 - t²) / (1 + t²)
//         // QM31Field.QM31 memory x = QM31Field.mul(QM31Field.sub(QM31Field.one(), tSquare), onePlusTSquaredInv);

//         // console.log("Computed x coordinate:");
//         // console.log("  x.first.real:", x.first.real);
//         // console.log("  x.first.imag:", x.first.imag);
//         // console.log("  x.second.real:", x.second.real);
//         // console.log("  x.second.imag:", x.second.imag);
        
//         // // y = 2t / (1 + t²)  
//         // QM31Field.QM31 memory y = QM31Field.mul(QM31Field.add(t, t), onePlusTSquaredInv);
//         // console.log("Computed y coordinate:");
//         // console.log("  y.first.real:", y.first.real);
//         // console.log("  y.first.imag:", y.first.imag);
//         // console.log("  y.second.real:", y.second.real);
//         // console.log("  y.second.imag:", y.second.imag);



//         CirclePoint.Point memory oodsPoint = CirclePoint.getRandomPoint(
//             IChannel(address(rustChannel))
//         );
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

//     /// @notice Events for testing
//     event CommitmentAdded(uint256 indexed treeIndex, bytes32 indexed root);
//     event VerificationStarted(bytes32 indexed proofHash);
//     event VerificationCompleted(bool indexed success);
// }
