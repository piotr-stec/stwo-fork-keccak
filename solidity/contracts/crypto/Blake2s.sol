/*
 * Blake2s library in Solidity
 *
 * Blake2s implementation according to RFC 7693 and compatible with Rust blake2 crate
 * - 32-bit words
 * - 10 rounds
 * - 64-byte blocks
 * - Maximum 32-byte output
 * - Proper parameter block initialization
 * - Variable length input support with padding
 */

pragma solidity ^0.8.26;

library Blake2s {
    // Blake2s IV - same as SHA-256 IV
    uint32 constant IV0 = 0x6A09E667;
    uint32 constant IV1 = 0xBB67AE85;
    uint32 constant IV2 = 0x3C6EF372;
    uint32 constant IV3 = 0xA54FF53A;
    uint32 constant IV4 = 0x510E527F;
    uint32 constant IV5 = 0x9B05688C;
    uint32 constant IV6 = 0x1F83D9AB;
    uint32 constant IV7 = 0x5BE0CD19;

    // Blake2s rotation constants
    uint32 constant R1 = 16;
    uint32 constant R2 = 12;
    uint32 constant R3 = 8;
    uint32 constant R4 = 7;

    // Blake2s block size
    uint constant BLOCKBYTES = 64;
    uint constant OUTBYTES = 32;
    uint constant KEYBYTES = 32;

    function getSigma(uint round) internal pure returns (uint8[16] memory) {
        if (round == 0)
            return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
        if (round == 1)
            return [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3];
        if (round == 2)
            return [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4];
        if (round == 3)
            return [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8];
        if (round == 4)
            return [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13];
        if (round == 5)
            return [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9];
        if (round == 6)
            return [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11];
        if (round == 7)
            return [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10];
        if (round == 8)
            return [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5];
        return [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]; // round 9
    }

    struct Instance {
        uint32[8] h; // State vector
        uint32[16] m; // Message block
        uint64 t; // Offset counter
        bool f; // Finalization flag
        uint8 out_len; // Output length
        bytes buffer; // Buffer for incomplete blocks
        uint buflen; // Current buffer length
    }

    /**
     * Initialize Blake2s with proper parameter block according to RFC 7693
     */
    function init(
        bytes memory key,
        uint8 out_len
    ) internal pure returns (Instance memory instance) {
        require(out_len > 0 && out_len <= 32, "Blake2s: invalid output length");
        require(key.length <= 32, "Blake2s: key too large");

        // Initialize with IV
        instance.h[0] = IV0;
        instance.h[1] = IV1;
        instance.h[2] = IV2;
        instance.h[3] = IV3;
        instance.h[4] = IV4;
        instance.h[5] = IV5;
        instance.h[6] = IV6;
        instance.h[7] = IV7;

        // Parameter block P[0] according to RFC 7693:
        // - digest_length: out_len (bits 0-7)
        // - key_length: key.length (bits 8-15)
        // - fanout: 1 (bits 16-23) - for sequential mode
        // - depth: 1 (bits 24-31) - for sequential mode
        uint32 param0 = uint32(out_len) | // digest_length
            (uint32(key.length) << 8) | // key_length
            (1 << 16) | // fanout = 1
            (1 << 24); // depth = 1

        instance.h[0] = instance.h[0] ^ param0;

        // P[1] = leaf_length (32 bits) = 0 for sequential mode
        // instance.h[1] already XORed with IV1, leaf_length = 0 so no change needed

        // P[2] = node_offset (64 bits) = 0 for sequential mode
        // P[3] = xof_length (64 bits) = 0 for Blake2s
        // instance.h[2] and instance.h[3] remain as IV2, IV3

        // P[4], P[5] = node_depth, inner_length, reserved, salt (all 0 for basic usage)
        // P[6], P[7] = personal (0 for basic usage)
        // instance.h[4] through instance.h[7] remain as IV4-IV7

        instance.out_len = out_len;
        instance.t = 0;
        instance.f = false;
        instance.buffer = new bytes(BLOCKBYTES);
        instance.buflen = 0;

        // Process key if provided (key becomes first block)
        if (key.length > 0) {
            bytes memory keyblock = new bytes(BLOCKBYTES);
            for (uint i = 0; i < key.length; i++) {
                keyblock[i] = key[i];
            }
            // Remaining bytes are already zero
            updateBlock(instance, keyblock, false);
        }
    }

    /**
     * Optimized one-shot hash function compatible with Rust blake2 crate
     */
    function hash(bytes memory input) internal pure returns (bytes32) {
        // For small inputs (≤64 bytes), use optimized direct path
        if (input.length <= BLOCKBYTES) {
            return hashSmallInput(input);
        }
        
        // For larger inputs, use general path
        Instance memory instance = init(hex"", 32);
        update(instance, input);
        bytes memory result = finalize(instance);
        bytes32 hash_result;
        assembly {
            hash_result := mload(add(result, 32))
        }
        return hash_result;
    }
    
    /**
     * Optimized hash for small inputs (≤64 bytes) - bypasses buffer operations
     */
    function hashSmallInput(bytes memory input) private pure returns (bytes32) {
        // Initialize state directly without Instance struct overhead
        uint32[8] memory h;
        h[0] = IV0 ^ uint32(32) ^ (1 << 16) ^ (1 << 24); // digest_length=32, fanout=1, depth=1
        h[1] = IV1;
        h[2] = IV2; 
        h[3] = IV3;
        h[4] = IV4;
        h[5] = IV5;
        h[6] = IV6;
        h[7] = IV7;
        
        // Prepare single block with input data
        uint32[16] memory m;
        uint inlen = input.length;
        
        // Load input into message block efficiently
        unchecked {
            uint i = 0;
            // Process complete 4-byte words
            while (i + 3 < inlen) {
                m[i / 4] = uint32(uint8(input[i])) |
                          (uint32(uint8(input[i + 1])) << 8) |
                          (uint32(uint8(input[i + 2])) << 16) |
                          (uint32(uint8(input[i + 3])) << 24);
                i += 4;
            }
            // Handle remaining bytes
            if (i < inlen) {
                uint32 word = 0;
                for (uint j = 0; i + j < inlen; j++) {
                    word |= uint32(uint8(input[i + j])) << (uint32(j) * 8);
                }
                m[i / 4] = word;
            }
        }
        
        // Compress with final flag
        compressDirect(h, m, uint64(inlen), true);
        
        // Extract result using uint32ToBytes optimized
        bytes memory output = new bytes(32);
        unchecked {
            uint32ToBytes(output, 0, h[0]);
            uint32ToBytes(output, 4, h[1]);
            uint32ToBytes(output, 8, h[2]);
            uint32ToBytes(output, 12, h[3]);
            uint32ToBytes(output, 16, h[4]);
            uint32ToBytes(output, 20, h[5]);
            uint32ToBytes(output, 24, h[6]);
            uint32ToBytes(output, 28, h[7]);
        }
        
        bytes32 result;
        assembly {
            result := mload(add(output, 32))
        }
        
        return result;
    }

    /**
     * Update with variable length input
     */
    function update(
        Instance memory instance,
        bytes memory input
    ) internal pure {
        uint inlen = input.length;
        uint in_offset = 0;

        if (inlen > 0) {
            uint left = instance.buflen;
            uint fill = BLOCKBYTES - left;

            if (inlen > fill) {
                instance.buflen = 0;
                // Copy fill bytes to buffer
                for (uint i = 0; i < fill; i++) {
                    instance.buffer[left + i] = input[in_offset + i];
                }
                unchecked {
                    in_offset += fill;
                    inlen -= fill;
                }
                updateBlock(instance, instance.buffer, false);

                // Process complete blocks
                while (inlen >= BLOCKBYTES) {
                    bytes memory data_block = new bytes(BLOCKBYTES);
                    for (uint i = 0; i < BLOCKBYTES; i++) {
                        data_block[i] = input[in_offset + i];
                    }
                    updateBlock(instance, data_block, false);
                    unchecked {
                        in_offset += BLOCKBYTES;
                        inlen -= BLOCKBYTES;
                    }
                }
            }

            // Store remaining bytes in buffer
            for (uint i = 0; i < inlen; i++) {
                instance.buffer[instance.buflen + i] = input[in_offset + i];
            }
            unchecked {
                instance.buflen += inlen;
            }
        }
    }

    /**
     * Finalize and return hash (consumes the instance)
     */
    function finalize(
        Instance memory instance
    ) internal pure returns (bytes memory) {
        // Pad final block with zeros
        for (uint i = instance.buflen; i < BLOCKBYTES; i++) {
            instance.buffer[i] = 0;
        }

        // Process final block
        unchecked {
            instance.t = instance.t + uint64(instance.buflen);
        }
        updateBlock(instance, instance.buffer, true);

        // Extract hash
        bytes memory output = new bytes(instance.out_len);
        for (uint i = 0; i < instance.out_len; i += 4) {
            uint32 word = instance.h[i / 4];
            uint remaining = instance.out_len - i;
            if (remaining >= 4) {
                uint32ToBytes(output, i, word);
            } else {
                // Handle partial word for non-multiple of 4 output lengths
                for (uint j = 0; j < remaining; j++) {
                    output[i + j] = bytes1(uint8(word >> (j * 8)));
                }
            }
        }

        return output;
    }

    /**
     * Finalize and reset instance to initial state (like Rust finalize_reset)
     */
    function finalizeReset(
        Instance memory instance
    ) internal pure returns (bytes memory) {
        // Create a copy for finalization
        Instance memory temp_instance;
        temp_instance.out_len = instance.out_len;
        temp_instance.t = instance.t;
        temp_instance.f = instance.f;
        temp_instance.buflen = instance.buflen;
        temp_instance.buffer = new bytes(BLOCKBYTES);

        // Copy state and buffer
        for (uint i = 0; i < 8; i++) {
            temp_instance.h[i] = instance.h[i];
        }
        for (uint i = 0; i < instance.buflen; i++) {
            temp_instance.buffer[i] = instance.buffer[i];
        }

        // Finalize the copy
        bytes memory result = finalize(temp_instance);

        // Reset original instance to initial state
        instance.h[0] = IV0;
        instance.h[1] = IV1;
        instance.h[2] = IV2;
        instance.h[3] = IV3;
        instance.h[4] = IV4;
        instance.h[5] = IV5;
        instance.h[6] = IV6;
        instance.h[7] = IV7;

        // Apply parameter block again
        uint32 param0 = uint32(instance.out_len) | // digest_length
            (1 << 16) | // fanout = 1
            (1 << 24); // depth = 1 (no key)
        instance.h[0] = instance.h[0] ^ param0;

        // Reset counters and buffer
        instance.t = 0;
        instance.f = false;
        instance.buflen = 0;
        for (uint i = 0; i < BLOCKBYTES; i++) {
            instance.buffer[i] = 0;
        }

        return result;
    }

    /**
     * Process a single 64-byte block
     */
    function updateBlock(
        Instance memory instance,
        bytes memory data_block,
        bool is_final
    ) internal pure {
        require(
            data_block.length == BLOCKBYTES,
            "Blake2s: block must be 64 bytes"
        );

        // Load block into message array
        for (uint i = 0; i < 16; i++) {
            instance.m[i] = bytesToUint32(data_block, i * 4);
        }

        if (!is_final) {
            unchecked {
                instance.t = instance.t + uint64(BLOCKBYTES);
            }
        }

        compress(instance, is_final);
    }

    /**
     * Optimized direct compression function for small inputs
     */
    function compressDirect(uint32[8] memory h, uint32[16] memory m, uint64 t, bool is_final)
        private
        pure
    {
        uint32[16] memory v;
        
        // Initialize working vector v[0..15]
        unchecked {
            for (uint i = 0; i < 8; i++) {
                v[i] = h[i];
            }
            v[8] = IV0;
            v[9] = IV1;
            v[10] = IV2;
            v[11] = IV3;
            
            // Low 32 bits of offset counter t
            v[12] = IV4 ^ uint32(t);
            // High 32 bits of offset counter t  
            v[13] = IV5 ^ uint32(t >> 32);
            
            // Finalization flag f
            v[14] = IV6;
            v[15] = IV7;
            if (is_final) {
                v[14] = v[14] ^ 0xFFFFFFFF;
            }
            
            // 10 rounds of mixing
            for (uint i = 0; i < 10; i++) {
                mixRound(v, m, getSigma(i));
            }
            
            // Update hash state
            for (uint i = 0; i < 8; i++) {
                h[i] = h[i] ^ v[i] ^ v[i + 8];
            }
        }
    }

    /**
     * Blake2s compression function
     */
    function compress(Instance memory instance, bool is_final) private pure {
        uint32[16] memory v;

        // Initialize working vector v[0..15]
        for (uint i = 0; i < 8; i++) {
            v[i] = instance.h[i];
        }
        v[8] = IV0;
        v[9] = IV1;
        v[10] = IV2;
        v[11] = IV3;

        // Low 32 bits of offset counter t
        v[12] = IV4 ^ uint32(instance.t);
        // High 32 bits of offset counter t
        v[13] = IV5 ^ uint32(instance.t >> 32);

        // Finalization flag f
        v[14] = IV6;
        v[15] = IV7;
        if (is_final) {
            v[14] = v[14] ^ 0xFFFFFFFF;
        }

        // 10 rounds of mixing
        for (uint i = 0; i < 10; i++) {
            mixRound(v, instance.m, getSigma(i));
        }

        // Update hash state
        for (uint i = 0; i < 8; i++) {
            instance.h[i] = instance.h[i] ^ v[i] ^ v[i + 8];
        }
    }

    function mixRound(
        uint32[16] memory v,
        uint32[16] memory m,
        uint8[16] memory sigma
    ) private pure {
        mix(v, 0, 4, 8, 12, m[sigma[0]], m[sigma[1]]);
        mix(v, 1, 5, 9, 13, m[sigma[2]], m[sigma[3]]);
        mix(v, 2, 6, 10, 14, m[sigma[4]], m[sigma[5]]);
        mix(v, 3, 7, 11, 15, m[sigma[6]], m[sigma[7]]);
        mix(v, 0, 5, 10, 15, m[sigma[8]], m[sigma[9]]);
        mix(v, 1, 6, 11, 12, m[sigma[10]], m[sigma[11]]);
        mix(v, 2, 7, 8, 13, m[sigma[12]], m[sigma[13]]);
        mix(v, 3, 4, 9, 14, m[sigma[14]], m[sigma[15]]);
    }

    function mix(
        uint32[16] memory v,
        uint a,
        uint b,
        uint c,
        uint d,
        uint32 x,
        uint32 y
    ) private pure {
        unchecked {
            v[a] = v[a] + v[b] + x;
            v[d] = rotr32(v[d] ^ v[a], R1);
            v[c] = v[c] + v[d];
            v[b] = rotr32(v[b] ^ v[c], R2);
            v[a] = v[a] + v[b] + y;
            v[d] = rotr32(v[d] ^ v[a], R3);
            v[c] = v[c] + v[d];
            v[b] = rotr32(v[b] ^ v[c], R4);
        }
    }

    function rotr32(uint32 x, uint32 n) private pure returns (uint32) {
        unchecked {
            n = n % 32;  // Prevent underflow when n > 32
            return (x >> n) | (x << (32 - n));
        }
    }

    function bytesToUint32(
        bytes memory data,
        uint offset
    ) private pure returns (uint32) {
        // Little-endian conversion
        return
            uint32(uint8(data[offset])) |
            (uint32(uint8(data[offset + 1])) << 8) |
            (uint32(uint8(data[offset + 2])) << 16) |
            (uint32(uint8(data[offset + 3])) << 24);
    }

    function uint32ToBytes(
        bytes memory data,
        uint offset,
        uint32 value
    ) private pure {
        // Little-endian conversion
        data[offset] = bytes1(uint8(value));
        data[offset + 1] = bytes1(uint8(value >> 8));
        data[offset + 2] = bytes1(uint8(value >> 16));
        data[offset + 3] = bytes1(uint8(value >> 24));
    }
}
