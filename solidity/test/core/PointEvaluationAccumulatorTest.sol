// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/core/PointEvaluationAccumulator.sol";
import "../../contracts/fields/QM31Field.sol";
/// @title PointEvaluationAccumulatorTest
/// @notice Test matching Rust test_point_evaluation_accumulator exactly
/// @dev Direct port of Rust test for verification compatibility
contract PointEvaluationAccumulatorTest is Test {
    using PointEvaluationAccumulator for PointEvaluationAccumulator.Accumulator;
    using QM31Field for QM31Field.QM31;

    /// @notice Test equivalent to Rust test_point_evaluation_accumulator
    /// @dev Uses same constants and logic as Rust test
    function testPointEvaluationAccumulator() public {
        console.log("=== Point Evaluation Accumulator Test ===");
        
        // Constants from Rust test
        uint32 MAX_LOG_SIZE = 10;
        uint32 MASK = 2147483647; // M31 prime P = 2^31 - 1
        
        // Actual data from Rust test
        uint32[] memory logSizes = new uint32[](100);
        logSizes[0] = 6; logSizes[1] = 6; logSizes[2] = 9; logSizes[3] = 9; logSizes[4] = 7;
        logSizes[5] = 6; logSizes[6] = 6; logSizes[7] = 5; logSizes[8] = 4; logSizes[9] = 9;
        logSizes[10] = 5; logSizes[11] = 5; logSizes[12] = 8; logSizes[13] = 8; logSizes[14] = 7;
        logSizes[15] = 5; logSizes[16] = 5; logSizes[17] = 9; logSizes[18] = 6; logSizes[19] = 9;
        logSizes[20] = 4; logSizes[21] = 6; logSizes[22] = 9; logSizes[23] = 4; logSizes[24] = 6;
        logSizes[25] = 9; logSizes[26] = 6; logSizes[27] = 5; logSizes[28] = 8; logSizes[29] = 6;
        logSizes[30] = 4; logSizes[31] = 8; logSizes[32] = 8; logSizes[33] = 6; logSizes[34] = 6;
        logSizes[35] = 8; logSizes[36] = 6; logSizes[37] = 6; logSizes[38] = 4; logSizes[39] = 4;
        logSizes[40] = 9; logSizes[41] = 5; logSizes[42] = 8; logSizes[43] = 8; logSizes[44] = 5;
        logSizes[45] = 5; logSizes[46] = 7; logSizes[47] = 7; logSizes[48] = 7; logSizes[49] = 4;
        logSizes[50] = 4; logSizes[51] = 6; logSizes[52] = 4; logSizes[53] = 9; logSizes[54] = 6;
        logSizes[55] = 6; logSizes[56] = 9; logSizes[57] = 8; logSizes[58] = 9; logSizes[59] = 9;
        logSizes[60] = 7; logSizes[61] = 8; logSizes[62] = 7; logSizes[63] = 6; logSizes[64] = 7;
        logSizes[65] = 5; logSizes[66] = 5; logSizes[67] = 8; logSizes[68] = 9; logSizes[69] = 8;
        logSizes[70] = 6; logSizes[71] = 6; logSizes[72] = 6; logSizes[73] = 5; logSizes[74] = 8;
        logSizes[75] = 9; logSizes[76] = 8; logSizes[77] = 8; logSizes[78] = 8; logSizes[79] = 6;
        logSizes[80] = 7; logSizes[81] = 4; logSizes[82] = 6; logSizes[83] = 5; logSizes[84] = 7;
        logSizes[85] = 8; logSizes[86] = 9; logSizes[87] = 7; logSizes[88] = 5; logSizes[89] = 9;
        logSizes[90] = 9; logSizes[91] = 7; logSizes[92] = 4; logSizes[93] = 6; logSizes[94] = 8;
        logSizes[95] = 9; logSizes[96] = 9; logSizes[97] = 5; logSizes[98] = 4; logSizes[99] = 5;
        
        console.log("Log sizes length:", logSizes.length);
        console.log("First few log sizes:");
        for (uint256 i = 0; i < 5 && i < logSizes.length; i++) {
            console.log("  logSizes[%d] = %d", i, logSizes[i]);
        }
        
        // Actual evaluation data from Rust test
        uint32[] memory evaluations = new uint32[](100);
        evaluations[0] = 406280215; evaluations[1] = 1619871109; evaluations[2] = 917696365; evaluations[3] = 262962254; evaluations[4] = 832694687;
        evaluations[5] = 1608050167; evaluations[6] = 1591606054; evaluations[7] = 1175399951; evaluations[8] = 2113046647; evaluations[9] = 2002385746;
        evaluations[10] = 1754903067; evaluations[11] = 1276103319; evaluations[12] = 527709358; evaluations[13] = 1143875375; evaluations[14] = 270054232;
        evaluations[15] = 1995240033; evaluations[16] = 146477567; evaluations[17] = 1857359239; evaluations[18] = 1159839286; evaluations[19] = 114827773;
        evaluations[20] = 1653534489; evaluations[21] = 1724505640; evaluations[22] = 764351823; evaluations[23] = 1252873349; evaluations[24] = 519403788;
        evaluations[25] = 252821606; evaluations[26] = 2092147571; evaluations[27] = 61899269; evaluations[28] = 1684331785; evaluations[29] = 1022488806;
        evaluations[30] = 2006152464; evaluations[31] = 640512868; evaluations[32] = 996138056; evaluations[33] = 1149958004; evaluations[34] = 908120119;
        evaluations[35] = 1232660272; evaluations[36] = 709184823; evaluations[37] = 404458604; evaluations[38] = 913402583; evaluations[39] = 1524009030;
        evaluations[40] = 1057107679; evaluations[41] = 957180951; evaluations[42] = 483176866; evaluations[43] = 1666759805; evaluations[44] = 2117632869;
        evaluations[45] = 333755593; evaluations[46] = 1905165735; evaluations[47] = 1306558257; evaluations[48] = 631083851; evaluations[49] = 2009934913;
        evaluations[50] = 1664720567; evaluations[51] = 1458676468; evaluations[52] = 783927720; evaluations[53] = 1061422377; evaluations[54] = 849317022;
        evaluations[55] = 1468191128; evaluations[56] = 1584632489; evaluations[57] = 1142141950; evaluations[58] = 682731178; evaluations[59] = 1258762437;
        evaluations[60] = 1153253871; evaluations[61] = 771189382; evaluations[62] = 755377687; evaluations[63] = 293433920; evaluations[64] = 2120259979;
        evaluations[65] = 682716110; evaluations[66] = 1141564828; evaluations[67] = 2105251809; evaluations[68] = 971492840; evaluations[69] = 1656816400;
        evaluations[70] = 676781070; evaluations[71] = 65165702; evaluations[72] = 958330527; evaluations[73] = 555844311; evaluations[74] = 2079161629;
        evaluations[75] = 461470117; evaluations[76] = 134316296; evaluations[77] = 878277110; evaluations[78] = 1585619106; evaluations[79] = 816273631;
        evaluations[80] = 1659152631; evaluations[81] = 1065636827; evaluations[82] = 1408770176; evaluations[83] = 1772553405; evaluations[84] = 1837151429;
        evaluations[85] = 2035067383; evaluations[86] = 445288152; evaluations[87] = 643544105; evaluations[88] = 2096534387; evaluations[89] = 1562148784;
        evaluations[90] = 1438953223; evaluations[91] = 277237148; evaluations[92] = 1754001662; evaluations[93] = 727464065; evaluations[94] = 1274053193;
        evaluations[95] = 1216280523; evaluations[96] = 4003254; evaluations[97] = 1683194957; evaluations[98] = 1457926041; evaluations[99] = 1131266152;
        
        console.log("Evaluations length:", evaluations.length);
        console.log("First few evaluations:");
        for (uint256 i = 0; i < 5 && i < evaluations.length; i++) {
            console.log("  evaluations[%d] = %d", i, evaluations[i]);
        }
        
        // Alpha from Rust: qm31!(2, 3, 4, 5)
        QM31Field.QM31 memory alpha = QM31Field.fromM31(2, 3, 4, 5);

        
        // Convert M31 evaluations to QM31 (SecureField)
        QM31Field.QM31[] memory qm31Evaluations = PointEvaluationAccumulator.m31ArrayToQM31Array(evaluations);
        
        // Test 1: Use accumulator (matches Rust accumulator usage)
        console.log("\n--- Testing Accumulator ---");
        PointEvaluationAccumulator.Accumulator memory accumulator = PointEvaluationAccumulator.newAccumulator(alpha);
        
        for (uint256 i = 0; i < logSizes.length; i++) {
            // Note: Rust test zips log_sizes with evaluations but only uses evaluation
            accumulator = PointEvaluationAccumulator.accumulate(accumulator, qm31Evaluations[i]);
        }
        
        QM31Field.QM31 memory accumulatorResult = PointEvaluationAccumulator.finalize(accumulator);
        console.log("Final accumulator result computed.");
        console.log("accumulator result 1 real :", accumulatorResult.first.real);
        console.log("accumulator result 1 imag :", accumulatorResult.first.imag);
        console.log("accumulator result 2 real :", accumulatorResult.second.real);
        console.log("accumulator result 2 imag :", accumulatorResult.second.imag);

        QM31Field.QM31 memory directResult = PointEvaluationAccumulator.directComputation(qm31Evaluations, alpha);

        console.log("\n--- Comparing Results ---");
        bool resultsMatch = (accumulatorResult.first.real == directResult.first.real && 
                           accumulatorResult.first.imag == directResult.first.imag &&
                           accumulatorResult.second.real == directResult.second.real &&
                           accumulatorResult.second.imag == directResult.second.imag);
        console.log("Results match:", resultsMatch);
        
        // Now we have real data, this should pass
        assertTrue(resultsMatch, "Accumulator and direct computation should give same result");
        
        // if (resultsMatch) {
        //     console.log("SUCCESS: Test PASSED: Accumulator matches direct computation");
        // } else {
        //     console.log("FAILED: Test FAILED: Results don't match");
        //     console.log("Difference detected - check implementation or data");
        // }
    }

   
}