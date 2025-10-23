// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../fields/QM31Field.sol";

/**
 * @title IChannel
 * @notice Interface for STWO verifier channels
 * @dev Channels provide cryptographic randomness and mixing for STARK proof verification
 */
interface IChannel {
    /**
     * @notice Number of bytes produced by the underlying hash function
     */
    function BYTES_PER_HASH() external pure returns (uint256);
    
    /**
     * @notice Verify proof-of-work nonce
     * @param nBits Number of leading zero bits required
     * @param nonce Proposed nonce value
     * @return valid True if nonce satisfies PoW requirement
     */
    function verifyPowNonce(uint32 nBits, uint64 nonce) external view returns (bool valid);
    
    /**
     * @notice Mix array of u32 values into channel state
     * @param data Array of 32-bit values to mix
     */
    function mixU32s(uint32[] calldata data) external;
    
    /**
     * @notice Mix secure field elements into channel state
     * @param felts Array of QM31 field elements to mix
     */
    function mixFelts(QM31Field.QM31[] calldata felts) external;
    
    /**
     * @notice Mix single u64 value into channel state
     * @param value 64-bit value to mix
     */
    function mixU64(uint64 value) external;
    
    /**
     * @notice Draw random secure field element
     * @return felt Random QM31 field element
     */
    function drawSecureFelt() external returns (QM31Field.QM31 memory felt);
    
    /**
     * @notice Draw multiple random secure field elements
     * @param nFelts Number of field elements to draw
     * @return felts Array of random QM31 field elements
     */
    function drawSecureFelts(uint256 nFelts) external returns (QM31Field.QM31[] memory felts);
    
    /**
     * @notice Draw random u32 values
     * @return values Array of random 32-bit values (length depends on hash function)
     */
    function drawU32s() external returns (uint32[] memory values);
    
    /**
     * @notice Get current channel digest
     * @return digest Current hash digest state
     */
    function getDigest() external view returns (bytes32 digest);
    
    /**
     * @notice Mix two elements sequentially (digest, commitment)
     * @param currentDigest Current digest state
     * @param commitment Commitment to mix
     * @return newDigest Updated digest after mixing
     */
    function mixRoot(bytes32 currentDigest, bytes32 commitment) external returns (bytes32 newDigest);
}