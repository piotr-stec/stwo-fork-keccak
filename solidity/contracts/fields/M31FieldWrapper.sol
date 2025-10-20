// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./M31Field.sol";

/**
 * @title M31FieldWrapper
 * @notice Wrapper contract for testing M31Field library functions that can revert
 * @dev This wrapper is needed because Foundry has issues detecting reverts in library functions
 */
contract M31FieldWrapper {
    using M31Field for uint32;

    function inverse(uint32 a) external pure returns (uint32) {
        return M31Field.inverse(a);
    }

    function batchInverse(uint32[] calldata elements) external pure returns (uint32[] memory) {
        return M31Field.batchInverse(elements);
    }

    function add(uint32 a, uint32 b) external pure returns (uint32) {
        return M31Field.add(a, b);
    }

    function mul(uint32 a, uint32 b) external pure returns (uint32) {
        return M31Field.mul(a, b);
    }

    function sub(uint32 a, uint32 b) external pure returns (uint32) {
        return M31Field.sub(a, b);
    }

    function neg(uint32 a) external pure returns (uint32) {
        return M31Field.neg(a);
    }
}