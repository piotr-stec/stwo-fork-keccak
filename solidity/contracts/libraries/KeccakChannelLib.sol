// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../channel/IChannel.sol";
import "../fields/M31Field.sol";
import "../fields/QM31Field.sol";

/**
 * @title KeccakChannelLib
 * @notice Library for STWO verifier channel using native EVM keccak256 for optimal gas efficiency
 * @dev Uses keccak256 (~36 gas) instead of Blake2s (~263k gas) for dramatic cost reduction
 */
library KeccakChannelLib {
    using M31Field for uint32;
    using QM31Field for uint256[4];
    
    /// @notice Channel state structure
    /// @param digest Current channel digest
    /// @param nDraws Number of draws performed
    struct ChannelState {
        bytes32 digest;
        uint32 nDraws;
    }
    
    // Constants matching STWO protocol
    uint32 private constant POW_PREFIX = 0x12345678;
    uint256 private constant KECCAK_BYTES_PER_HASH = 32;
    uint256 private constant FELTS_PER_HASH = 8;
    uint256 private constant SECURE_EXTENSION_DEGREE = 4;
    
    /// @notice Initialize channel state with zero digest
    /// @param state Channel state to initialize
    function initialize(ChannelState storage state) internal {
        state.digest = bytes32(0);
        state.nDraws = 0;
    }
    
    /// @notice Initialize channel state with specific digest and draw counter
    /// @param state Channel state to initialize
    /// @param digest Initial digest value
    /// @param nDraws Initial number of draws
    function initializeWith(ChannelState storage state, bytes32 digest, uint32 nDraws) internal {
        state.digest = digest;
        state.nDraws = nDraws;
    }
    
    /// @notice Clear channel state after verification
    /// @param state Channel state to clear
    function clearState(ChannelState storage state) internal {
        state.digest = bytes32(0);
        state.nDraws = 0;
    }
    
    /// @notice Update digest and reset draw counter
    /// @param state Channel state
    /// @param newDigest New digest value
    function updateDigest(ChannelState storage state, bytes32 newDigest) internal {
        state.digest = newDigest;
        state.nDraws = 0;
    }
    
    /// @notice Number of bytes produced by keccak256
    function BYTES_PER_HASH() internal pure returns (uint256) {
        return KECCAK_BYTES_PER_HASH;
    }
    
    /// @notice Mix array of u32 values using keccak256
    /// @param state Channel state
    /// @param data U32 array to mix
    function mixU32s(ChannelState storage state, uint32[] memory data) internal {
        bytes memory input = abi.encodePacked(state.digest);
        
        // Append u32 values in little-endian format (matching Rust)
        for (uint256 i = 0; i < data.length; i++) {
            input = abi.encodePacked(input, _u32ToLittleEndian(data[i]));
        }
        
        state.digest = keccak256(input);
        state.nDraws = 0;
    }
    
    /// @notice Mix array of QM31 field elements into channel
    /// @dev Matches Rust implementation exactly:
    ///      let felts_bytes = felts.iter().flat_map(|qm31| qm31.to_m31_array()).flat_map(|m31| m31.0.to_le_bytes()).collect_vec();
    ///      hasher.update(self.digest); hasher.update(&felts_bytes); self.update_digest(hasher.finalize())
    /// @param state Channel state to update
    /// @param felts Array of QM31 field elements to mix
    function mixFelts(ChannelState storage state, QM31Field.QM31[] memory felts) internal {
        // Step 1: Convert all felts to bytes (matches felts_bytes collection in Rust)
        // felts.iter().flat_map(|qm31| qm31.to_m31_array()).flat_map(|m31| m31.0.to_le_bytes())
        bytes memory feltsBytes = new bytes(felts.length * 16); // Each QM31 = 4×M31 = 4×4 bytes = 16 bytes
        uint256 byteIndex = 0;
        
        for (uint256 i = 0; i < felts.length; i++) {
            uint32[4] memory m31Array = QM31Field.toM31Array(felts[i]);
            for (uint256 j = 0; j < 4; j++) {
                bytes4 m31Bytes = _u32ToLittleEndian(m31Array[j]);
                for (uint256 k = 0; k < 4; k++) {
                    feltsBytes[byteIndex] = m31Bytes[k];
                    byteIndex++;
                }
            }
        }
        
        // Step 2: Hash digest + felts_bytes (matches Rust hasher pattern)
        // hasher.update(self.digest); hasher.update(&felts_bytes); 
        bytes memory input = abi.encodePacked(state.digest, feltsBytes);
        
        // Step 3: Update digest (matches self.update_digest(hasher.finalize()))
        state.digest = keccak256(input);
        state.nDraws = 0;
    }
    
    /// @notice Mix u64 value by splitting into two u32s
    /// @param state Channel state
    /// @param value U64 value to mix
    function mixU64(ChannelState storage state, uint64 value) internal {
        uint32[] memory u32s = new uint32[](2);
        u32s[0] = uint32(value);        // Lower 32 bits
        u32s[1] = uint32(value >> 32);  // Upper 32 bits
        mixU32s(state, u32s);
    }
    
    /// @notice Draw random secure field element
    /// @param state Channel state
    /// @return Random QM31 element
    function drawSecureFelt(ChannelState storage state) internal returns (QM31Field.QM31 memory) {
        uint32[FELTS_PER_HASH] memory basefelts = _drawBaseFelts(state);
        
        // Take first 4 elements for QM31 (SECURE_EXTENSION_DEGREE = 4)
        uint32[4] memory secureArray;
        for (uint256 i = 0; i < SECURE_EXTENSION_DEGREE; i++) {
            secureArray[i] = basefelts[i];
        }
        
        return QM31Field.fromM31Array(secureArray);
    }
    
    /// @notice Draw multiple random secure field elements
    /// @param state Channel state
    /// @param nFelts Number of elements to draw
    /// @return Array of random QM31 elements
    function drawSecureFelts(ChannelState storage state, uint256 nFelts) internal returns (QM31Field.QM31[] memory) {
        QM31Field.QM31[] memory result = new QM31Field.QM31[](nFelts);
        
        uint32[FELTS_PER_HASH] memory currentBatch;
        uint256 batchIndex = FELTS_PER_HASH; // Force initial generation
        
        for (uint256 i = 0; i < nFelts; i++) {
            // Generate new batch if needed
            if (batchIndex + SECURE_EXTENSION_DEGREE > FELTS_PER_HASH) {
                currentBatch = _drawBaseFelts(state);
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
    
    /// @notice Draw random u32 values from current state
    /// @param state Channel state
    /// @return Array of random u32 values
    function drawU32s(ChannelState storage state) internal returns (uint32[] memory) {
        bytes memory input = abi.encodePacked(
            state.digest,
            _u32ToLittleEndian(state.nDraws),
            uint8(0) // Domain separation byte
        );
        
        state.nDraws++;
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
    
    /// @notice Verify proof-of-work nonce
    /// @param state Channel state
    /// @param nBits Required number of leading zeros
    /// @param nonce Proof-of-work nonce
    /// @return True if nonce is valid
    function verifyPowNonce(ChannelState storage state, uint32 nBits, uint64 nonce) internal view returns (bool) {
        // First hash: H(POW_PREFIX, padding, digest, nBits)
        bytes memory prefixInput = abi.encodePacked(
            _u32ToLittleEndian(POW_PREFIX),
            new bytes(24), // 24 zero bytes padding (matching Blake2s implementation)
            state.digest,
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
    
    /// @notice Hash two elements sequentially like Rust keccak.update(element1).update(element2)
    /// @param state Channel state
    /// @param left First element to hash
    /// @param right Second element to hash
    /// @return Final hash after sequential updates
    function mixRoot(ChannelState storage state, bytes32 left, bytes32 right) internal returns (bytes32) {
        bytes32 newDigest = keccak256(abi.encodePacked(left, right));
        state.nDraws = 0;
        state.digest = newDigest;
        return newDigest;
    }
    
    /// @notice Generate uniform random M31 field elements
    /// @param state Channel state
    /// @return Array of valid M31 field elements
    function _drawBaseFelts(ChannelState storage state) private returns (uint32[FELTS_PER_HASH] memory) {
        uint32 maxRetries = 100; // Prevent infinite loops
        uint32 retries = 0;
        
        while (retries < maxRetries) {
            uint32[] memory u32s = drawU32s(state);
            
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
        revert("KeccakChannelLib: Failed to generate valid base felts");
    }

    /// @notice Convert u32 to little-endian bytes
    /// @param value U32 value to convert
    /// @return Little-endian bytes representation
    function _u32ToLittleEndian(uint32 value) private pure returns (bytes4) {
        // Convert to little-endian: least significant byte first
        return bytes4(abi.encodePacked(
            uint8(value),           // byte 0 (LSB)
            uint8(value >> 8),      // byte 1
            uint8(value >> 16),     // byte 2  
            uint8(value >> 24)      // byte 3 (MSB)
        ));
    }
    
    /// @notice Convert u64 to little-endian bytes
    /// @param value U64 value to convert
    /// @return Little-endian bytes representation
    function _u64ToLittleEndian(uint64 value) private pure returns (bytes8) {
        return bytes8(
            _u32ToLittleEndian(uint32(value)) |
            (bytes8(_u32ToLittleEndian(uint32(value >> 32))) << 32)
        );
    }
    
    /// @notice Count trailing zeros in hash (little-endian interpretation)
    /// @param hash Hash to analyze
    /// @return Number of trailing zeros
    function _countTrailingZeros(bytes32 hash) private pure returns (uint256) {
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