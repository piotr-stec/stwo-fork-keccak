// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/ProofParser.sol";
import "../../contracts/fields/QM31Field.sol";
import "../../contracts/fields/CM31Field.sol";

/// @title ProofParserTest
/// @notice TDD tests for ProofParser contract
contract ProofParserTest is Test {
    using QM31Field for QM31Field.QM31;

    ProofParser parser;

    function setUp() public {
        parser = new ProofParser();
    }

    /// @notice Test basic proof creation from sampled values
    function testCreateProofFromSampledValues() public {
        // Create simple 3D sampled values structure
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](2);
        
        // Tree 0: Regular trace with 2 columns
        sampledValues[0] = new QM31Field.QM31[][](2);
        sampledValues[0][0] = new QM31Field.QM31[](3);
        sampledValues[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
        sampledValues[0][0][1] = QM31Field.fromM31(110, 210, 310, 410);
        sampledValues[0][0][2] = QM31Field.fromM31(120, 220, 320, 420);
        sampledValues[0][1] = new QM31Field.QM31[](2);
        sampledValues[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);
        sampledValues[0][1][1] = QM31Field.fromM31(510, 610, 710, 810);

        // Tree 1: Composition tree with 4 columns (SECURE_EXTENSION_DEGREE)
        sampledValues[1] = new QM31Field.QM31[][](4);
        for (uint256 col = 0; col < 4; col++) {
            sampledValues[1][col] = new QM31Field.QM31[](1);
            sampledValues[1][col][0] = QM31Field.fromM31(
                uint32(1000 + col), 
                uint32(2000 + col), 
                uint32(3000 + col), 
                uint32(4000 + col)
            );
        }

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);

        // Verify proof structure
        assertEq(proof.nTrees, 2, "Should have 2 trees");
        assertEq(proof.nColumns[0], 2, "Tree 0 should have 2 columns");
        assertEq(proof.nColumns[1], 4, "Tree 1 should have 4 columns");
        assertTrue(proof.isValid, "Proof should be valid");
        
        console.log("Created proof with", proof.nTrees, "trees");
    }

    /// @notice Test composition OODS extraction from valid proof
    function testExtractCompositionOodsEvalValid() public {
        // Create valid proof with composition tree
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](1);
        sampledValues[0] = new QM31Field.QM31[][](4); // Composition tree

        // Set up composition mask with one evaluation per column
        for (uint256 col = 0; col < 4; col++) {
            sampledValues[0][col] = new QM31Field.QM31[](1);
            sampledValues[0][col][0] = QM31Field.fromM31(
                uint32(100 + col * 10), 
                uint32(200 + col * 10), 
                uint32(300 + col * 10), 
                uint32(400 + col * 10)
            );
        }

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);
        ProofParser.CompositionOods memory result = parser.extractCompositionOodsEval(proof);

        assertTrue(result.isValid, "OODS extraction should be valid");
        assertTrue(uint256(result.error) == 0, "Should have no error"); // VerificationError.None

        console.log("Extracted OODS evaluation:");
        console.log("  first.real:", result.evaluation.first.real);
        console.log("  first.imag:", result.evaluation.first.imag);
        console.log("  second.real:", result.evaluation.second.real);
        console.log("  second.imag:", result.evaluation.second.imag);
    }

    /// @notice Test composition OODS extraction from invalid proof structure
    function testExtractCompositionOodsEvalInvalidStructure() public {
        // Create invalid proof (wrong number of composition columns)
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](1);
        sampledValues[0] = new QM31Field.QM31[][](3); // Wrong! Should be 4 for composition

        for (uint256 col = 0; col < 3; col++) {
            sampledValues[0][col] = new QM31Field.QM31[](1);
            sampledValues[0][col][0] = QM31Field.fromM31(100, 200, 300, 400);
        }

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);
        ProofParser.CompositionOods memory result = parser.extractCompositionOodsEval(proof);

        assertFalse(result.isValid, "OODS extraction should be invalid");
        assertTrue(uint256(result.error) == 1, "Should have InvalidStructure error");
    }

    /// @notice Test composition OODS extraction with wrong number of evaluations per column
    function testExtractCompositionOodsEvalWrongEvaluations() public {
        // Create proof with wrong number of evaluations per column
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](1);
        sampledValues[0] = new QM31Field.QM31[][](4);

        // Set up composition mask with MULTIPLE evaluations per column (wrong!)
        for (uint256 col = 0; col < 4; col++) {
            sampledValues[0][col] = new QM31Field.QM31[](2); // Wrong! Should be 1
            sampledValues[0][col][0] = QM31Field.fromM31(100, 200, 300, 400);
            sampledValues[0][col][1] = QM31Field.fromM31(500, 600, 700, 800);
        }

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);
        ProofParser.CompositionOods memory result = parser.extractCompositionOodsEval(proof);

        assertFalse(result.isValid, "OODS extraction should be invalid");
        assertTrue(uint256(result.error) == 1, "Should have InvalidStructure error");
    }

    /// @notice Test proof structure validation
    function testValidateProofStructure() public {
        // Create valid proof
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](2);
        
        // Tree 0: Regular trace
        sampledValues[0] = new QM31Field.QM31[][](2);
        sampledValues[0][0] = new QM31Field.QM31[](3);
        sampledValues[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
        sampledValues[0][0][1] = QM31Field.fromM31(110, 210, 310, 410);
        sampledValues[0][0][2] = QM31Field.fromM31(120, 220, 320, 420);
        sampledValues[0][1] = new QM31Field.QM31[](2);
        sampledValues[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);
        sampledValues[0][1][1] = QM31Field.fromM31(510, 610, 710, 810);

        // Tree 1: Composition tree
        sampledValues[1] = new QM31Field.QM31[][](4);
        for (uint256 col = 0; col < 4; col++) {
            sampledValues[1][col] = new QM31Field.QM31[](1);
            sampledValues[1][col][0] = QM31Field.fromM31(1000 + uint32(col), 2000, 3000, 4000);
        }

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);
        (bool isValid, ProofParser.VerificationError error) = parser.validateProofStructure(proof);

        assertTrue(isValid, "Proof structure should be valid");
        assertTrue(uint256(error) == 0, "Should have no error");
    }

    /// @notice Test proof structure validation with invalid structure
    function testValidateProofStructureInvalid() public {
        // Create proof with mismatched tree count
        ProofParser.StarkProof memory invalidProof;
        invalidProof.nTrees = 2;
        invalidProof.sampledValues = new QM31Field.QM31[][][](1); // Wrong! Should match nTrees
        invalidProof.nColumns = new uint256[](2);
        invalidProof.nColumns[0] = 1;
        invalidProof.nColumns[1] = 1;
        invalidProof.isValid = true;

        (bool isValid, ProofParser.VerificationError error) = parser.validateProofStructure(invalidProof);

        assertFalse(isValid, "Invalid proof structure should be detected");
        assertTrue(uint256(error) == 1, "Should have InvalidStructure error");
    }

    /// @notice Test sampled values access functions
    function testSampledValuesAccess() public {
        // Create test proof
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](2);
        
        sampledValues[0] = new QM31Field.QM31[][](2);
        sampledValues[0][0] = new QM31Field.QM31[](2);
        sampledValues[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
        sampledValues[0][0][1] = QM31Field.fromM31(110, 210, 310, 410);
        sampledValues[0][1] = new QM31Field.QM31[](1);
        sampledValues[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);

        sampledValues[1] = new QM31Field.QM31[][](4);
        for (uint256 col = 0; col < 4; col++) {
            sampledValues[1][col] = new QM31Field.QM31[](1);
            sampledValues[1][col][0] = QM31Field.fromM31(1000 + uint32(col), 2000, 3000, 4000);
        }

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);

        // Test tree count
        uint256 treeCount = parser.getTreeCount(proof);
        assertEq(treeCount, 2, "Should have 2 trees");

        // Test column count
        uint256 tree0Columns = parser.getColumnCount(proof, 0);
        uint256 tree1Columns = parser.getColumnCount(proof, 1);
        assertEq(tree0Columns, 2, "Tree 0 should have 2 columns");
        assertEq(tree1Columns, 4, "Tree 1 should have 4 columns");

        // Test sampled values access
        QM31Field.QM31[] memory tree0Col0Values = parser.getSampledValues(proof, 0, 0);
        assertEq(tree0Col0Values.length, 2, "Tree 0 column 0 should have 2 values");
        assertEq(tree0Col0Values[0].first.real, 100, "First value should match");

        // Test composition tree detection
        bool hasComposition = parser.hasCompositionTree(proof);
        assertTrue(hasComposition, "Should detect composition tree");
    }

    /// @notice Test error conditions
    function testErrorConditions() public {
        QM31Field.QM31[][][] memory sampledValues = new QM31Field.QM31[][][](1);
        sampledValues[0] = new QM31Field.QM31[][](2);
        sampledValues[0][0] = new QM31Field.QM31[](1);
        sampledValues[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
        sampledValues[0][1] = new QM31Field.QM31[](1);
        sampledValues[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);

        ProofParser.StarkProof memory proof = parser.createProofFromSampledValues(sampledValues);

        // Test tree index out of bounds
        vm.expectRevert();
        parser.getSampledValues(proof, 999, 0);

        vm.expectRevert();
        parser.getColumnCount(proof, 999);

        // Test column index out of bounds
        vm.expectRevert("Column index out of bounds");
        parser.getSampledValues(proof, 0, 999);
    }

    /// @notice Test simple proof parsing from bytes
    function testParseProofFromBytes() public {
        bytes memory proofData = abi.encodePacked(
            bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            uint256(42),
            uint256(84)
        );

        ProofParser.StarkProof memory proof = parser.parseProof(proofData);

        assertTrue(proof.isValid, "Parsed proof should be valid");
        assertEq(proof.nTrees, 1, "Should have 1 tree");
        assertEq(proof.nColumns[0], 4, "Should have 4 columns (composition)");
        
        console.log("Parsed proof commitment:");
        console.logBytes32(proof.commitment);
    }

    /// @notice Test parsing with insufficient data
    function testParseProofInsufficientData() public {
        bytes memory insufficientData = abi.encodePacked(uint128(42)); // Only 16 bytes, too short

        ProofParser.StarkProof memory proof = parser.parseProof(insufficientData);

        assertFalse(proof.isValid, "Proof with insufficient data should be invalid");
    }

    /// @notice Test composition tree detection edge cases
    function testCompositionTreeDetection() public {
        // Test with empty proof
        ProofParser.StarkProof memory emptyProof;
        bool hasComposition1 = parser.hasCompositionTree(emptyProof);
        assertFalse(hasComposition1, "Empty proof should not have composition tree");

        // Test with trace-only proof (no composition)
        QM31Field.QM31[][][] memory traceOnly = new QM31Field.QM31[][][](1);
        traceOnly[0] = new QM31Field.QM31[][](2); // 2 columns, not 4
        traceOnly[0][0] = new QM31Field.QM31[](1);
        traceOnly[0][0][0] = QM31Field.fromM31(100, 200, 300, 400);
        traceOnly[0][1] = new QM31Field.QM31[](1);
        traceOnly[0][1][0] = QM31Field.fromM31(500, 600, 700, 800);

        ProofParser.StarkProof memory traceProof = parser.createProofFromSampledValues(traceOnly);
        bool hasComposition2 = parser.hasCompositionTree(traceProof);
        assertFalse(hasComposition2, "Trace-only proof should not have composition tree");

        // Test with proper composition tree
        QM31Field.QM31[][][] memory withComposition = new QM31Field.QM31[][][](1);
        withComposition[0] = new QM31Field.QM31[][](4); // 4 columns = composition
        for (uint256 col = 0; col < 4; col++) {
            withComposition[0][col] = new QM31Field.QM31[](1);
            withComposition[0][col][0] = QM31Field.fromM31(100, 200, 300, 400);
        }

        ProofParser.StarkProof memory compositionProof = parser.createProofFromSampledValues(withComposition);
        bool hasComposition3 = parser.hasCompositionTree(compositionProof);
        assertTrue(hasComposition3, "Proof with composition tree should be detected");
    }

    /// @notice Test complex multi-tree proof structure
    function testComplexProofStructure() public {
        // Create complex proof with multiple trace trees + composition
        QM31Field.QM31[][][] memory complexSampledValues = new QM31Field.QM31[][][](4);
        
        // Tree 0: Main trace (3 columns)
        complexSampledValues[0] = new QM31Field.QM31[][](3);
        for (uint256 col = 0; col < 3; col++) {
            complexSampledValues[0][col] = new QM31Field.QM31[](5); // 5 samples per column
            for (uint256 sample = 0; sample < 5; sample++) {
                complexSampledValues[0][col][sample] = QM31Field.fromM31(
                    uint32(100 + col * 10 + sample),
                    uint32(200 + col * 10 + sample),
                    uint32(300 + col * 10 + sample),
                    uint32(400 + col * 10 + sample)
                );
            }
        }

        // Tree 1: Permutation trace (2 columns)
        complexSampledValues[1] = new QM31Field.QM31[][](2);
        for (uint256 col = 0; col < 2; col++) {
            complexSampledValues[1][col] = new QM31Field.QM31[](3); // 3 samples per column
            for (uint256 sample = 0; sample < 3; sample++) {
                complexSampledValues[1][col][sample] = QM31Field.fromM31(
                    uint32(500 + col * 10 + sample),
                    uint32(600 + col * 10 + sample),
                    uint32(700 + col * 10 + sample),
                    uint32(800 + col * 10 + sample)
                );
            }
        }

        // Tree 2: Auxiliary trace (1 column)
        complexSampledValues[2] = new QM31Field.QM31[][](1);
        complexSampledValues[2][0] = new QM31Field.QM31[](2);
        complexSampledValues[2][0][0] = QM31Field.fromM31(900, 1000, 1100, 1200);
        complexSampledValues[2][0][1] = QM31Field.fromM31(910, 1010, 1110, 1210);

        // Tree 3: Composition tree (4 columns)
        complexSampledValues[3] = new QM31Field.QM31[][](4);
        for (uint256 col = 0; col < 4; col++) {
            complexSampledValues[3][col] = new QM31Field.QM31[](1); // 1 sample per column
            complexSampledValues[3][col][0] = QM31Field.fromM31(
                uint32(1300 + col),
                uint32(1400 + col),
                uint32(1500 + col),
                uint32(1600 + col)
            );
        }

        ProofParser.StarkProof memory complexProof = parser.createProofFromSampledValues(complexSampledValues);

        // Validate complex structure
        (bool isValid, ) = parser.validateProofStructure(complexProof);
        assertTrue(isValid, "Complex proof structure should be valid");

        // Test composition OODS extraction
        ProofParser.CompositionOods memory oods = parser.extractCompositionOodsEval(complexProof);
        assertTrue(oods.isValid, "OODS extraction should succeed");

        // Test access functions
        assertEq(parser.getTreeCount(complexProof), 4, "Should have 4 trees");
        assertEq(parser.getColumnCount(complexProof, 0), 3, "Tree 0 should have 3 columns");
        assertEq(parser.getColumnCount(complexProof, 1), 2, "Tree 1 should have 2 columns");
        assertEq(parser.getColumnCount(complexProof, 2), 1, "Tree 2 should have 1 column");
        assertEq(parser.getColumnCount(complexProof, 3), 4, "Tree 3 should have 4 columns");

        assertTrue(parser.hasCompositionTree(complexProof), "Should detect composition tree");

        console.log("Complex proof validation completed successfully");
    }
}