// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../../contracts/core/OodsVerifier.sol";
// import "../../contracts/core/MaskPointsGenerator.sol";
// import "../../contracts/core/CompositionEvaluator.sol";
// import "../../contracts/core/ProofParser.sol";
// import "../../contracts/core/CirclePoint.sol";
// import "../../contracts/fields/QM31Field.sol";
// import "../../contracts/fields/CM31Field.sol";
// import "../../contracts/libraries/KeccakChannelLib.sol";

// /// @title OodsVerifierTest
// /// @notice TDD tests for OodsVerifier contract (Integration tests)
// contract OodsVerifierTest is Test {
//     using QM31Field for QM31Field.QM31;
//     using CirclePoint for CirclePoint.Point;
//     using KeccakChannelLib for KeccakChannelLib.ChannelState;

//     OodsVerifier oodsVerifier;
//     MaskPointsGenerator maskGenerator;
//     CompositionEvaluator compositionEvaluator;
//     ProofParser proofParser;
//     KeccakChannelLib.ChannelState channelState;
    
//     CirclePoint.Point oodsPoint;
//     QM31Field.QM31 randomCoeff;

//     function setUp() public {
//         // Deploy component contracts
//         maskGenerator = new MaskPointsGenerator();
//         compositionEvaluator = new CompositionEvaluator();
//         proofParser = new ProofParser();
        
//         // Deploy OODS verifier with component references
//         oodsVerifier = new OodsVerifier(
//             address(maskGenerator),
//             address(compositionEvaluator),
//             address(proofParser)
//         );

//         // Set up test OODS point
//         oodsPoint = CirclePoint.Point({
//             x: QM31Field.QM31({
//                 first: CM31Field.CM31({real: 1000000000, imag: 2000000000}),
//                 second: CM31Field.CM31({real: 3000000000, imag: 400000000})
//             }),
//             y: QM31Field.QM31({
//                 first: CM31Field.CM31({real: 500000000, imag: 600000000}),
//                 second: CM31Field.CM31({real: 700000000, imag: 800000000})
//             })
//         });

//         // Set up test random coefficient
//         randomCoeff = QM31Field.QM31({
//             first: CM31Field.CM31({real: 12345, imag: 67890}),
//             second: CM31Field.CM31({real: 11111, imag: 22222})
//         });

//         // Configure components for testing
//         _setupTestComponents();
//     }

//     /// @notice Set up test components with basic configurations
//     function _setupTestComponents() internal {
//         // Add a basic component to mask generator
//         MaskPointsGenerator.MaskOffset[] memory maskOffsets = new MaskPointsGenerator.MaskOffset[](2);
//         maskOffsets[0] = MaskPointsGenerator.MaskOffset({offset: 0, columnIdx: 0});
//         maskOffsets[1] = MaskPointsGenerator.MaskOffset({offset: 1, columnIdx: 0});
        
//         uint256[] memory preprocessedColumns = new uint256[](0);
//         maskGenerator.addComponent(0, 8, maskOffsets, preprocessedColumns);

//         // Add a basic AIR component to composition evaluator
//         uint256[] memory constraintDegrees = new uint256[](2);
//         constraintDegrees[0] = 1;
//         constraintDegrees[1] = 2;
//         compositionEvaluator.addAirComponent(0, 8, constraintDegrees);
//     }

//     /// @notice Test OODS verifier initialization
//     function testOodsVerifierInitialization() public {
//         assertTrue(address(oodsVerifier.maskPointsGenerator()) != address(0), "Mask generator should be set");
//         assertTrue(address(oodsVerifier.compositionEvaluator()) != address(0), "Composition evaluator should be set");
//         assertTrue(address(oodsVerifier.proofParser()) != address(0), "Proof parser should be set");
        
//         assertEq(oodsVerifier.SECURE_EXTENSION_DEGREE(), 4, "Should have correct secure extension degree");
//     }

//     /// @notice Test component validation
//     function testComponentValidation() public {
//         (bool isValid, string memory errorMessage) = oodsVerifier.validateComponents();
//         assertTrue(isValid, "Components should be valid");
//         assertEq(bytes(errorMessage).length > 0, true, "Should have success message");
        
//         console.log("Component validation result:", errorMessage);
//     }

//     /// @notice Test sample points generation
//     function testSamplePointsGeneration() public {
//         MaskPointsGenerator.SamplePoints memory samplePoints = oodsVerifier.getSamplePoints(oodsPoint);
        
//         assertTrue(samplePoints.nTrees > 0, "Should generate sample points");
//         assertTrue(samplePoints.totalPoints > 0, "Should have total points");
        
//         console.log("Generated sample points:");
//         console.log("  Trees:", samplePoints.nTrees);
//         console.log("  Total points:", samplePoints.totalPoints);
//     }

//     /// @notice Test verification statistics
//     function testVerificationStatistics() public {
//         (uint256 totalPoints, uint256 columnsCount) = oodsVerifier.getVerificationStatistics(oodsPoint);
        
//         assertTrue(totalPoints > 0, "Should have total points");
//         assertTrue(columnsCount > 0, "Should have columns count");
        
//         console.log("Verification statistics:");
//         console.log("  Total points:", totalPoints);
//         console.log("  Columns count:", columnsCount);
//     }

//     /// @notice Test OODS context generation
//     function testOodsContextGeneration() public {
//         // Create test proof
//         ProofParser.StarkProof memory proof = _createTestProof();
        
//         OodsVerifier.OodsVerificationContext memory ctx = oodsVerifier.generateOodsContext(
//             oodsPoint,
//             proof,
//             randomCoeff
//         );

//         assertTrue(ctx.totalSamplePoints > 0, "Context should have sample points");
//         assertTrue(ctx.sampledColumnsCount > 0, "Context should have columns count");
        
//         console.log("OODS context generated:");
//         console.log("  Total sample points:", ctx.totalSamplePoints);
//         console.log("  Sampled columns:", ctx.sampledColumnsCount);
//     }

//     /// @notice Test simplified OODS verification with matching values
//     function testSimpleOodsVerificationSuccess() public {
//         // Create test sampled values
//         QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](4);
//         sampledValues[0] = QM31Field.fromM31(1111, 2222, 3333, 4444);
//         sampledValues[1] = QM31Field.fromM31(5555, 6666, 7777, 8888);
//         sampledValues[2] = QM31Field.fromM31(9999, 1010, 1111, 1212);
//         sampledValues[3] = QM31Field.fromM31(1313, 1414, 1515, 1616);

//         // Compute expected composition OODS evaluation
//         QM31Field.QM31 memory expectedOods = compositionEvaluator.evalCompositionPolynomialSimple(
//             oodsPoint,
//             sampledValues,
//             randomCoeff
//         );

//         // Verify OODS with matching expected value
//         bool isValid = oodsVerifier.verifyOodsSimple(
//             oodsPoint,
//             sampledValues,
//             randomCoeff,
//             expectedOods
//         );

//         assertTrue(isValid, "OODS verification should succeed with matching values");
        
//         console.log("Simple OODS verification passed");
//         console.log("Expected OODS first.real:", expectedOods.first.real);
//     }

//     /// @notice Test simplified OODS verification with mismatched values
//     function testSimpleOodsVerificationFailure() public {
//         // Create test sampled values
//         QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](4);
//         sampledValues[0] = QM31Field.fromM31(1111, 2222, 3333, 4444);
//         sampledValues[1] = QM31Field.fromM31(5555, 6666, 7777, 8888);
//         sampledValues[2] = QM31Field.fromM31(9999, 1010, 1111, 1212);
//         sampledValues[3] = QM31Field.fromM31(1313, 1414, 1515, 1616);

//         // Use wrong expected OODS evaluation
//         QM31Field.QM31 memory wrongExpectedOods = QM31Field.fromM31(99999, 88888, 77777, 66666);

//         // Verify OODS with wrong expected value
//         bool isValid = oodsVerifier.verifyOodsSimple(
//             oodsPoint,
//             sampledValues,
//             randomCoeff,
//             wrongExpectedOods
//         );

//         assertFalse(isValid, "OODS verification should fail with mismatched values");
        
//         console.log("Simple OODS verification correctly failed");
//     }

//     /// @notice Test full OODS verification with valid proof
//     function testFullOodsVerificationSuccess() public {
//         // Create test proof with matching composition evaluation
//         ProofParser.StarkProof memory proof = _createTestProofWithMatchingComposition();
        
//         OodsVerifier.OodsVerificationResult memory result = oodsVerifier.verifyOods(
//             oodsPoint,
//             proof,
//             randomCoeff
//         );

//         console.log("Full OODS verification result:");
//         console.log("  Is valid:", result.isValid);
//         console.log("  Error code:", uint256(result.error));
//         console.log("  Extracted OODS first.real:", result.extractedCompositionOods.first.real);
//         console.log("  Computed OODS first.real:", result.computedCompositionOods.first.real);
//         console.log("  Error message:", result.errorMessage);
        
//         assertTrue(result.isValid, "Full OODS verification should succeed");
//         assertTrue(uint256(result.error) == 0, "Should have no error");
//     }

//     /// @notice Test full OODS verification with invalid proof structure
//     function testFullOodsVerificationInvalidProof() public {
//         // Create invalid proof
//         ProofParser.StarkProof memory invalidProof;
//         invalidProof.isValid = false;
        
//         OodsVerifier.OodsVerificationResult memory result = oodsVerifier.verifyOods(
//             oodsPoint,
//             invalidProof,
//             randomCoeff
//         );

//         assertFalse(result.isValid, "OODS verification should fail with invalid proof");
//         assertTrue(uint256(result.error) == 1, "Should have InvalidStructure error");
        
//         console.log("OODS verification correctly failed with invalid proof");
//         console.log("  Error message:", result.errorMessage);
//     }

//     /// @notice Test full OODS verification with mismatched composition evaluation
//     function testFullOodsVerificationMismatchedComposition() public {
//         // Create proof with mismatched composition evaluation
//         ProofParser.StarkProof memory proof = _createTestProofWithMismatchedComposition();
        
//         OodsVerifier.OodsVerificationResult memory result = oodsVerifier.verifyOods(
//             oodsPoint,
//             proof,
//             randomCoeff
//         );

//         assertFalse(result.isValid, "OODS verification should fail with mismatched composition");
//         assertTrue(uint256(result.error) == 2, "Should have OodsNotMatching error");
        
//         console.log("OODS verification correctly failed with mismatched composition");
//         console.log("  Extracted OODS first.real:", result.extractedCompositionOods.first.real);
//         console.log("  Computed OODS first.real:", result.computedCompositionOods.first.real);
//         console.log("  Error message:", result.errorMessage);
//     }

//     /// @notice Test dry run verification check
//     function testCheckOodsVerification() public {
//         // Test with valid proof
//         ProofParser.StarkProof memory validProof = _createTestProofWithMatchingComposition();
//         (bool wouldPass, string memory reason) = oodsVerifier.checkOodsVerification(
//             oodsPoint,
//             validProof,
//             randomCoeff
//         );
        
//         assertTrue(wouldPass, "Check should indicate verification would pass");
//         console.log("Dry run check passed:", reason);

//         // Test with invalid proof
//         ProofParser.StarkProof memory invalidProof;
//         invalidProof.isValid = false;
//         (bool wouldFail, string memory failReason) = oodsVerifier.checkOodsVerification(
//             oodsPoint,
//             invalidProof,
//             randomCoeff
//         );
        
//         assertFalse(wouldFail, "Check should indicate verification would fail");
//         console.log("Dry run check failed:", failReason);
//     }

//     /// @notice Test with realistic OODS point from channel
//     function testWithRealisticOODSPoint() public {
//         // Initialize channel state using library
//         channelState.initialize();
        
//         // Set up channel state
//         bytes32 commitment = 0x7f3fb23a36bd8b85697aadc79cd031fab8fe3b65a557d923e8fd5d1879d02e13;
//         uint32[] memory commitmentU32s = new uint32[](8);
//         for (uint256 i = 0; i < 8; i++) {
//             commitmentU32s[i] = uint32(uint256(commitment) >> (8 * (28 - i * 4)));
//         }
//         channelState.mixU32s(commitmentU32s);
        
//         // Generate realistic OODS point and random coefficient
//         CirclePoint.Point memory realisticOODS = CirclePoint.getRandomPointFromState(channelState);
//         QM31Field.QM31 memory realisticRandomCoeff = channelState.drawSecureFelt();

//         // Test sample points generation
//         MaskPointsGenerator.SamplePoints memory samplePoints = oodsVerifier.getSamplePoints(realisticOODS);
//         assertTrue(samplePoints.totalPoints > 0, "Should generate sample points with realistic OODS");

//         // Test verification statistics
//         (uint256 totalPoints, uint256 columnsCount) = oodsVerifier.getVerificationStatistics(realisticOODS);
//         assertTrue(totalPoints > 0, "Should have statistics with realistic OODS");

//         // Test simple verification
//         QM31Field.QM31[] memory sampledValues = new QM31Field.QM31[](6);
//         for (uint256 i = 0; i < 6; i++) {
//             sampledValues[i] = QM31Field.fromM31(
//                 uint32(1000 + i * 100),
//                 uint32(2000 + i * 100),
//                 uint32(3000 + i * 100),
//                 uint32(4000 + i * 100)
//             );
//         }

//         QM31Field.QM31 memory expectedOods = compositionEvaluator.evalCompositionPolynomialSimple(
//             realisticOODS,
//             sampledValues,
//             realisticRandomCoeff
//         );

//         bool isValid = oodsVerifier.verifyOodsSimple(
//             realisticOODS,
//             sampledValues,
//             realisticRandomCoeff,
//             expectedOods
//         );

//         assertTrue(isValid, "OODS verification should work with realistic points");
        
//         console.log("Realistic OODS verification completed successfully");
//         console.log("  Total sample points:", totalPoints);
//         console.log("  Columns count:", columnsCount);
//     }

//     /// @notice Test error conditions and edge cases
//     function testErrorConditions() public {
//         // Test verifier with invalid components (should revert during construction)
//         vm.expectRevert("Invalid mask points generator");
//         new OodsVerifier(address(0), address(compositionEvaluator), address(proofParser));

//         vm.expectRevert("Invalid composition evaluator");
//         new OodsVerifier(address(maskGenerator), address(0), address(proofParser));

//         vm.expectRevert("Invalid proof parser");
//         new OodsVerifier(address(maskGenerator), address(compositionEvaluator), address(0));
//     }

//     // =============================================================================
//     // Helper Functions
//     // =============================================================================

//     /// @notice Create a test proof with basic structure
//     function _createTestProof() internal pure returns (ProofParser.StarkProof memory proof) {
//         // Create sampled values structure: [trace_tree, composition_tree]
//         QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](2);
        
//         // Tree 0: Regular trace with 2 columns
//         sampledValues[0] = new QM31Field.QM31[][](2);
//         sampledValues[0][0] = new QM31Field.QM31[](3);
//         sampledValues[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
//         sampledValues[0][0][1] = QM31Field.fromM31(110, 210, 310, 410);
//         sampledValues[0][0][2] = QM31Field.fromM31(120, 220, 320, 420);
//         sampledValues[0][1] = new QM31Field.QM31[](2);
//         sampledValues[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);
//         sampledValues[0][1][1] = QM31Field.fromM31(510, 610, 710, 810);

//         // Tree 1: Composition tree with 4 columns
//         sampledValues[1] = new QM31Field.QM31[][](4);
//         for (uint256 col = 0; col < 4; col++) {
//             sampledValues[1][col] = new QM31Field.QM31[](1);
//             sampledValues[1][col][0] = QM31Field.fromM31(
//                 uint32(1000 + col * 10), 
//                 uint32(2000 + col * 10), 
//                 uint32(3000 + col * 10), 
//                 uint32(4000 + col * 10)
//             );
//         }

//         proof.sampledValues = sampledValues;
//         proof.nTrees = 2;
//         proof.nColumns = new uint256[](2);
//         proof.nColumns[0] = 2;
//         proof.nColumns[1] = 4;
//         proof.commitment = keccak256("test_commitment");
//         proof.isValid = true;
//     }

//     /// @notice Create test proof where extracted composition matches computed composition
//     function _createTestProofWithMatchingComposition() internal view returns (ProofParser.StarkProof memory proof) {
//         proof = _createTestProof();
        
//         // Compute what the composition evaluation should be
//         QM31Field.QM31 memory computedComposition = compositionEvaluator.evalCompositionPolynomialAtPoint(
//             oodsPoint,
//             proof.sampledValues,
//             randomCoeff
//         );
        
//         // Set the composition tree to match this computed value
//         // Each column gets one M31 component of the computed composition
//         // The ProofParser will reconstruct the QM31 from these 4 M31 components
//         uint32[4] memory components = QM31Field.toM31Array(computedComposition);
//         for (uint256 col = 0; col < 4; col++) {
//             // Store each M31 component as the real part of the first component
//             proof.sampledValues[1][col][0] = QM31Field.fromM31(components[col], 0, 0, 0);
//         }
//     }

//     /// @notice Create test proof where extracted composition doesn't match computed composition
//     function _createTestProofWithMismatchedComposition() internal pure returns (ProofParser.StarkProof memory proof) {
//         proof = _createTestProof();
        
//         // Set composition tree to obviously wrong values
//         for (uint256 col = 0; col < 4; col++) {
//             proof.sampledValues[1][col][0] = QM31Field.fromM31(99999, 88888, 77777, 66666);
//         }
//     }
// }