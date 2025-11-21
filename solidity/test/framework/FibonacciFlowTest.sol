import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/framework/WideFibonacciEval.sol";
import "../../contracts/framework/FibonacciEval.sol";

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
contract FibonacciFlowTest is Test {
    using QM31Field for QM31Field.QM31;
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;
    using FrameworkComponentLib for FrameworkComponentLib.ComponentState;
    using TraceLocationAllocatorLib for TraceLocationAllocatorLib.AllocatorState;
    using ProofLib for ProofLib.Proof;
    using KeccakChannelLib for KeccakChannelLib.ChannelState;
    using CommitmentSchemeVerifierLib for CommitmentSchemeVerifierLib.VerifierState;
    using FriVerifier for FriVerifier.FriVerifierState;
    using PcsConfig for PcsConfig.Config;

    /// @notice Get proof data from proof_fib_2.json
    function getFib2Proof() internal pure returns (ProofParser.Proof memory proof) {
        // Config from proof_fib_2.json
        proof.config.powBits = 10;
        proof.config.friConfig.logBlowupFactor = 1;
        proof.config.friConfig.logLastLayerDegreeBound = 0;
        proof.config.friConfig.nQueries = 3;

        // Commitments
        proof.commitments = new bytes32[](3);

        // Commitment 0 from proof_fib_2.json
        uint8[32] memory commit0 = [
            150, 93, 46, 166, 193, 179, 224, 254,
            77, 21, 163, 204, 63, 72, 175, 116,
            11, 82, 180, 189, 169, 54, 19, 51,
            136, 97, 184, 124, 193, 150, 220, 7
        ];
        proof.commitments[0] = _uint8ArrayToBytes32(commit0);

        // Commitment 1 from proof_fib_2.json
        uint8[32] memory commit1 = [
            202, 127, 183, 50, 75, 58, 8, 211,
            43, 153, 127, 223, 140, 208, 151, 28,
            10, 117, 171, 254, 70, 145, 237, 5,
            85, 26, 203, 193, 148, 160, 124, 214
        ];
        proof.commitments[1] = _uint8ArrayToBytes32(commit1);

        // Commitment 2 from proof_fib_2.json
        uint8[32] memory commit2 = [
            241, 237, 129, 29, 239, 105, 35, 190,
            75, 39, 135, 54, 163, 33, 19, 47,
            245, 123, 118, 165, 157, 205, 185, 152,
            98, 56, 84, 56, 24, 74, 229, 91
        ];
        proof.commitments[2] = _uint8ArrayToBytes32(commit2);


        // Sampled Values
        proof.sampledValues = new QM31Field.QM31[][][](3);

        // Tree 0: empty
        proof.sampledValues[0] = new QM31Field.QM31[][](0);

        // Tree 1: 3 columns
        proof.sampledValues[1] = new QM31Field.QM31[][](3);
        proof.sampledValues[1][0] = new QM31Field.QM31[](1);
        proof.sampledValues[1][0][0] = QM31Field.fromM31( 619588416, 287003406,  815407223,  272308883 );
        proof.sampledValues[1][1] = new QM31Field.QM31[](1);
        proof.sampledValues[1][1][0] = QM31Field.fromM31( 1339417634, 372378780,  1460002016,  2088746174 );
        proof.sampledValues[1][2] = new QM31Field.QM31[](1);
        proof.sampledValues[1][2][0] = QM31Field.fromM31( 1959006050, 659382186,  127925592,  213571410 );

        // Tree 2: 4 columns
        proof.sampledValues[2] = new QM31Field.QM31[][](4);
        proof.sampledValues[2][0] = new QM31Field.QM31[](1);
        proof.sampledValues[2][0][0] = QM31Field.fromM31( 0, 0,  0,  0 );
        proof.sampledValues[2][1] = new QM31Field.QM31[](1);
        proof.sampledValues[2][1][0] = QM31Field.fromM31( 0, 0,  0,  0 );
        proof.sampledValues[2][2] = new QM31Field.QM31[](1);
        proof.sampledValues[2][2][0] = QM31Field.fromM31( 0, 0,  0,  0 );
        proof.sampledValues[2][3] = new QM31Field.QM31[](1);
        proof.sampledValues[2][3][0] = QM31Field.fromM31( 0, 0,  0,  0 );


        // Queried Values
        proof.queriedValues = new uint32[][](3);

        // Tree 0: empty
        proof.queriedValues[0] = new uint32[](0);

        // Tree 1: 9 values
        proof.queriedValues[1] = new uint32[](9);
        proof.queriedValues[1][0] = 1064693394;
        proof.queriedValues[1][1] = 1501576514;
        proof.queriedValues[1][2] = 418786261;
        proof.queriedValues[1][3] = 1750076158;
        proof.queriedValues[1][4] = 1689137234;
        proof.queriedValues[1][5] = 1291729745;
        proof.queriedValues[1][6] = 1321206774;
        proof.queriedValues[1][7] = 1636159373;
        proof.queriedValues[1][8] = 809882500;

        // Tree 2: 12 values
        proof.queriedValues[2] = new uint32[](12);
        proof.queriedValues[2][0] = 0;
        proof.queriedValues[2][1] = 0;
        proof.queriedValues[2][2] = 0;
        proof.queriedValues[2][3] = 0;
        proof.queriedValues[2][4] = 0;
        proof.queriedValues[2][5] = 0;
        proof.queriedValues[2][6] = 0;
        proof.queriedValues[2][7] = 0;
        proof.queriedValues[2][8] = 0;
        proof.queriedValues[2][9] = 0;
        proof.queriedValues[2][10] = 0;
        proof.queriedValues[2][11] = 0;


        // Decommitments
       proof.decommitments = new MerkleVerifier.Decommitment[](3);

        // Tree 0: empty decommitment
        proof.decommitments[0].hashWitness = new bytes32[](0);
        proof.decommitments[0].columnWitness = new uint32[](0);

        // Tree 1: 13 hash witnesses
        proof.decommitments[1].hashWitness = new bytes32[](13);
        {
            uint8[32] memory hashWitness1_0 = [
            47, 44, 104, 95, 216, 190, 75, 105,
            148, 246, 115, 201, 229, 187, 115, 176,
            36, 51, 208, 237, 6, 64, 136, 53,
            42, 110, 90, 145, 1, 138, 64, 25
        ];
            proof.decommitments[1].hashWitness[0] = _uint8ArrayToBytes32(hashWitness1_0);

        }
        {
            uint8[32] memory hashWitness1_1 = [
            206, 144, 182, 165, 49, 236, 58, 196,
            35, 29, 1, 106, 11, 252, 236, 109,
            189, 68, 71, 202, 150, 163, 78, 49,
            248, 33, 184, 17, 48, 24, 213, 20
        ];
            proof.decommitments[1].hashWitness[1] = _uint8ArrayToBytes32(hashWitness1_1);
        }
        {
            uint8[32] memory hashWitness1_2 = [
            47, 144, 21, 218, 87, 59, 67, 65,
            87, 242, 154, 4, 71, 89, 234, 232,
            245, 32, 7, 37, 203, 28, 244, 170,
            192, 120, 188, 58, 138, 172, 39, 87
        ];
            proof.decommitments[1].hashWitness[2] = _uint8ArrayToBytes32(hashWitness1_2);
        }
        {
            uint8[32] memory hashWitness1_3 = [
            14, 33, 132, 136, 48, 140, 244, 250,
            43, 242, 134, 245, 39, 174, 242, 70,
            150, 212, 100, 157, 97, 179, 239, 170,
            113, 114, 57, 7, 102, 36, 231, 87
        ];
            proof.decommitments[1].hashWitness[3] = _uint8ArrayToBytes32(hashWitness1_3);
        }
        {
            uint8[32] memory hashWitness1_4 = [
            44, 217, 119, 179, 40, 237, 89, 201,
            2, 106, 119, 161, 74, 76, 153, 239,
            77, 64, 54, 248, 229, 63, 138, 247,
            181, 131, 85, 77, 197, 144, 130, 152
        ];
            proof.decommitments[1].hashWitness[4] = _uint8ArrayToBytes32(hashWitness1_4);
        }
        {
            uint8[32] memory hashWitness1_5 = [
            98, 72, 151, 197, 213, 66, 140, 214,
            56, 14, 104, 17, 178, 207, 21, 234,
            130, 173, 100, 188, 212, 129, 133, 90,
            95, 9, 82, 145, 254, 165, 196, 122
        ];
            proof.decommitments[1].hashWitness[5] = _uint8ArrayToBytes32(hashWitness1_5);
        }
        {
            uint8[32] memory hashWitness1_6 = [
            21, 112, 107, 170, 231, 131, 22, 115,
            223, 19, 145, 127, 101, 199, 139, 123,
            23, 56, 93, 34, 164, 136, 159, 78,
            148, 228, 97, 241, 143, 31, 87, 182
        ];
            proof.decommitments[1].hashWitness[6] = _uint8ArrayToBytes32(hashWitness1_6);
        }
        {
            uint8[32] memory hashWitness1_7 = [
            34, 212, 175, 175, 22, 20, 203, 119,
            129, 130, 235, 48, 28, 81, 174, 182,
            200, 91, 129, 32, 210, 130, 175, 28,
            16, 226, 209, 17, 43, 17, 237, 55
        ];
            proof.decommitments[1].hashWitness[7] = _uint8ArrayToBytes32(hashWitness1_7);
        }
        {
            uint8[32] memory hashWitness1_8 = [
            55, 197, 21, 112, 242, 44, 107, 83,
            154, 155, 141, 247, 190, 74, 141, 41,
            237, 141, 249, 198, 133, 185, 14, 93,
            48, 13, 60, 121, 185, 162, 230, 222
        ];
            proof.decommitments[1].hashWitness[8] = _uint8ArrayToBytes32(hashWitness1_8);
        }
        {
            uint8[32] memory hashWitness1_9 = [
            100, 111, 43, 234, 197, 31, 45, 82,
            141, 221, 48, 35, 222, 132, 96, 142,
            219, 54, 46, 136, 71, 34, 60, 56,
            10, 52, 61, 229, 161, 168, 125, 254
        ];
            proof.decommitments[1].hashWitness[9] = _uint8ArrayToBytes32(hashWitness1_9);
        }
        {
            uint8[32] memory hashWitness1_10 = [
            216, 193, 209, 32, 255, 241, 26, 83,
            221, 167, 68, 50, 150, 204, 110, 206,
            66, 186, 67, 125, 150, 157, 161, 119,
            196, 55, 136, 207, 173, 136, 19, 150
        ];
            proof.decommitments[1].hashWitness[10] = _uint8ArrayToBytes32(hashWitness1_10);
        }
        {
            uint8[32] memory hashWitness1_11 = [
            184, 143, 206, 97, 229, 42, 169, 195,
            173, 156, 180, 142, 240, 209, 207, 112,
            163, 141, 236, 249, 8, 184, 212, 182,
            173, 60, 252, 73, 114, 75, 49, 135
        ];
            proof.decommitments[1].hashWitness[11] = _uint8ArrayToBytes32(hashWitness1_11);
        }
        {
            uint8[32] memory hashWitness1_12 = [
            164, 153, 177, 167, 16, 238, 24, 14,
            139, 213, 98, 230, 163, 230, 153, 17,
            120, 27, 201, 57, 239, 116, 121, 195,
            225, 94, 14, 31, 38, 47, 233, 84
        ];
            proof.decommitments[1].hashWitness[12] = _uint8ArrayToBytes32(hashWitness1_12);
        }
        proof.decommitments[1].columnWitness = new uint32[](0);

        // Tree 2: 16 hash witnesses
        proof.decommitments[2].hashWitness = new bytes32[](16);
        {
            uint8[32] memory hashWitness2_0 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            proof.decommitments[2].hashWitness[0] = _uint8ArrayToBytes32(hashWitness2_0);
        }
        {
            uint8[32] memory hashWitness2_1 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            proof.decommitments[2].hashWitness[1] = _uint8ArrayToBytes32(hashWitness2_1);
        }
        {
            uint8[32] memory hashWitness2_2 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            proof.decommitments[2].hashWitness[2] = _uint8ArrayToBytes32(hashWitness2_2);
        }
        {
            uint8[32] memory hashWitness2_3 = [
            50, 92, 80, 167, 201, 186, 48, 118,
            40, 229, 240, 169, 189, 91, 239, 102,
            136, 173, 49, 45, 13, 27, 100, 238,
            108, 207, 63, 173, 208, 248, 42, 36
        ];
            proof.decommitments[2].hashWitness[3] = _uint8ArrayToBytes32(hashWitness2_3);
        }
        {
            uint8[32] memory hashWitness2_4 = [
            50, 92, 80, 167, 201, 186, 48, 118,
            40, 229, 240, 169, 189, 91, 239, 102,
            136, 173, 49, 45, 13, 27, 100, 238,
            108, 207, 63, 173, 208, 248, 42, 36
        ];
            proof.decommitments[2].hashWitness[4] = _uint8ArrayToBytes32(hashWitness2_4);
        }
        {
            uint8[32] memory hashWitness2_5 = [
            50, 92, 80, 167, 201, 186, 48, 118,
            40, 229, 240, 169, 189, 91, 239, 102,
            136, 173, 49, 45, 13, 27, 100, 238,
            108, 207, 63, 173, 208, 248, 42, 36
        ];
            proof.decommitments[2].hashWitness[5] = _uint8ArrayToBytes32(hashWitness2_5);
        }
        {
            uint8[32] memory hashWitness2_6 = [
            58, 8, 109, 44, 213, 188, 98, 82,
            228, 161, 119, 179, 76, 221, 211, 242,
            155, 15, 83, 95, 110, 124, 123, 44,
            180, 233, 178, 216, 3, 200, 171, 58
        ];
            proof.decommitments[2].hashWitness[6] = _uint8ArrayToBytes32(hashWitness2_6);
        }
        {
            uint8[32] memory hashWitness2_7 = [
            58, 8, 109, 44, 213, 188, 98, 82,
            228, 161, 119, 179, 76, 221, 211, 242,
            155, 15, 83, 95, 110, 124, 123, 44,
            180, 233, 178, 216, 3, 200, 171, 58
        ];
            proof.decommitments[2].hashWitness[7] = _uint8ArrayToBytes32(hashWitness2_7);
        }
        {
            uint8[32] memory hashWitness2_8 = [
            58, 8, 109, 44, 213, 188, 98, 82,
            228, 161, 119, 179, 76, 221, 211, 242,
            155, 15, 83, 95, 110, 124, 123, 44,
            180, 233, 178, 216, 3, 200, 171, 58
        ];
            proof.decommitments[2].hashWitness[8] = _uint8ArrayToBytes32(hashWitness2_8);
        }
        {
            uint8[32] memory hashWitness2_9 = [
            226, 74, 37, 64, 18, 215, 102, 235,
            189, 54, 100, 183, 213, 123, 245, 167,
            54, 26, 246, 116, 89, 18, 56, 27,
            146, 229, 206, 199, 214, 117, 69, 7
        ];
            proof.decommitments[2].hashWitness[9] = _uint8ArrayToBytes32(hashWitness2_9);
        }
        {
            uint8[32] memory hashWitness2_10 = [
            226, 74, 37, 64, 18, 215, 102, 235,
            189, 54, 100, 183, 213, 123, 245, 167,
            54, 26, 246, 116, 89, 18, 56, 27,
            146, 229, 206, 199, 214, 117, 69, 7
        ];
            proof.decommitments[2].hashWitness[10] = _uint8ArrayToBytes32(hashWitness2_10);
        }
        {
            uint8[32] memory hashWitness2_11 = [
            226, 74, 37, 64, 18, 215, 102, 235,
            189, 54, 100, 183, 213, 123, 245, 167,
            54, 26, 246, 116, 89, 18, 56, 27,
            146, 229, 206, 199, 214, 117, 69, 7
        ];
            proof.decommitments[2].hashWitness[11] = _uint8ArrayToBytes32(hashWitness2_11);
        }
        {
            uint8[32] memory hashWitness2_12 = [
            47, 157, 158, 144, 122, 106, 6, 152,
            1, 50, 228, 151, 193, 72, 40, 119,
            91, 14, 118, 149, 204, 44, 126, 226,
            40, 182, 9, 70, 60, 214, 91, 229
        ];
            proof.decommitments[2].hashWitness[12] = _uint8ArrayToBytes32(hashWitness2_12);
        }
        {
            uint8[32] memory hashWitness2_13 = [
            10, 135, 54, 55, 212, 122, 161, 55,
            191, 43, 2, 164, 171, 248, 96, 144,
            213, 49, 181, 136, 96, 147, 173, 226,
            190, 205, 43, 196, 148, 214, 244, 132
        ];
            proof.decommitments[2].hashWitness[13] = _uint8ArrayToBytes32(hashWitness2_13);
        }
        {
            uint8[32] memory hashWitness2_14 = [
            10, 135, 54, 55, 212, 122, 161, 55,
            191, 43, 2, 164, 171, 248, 96, 144,
            213, 49, 181, 136, 96, 147, 173, 226,
            190, 205, 43, 196, 148, 214, 244, 132
        ];
            proof.decommitments[2].hashWitness[14] = _uint8ArrayToBytes32(hashWitness2_14);
        }
        {
            uint8[32] memory hashWitness2_15 = [
            134, 155, 113, 103, 154, 192, 3, 29,
            28, 69, 26, 253, 140, 57, 29, 163,
            115, 186, 199, 32, 124, 137, 91, 74,
            57, 182, 165, 70, 19, 95, 34, 55
        ];
            proof.decommitments[2].hashWitness[15] = _uint8ArrayToBytes32(hashWitness2_15);
        }
        proof.decommitments[2].columnWitness = new uint32[](0);


        // Proof of Work
        proof.proofOfWork = 843;

        // FRI Proof
        // FRI Proof from proof_fib_2.json
        // First layer FRI witness (6 elements)
        QM31Field.QM31[] memory firstLayerWitness = new QM31Field.QM31[](6);
        firstLayerWitness[0] = QM31Field.fromM31(0, 0, 0, 0);
        firstLayerWitness[1] = QM31Field.fromM31(0, 0, 0, 0);
        firstLayerWitness[2] = QM31Field.fromM31(0, 0, 0, 0);
        firstLayerWitness[3] = QM31Field.fromM31(651811034, 2078829206, 747521906, 1972637192);
        firstLayerWitness[4] = QM31Field.fromM31(1499639910, 317379938, 1516147634, 754750708);
        firstLayerWitness[5] = QM31Field.fromM31(1492658845, 646820244, 1525358987, 1363252974);

        // First layer hash witness (16 elements)
        bytes32[] memory firstLayerHashWitness = new bytes32[](16);
        {
            uint8[32] memory hashWitness0 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            firstLayerHashWitness[0] = _uint8ArrayToBytes32(hashWitness0);
        }
        {
            uint8[32] memory hashWitness1 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            firstLayerHashWitness[1] = _uint8ArrayToBytes32(hashWitness1);
        }
        {
            uint8[32] memory hashWitness2 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            firstLayerHashWitness[2] = _uint8ArrayToBytes32(hashWitness2);
        }
        {
            uint8[32] memory hashWitness3 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            firstLayerHashWitness[3] = _uint8ArrayToBytes32(hashWitness3);
        }
        {
            uint8[32] memory hashWitness4 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            firstLayerHashWitness[4] = _uint8ArrayToBytes32(hashWitness4);
        }
        {
            uint8[32] memory hashWitness5 = [
            171, 202, 64, 193, 28, 82, 54, 15,
            9, 244, 176, 201, 231, 102, 70, 112,
            123, 105, 202, 187, 159, 59, 59, 243,
            93, 8, 29, 32, 13, 220, 39, 50
        ];
            firstLayerHashWitness[5] = _uint8ArrayToBytes32(hashWitness5);
        }
        {
            uint8[32] memory hashWitness6 = [
            79, 207, 150, 250, 103, 242, 137, 186,
            91, 241, 147, 95, 108, 154, 88, 242,
            153, 155, 16, 120, 122, 234, 18, 42,
            49, 208, 181, 127, 198, 22, 236, 193
        ];
            firstLayerHashWitness[6] = _uint8ArrayToBytes32(hashWitness6);
        }
        {
            uint8[32] memory hashWitness7 = [
            216, 1, 19, 63, 106, 58, 73, 132,
            84, 81, 245, 36, 41, 144, 55, 193,
            234, 119, 11, 209, 36, 164, 2, 157,
            162, 239, 224, 6, 244, 166, 183, 211
        ];
            firstLayerHashWitness[7] = _uint8ArrayToBytes32(hashWitness7);
        }
        {
            uint8[32] memory hashWitness8 = [
            207, 233, 57, 160, 19, 232, 120, 10,
            150, 22, 254, 163, 207, 110, 126, 139,
            171, 159, 124, 118, 109, 58, 21, 110,
            181, 172, 167, 224, 105, 155, 159, 226
        ];
            firstLayerHashWitness[8] = _uint8ArrayToBytes32(hashWitness8);
        }
        {
            uint8[32] memory hashWitness9 = [
            206, 171, 139, 134, 196, 226, 138, 239,
            127, 87, 88, 245, 62, 77, 22, 214,
            117, 245, 125, 11, 99, 159, 216, 159,
            139, 230, 218, 231, 131, 242, 125, 241
        ];
            firstLayerHashWitness[9] = _uint8ArrayToBytes32(hashWitness9);
        }
        {
            uint8[32] memory hashWitness10 = [
            188, 184, 42, 13, 149, 251, 76, 63,
            2, 235, 115, 160, 47, 170, 43, 184,
            159, 164, 159, 28, 216, 90, 34, 115,
            145, 255, 115, 217, 242, 164, 80, 164
        ];
            firstLayerHashWitness[10] = _uint8ArrayToBytes32(hashWitness10);
        }
        {
            uint8[32] memory hashWitness11 = [
            83, 179, 188, 132, 208, 138, 136, 252,
            217, 234, 15, 174, 13, 144, 130, 195,
            233, 205, 164, 214, 207, 51, 35, 222,
            219, 101, 162, 226, 62, 30, 252, 216
        ];
            firstLayerHashWitness[11] = _uint8ArrayToBytes32(hashWitness11);
        }
        {
            uint8[32] memory hashWitness12 = [
            29, 8, 58, 86, 201, 110, 108, 137,
            2, 152, 145, 235, 58, 172, 173, 155,
            161, 170, 192, 174, 123, 137, 25, 10,
            50, 208, 113, 51, 92, 73, 211, 56
        ];
            firstLayerHashWitness[12] = _uint8ArrayToBytes32(hashWitness12);
        }
        {
            uint8[32] memory hashWitness13 = [
            13, 122, 236, 252, 54, 75, 104, 199,
            171, 223, 222, 129, 117, 199, 213, 253,
            1, 228, 0, 231, 119, 130, 189, 229,
            253, 162, 206, 193, 45, 135, 253, 60
        ];
            firstLayerHashWitness[13] = _uint8ArrayToBytes32(hashWitness13);
        }
        {
            uint8[32] memory hashWitness14 = [
            239, 197, 53, 178, 104, 210, 27, 191,
            194, 234, 220, 45, 146, 42, 112, 41,
            210, 156, 242, 33, 56, 158, 134, 16,
            66, 71, 98, 4, 16, 82, 4, 67
        ];
            firstLayerHashWitness[14] = _uint8ArrayToBytes32(hashWitness14);
        }
        {
            uint8[32] memory hashWitness15 = [
            245, 25, 107, 195, 124, 158, 44, 187,
            182, 119, 36, 154, 17, 103, 236, 200,
            240, 224, 137, 75, 167, 84, 218, 53,
            253, 127, 225, 13, 143, 40, 3, 170
        ];
            firstLayerHashWitness[15] = _uint8ArrayToBytes32(hashWitness15);
        }

        // Encode first layer decommitment
        bytes memory firstLayerDecommitment = abi.encodePacked(
            uint256(firstLayerHashWitness.length), // hashWitnessLength
            firstLayerHashWitness, // hashWitness array
            uint256(0), // columnWitnessLength (0 for empty)
            new uint32[](0) // empty columnWitness
        );

        uint8[32] memory firstLayerCommitmentBytes = [
            175, 105, 103, 59, 29, 173, 151, 195,
            147, 240, 68, 127, 157, 74, 132, 240,
            229, 99, 50, 106, 81, 6, 215, 12,
            135, 12, 225, 181, 237, 142, 220, 117
        ];

        proof.friProof.firstLayer = FriVerifier.FriLayerProof({
            friWitness: firstLayerWitness,
            decommitment: firstLayerDecommitment,
            commitment: _uint8ArrayToBytes32(firstLayerCommitmentBytes)
        });

        // Inner layers (6 layers)
        proof.friProof.innerLayers = new FriVerifier.FriLayerProof[](6);

        // Inner layer 0 FRI witness
        QM31Field.QM31[] memory innerLayer0Witness = new QM31Field.QM31[](3);
        innerLayer0Witness[0] = QM31Field.fromM31(0, 0, 0, 0);
        innerLayer0Witness[1] = QM31Field.fromM31(0, 0, 0, 0);
        innerLayer0Witness[2] = QM31Field.fromM31(0, 0, 0, 0);

        // Inner layer 0 hash witness
        bytes32[] memory innerLayer0HashWitness = new bytes32[](10);
        {
            uint8[32] memory hashWitness0_0 = [
            50, 92, 80, 167, 201, 186, 48, 118,
            40, 229, 240, 169, 189, 91, 239, 102,
            136, 173, 49, 45, 13, 27, 100, 238,
            108, 207, 63, 173, 208, 248, 42, 36
        ];
            innerLayer0HashWitness[0] = _uint8ArrayToBytes32(hashWitness0_0);
        }
        {
            uint8[32] memory hashWitness0_1 = [
            50, 92, 80, 167, 201, 186, 48, 118,
            40, 229, 240, 169, 189, 91, 239, 102,
            136, 173, 49, 45, 13, 27, 100, 238,
            108, 207, 63, 173, 208, 248, 42, 36
        ];
            innerLayer0HashWitness[1] = _uint8ArrayToBytes32(hashWitness0_1);
        }
        {
            uint8[32] memory hashWitness0_2 = [
            50, 92, 80, 167, 201, 186, 48, 118,
            40, 229, 240, 169, 189, 91, 239, 102,
            136, 173, 49, 45, 13, 27, 100, 238,
            108, 207, 63, 173, 208, 248, 42, 36
        ];
            innerLayer0HashWitness[2] = _uint8ArrayToBytes32(hashWitness0_2);
        }
        {
            uint8[32] memory hashWitness0_3 = [
            58, 8, 109, 44, 213, 188, 98, 82,
            228, 161, 119, 179, 76, 221, 211, 242,
            155, 15, 83, 95, 110, 124, 123, 44,
            180, 233, 178, 216, 3, 200, 171, 58
        ];
            innerLayer0HashWitness[3] = _uint8ArrayToBytes32(hashWitness0_3);
        }
        {
            uint8[32] memory hashWitness0_4 = [
            58, 8, 109, 44, 213, 188, 98, 82,
            228, 161, 119, 179, 76, 221, 211, 242,
            155, 15, 83, 95, 110, 124, 123, 44,
            180, 233, 178, 216, 3, 200, 171, 58
        ];
            innerLayer0HashWitness[4] = _uint8ArrayToBytes32(hashWitness0_4);
        }
        {
            uint8[32] memory hashWitness0_5 = [
            58, 8, 109, 44, 213, 188, 98, 82,
            228, 161, 119, 179, 76, 221, 211, 242,
            155, 15, 83, 95, 110, 124, 123, 44,
            180, 233, 178, 216, 3, 200, 171, 58
        ];
            innerLayer0HashWitness[5] = _uint8ArrayToBytes32(hashWitness0_5);
        }
        {
            uint8[32] memory hashWitness0_6 = [
            226, 74, 37, 64, 18, 215, 102, 235,
            189, 54, 100, 183, 213, 123, 245, 167,
            54, 26, 246, 116, 89, 18, 56, 27,
            146, 229, 206, 199, 214, 117, 69, 7
        ];
            innerLayer0HashWitness[6] = _uint8ArrayToBytes32(hashWitness0_6);
        }
        {
            uint8[32] memory hashWitness0_7 = [
            47, 157, 158, 144, 122, 106, 6, 152,
            1, 50, 228, 151, 193, 72, 40, 119,
            91, 14, 118, 149, 204, 44, 126, 226,
            40, 182, 9, 70, 60, 214, 91, 229
        ];
            innerLayer0HashWitness[7] = _uint8ArrayToBytes32(hashWitness0_7);
        }
        {
            uint8[32] memory hashWitness0_8 = [
            47, 157, 158, 144, 122, 106, 6, 152,
            1, 50, 228, 151, 193, 72, 40, 119,
            91, 14, 118, 149, 204, 44, 126, 226,
            40, 182, 9, 70, 60, 214, 91, 229
        ];
            innerLayer0HashWitness[8] = _uint8ArrayToBytes32(hashWitness0_8);
        }
        {
            uint8[32] memory hashWitness0_9 = [
            245, 123, 132, 114, 217, 83, 182, 162,
            221, 188, 102, 149, 19, 192, 251, 65,
            140, 238, 204, 197, 210, 147, 117, 241,
            17, 153, 147, 227, 10, 86, 78, 224
        ];
            innerLayer0HashWitness[9] = _uint8ArrayToBytes32(hashWitness0_9);
        }

        bytes memory innerLayer0Decommitment = abi.encodePacked(
            uint256(innerLayer0HashWitness.length),
            innerLayer0HashWitness,
            uint256(0),
            new uint32[](0)
        );

        uint8[32] memory innerLayer0Commitment = [
            134, 155, 113, 103, 154, 192, 3, 29,
            28, 69, 26, 253, 140, 57, 29, 163,
            115, 186, 199, 32, 124, 137, 91, 74,
            57, 182, 165, 70, 19, 95, 34, 55
        ];

        proof.friProof.innerLayers[0] = FriVerifier.FriLayerProof({
            friWitness: innerLayer0Witness,
            decommitment: innerLayer0Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer0Commitment)
        });

        // Inner layer 1 FRI witness
        QM31Field.QM31[] memory innerLayer1Witness = new QM31Field.QM31[](3);
        innerLayer1Witness[0] = QM31Field.fromM31(1519673473, 616585061, 62159145, 831474336);
        innerLayer1Witness[1] = QM31Field.fromM31(1191298254, 498722685, 1824017641, 568906693);
        innerLayer1Witness[2] = QM31Field.fromM31(1918603959, 1631071198, 1322639068, 22957904);

        // Inner layer 1 hash witness
        bytes32[] memory innerLayer1HashWitness = new bytes32[](7);
        {
            uint8[32] memory hashWitness1_0 = [
            193, 184, 184, 163, 1, 181, 247, 40,
            109, 235, 165, 198, 82, 20, 195, 218,
            159, 132, 193, 186, 236, 234, 56, 16,
            101, 45, 231, 48, 135, 235, 109, 167
        ];
            innerLayer1HashWitness[0] = _uint8ArrayToBytes32(hashWitness1_0);
        }
        {
            uint8[32] memory hashWitness1_1 = [
            80, 213, 198, 144, 109, 173, 92, 109,
            182, 183, 151, 125, 96, 201, 81, 90,
            181, 162, 124, 190, 166, 40, 218, 227,
            156, 43, 52, 81, 158, 207, 67, 133
        ];
            innerLayer1HashWitness[1] = _uint8ArrayToBytes32(hashWitness1_1);
        }
        {
            uint8[32] memory hashWitness1_2 = [
            187, 27, 164, 137, 137, 124, 156, 10,
            218, 96, 233, 173, 145, 101, 76, 172,
            185, 87, 165, 104, 152, 141, 205, 156,
            5, 130, 32, 129, 57, 15, 69, 218
        ];
            innerLayer1HashWitness[2] = _uint8ArrayToBytes32(hashWitness1_2);
        }
        {
            uint8[32] memory hashWitness1_3 = [
            187, 211, 104, 245, 229, 42, 161, 234,
            84, 96, 79, 249, 190, 21, 156, 84,
            18, 34, 124, 229, 246, 124, 251, 107,
            83, 6, 210, 52, 178, 52, 221, 107
        ];
            innerLayer1HashWitness[3] = _uint8ArrayToBytes32(hashWitness1_3);
        }
        {
            uint8[32] memory hashWitness1_4 = [
            119, 230, 215, 154, 244, 24, 49, 146,
            59, 47, 137, 177, 41, 200, 83, 252,
            182, 218, 172, 111, 83, 156, 70, 13,
            249, 139, 35, 149, 197, 161, 84, 252
        ];
            innerLayer1HashWitness[4] = _uint8ArrayToBytes32(hashWitness1_4);
        }
        {
            uint8[32] memory hashWitness1_5 = [
            156, 155, 249, 33, 129, 122, 113, 91,
            141, 27, 188, 81, 98, 8, 106, 49,
            149, 171, 129, 197, 65, 55, 106, 157,
            243, 231, 107, 132, 232, 2, 151, 104
        ];
            innerLayer1HashWitness[5] = _uint8ArrayToBytes32(hashWitness1_5);
        }
        {
            uint8[32] memory hashWitness1_6 = [
            20, 192, 169, 1, 117, 158, 209, 191,
            143, 45, 216, 160, 193, 185, 41, 155,
            237, 25, 124, 167, 19, 35, 82, 21,
            28, 16, 69, 50, 18, 85, 27, 119
        ];
            innerLayer1HashWitness[6] = _uint8ArrayToBytes32(hashWitness1_6);
        }

        bytes memory innerLayer1Decommitment = abi.encodePacked(
            uint256(innerLayer1HashWitness.length),
            innerLayer1HashWitness,
            uint256(0),
            new uint32[](0)
        );

        uint8[32] memory innerLayer1Commitment = [
            221, 192, 235, 108, 101, 42, 20, 45,
            145, 101, 96, 51, 174, 240, 156, 245,
            11, 131, 132, 85, 235, 58, 51, 191,
            211, 10, 132, 106, 140, 197, 175, 163
        ];

        proof.friProof.innerLayers[1] = FriVerifier.FriLayerProof({
            friWitness: innerLayer1Witness,
            decommitment: innerLayer1Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer1Commitment)
        });

        // Inner layer 2 FRI witness
        QM31Field.QM31[] memory innerLayer2Witness = new QM31Field.QM31[](3);
        innerLayer2Witness[0] = QM31Field.fromM31(1919529987, 266062826, 2001281735, 1117838056);
        innerLayer2Witness[1] = QM31Field.fromM31(1679652363, 533043946, 125830178, 1063985909);
        innerLayer2Witness[2] = QM31Field.fromM31(1646767338, 1588330614, 1782952559, 1000558776);

        // Inner layer 2 hash witness
        bytes32[] memory innerLayer2HashWitness = new bytes32[](4);
        {
            uint8[32] memory hashWitness2_0 = [
            135, 206, 205, 239, 209, 100, 223, 22,
            87, 31, 17, 197, 201, 211, 242, 82,
            40, 158, 57, 104, 200, 201, 217, 184,
            179, 130, 54, 131, 200, 90, 136, 149
        ];
            innerLayer2HashWitness[0] = _uint8ArrayToBytes32(hashWitness2_0);
        }
        {
            uint8[32] memory hashWitness2_1 = [
            63, 184, 114, 152, 25, 155, 7, 158,
            29, 68, 162, 9, 230, 218, 182, 135,
            126, 119, 218, 253, 209, 69, 203, 135,
            69, 122, 80, 133, 72, 33, 238, 235
        ];
            innerLayer2HashWitness[1] = _uint8ArrayToBytes32(hashWitness2_1);
        }
        {
            uint8[32] memory hashWitness2_2 = [
            71, 220, 207, 92, 82, 39, 109, 193,
            39, 64, 84, 50, 163, 164, 145, 175,
            233, 254, 93, 85, 123, 217, 84, 68,
            39, 8, 37, 172, 123, 216, 84, 249
        ];
            innerLayer2HashWitness[2] = _uint8ArrayToBytes32(hashWitness2_2);
        }
        {
            uint8[32] memory hashWitness2_3 = [
            57, 50, 59, 39, 108, 16, 131, 126,
            22, 220, 12, 26, 160, 54, 172, 23,
            73, 55, 204, 4, 173, 205, 129, 82,
            92, 83, 22, 221, 221, 235, 209, 19
        ];
            innerLayer2HashWitness[3] = _uint8ArrayToBytes32(hashWitness2_3);
        }

        bytes memory innerLayer2Decommitment = abi.encodePacked(
            uint256(innerLayer2HashWitness.length),
            innerLayer2HashWitness,
            uint256(0),
            new uint32[](0)
        );

        uint8[32] memory innerLayer2Commitment = [
            253, 132, 165, 96, 202, 230, 64, 36,
            207, 195, 180, 94, 247, 212, 107, 91,
            233, 235, 31, 35, 225, 105, 53, 174,
            253, 13, 220, 197, 191, 255, 146, 86
        ];

        proof.friProof.innerLayers[2] = FriVerifier.FriLayerProof({
            friWitness: innerLayer2Witness,
            decommitment: innerLayer2Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer2Commitment)
        });

        // Inner layer 3 FRI witness
        QM31Field.QM31[] memory innerLayer3Witness = new QM31Field.QM31[](1);
        innerLayer3Witness[0] = QM31Field.fromM31(559522814, 339034307, 641646432, 1148595115);

        // Inner layer 3 hash witness
        bytes32[] memory innerLayer3HashWitness = new bytes32[](3);
        {
            uint8[32] memory hashWitness3_0 = [
            82, 19, 47, 25, 24, 62, 101, 125,
            80, 79, 139, 204, 240, 178, 68, 206,
            59, 85, 57, 109, 95, 76, 127, 186,
            67, 25, 115, 111, 41, 229, 168, 89
        ];
            innerLayer3HashWitness[0] = _uint8ArrayToBytes32(hashWitness3_0);
        }
        {
            uint8[32] memory hashWitness3_1 = [
            214, 29, 85, 31, 235, 137, 185, 73,
            115, 138, 128, 107, 205, 215, 212, 172,
            72, 124, 153, 96, 172, 182, 18, 148,
            133, 206, 182, 58, 29, 217, 179, 114
        ];
            innerLayer3HashWitness[1] = _uint8ArrayToBytes32(hashWitness3_1);
        }
        {
            uint8[32] memory hashWitness3_2 = [
            195, 243, 160, 132, 161, 15, 66, 127,
            234, 115, 48, 218, 121, 103, 9, 113,
            99, 27, 33, 92, 132, 201, 36, 107,
            201, 205, 75, 132, 132, 176, 166, 68
        ];
            innerLayer3HashWitness[2] = _uint8ArrayToBytes32(hashWitness3_2);
        }

        bytes memory innerLayer3Decommitment = abi.encodePacked(
            uint256(innerLayer3HashWitness.length),
            innerLayer3HashWitness,
            uint256(0),
            new uint32[](0)
        );

        uint8[32] memory innerLayer3Commitment = [
            65, 198, 51, 67, 181, 154, 180, 168,
            83, 57, 222, 216, 255, 190, 25, 120,
            104, 36, 54, 162, 182, 188, 41, 205,
            95, 180, 171, 72, 189, 248, 116, 189
        ];

        proof.friProof.innerLayers[3] = FriVerifier.FriLayerProof({
            friWitness: innerLayer3Witness,
            decommitment: innerLayer3Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer3Commitment)
        });

        // Inner layer 4 FRI witness
        QM31Field.QM31[] memory innerLayer4Witness = new QM31Field.QM31[](2);
        innerLayer4Witness[0] = QM31Field.fromM31(1223099037, 1125475337, 1992831874, 1929475499);
        innerLayer4Witness[1] = QM31Field.fromM31(960148108, 418459696, 654018338, 2106335246);

        // Inner layer 4 hash witness
        bytes32[] memory innerLayer4HashWitness = new bytes32[](1);
        {
            uint8[32] memory hashWitness4_0 = [
            98, 29, 28, 89, 247, 131, 27, 108,
            161, 20, 31, 7, 248, 250, 161, 148,
            156, 115, 74, 86, 139, 209, 142, 9,
            89, 34, 62, 150, 28, 143, 214, 224
        ];
            innerLayer4HashWitness[0] = _uint8ArrayToBytes32(hashWitness4_0);
        }

        bytes memory innerLayer4Decommitment = abi.encodePacked(
            uint256(innerLayer4HashWitness.length),
            innerLayer4HashWitness,
            uint256(0),
            new uint32[](0)
        );

        uint8[32] memory innerLayer4Commitment = [
            125, 69, 146, 236, 15, 250, 111, 182,
            96, 72, 85, 179, 179, 106, 108, 74,
            189, 224, 58, 148, 183, 56, 228, 138,
            233, 145, 212, 99, 86, 79, 32, 81
        ];

        proof.friProof.innerLayers[4] = FriVerifier.FriLayerProof({
            friWitness: innerLayer4Witness,
            decommitment: innerLayer4Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer4Commitment)
        });

        // Inner layer 5 FRI witness
        QM31Field.QM31[] memory innerLayer5Witness = new QM31Field.QM31[](0);

        // Inner layer 5 hash witness
        bytes32[] memory innerLayer5HashWitness = new bytes32[](1);
        {
            uint8[32] memory hashWitness5_0 = [
            47, 133, 127, 68, 124, 127, 226, 195,
            6, 126, 0, 77, 166, 71, 146, 52,
            8, 218, 77, 239, 9, 221, 21, 65,
            121, 240, 153, 135, 183, 114, 204, 162
        ];
            innerLayer5HashWitness[0] = _uint8ArrayToBytes32(hashWitness5_0);
        }

        bytes memory innerLayer5Decommitment = abi.encodePacked(
            uint256(innerLayer5HashWitness.length),
            innerLayer5HashWitness,
            uint256(0),
            new uint32[](0)
        );

        uint8[32] memory innerLayer5Commitment = [
            111, 168, 160, 95, 49, 197, 23, 74,
            251, 131, 221, 247, 156, 241, 249, 246,
            226, 170, 89, 0, 177, 229, 155, 31,
            212, 88, 255, 251, 65, 147, 82, 25
        ];

        proof.friProof.innerLayers[5] = FriVerifier.FriLayerProof({
            friWitness: innerLayer5Witness,
            decommitment: innerLayer5Decommitment,
            commitment: _uint8ArrayToBytes32(innerLayer5Commitment)
        });

        // Last layer polynomial
        proof.friProof.lastLayerPoly = new QM31Field.QM31[](1);
        proof.friProof.lastLayerPoly[0] = QM31Field.fromM31(150444102, 954269915, 396309850, 1686235316);


        return proof;
    }

    function test_FibonacciFlowProofVerification() public {
        ProofParser.Proof memory proof = getFib2Proof();
        FibonacciEval fibEvalAddress = new FibonacciEval(6);
        STWOVerifier verifier = new STWOVerifier();

        bytes32[] memory treeRoots = new bytes32[](2);
        treeRoots[0] = proof.commitments[0]; // PREPROCESSED
        treeRoots[1] = proof.commitments[1]; // ORIGINAL_TRACE
        uint32[][] memory treeColumnLogSizes = new uint32[][](2);
        // Tree 0: Empty (preprocessed) - extended log sizes: []
        treeColumnLogSizes[0] = new uint32[](0);

        // Tree 1: 50 trace columns - extended log sizes: [4, 4, 4, ...] (50 times)
        treeColumnLogSizes[1] = new uint32[](3);
        for (uint256 i = 0; i < 3; i++) {
            treeColumnLogSizes[1][i] = 7; // logSize(3) + logBlowupFactor(1) = 4
        }

        int32[][][] memory maskOffsets = new int32[][][](2); // 2 trees
        maskOffsets[0] = new int32[][](0); // Tree 0: PREPROCESSED - empty
        maskOffsets[1] = new int32[][](3); // Tree 1: ORIGINAL_TRACE (50 columns for WideFibonacci)
        for (uint256 i = 0; i < 3; i++) {
            maskOffsets[1][i] = new int32[](1); 
            maskOffsets[1][i][0] = 0; // Offset is 0 (current row)
        }

        FrameworkComponentLib.ComponentInfo
            memory componentInfo = FrameworkComponentLib.ComponentInfo({
                nConstraints: 1,
                maxConstraintLogDegreeBound: 7,
                logSize: 6,
                componentName: "WideFibonacciComponent",
                description: "Wide Fibonacci component for testing",
                maskOffsets: maskOffsets,
                preprocessedColumns: new uint256[](0)
            });

        bytes32 digest = 0x8967316dba25c11866b9dc29d5b956d7341c49f4694cbebc3b29e492355ce8c5;
        STWOVerifier.VerificationParams memory params = STWOVerifier
            .VerificationParams({
                evaluator: address(fibEvalAddress),
                claimedSum: QM31Field.zero(),
                componentInfo: componentInfo
            });
        // gas before
        uint256 gasBefore = gasleft();
       bool result = verifier.verify(
            proof,
            params,
            treeRoots,
            treeColumnLogSizes,
            digest,
            0
        );

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        emit log_named_uint("FibonacciFlow proof verification gas used", gasUsed);

        assertTrue(result, "FibonacciFlow proof verification failed");
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