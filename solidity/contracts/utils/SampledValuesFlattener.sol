// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../fields/QM31Field.sol";

/// @title SampledValuesFlattener
/// @notice Utility functions for flattening sampled values structures
library SampledValuesFlattener {
    using QM31Field for QM31Field.QM31;

    /// @notice Create real sampled values and flatten them
    /// @dev Creates the same structure as _createRealSampledValues but returns flattened array
    /// @return flattened Flattened array of all sampled values
    function createRealSampledValuesFlattened(uint32[] memory fibValues) 
        internal 
        pure 
        returns (QM31Field.QM31[] memory flattened) 
    {
        // Calculate total length for flattened array
        uint256 totalLength = 0;
        
        // Tree 0: Preprocessed (empty) - contributes 0
        totalLength += 0;
        
        // Tree 1: Trace (51 Fibonacci values) - each value is 1 element
        totalLength += fibValues.length;
        
        // Tree 2: Interaction (4 zero values) - each value is 1 element  
        totalLength += 4;
        
        // Create flattened array
        flattened = new QM31Field.QM31[](totalLength);
        uint256 currentIndex = 0;
        
        // Tree 0: Preprocessed (empty) - nothing to add
        
        // Tree 1: Trace (Fibonacci values)
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

    /// @notice Flatten a 3D QM31 array to 1D
    /// @dev Flattens QM31[][][] to QM31[] by iterating through all dimensions
    /// @param sampledValues 3D array of sampled values
    /// @return flattened 1D array containing all values
    function flatten3D(QM31Field.QM31[][][] memory sampledValues) 
        internal 
        pure 
        returns (QM31Field.QM31[] memory flattened) 
    {
        // First pass: calculate total length
        uint256 totalLength = 0;
        for (uint256 treeIdx = 0; treeIdx < sampledValues.length; treeIdx++) {
            for (uint256 colIdx = 0; colIdx < sampledValues[treeIdx].length; colIdx++) {
                totalLength += sampledValues[treeIdx][colIdx].length;
            }
        }
        
        // Create flattened array
        flattened = new QM31Field.QM31[](totalLength);
        uint256 currentIndex = 0;
        
        // Second pass: copy all values
        for (uint256 treeIdx = 0; treeIdx < sampledValues.length; treeIdx++) {
            for (uint256 colIdx = 0; colIdx < sampledValues[treeIdx].length; colIdx++) {
                for (uint256 valIdx = 0; valIdx < sampledValues[treeIdx][colIdx].length; valIdx++) {
                    flattened[currentIndex] = sampledValues[treeIdx][colIdx][valIdx];
                    currentIndex++;
                }
            }
        }
    }

    /// @notice Get real Fibonacci values for sampled values
    /// @dev Returns the same values as getRealFibonacciValues() but as internal function
    /// @return fibValues Array of Fibonacci values from proof.json
    function getRealFibonacciValues() internal pure returns (uint32[] memory fibValues) {
        fibValues = new uint32[](51);
        fibValues[0] = 1;
        fibValues[1] = 1;
        fibValues[2] = 2;
        fibValues[3] = 3;
        fibValues[4] = 5;
        fibValues[5] = 8;
        fibValues[6] = 13;
        fibValues[7] = 21;
        fibValues[8] = 34;
        fibValues[9] = 55;
        fibValues[10] = 89;
        fibValues[11] = 144;
        fibValues[12] = 233;
        fibValues[13] = 377;
        fibValues[14] = 610;
        fibValues[15] = 987;
        fibValues[16] = 1597;
        fibValues[17] = 2584;
        fibValues[18] = 4181;
        fibValues[19] = 6765;
        fibValues[20] = 10946;
        fibValues[21] = 17711;
        fibValues[22] = 28657;
        fibValues[23] = 46368;
        fibValues[24] = 75025;
        fibValues[25] = 121393;
        fibValues[26] = 196418;
        fibValues[27] = 317811;
        fibValues[28] = 514229;
        fibValues[29] = 832040;
        fibValues[30] = 1346269;
        fibValues[31] = 2178309;
        fibValues[32] = 3524578;
        fibValues[33] = 5702887;
        fibValues[34] = 9227465;
        fibValues[35] = 14930352;
        fibValues[36] = 24157817;
        fibValues[37] = 39088169;
        fibValues[38] = 63245986;
        fibValues[39] = 102334155;
        fibValues[40] = 165580141;
        fibValues[41] = 267914296;
        fibValues[42] = 433494437;
        fibValues[43] = 701408733;
        fibValues[44] = 1134903170;
        fibValues[45] = 1836311903;
        fibValues[46] = 823731426;
        fibValues[47] = 512559682;
        fibValues[48] = 1336291108;
        fibValues[49] = 0;
        fibValues[50] = 0; // Last value for 51 columns
    }
}