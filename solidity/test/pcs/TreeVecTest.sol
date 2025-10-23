// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/pcs/TreeVec.sol";

/// @title TreeVecTest
/// @notice TDD tests for TreeVec library functionality
contract TreeVecTest is Test {
    using TreeVec for TreeVec.Bytes32TreeVec;
    using TreeVec for TreeVec.Uint32ArrayTreeVec;
    using TreeVec for TreeVec.Uint256TreeVec;

    /// @notice Test basic TreeVec creation and operations
    function testBytes32TreeVecBasics() public pure {
        // Test empty creation
        TreeVec.Bytes32TreeVec memory treeVec = TreeVec.newBytes32();
        assertEq(treeVec.length(), 0, "New TreeVec should be empty");
        assertTrue(treeVec.isEmpty(), "New TreeVec should report as empty");

        // Test push operation
        bytes32 value1 = keccak256("test1");
        treeVec = treeVec.push(value1);
        assertEq(treeVec.length(), 1, "TreeVec should have 1 element after push");
        assertFalse(treeVec.isEmpty(), "TreeVec should not be empty after push");
        assertEq(treeVec.get(0), value1, "First element should match pushed value");

        // Test multiple pushes
        bytes32 value2 = keccak256("test2");
        bytes32 value3 = keccak256("test3");
        treeVec = treeVec.push(value2);
        treeVec = treeVec.push(value3);
        
        assertEq(treeVec.length(), 3, "TreeVec should have 3 elements");
        assertEq(treeVec.get(0), value1, "First element should be preserved");
        assertEq(treeVec.get(1), value2, "Second element should match");
        assertEq(treeVec.get(2), value3, "Third element should match");
    }

    /// @notice Test TreeVec creation from array
    function testFromArray() public pure {
        bytes32[] memory data = new bytes32[](3);
        data[0] = keccak256("item0");
        data[1] = keccak256("item1");
        data[2] = keccak256("item2");

        TreeVec.Bytes32TreeVec memory treeVec = TreeVec.fromBytes32Array(data);
        
        assertEq(treeVec.length(), 3, "TreeVec should have same length as source array");
        for (uint256 i = 0; i < data.length; i++) {
            assertEq(treeVec.get(i), data[i], "Element should match source array");
        }
    }

    /// @notice Test TreeVec set operation
    function testSetOperation() public pure {
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256("original0");
        data[1] = keccak256("original1");

        TreeVec.Bytes32TreeVec memory treeVec = TreeVec.fromBytes32Array(data);
        
        bytes32 newValue = keccak256("modified");
        treeVec.set(1, newValue);
        
        assertEq(treeVec.get(0), data[0], "Unmodified element should remain unchanged");
        assertEq(treeVec.get(1), newValue, "Modified element should have new value");
    }

    /// @notice Test TreeVec error conditions
    function testErrorConditions() public {
        TreeVec.Bytes32TreeVec memory treeVec = TreeVec.newBytes32();
        
        // Test invalid index access on empty TreeVec
        try this._testGetInvalidIndex(treeVec, 0) {
            fail("Should have reverted");
        } catch (bytes memory reason) {
            // Check that it's the correct custom error
            bytes4 selector = bytes4(reason);
            assertEq(selector, TreeVec.InvalidTreeIndex.selector, "Should be InvalidTreeIndex error");
        }
        
        // Add element and test out of bounds
        treeVec = treeVec.push(keccak256("test"));
        
        try this._testGetInvalidIndex(treeVec, 1) {
            fail("Should have reverted");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, TreeVec.InvalidTreeIndex.selector, "Should be InvalidTreeIndex error");
        }
        
        try this._testSetInvalidIndex(treeVec, 1, keccak256("invalid")) {
            fail("Should have reverted");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, TreeVec.InvalidTreeIndex.selector, "Should be InvalidTreeIndex error");
        }
    }
    
    function _testGetInvalidIndex(TreeVec.Bytes32TreeVec memory treeVec, uint256 index) external pure {
        treeVec.get(index);
    }
    
    function _testSetInvalidIndex(TreeVec.Bytes32TreeVec memory treeVec, uint256 index, bytes32 value) external pure {
        treeVec.set(index, value);
    }

    /// @notice Test Uint32Array TreeVec operations
    function testUint32ArrayTreeVec() public pure {
        TreeVec.Uint32ArrayTreeVec memory treeVec = TreeVec.newUint32Array();
        
        // Create test arrays
        uint32[] memory array1 = new uint32[](3);
        array1[0] = 10;
        array1[1] = 20;
        array1[2] = 30;
        
        uint32[] memory array2 = new uint32[](2);
        array2[0] = 100;
        array2[1] = 200;
        
        // Test push operations
        treeVec = treeVec.push(array1);
        treeVec = treeVec.push(array2);
        
        assertEq(treeVec.length(), 2, "Should have 2 arrays");
        
        // Test retrieval
        uint32[] memory retrieved1 = treeVec.get(0);
        uint32[] memory retrieved2 = treeVec.get(1);
        
        assertEq(retrieved1.length, 3, "First array should have 3 elements");
        assertEq(retrieved1[0], 10, "First array first element");
        assertEq(retrieved1[1], 20, "First array second element");
        assertEq(retrieved1[2], 30, "First array third element");
        
        assertEq(retrieved2.length, 2, "Second array should have 2 elements");
        assertEq(retrieved2[0], 100, "Second array first element");
        assertEq(retrieved2[1], 200, "Second array second element");
    }

    /// @notice Test Uint256 TreeVec operations
    function testUint256TreeVec() public pure {
        TreeVec.Uint256TreeVec memory treeVec = TreeVec.newUint256();
        
        uint256 value1 = 12345;
        uint256 value2 = 67890;
        
        treeVec = treeVec.push(value1);
        treeVec = treeVec.push(value2);
        
        assertEq(treeVec.length(), 2, "Should have 2 elements");
        assertEq(treeVec.get(0), value1, "First element should match");
        assertEq(treeVec.get(1), value2, "Second element should match");
    }

    /// @notice Test TreeVec utility functions
    function testUtilityFunctions() public pure {
        // Test withCapacity
        TreeVec.Bytes32TreeVec memory treeVec = TreeVec.withCapacity(5);
        assertEq(treeVec.length(), 5, "Should have specified capacity");
        
        // Test flatten
        bytes32[] memory data = new bytes32[](3);
        data[0] = keccak256("a");
        data[1] = keccak256("b");
        data[2] = keccak256("c");
        
        treeVec = TreeVec.fromBytes32Array(data);
        bytes32[] memory flattened = treeVec.flatten();
        
        assertEq(flattened.length, 3, "Flattened should have same length");
        for (uint256 i = 0; i < data.length; i++) {
            assertEq(flattened[i], data[i], "Flattened element should match");
        }
    }

    /// @notice Test TreeVec with real commitment scheme data
    function testCommitmentSchemeUsage() public pure {
        // Simulate commitment tree roots
        TreeVec.Bytes32TreeVec memory commitmentRoots = TreeVec.newBytes32();
        
        bytes32 treeRoot1 = keccak256("tree1_commitment");
        bytes32 treeRoot2 = keccak256("tree2_commitment");
        bytes32 treeRoot3 = keccak256("tree3_commitment");
        
        commitmentRoots = commitmentRoots.push(treeRoot1);
        commitmentRoots = commitmentRoots.push(treeRoot2);
        commitmentRoots = commitmentRoots.push(treeRoot3);
        
        // Verify structure
        assertEq(commitmentRoots.length(), 3, "Should have 3 commitment trees");
        assertEq(commitmentRoots.get(0), treeRoot1, "First tree root");
        assertEq(commitmentRoots.get(1), treeRoot2, "Second tree root");
        assertEq(commitmentRoots.get(2), treeRoot3, "Third tree root");
        
        // Simulate column log sizes for each tree
        TreeVec.Uint32ArrayTreeVec memory columnLogSizes = TreeVec.newUint32Array();
        
        uint32[] memory tree1Sizes = new uint32[](2);
        tree1Sizes[0] = 10; // 2^10 = 1024 elements
        tree1Sizes[1] = 12; // 2^12 = 4096 elements
        
        uint32[] memory tree2Sizes = new uint32[](1);
        tree2Sizes[0] = 8;  // 2^8 = 256 elements
        
        uint32[] memory tree3Sizes = new uint32[](3);
        tree3Sizes[0] = 15; // 2^15 = 32768 elements
        tree3Sizes[1] = 10;
        tree3Sizes[2] = 10;
        
        columnLogSizes = columnLogSizes.push(tree1Sizes);
        columnLogSizes = columnLogSizes.push(tree2Sizes);
        columnLogSizes = columnLogSizes.push(tree3Sizes);
        
        // Verify column configurations
        assertEq(columnLogSizes.length(), 3, "Should have configs for 3 trees");
        
        uint32[] memory retrievedTree1 = columnLogSizes.get(0);
        assertEq(retrievedTree1.length, 2, "Tree 1 should have 2 columns");
        assertEq(retrievedTree1[0], 10, "Tree 1 column 0 log size");
        assertEq(retrievedTree1[1], 12, "Tree 1 column 1 log size");
        
        uint32[] memory retrievedTree2 = columnLogSizes.get(1);
        assertEq(retrievedTree2.length, 1, "Tree 2 should have 1 column");
        assertEq(retrievedTree2[0], 8, "Tree 2 column 0 log size");
        
        uint32[] memory retrievedTree3 = columnLogSizes.get(2);
        assertEq(retrievedTree3.length, 3, "Tree 3 should have 3 columns");
        assertEq(retrievedTree3[0], 15, "Tree 3 column 0 log size");
        assertEq(retrievedTree3[1], 10, "Tree 3 column 1 log size");
        assertEq(retrievedTree3[2], 10, "Tree 3 column 2 log size");
    }

    /// @notice Test performance with larger datasets
    function testLargeDataset() public pure {
        TreeVec.Bytes32TreeVec memory treeVec = TreeVec.newBytes32();
        
        // Add 100 elements
        for (uint256 i = 0; i < 100; i++) {
            bytes32 value = keccak256(abi.encodePacked("element", i));
            treeVec = treeVec.push(value);
        }
        
        assertEq(treeVec.length(), 100, "Should have 100 elements");
        
        // Verify all elements
        for (uint256 i = 0; i < 100; i++) {
            bytes32 expected = keccak256(abi.encodePacked("element", i));
            assertEq(treeVec.get(i), expected, "Element should match expected value");
        }
    }
}