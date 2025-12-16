use core::iter::zip;

use itertools::Itertools;
use std_shims::Vec;

use super::super::circle::CirclePoint;
use super::super::fields::qm31::SecureField;
use super::super::fri::{CirclePolyDegreeBound, FriVerifier};
use super::quotients::{fri_answers, PointSample};
use super::utils::TreeVec;
use super::PcsConfig;
use crate::core::channel::{Channel, MerkleChannel};
use crate::core::pcs::quotients::CommitmentSchemeProof;
use crate::core::vcs::verifier::MerkleVerifier;
use crate::core::vcs::MerkleHasher;
use crate::core::verifier::VerificationError;
use crate::core::ColumnVec;

/// The verifier side of a FRI polynomial commitment scheme. See [super].
#[derive(Default)]
pub struct CommitmentSchemeVerifier<MC: MerkleChannel> {
    pub trees: TreeVec<MerkleVerifier<MC::H>>,
    pub config: PcsConfig,
}

impl<MC: MerkleChannel> CommitmentSchemeVerifier<MC> {
    pub fn new(config: PcsConfig) -> Self {
        Self {
            trees: TreeVec::default(),
            config,
        }
    }

    /// A [TreeVec<ColumnVec>] of the log sizes of each column in each commitment tree.
    fn column_log_sizes(&self) -> TreeVec<ColumnVec<u32>> {
        self.trees
            .as_ref()
            .map(|tree| tree.column_log_sizes.clone())
    }

    /// Reads a commitment from the prover.
    pub fn commit(
        &mut self,
        commitment: <MC::H as MerkleHasher>::Hash,
        log_sizes: &[u32],
        channel: &mut MC::C,
    ) {
        MC::mix_root(channel, commitment);
        let extended_log_sizes = log_sizes
            .iter()
            .map(|&log_size| log_size + self.config.fri_config.log_blowup_factor)
            .collect();
        println!("Creating MerkleVerifier with commitment and extended log sizes:");
        println!("Commitment received: {:?}", commitment);
        println!("Extended log sizes: {:?}", extended_log_sizes);
        let verifier = MerkleVerifier::new(commitment, extended_log_sizes);
        self.trees.push(verifier);
    }

    pub fn verify_values(
        &self,
        sampled_points: TreeVec<ColumnVec<Vec<CirclePoint<SecureField>>>>,
        proof: CommitmentSchemeProof<MC::H>,
        channel: &mut MC::C,
    ) -> Result<(), VerificationError> {
        channel.mix_felts(&proof.sampled_values.clone().flatten_cols());
        let random_coeff = channel.draw_secure_felt();

        let bounds = self
            .column_log_sizes()
            .flatten()
            .into_iter()
            .sorted()
            .rev()
            .dedup()
            .map(|log_size| {
                CirclePolyDegreeBound::new(log_size - self.config.fri_config.log_blowup_factor)
            })
            .collect_vec();
        println!("Channel state before commit Fri: {:?}", channel);

        println!("Creating FRI verifier and committing...");
        println!("FRI bounds: {:?}", bounds);
        println!("FRI config: {:?}", self.config.fri_config);
        println!("Proof FRI proof: {:?}", proof.fri_proof);
        // FRI commitment phase on OODS quotients.
        let mut fri_verifier =
            FriVerifier::<MC>::commit(channel, self.config.fri_config, proof.fri_proof, bounds)?;
        
        println!("Fri first layer commitment domains after commit: {:?}", fri_verifier.first_layer.column_commitment_domains);

        // Verify proof of work.
        println!("Channel state before POW verification: {:?}", channel);
        if !channel.verify_pow_nonce(self.config.pow_bits, proof.proof_of_work) {
            return Err(VerificationError::ProofOfWork);
        }
        channel.mix_u64(proof.proof_of_work);
        println!("Channel state after POW verification: {:?}", channel);
        // Get FRI query positions.
        let query_positions_per_log_size = fri_verifier.sample_query_positions(channel);
        println!("FRI query positions per log size: {:?}", query_positions_per_log_size);
        println!("Self trees len: {:?}", self.trees.len());
        println!("Verifying merkle decommitments...");
        // Verify merkle decommitments.
        self.trees
            .as_ref()
            .zip_eq(proof.decommitments)
            .zip_eq(proof.queried_values.clone())
            .map(|((tree, decommitment), queried_values)| {
                tree.verify(&query_positions_per_log_size, queried_values, decommitment)
            })
            .0
            .into_iter()
            .collect::<Result<(), _>>()?;
        println!("Merkle decommitments verified.");
        // Answer FRI queries.
        let samples = sampled_points.zip_cols(proof.sampled_values).map_cols(
            |(sampled_points, sampled_values)| {
                zip(sampled_points, sampled_values)
                    .map(|(point, value)| PointSample { point, value })
                    .collect_vec()
            },
        );


        let n_columns_per_log_size = self.trees.as_ref().map(|tree| &tree.n_columns_per_log_size);
        println!("Computing FRI answers...");
        println!("Column log sizes: {:?}", self.column_log_sizes());
        println!("Sampled points: {:?}", samples);
        println!("Random coeff: {:?}", random_coeff);
        println!("Queried values: {:?}", proof.queried_values);
        println!("Query positions per log size: {:?}", query_positions_per_log_size);

        println!("N columns per log size: {:?}", n_columns_per_log_size);
        let fri_answers = fri_answers(
            self.column_log_sizes(),
            samples,
            random_coeff,
            &query_positions_per_log_size,
            proof.queried_values,
            n_columns_per_log_size,
        )?;

        println!("Fri answers computed: {:?}", fri_answers);

        fri_verifier.decommit(fri_answers)?;

        Ok(())
    }
}
