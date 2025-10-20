use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};

use super::keccak_hash::KeccakHash;
use crate::core::channel::{KeccakChannel, MerkleChannel};
use crate::core::fields::m31::BaseField;
use crate::core::vcs::MerkleHasher;

pub const LEAF_PREFIX: [u8; 64] = [
    b'l', b'e', b'a', b'f', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0,
];
pub const NODE_PREFIX: [u8; 64] = [
    b'n', b'o', b'd', b'e', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0,
];

#[derive(Copy, Clone, Debug, PartialEq, Eq, Default, Deserialize, Serialize)]
pub struct KeccakMerkleHasher;

impl MerkleHasher for KeccakMerkleHasher {
    type Hash = KeccakHash;

    fn hash_node(
        children_hashes: Option<(Self::Hash, Self::Hash)>,
        column_values: &[BaseField],
    ) -> Self::Hash {
        let mut hasher = Keccak256::new();

        // Use same prefix structure as Blake2s for compatibility
        if let Some((left_child, right_child)) = children_hashes {
            hasher.update(NODE_PREFIX);
            hasher.update(left_child.as_ref());
            hasher.update(right_child.as_ref());
        } else {
            hasher.update(LEAF_PREFIX);
        }

        for value in column_values {
            hasher.update(value.0.to_le_bytes());
        }

        KeccakHash(hasher.finalize().into())
    }
}

#[derive(Default)]
pub struct KeccakMerkleChannel;

impl MerkleChannel for KeccakMerkleChannel {
    type C = KeccakChannel;
    type H = KeccakMerkleHasher;

    fn mix_root(channel: &mut Self::C, root: <Self::H as MerkleHasher>::Hash) {
        channel.update_digest(super::keccak_hash::KeccakHasher::concat_and_hash(
            &channel.digest(),
            &root,
        ));
    }
}

#[cfg(test)]
mod tests {
    use crate::core::fields::m31::BaseField;
    use crate::core::vcs::keccak_merkle::KeccakMerkleHasher;
    use crate::core::vcs::MerkleHasher;

    #[test]
    fn test_hash_comparison_with_blake2s() {
        use crate::core::vcs::blake2_merkle::Blake2sMerkleHasher;
        
        // Create test data
        let values = vec![BaseField::from(1), BaseField::from(2), BaseField::from(3)];
        
        // Hash with both implementations
        let keccak_hash = KeccakMerkleHasher::hash_node(None, &values);
        let blake2s_hash = Blake2sMerkleHasher::hash_node(None, &values);
        
        // Hashes should be different (different algorithms)
        assert_ne!(keccak_hash.0.to_vec(), blake2s_hash.0.to_vec());
        
        // But both should be non-zero
        assert_ne!(keccak_hash.0, [0u8; 32]);
        assert_ne!(blake2s_hash.0, [0u8; 32]);
    }

    #[test]
    fn test_leaf_vs_node_hashing() {
        let values = vec![BaseField::from(42)];
        
        // Hash as leaf (no children)
        let leaf_hash = KeccakMerkleHasher::hash_node(None, &values);
        
        // Hash as node (with dummy children)
        let dummy_child = leaf_hash;
        let node_hash = KeccakMerkleHasher::hash_node(Some((dummy_child, dummy_child)), &values);
        
        // Should produce different hashes due to different prefixes
        assert_ne!(leaf_hash, node_hash);
    }

    #[test]
    fn test_deterministic_hashing() {
        let values = vec![BaseField::from(123), BaseField::from(456)];
        
        let hash1 = KeccakMerkleHasher::hash_node(None, &values);
        let hash2 = KeccakMerkleHasher::hash_node(None, &values);
        
        // Should be deterministic
        assert_eq!(hash1, hash2);
    }
}