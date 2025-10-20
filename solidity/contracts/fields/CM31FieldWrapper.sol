// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./CM31Field.sol";

/**
 * @title CM31FieldWrapper
 * @notice Wrapper contract for testing CM31Field library functions that can revert
 * @dev This wrapper is needed because Foundry has issues detecting reverts in library functions
 */
contract CM31FieldWrapper {
    using CM31Field for CM31Field.CM31;

    /// @notice Wrapper for inverse function
    function inverse(uint32 real, uint32 imag) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory result = CM31Field.inverse(a);
        return (result.real, result.imag);
    }

    /// @notice Wrapper for division function
    function div(
        uint32 aReal, uint32 aImag,
        uint32 bReal, uint32 bImag
    ) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        CM31Field.CM31 memory result = CM31Field.div(a, b);
        return (result.real, result.imag);
    }

    /// @notice Wrapper for divScalar function
    function divScalar(uint32 real, uint32 imag, uint32 scalar) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory result = CM31Field.divScalar(a, scalar);
        return (result.real, result.imag);
    }

    /// @notice Wrapper for batchInverse function
    function batchInverse(
        uint32[] calldata reals,
        uint32[] calldata imags
    ) external pure returns (uint32[] memory resultReals, uint32[] memory resultImags) {
        require(reals.length == imags.length, "Array length mismatch");
        
        CM31Field.CM31[] memory elements = new CM31Field.CM31[](reals.length);
        for (uint256 i = 0; i < reals.length; i++) {
            elements[i] = CM31Field.fromM31(reals[i], imags[i]);
        }
        
        CM31Field.CM31[] memory inverses = CM31Field.batchInverse(elements);
        
        resultReals = new uint32[](inverses.length);
        resultImags = new uint32[](inverses.length);
        
        for (uint256 i = 0; i < inverses.length; i++) {
            resultReals[i] = inverses[i].real;
            resultImags[i] = inverses[i].imag;
        }
    }

    /// @notice Helper functions for testing basic operations (non-reverting)
    function add(
        uint32 aReal, uint32 aImag,
        uint32 bReal, uint32 bImag
    ) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        CM31Field.CM31 memory result = CM31Field.add(a, b);
        return (result.real, result.imag);
    }

    function mul(
        uint32 aReal, uint32 aImag,
        uint32 bReal, uint32 bImag
    ) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        CM31Field.CM31 memory result = CM31Field.mul(a, b);
        return (result.real, result.imag);
    }

    function sub(
        uint32 aReal, uint32 aImag,
        uint32 bReal, uint32 bImag
    ) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(aReal, aImag);
        CM31Field.CM31 memory b = CM31Field.fromM31(bReal, bImag);
        CM31Field.CM31 memory result = CM31Field.sub(a, b);
        return (result.real, result.imag);
    }

    function neg(uint32 real, uint32 imag) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory result = CM31Field.neg(a);
        return (result.real, result.imag);
    }

    function conjugate(uint32 real, uint32 imag) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory result = CM31Field.conjugate(a);
        return (result.real, result.imag);
    }

    function norm(uint32 real, uint32 imag) external pure returns (uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        return CM31Field.norm(a);
    }

    function mulScalar(uint32 real, uint32 imag, uint32 scalar) external pure returns (uint32, uint32) {
        CM31Field.CM31 memory a = CM31Field.fromM31(real, imag);
        CM31Field.CM31 memory result = CM31Field.mulScalar(a, scalar);
        return (result.real, result.imag);
    }
}