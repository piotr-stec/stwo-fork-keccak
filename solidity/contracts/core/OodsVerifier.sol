// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.20;

// import "../core/CirclePoint.sol";
// import "../core/MaskPointsGenerator.sol";
// import "../core/CompositionEvaluator.sol";
// import "../core/ProofParser.sol";
// import "../fields/QM31Field.sol";
// import "../channel/IChannel.sol";

// /// @title OodsVerifier
// /// @notice Out-of-Domain Sampling (OODS) verification for STARK proofs
// /// @dev Implements the complete OODS verification process equivalent to Rust stwo implementation
// contract OodsVerifier {
//     using QM31Field for QM31Field.QM31;
//     using CirclePoint for CirclePoint.Point;

//     /// @notice Reference to mask points generator
//     MaskPointsGenerator public immutable maskPointsGenerator;
    
//     /// @notice Reference to composition evaluator
//     CompositionEvaluator public immutable compositionEvaluator;
    
//     /// @notice Reference to proof parser
//     ProofParser public immutable proofParser;

//     /// @notice Secure extension degree for QM31 field (4 components)
//     uint256 public constant SECURE_EXTENSION_DEGREE = 4;

//     /// @notice OODS verification context
//     struct OodsVerificationContext {
//         CirclePoint.Point oodsPoint;                           // Out-of-domain sampling point
//         QM31Field.QM31 randomCoeff;                           // Random coefficient for linear combination
//         MaskPointsGenerator.SamplePoints samplePoints;        // Generated sample points
//         ProofParser.StarkProof proof;                         // STARK proof being verified
//         uint256 totalSamplePoints;                            // Total number of sample points
//         uint256 sampledColumnsCount;                          // Number of sampled columns
//     }

//     /// @notice OODS verification result
//     struct OodsVerificationResult {
//         bool isValid;                                          // Whether verification passed
//         ProofParser.VerificationError error;                  // Error code if verification failed
//         QM31Field.QM31 extractedCompositionOods;             // Extracted composition OODS evaluation
//         QM31Field.QM31 computedCompositionOods;              // Computed composition OODS evaluation
//         string errorMessage;                                   // Human-readable error message
//     }

//     /// @notice Error thrown when verification components are not properly initialized
//     error InvalidVerificationComponents(string reason);

//     /// @notice Error thrown when OODS verification fails
//     error OodsVerificationFailed(string reason);

//     /// @notice Initialize OODS verifier with required components
//     /// @param _maskPointsGenerator Mask points generator contract
//     /// @param _compositionEvaluator Composition evaluator contract  
//     /// @param _proofParser Proof parser contract
//     constructor(
//         address _maskPointsGenerator,
//         address _compositionEvaluator,
//         address _proofParser
//     ) {
//         require(_maskPointsGenerator != address(0), "Invalid mask points generator");
//         require(_compositionEvaluator != address(0), "Invalid composition evaluator");
//         require(_proofParser != address(0), "Invalid proof parser");

//         maskPointsGenerator = MaskPointsGenerator(_maskPointsGenerator);
//         compositionEvaluator = CompositionEvaluator(_compositionEvaluator);
//         proofParser = ProofParser(_proofParser);
//     }

//     /// @notice Perform complete OODS verification process
//     /// @param oodsPoint Out-of-domain sampling point
//     /// @param proof STARK proof to verify
//     /// @param randomCoeff Random coefficient from channel
//     /// @return result OODS verification result
//     function verifyOods(
//         CirclePoint.Point memory oodsPoint,
//         ProofParser.StarkProof memory proof,
//         QM31Field.QM31 memory randomCoeff
//     ) external view returns (OodsVerificationResult memory result) {
//         // Initialize verification context
//         OodsVerificationContext memory ctx = OodsVerificationContext({
//             oodsPoint: oodsPoint,
//             randomCoeff: randomCoeff,
//             samplePoints: MaskPointsGenerator.SamplePoints({
//                 nTrees: 0,
//                 points: new CirclePoint.Point[][][](0),
//                 nColumns: new uint256[](0),
//                 totalPoints: 0
//             }),
//             proof: proof,
//             totalSamplePoints: 0,
//             sampledColumnsCount: 0
//         });

//         // Step 1: Generate mask sample points relative to OODS point
//         ctx.samplePoints = maskPointsGenerator.maskPoints(oodsPoint);
        
//         // Step 2: Add composition polynomial mask points
//         ctx.samplePoints = maskPointsGenerator.addCompositionMaskPoints(ctx.samplePoints, oodsPoint);
        
//         // Calculate sample points statistics
//         ctx.totalSamplePoints = maskPointsGenerator.getTotalSamplePoints(ctx.samplePoints);
//         ctx.sampledColumnsCount = maskPointsGenerator.getSampledColumnsCount(ctx.samplePoints);

//         // Step 3: Extract composition OODS evaluation from proof
//         ProofParser.CompositionOods memory extractedOods = proofParser.extractCompositionOodsEval(proof);
        
//         if (!extractedOods.isValid) {
//             result.isValid = false;
//             result.error = extractedOods.error;
//             result.errorMessage = "Failed to extract composition OODS evaluation from proof";
//             return result;
//         }

//         result.extractedCompositionOods = extractedOods.evaluation;

//         // Step 4: Compute composition polynomial evaluation at OODS point from sampled values
//         result.computedCompositionOods = compositionEvaluator.evalCompositionPolynomialAtPoint(
//             oodsPoint,
//             proof.sampledValues,
//             randomCoeff
//         );

//         // Step 5: Compare extracted vs computed composition OODS evaluations
//         bool oodsMatches = _compareQM31(result.extractedCompositionOods, result.computedCompositionOods);
        
//         if (!oodsMatches) {
//             result.isValid = false;
//             result.error = ProofParser.VerificationError.OodsNotMatching;
//             result.errorMessage = "Composition OODS evaluation mismatch";
//             return result;
//         }

//         // Verification passed
//         result.isValid = true;
//         result.error = ProofParser.VerificationError.None;
//         result.errorMessage = "OODS verification successful";
//     }

//     /// @notice Perform simplified OODS verification with flattened sampled values
//     /// @param oodsPoint Out-of-domain sampling point
//     /// @param sampledValues Flattened sampled values array
//     /// @param randomCoeff Random coefficient
//     /// @param expectedCompositionOods Expected composition OODS evaluation
//     /// @return isValid Whether verification passed
//     function verifyOodsSimple(
//         CirclePoint.Point memory oodsPoint,
//         QM31Field.QM31[] memory sampledValues,
//         QM31Field.QM31 memory randomCoeff,
//         QM31Field.QM31 memory expectedCompositionOods
//     ) external view returns (bool isValid) {
//         // Generate sample points
//         MaskPointsGenerator.SamplePoints memory samplePoints = maskPointsGenerator.maskPoints(oodsPoint);
//         samplePoints = maskPointsGenerator.addCompositionMaskPoints(samplePoints, oodsPoint);

//         // Compute composition polynomial evaluation
//         QM31Field.QM31 memory computedOods = compositionEvaluator.evalCompositionPolynomialSimple(
//             oodsPoint,
//             sampledValues,
//             randomCoeff
//         );

//         // Compare with expected value
//         return _compareQM31(expectedCompositionOods, computedOods);
//     }

//     /// @notice Generate complete OODS verification context for inspection
//     /// @param oodsPoint Out-of-domain sampling point
//     /// @param proof STARK proof
//     /// @param randomCoeff Random coefficient
//     /// @return ctx Complete verification context
//     function generateOodsContext(
//         CirclePoint.Point memory oodsPoint,
//         ProofParser.StarkProof memory proof,
//         QM31Field.QM31 memory randomCoeff
//     ) external view returns (OodsVerificationContext memory ctx) {
//         ctx.oodsPoint = oodsPoint;
//         ctx.randomCoeff = randomCoeff;
//         ctx.proof = proof;

//         // Generate mask points
//         ctx.samplePoints = maskPointsGenerator.maskPoints(oodsPoint);
//         ctx.samplePoints = maskPointsGenerator.addCompositionMaskPoints(ctx.samplePoints, oodsPoint);
        
//         // Calculate statistics
//         ctx.totalSamplePoints = maskPointsGenerator.getTotalSamplePoints(ctx.samplePoints);
//         ctx.sampledColumnsCount = maskPointsGenerator.getSampledColumnsCount(ctx.samplePoints);
//     }

//     /// @notice Get sample points for OODS verification
//     /// @param oodsPoint Out-of-domain sampling point
//     /// @return samplePoints Generated sample points including composition
//     function getSamplePoints(CirclePoint.Point memory oodsPoint) 
//         external 
//         view 
//         returns (MaskPointsGenerator.SamplePoints memory samplePoints) 
//     {
//         // Get mask sample points relative to OODS point
//         samplePoints = maskPointsGenerator.maskPoints(oodsPoint);
        
//         // Add composition polynomial mask points
//         samplePoints = maskPointsGenerator.addCompositionMaskPoints(samplePoints, oodsPoint);
//     }

//     /// @notice Get verification statistics for sample points
//     /// @param oodsPoint Out-of-domain sampling point
//     /// @return totalPoints Total number of sample points
//     /// @return columnsCount Number of columns being sampled
//     function getVerificationStatistics(CirclePoint.Point memory oodsPoint) 
//         external 
//         view 
//         returns (uint256 totalPoints, uint256 columnsCount) 
//     {
//         MaskPointsGenerator.SamplePoints memory samplePoints = maskPointsGenerator.maskPoints(oodsPoint);
//         samplePoints = maskPointsGenerator.addCompositionMaskPoints(samplePoints, oodsPoint);
        
//         totalPoints = maskPointsGenerator.getTotalSamplePoints(samplePoints);
//         columnsCount = maskPointsGenerator.getSampledColumnsCount(samplePoints);
//     }

//     /// @notice Validate that verification components are properly configured
//     /// @return isValid Whether all components are valid
//     /// @return errorMessage Error description if validation fails
//     function validateComponents() external view returns (bool isValid, string memory errorMessage) {
//         try maskPointsGenerator.SECURE_EXTENSION_DEGREE() returns (uint256 maskSecureExtension) {
//             if (maskSecureExtension != SECURE_EXTENSION_DEGREE) {
//                 return (false, "MaskPointsGenerator SECURE_EXTENSION_DEGREE mismatch");
//             }
//         } catch {
//             return (false, "MaskPointsGenerator not accessible");
//         }

//         try compositionEvaluator.getComponentCount() returns (uint256) {
//             // Component count check passed
//         } catch {
//             return (false, "CompositionEvaluator not accessible");
//         }

//         try proofParser.SECURE_EXTENSION_DEGREE() returns (uint256 parserSecureExtension) {
//             if (parserSecureExtension != SECURE_EXTENSION_DEGREE) {
//                 return (false, "ProofParser SECURE_EXTENSION_DEGREE mismatch");
//             }
//         } catch {
//             return (false, "ProofParser not accessible");
//         }

//         return (true, "All components valid");
//     }

//     /// @notice Check if OODS verification would pass for given inputs (dry run)
//     /// @param oodsPoint Out-of-domain sampling point
//     /// @param proof STARK proof
//     /// @param randomCoeff Random coefficient
//     /// @return wouldPass Whether verification would pass
//     /// @return reason Reason for failure if applicable
//     function checkOodsVerification(
//         CirclePoint.Point memory oodsPoint,
//         ProofParser.StarkProof memory proof,
//         QM31Field.QM31 memory randomCoeff
//     ) external view returns (bool wouldPass, string memory reason) {
//         OodsVerificationResult memory result = this.verifyOods(oodsPoint, proof, randomCoeff);
//         return (result.isValid, result.errorMessage);
//     }

//     // =============================================================================
//     // Internal Functions
//     // =============================================================================

//     /// @notice Compare two QM31 field elements for equality
//     /// @param a First QM31 element
//     /// @param b Second QM31 element
//     /// @return isEqual Whether elements are equal
//     function _compareQM31(QM31Field.QM31 memory a, QM31Field.QM31 memory b) 
//         internal 
//         pure 
//         returns (bool isEqual) 
//     {
//         return (
//             a.first.real == b.first.real &&
//             a.first.imag == b.first.imag &&
//             a.second.real == b.second.real &&
//             a.second.imag == b.second.imag
//         );
//     }

//     /// @notice Convert verification error to human-readable string
//     /// @param error Verification error enum
//     /// @return errorString Error description
//     function _errorToString(ProofParser.VerificationError error) 
//         internal 
//         pure 
//         returns (string memory errorString) 
//     {
//         if (error == ProofParser.VerificationError.None) return "None";
//         if (error == ProofParser.VerificationError.InvalidStructure) return "InvalidStructure";
//         if (error == ProofParser.VerificationError.OodsNotMatching) return "OodsNotMatching";
//         if (error == ProofParser.VerificationError.MerkleError) return "MerkleError";
//         if (error == ProofParser.VerificationError.FriError) return "FriError";
//         if (error == ProofParser.VerificationError.ProofOfWork) return "ProofOfWork";
//         return "Unknown";
//     }
// }