// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./TreeSubspan.sol";

/// @title TraceLocationAllocator
/// @notice Allocates trace locations for constraint framework components
/// @dev Direct port from Rust constraint_framework::component::TraceLocationAllocator
contract TraceLocationAllocator {
    using TreeSubspan for TreeSubspan.Subspan;
    using TreeSubspan for TreeSubspan.TreeSubspanVec;

    // =============================================================================
    // Constants & Types
    // =============================================================================

    /// @notice Preprocessed column allocation modes
    enum PreprocessedColumnsAllocationMode {
        Dynamic,  // Columns allocated dynamically as needed
        Static    // Columns pre-allocated in constructor
    }

    /// @notice Preprocessed column identifier
    /// @param id String identifier for the column
    /// @param logSize Log size of the column
    /// @param description Human-readable description
    struct PreProcessedColumnId {
        string id;
        uint32 logSize;
        string description;
    }

    // =============================================================================
    // State Variables (matching Rust implementation)
    // =============================================================================

    /// @notice Mapping of tree index to next available column offset
    /// @dev Maps to: next_tree_offsets: TreeVec<usize>
    mapping(uint256 => uint256) public nextTreeOffsets;

    /// @notice Number of trees currently tracked
    uint256 public numTrees;

    /// @notice Mapping of preprocessed columns to their index
    /// @dev Maps to: preprocessed_columns: Vec<PreProcessedColumnId>
    PreProcessedColumnId[] public preprocessedColumns;

    /// @notice Controls whether preprocessed columns are dynamic or static
    /// @dev Maps to: preprocessed_columns_allocation_mode: PreprocessedColumnsAllocationMode
    PreprocessedColumnsAllocationMode public preprocessedColumnsAllocationMode;

    // =============================================================================
    // Events
    // =============================================================================

    event TraceLocationAllocated(
        uint256 indexed componentId,
        uint256 treeIndex,
        uint256 colStart,
        uint256 colEnd
    );

    event PreprocessedColumnAdded(
        string indexed columnId,
        uint256 indexed columnIndex,
        uint32 logSize
    );

    // =============================================================================
    // Constructor & Initialization
    // =============================================================================

    /// @notice Create new TraceLocationAllocator with dynamic preprocessed columns
    /// @dev Maps to: TraceLocationAllocator::default()
    constructor() {
        preprocessedColumnsAllocationMode = PreprocessedColumnsAllocationMode.Dynamic;
        numTrees = 0;
    }

    /// @notice Create TraceLocationAllocator with fixed preprocessed columns
    /// @dev Maps to: TraceLocationAllocator::new_with_preprocessed_columns(preprocessed_columns)
    /// @param _preprocessedColumns Array of preprocessed column definitions
    function initializeWithPreprocessedColumns(
        PreProcessedColumnId[] memory _preprocessedColumns
    ) external {
        require(
            preprocessedColumns.length == 0, 
            "Preprocessed columns already initialized"
        );
        
        // Validate uniqueness
        for (uint256 i = 0; i < _preprocessedColumns.length; i++) {
            for (uint256 j = i + 1; j < _preprocessedColumns.length; j++) {
                require(
                    keccak256(bytes(_preprocessedColumns[i].id)) != 
                    keccak256(bytes(_preprocessedColumns[j].id)),
                    "Duplicate preprocessed columns are not allowed"
                );
            }
        }

        // Store preprocessed columns
        for (uint256 i = 0; i < _preprocessedColumns.length; i++) {
            preprocessedColumns.push(_preprocessedColumns[i]);
            emit PreprocessedColumnAdded(
                _preprocessedColumns[i].id,
                i,
                _preprocessedColumns[i].logSize
            );
        }

        preprocessedColumnsAllocationMode = PreprocessedColumnsAllocationMode.Static;
    }

    // =============================================================================
    // Core Allocation Functions
    // =============================================================================

    /// @notice Allocate trace locations for component structure
    /// @dev Maps to: next_for_structure<T>(&mut self, structure: &TreeVec<ColumnVec<T>>) -> TreeVec<TreeSubspan>
    /// @param treeSizes Array representing structure as TreeVec<ColumnVec<T>>
    /// @param componentId Unique identifier for the component
    /// @return traceLocations Array of TreeSubspan for allocated locations
    function nextForStructure(
        uint256[] memory treeSizes,
        uint256 componentId
    ) external returns (TreeSubspan.Subspan[] memory traceLocations) {
        
        // Ensure we have enough trees tracked
        uint256 requiredTrees = treeSizes.length;
        if (requiredTrees > numTrees) {
            numTrees = requiredTrees;
        }

        traceLocations = new TreeSubspan.Subspan[](treeSizes.length);

        for (uint256 treeIndex = 0; treeIndex < treeSizes.length; treeIndex++) {
            uint256 colStart = nextTreeOffsets[treeIndex];
            uint256 colEnd = colStart + treeSizes[treeIndex];
            
            // Allocate trace location
            traceLocations[treeIndex] = TreeSubspan.newSubspan(
                treeIndex,
                colStart,
                colEnd
            );

            // Update next available offset for this tree
            nextTreeOffsets[treeIndex] = colEnd;

            emit TraceLocationAllocated(componentId, treeIndex, colStart, colEnd);
        }

        return traceLocations;
    }

    /// @notice Get or add preprocessed column index
    /// @dev Maps to logic within FrameworkComponent::new for preprocessed_column_indices
    /// @param columnId Preprocessed column to get/add
    /// @return columnIndex Index of the preprocessed column
    function getPreprocessedColumnIndex(PreProcessedColumnId memory columnId)
        external
        returns (uint256 columnIndex)
    {
        // Look for existing column
        for (uint256 i = 0; i < preprocessedColumns.length; i++) {
            if (keccak256(bytes(preprocessedColumns[i].id)) == keccak256(bytes(columnId.id))) {
                return i;
            }
        }

        // If not found, add new column (only in dynamic mode)
        if (preprocessedColumnsAllocationMode == PreprocessedColumnsAllocationMode.Static) {
            revert("Preprocessed column missing from static allocation");
        }

        // Add new column
        uint256 newIndex = preprocessedColumns.length;
        preprocessedColumns.push(columnId);
        
        emit PreprocessedColumnAdded(columnId.id, newIndex, columnId.logSize);
        
        return newIndex;
    }

    /// @notice Get multiple preprocessed column indices
    /// @param columnIds Array of preprocessed columns to get/add
    /// @return columnIndices Array of indices for the preprocessed columns
    function getPreprocessedColumnIndices(PreProcessedColumnId[] memory columnIds)
        external
        returns (uint256[] memory columnIndices)
    {
        columnIndices = new uint256[](columnIds.length);
        
        for (uint256 i = 0; i < columnIds.length; i++) {
            columnIndices[i] = this.getPreprocessedColumnIndex(columnIds[i]);
        }
        
        return columnIndices;
    }

    // =============================================================================
    // Getter Functions
    // =============================================================================

    /// @notice Get all preprocessed columns
    /// @dev Maps to: preprocessed_columns(&self) -> &Vec<PreProcessedColumnId>
    /// @return columns Array of all preprocessed columns
    function getPreprocessedColumns() 
        external 
        view 
        returns (PreProcessedColumnId[] memory columns) 
    {
        return preprocessedColumns;
    }

    /// @notice Get specific preprocessed column
    /// @param index Index of the preprocessed column
    /// @return column Preprocessed column at index
    function getPreprocessedColumn(uint256 index)
        external
        view
        returns (PreProcessedColumnId memory column)
    {
        require(index < preprocessedColumns.length, "Index out of bounds");
        return preprocessedColumns[index];
    }

    /// @notice Get next available offset for a tree
    /// @param treeIndex Index of the tree
    /// @return nextOffset Next available column offset
    function getNextTreeOffset(uint256 treeIndex) 
        external 
        view 
        returns (uint256 nextOffset) 
    {
        return nextTreeOffsets[treeIndex];
    }

    /// @notice Get number of preprocessed columns
    /// @return count Number of preprocessed columns
    function getPreprocessedColumnsCount() external view returns (uint256 count) {
        return preprocessedColumns.length;
    }

    /// @notice Get allocation mode
    /// @return mode Current allocation mode
    function getAllocationMode() 
        external 
        view 
        returns (PreprocessedColumnsAllocationMode mode) 
    {
        return preprocessedColumnsAllocationMode;
    }

    // =============================================================================
    // Validation Functions
    // =============================================================================

    /// @notice Validate preprocessed columns against expected set
    /// @dev Maps to: validate_preprocessed_columns(&self, preprocessed_columns: &[PreProcessedColumnId])
    /// @param expectedColumns Expected preprocessed columns
    /// @return isValid True if current columns match expected
    /// @return errorMessage Error description if validation fails
    function validatePreprocessedColumns(PreProcessedColumnId[] memory expectedColumns)
        external
        view
        returns (bool isValid, string memory errorMessage)
    {
        if (preprocessedColumns.length != expectedColumns.length) {
            return (false, "Preprocessed columns count mismatch");
        }

        // Create sorted arrays for comparison
        string[] memory currentIds = new string[](preprocessedColumns.length);
        string[] memory expectedIds = new string[](expectedColumns.length);

        for (uint256 i = 0; i < preprocessedColumns.length; i++) {
            currentIds[i] = preprocessedColumns[i].id;
        }

        for (uint256 i = 0; i < expectedColumns.length; i++) {
            expectedIds[i] = expectedColumns[i].id;
        }

        // Simple validation - in production would need proper sorting
        for (uint256 i = 0; i < currentIds.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < expectedIds.length; j++) {
                if (keccak256(bytes(currentIds[i])) == keccak256(bytes(expectedIds[j]))) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return (false, "Preprocessed columns are not a permutation");
            }
        }

        return (true, "Preprocessed columns validation passed");
    }

    // =============================================================================
    // Utility Functions
    // =============================================================================

    /// @notice Reset allocator state (for testing)
    function reset() external {
        // Clear tree offsets
        for (uint256 i = 0; i < numTrees; i++) {
            nextTreeOffsets[i] = 0;
        }
        numTrees = 0;

        // Clear preprocessed columns (only in dynamic mode)
        if (preprocessedColumnsAllocationMode == PreprocessedColumnsAllocationMode.Dynamic) {
            delete preprocessedColumns;
        }
    }

    /// @notice Get current allocation summary
    /// @return totalTrees Number of trees being tracked
    /// @return treeOffsets Current offsets for each tree
    /// @return totalPreprocessedColumns Number of preprocessed columns
    function getAllocationSummary()
        external
        view
        returns (
            uint256 totalTrees,
            uint256[] memory treeOffsets,
            uint256 totalPreprocessedColumns
        )
    {
        totalTrees = numTrees;
        treeOffsets = new uint256[](numTrees);
        
        for (uint256 i = 0; i < numTrees; i++) {
            treeOffsets[i] = nextTreeOffsets[i];
        }
        
        totalPreprocessedColumns = preprocessedColumns.length;
    }
}