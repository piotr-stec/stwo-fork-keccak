// use std::fs;

// use num_traits::Zero;
// use serde_json::Value;
// use stwo::core::air::Component;
// use stwo::core::channel::KeccakChannel;
// use stwo::core::fields::qm31::SecureField;
// use stwo::core::pcs::CommitmentSchemeVerifier;
// use stwo::core::proof::StarkProof;
// use stwo::core::vcs::keccak_merkle::{KeccakMerkleChannel, KeccakMerkleHasher};
// use stwo_constraint_framework::TraceLocationAllocator;
// use wide_circuit::{WideFibonacciComponent, WideFibonacciEval};

// fn main() {
//     println!("=== STARK Verifier - Wide Fibonacci ===\n");

//     // Read proof metadata
//     println!("Reading proof metadata...");
//     let metadata_str = fs::read_to_string("proof_metadata.json")
//         .expect("Failed to read proof_metadata.json. Make sure to run the prover first!");

//     let metadata: Value =
//         serde_json::from_str(&metadata_str).expect("Failed to parse proof metadata");

//     let log_n_rows = metadata["log_n_rows"].as_u64().unwrap() as u32;
//     let n_rows = metadata["n_rows"].as_u64().unwrap();
//     let n_columns = metadata["n_columns"].as_u64().unwrap() as usize;
//     let initial_a = metadata["initial_a"].as_u64().unwrap() as u32;
//     let initial_b = metadata["initial_b"].as_u64().unwrap() as u32;
//     let last_fib_value = metadata["last_fib_value"].as_u64().unwrap() as u32;

//     println!("✓ Metadata loaded");
//     println!();
//     println!("Proof claims:");
//     println!(
//         "  Structure: HORIZONTAL ({} rows × {} columns)",
//         n_rows, n_columns
//     );
//     println!("  Initial values: f(0)={}, f(1)={}", initial_a, initial_b);
//     println!(
//         "  Last value: f({}) = {} (mod 2^31-1)",
//         n_columns - 1,
//         last_fib_value
//     );
//     println!();

//     // Load proof from file
//     println!("Loading proof from file...");
//     let proof_json = fs::read_to_string("proof.json")
//         .expect("Failed to read proof.json. Make sure to run the prover first!");

//     let proof: StarkProof<KeccakMerkleHasher> =
//         serde_json::from_str(&proof_json).expect("Failed to deserialize proof");

//     println!("✓ Proof loaded from proof.json");
//     println!("  Proof size estimate: {} bytes", proof.size_estimate());
//     println!();
//     println!("Log n rows: {:?}", log_n_rows);
//     // Create component for verification
//     let component = WideFibonacciComponent::new(
//         &mut TraceLocationAllocator::default(),
//         WideFibonacciEval {
//             log_n_rows: log_n_rows,
//             n_columns: n_columns,
//         },
//         SecureField::zero(),
//     );

//     println!("Trace location allocator default {:?}", TraceLocationAllocator::default());

//     // Verify the proof
//     println!("Verifying proof...");

//     let channel = &mut KeccakChannel::default();
//     println!("Proof config: {:?}", proof.config);
//     let commitment_scheme = &mut CommitmentSchemeVerifier::<KeccakMerkleChannel>::new(proof.config);
//     println!("Channel before committing preprocessed: {:?}", channel);

//     // Commit preprocessed
//     commitment_scheme.commit(
//         proof.commitments[0],
//         &component.trace_log_degree_bounds()[0],
//         channel,
//     );

//     println!("Channel after committing preprocessed 0: {:?}, {:?}", channel, &component.trace_log_degree_bounds()[0]);

//     // Commit trace
//     commitment_scheme.commit(
//         proof.commitments[1],
//         &component.trace_log_degree_bounds()[1],
//         channel,
//     );

//         // println!("Commitment scheme log sizes: {:?}", commitment_scheme.column_log_sizes());

//     println!("Component nConstraints: {}", component.n_constraints());

//     println!("Component max constraint degree: {}", component.max_constraint_log_degree_bound());

//     // println!("Component log size: {}", component.info.logup.log_size);

//     println!("Channel after committing preprocessed 1: {:?}, {:?}", channel, &component.trace_log_degree_bounds()[1]);

//     println!("Trace locations: {:?}", component.trace_locations());

//     println!("Proof commitments len: {}", proof.commitments.len());

//     // println!(
//     //     "Proof: {:#?}",
//     //     serde_json::to_string_pretty(&proof).unwrap()
//     // );
//     println!("Mask offsets: {:?}", component.info.mask_offsets);
//     // Verify!
//     // println!("Proof commitment 0: {:?}", proof.commitments[0]);
//     stwo::core::verifier::verify(&[&component], channel, commitment_scheme, proof).unwrap();

//     println!("✓ Proof verified successfully!");
//     // println!();
//     // println!("Verification result:");
//     // println!("  ✓ HORIZONTAL Fibonacci sequence is CORRECT");
//     // println!("  ✓ {} rows, each with {} Fibonacci values", n_rows, n_columns);
//     // println!("  ✓ Proof loaded from file and verified");
// }
