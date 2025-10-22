// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IChannel.sol";
import "../fields/M31Field.sol";
import "../fields/QM31Field.sol";

/**
 * @title KeccakChannel
 * @notice STWO verifier channel using native EVM keccak256 for optimal gas efficiency
 * @dev Uses keccak256 (~36 gas) instead of Blake2s (~263k gas) for dramatic cost reduction
 */
contract KeccakChannel is IChannel {
    using M31Field for uint32;
    using QM31Field for uint256[4];
    
    // Channel state
    bytes32 private digest;
    uint32 private nDraws;
    
    // Constants matching STWO protocol
    uint32 private constant POW_PREFIX = 0x12345678;
    uint256 private constant KECCAK_BYTES_PER_HASH = 32;
    uint256 private constant FELTS_PER_HASH = 8;
    uint256 private constant SECURE_EXTENSION_DEGREE = 4;
    
    /**
     * @notice Initialize channel with zero digest
     */
    constructor() {
        digest = bytes32(0);
        nDraws = 0;
    }
    
    /**
     * @notice Get current digest state
     */
    function getDigest() external view returns (bytes32) {
        return digest;
    }
    
    /**
     * @notice Update digest and reset draw counter
     */
    function updateDigest(bytes32 newDigest) external {
        digest = newDigest;
        nDraws = 0;
    }
    
    /**
     * @notice Number of bytes produced by keccak256
     */
    function BYTES_PER_HASH() external pure override returns (uint256) {
        return KECCAK_BYTES_PER_HASH;
    }
    
    /**
     * @notice Mix array of u32 values using keccak256
     */
    function mixU32s(uint32[] calldata data) external override {
        bytes memory input = abi.encodePacked(digest);
        
        // Append u32 values in little-endian format (matching Rust)
        for (uint256 i = 0; i < data.length; i++) {
            input = abi.encodePacked(input, _u32ToLittleEndian(data[i]));
        }
        
        digest = keccak256(input);
        nDraws = 0;
    }
    
    /**
     * @notice Mix secure field elements using keccak256
     */
    function mixFelts(QM31Field.QM31[] calldata felts) external override {
        bytes memory input = abi.encodePacked(digest);
        
        // Convert QM31 elements to M31 array and encode as little-endian bytes
        for (uint256 i = 0; i < felts.length; i++) {
            uint32[4] memory m31Array = QM31Field.toM31Array(felts[i]);
            for (uint256 j = 0; j < 4; j++) {
                input = abi.encodePacked(input, _u32ToLittleEndian(m31Array[j]));
            }
        }
        
        digest = keccak256(input);
        nDraws = 0;
    }
    
    /**
     * @notice Mix u64 value by splitting into two u32s
     */
    function mixU64(uint64 value) external override {
        uint32[] memory u32s = new uint32[](2);
        u32s[0] = uint32(value);        // Lower 32 bits
        u32s[1] = uint32(value >> 32);  // Upper 32 bits
        this.mixU32s(u32s);
    }
    
    /**
     * @notice Draw random secure field element
     */
    function drawSecureFelt() external override returns (QM31Field.QM31 memory) {
        uint32[FELTS_PER_HASH] memory basefelts = _drawBaseFelts();
        
        // Take first 4 elements for QM31 (SECURE_EXTENSION_DEGREE = 4)
        uint32[4] memory secureArray;
        for (uint256 i = 0; i < SECURE_EXTENSION_DEGREE; i++) {
            secureArray[i] = basefelts[i];
        }
        
        return QM31Field.fromM31Array(secureArray);
    }
    
    /**
     * @notice Draw multiple random secure field elements
     */
    function drawSecureFelts(uint256 nFelts) external override returns (QM31Field.QM31[] memory) {
        QM31Field.QM31[] memory result = new QM31Field.QM31[](nFelts);
        
        uint256 feltsGenerated = 0;
        uint32[FELTS_PER_HASH] memory currentBatch;
        uint256 batchIndex = FELTS_PER_HASH; // Force initial generation
        
        for (uint256 i = 0; i < nFelts; i++) {
            // Generate new batch if needed
            if (batchIndex + SECURE_EXTENSION_DEGREE > FELTS_PER_HASH) {
                currentBatch = _drawBaseFelts();
                batchIndex = 0;
            }
            
            // Extract 4 M31 elements for QM31
            uint32[4] memory secureArray;
            for (uint256 j = 0; j < SECURE_EXTENSION_DEGREE; j++) {
                secureArray[j] = currentBatch[batchIndex + j];
            }
            
            result[i] = QM31Field.fromM31Array(secureArray);
            batchIndex += SECURE_EXTENSION_DEGREE;
        }
        
        return result;
    }
    
    /**
     * @notice Draw random u32 values from current state
     */
    function drawU32s() external override returns (uint32[] memory) {
        bytes memory input = abi.encodePacked(
            digest,
            _u32ToLittleEndian(nDraws),
            uint8(0) // Domain separation byte
        );
        
        nDraws++;
        bytes32 hash = keccak256(input);
        
        // Extract 8 u32 values from 32-byte hash (like Blake2s)
        uint32[] memory result = new uint32[](FELTS_PER_HASH);
        for (uint256 i = 0; i < FELTS_PER_HASH; i++) {
            // Extract 4-byte chunks in little-endian order
            uint256 offset = i * 4;
            result[i] = uint32(uint8(hash[offset])) |
                       (uint32(uint8(hash[offset + 1])) << 8) |
                       (uint32(uint8(hash[offset + 2])) << 16) |
                       (uint32(uint8(hash[offset + 3])) << 24);
        }
        
        return result;
    }
    
    /**
     * @notice Verify proof-of-work nonce
     * @dev Verifies H(H(POW_PREFIX, padding, digest, nBits), nonce) has nBits leading zeros
     */
    function verifyPowNonce(uint32 nBits, uint64 nonce) external view override returns (bool) {
        // First hash: H(POW_PREFIX, padding, digest, nBits)
        bytes memory prefixInput = abi.encodePacked(
            _u32ToLittleEndian(POW_PREFIX),
            new bytes(24), // 24 zero bytes padding (matching Blake2s implementation)
            digest,
            _u32ToLittleEndian(nBits)
        );
        bytes32 prefixedDigest = keccak256(prefixInput);
        
        // Second hash: H(prefixedDigest, nonce)
        bytes memory finalInput = abi.encodePacked(
            prefixedDigest,
            _u64ToLittleEndian(nonce)
        );
        bytes32 finalHash = keccak256(finalInput);
        
        // Count trailing zeros in little-endian interpretation
        uint256 trailingZeros = _countTrailingZeros(finalHash);
        
        return trailingZeros >= nBits;
    }
    
    /**
     * @notice Generate uniform random M31 field elements
     * @dev Retries until all values are in valid range [0, 2*P)
     */
    function _drawBaseFelts() internal returns (uint32[FELTS_PER_HASH] memory) {
        uint32 maxRetries = 100; // Prevent infinite loops
        uint32 retries = 0;
        
        while (retries < maxRetries) {
            uint32[] memory u32s = this.drawU32s();
            
            // Check if all values are in valid M31 range [0, 2*P)
            bool allValid = true;
            for (uint256 i = 0; i < FELTS_PER_HASH; i++) {
                if (u32s[i] >= 2 * M31Field.MODULUS) {
                    allValid = false;
                    break;
                }
            }
            
            if (allValid) {
                uint32[FELTS_PER_HASH] memory result;
                for (uint256 i = 0; i < FELTS_PER_HASH; i++) {
                    result[i] = M31Field.reduce(uint64(u32s[i]));
                }
                return result;
            }
            
            retries++;
        }
        
        // Fallback: force valid values (should be extremely rare)
        revert("KeccakChannel: Failed to generate valid base felts");
    }
    
    /**
     * @notice Convert u32 to little-endian bytes
     */
    function _u32ToLittleEndian(uint32 value) internal pure returns (bytes4) {
        return bytes4(
            bytes1(uint8(value)) |
            (bytes1(uint8(value >> 8)) << 8) |
            (bytes1(uint8(value >> 16)) << 16) |
            (bytes1(uint8(value >> 24)) << 24)
        );
    }
    
    /**
     * @notice Convert u64 to little-endian bytes
     */
    function _u64ToLittleEndian(uint64 value) internal pure returns (bytes8) {
        return bytes8(
            _u32ToLittleEndian(uint32(value)) |
            (bytes8(_u32ToLittleEndian(uint32(value >> 32))) << 32)
        );
    }
    
    /**
     * @notice Count trailing zeros in hash (little-endian interpretation)
     */
    function _countTrailingZeros(bytes32 hash) internal pure returns (uint256) {
        uint256 zeros = 0;
        
        // Process hash as little-endian uint256
        uint256 value = 0;
        for (uint256 i = 0; i < 32; i++) {
            value |= uint256(uint8(hash[i])) << (i * 8);
        }
        
        // Count trailing zeros
        if (value == 0) {
            return 256;
        }
        
        while ((value & 1) == 0) {
            value >>= 1;
            zeros++;
        }
        
        return zeros;
    }
}