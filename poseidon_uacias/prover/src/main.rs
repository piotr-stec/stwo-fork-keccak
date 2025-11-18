use std::{env, fs};

use num_traits::Zero;
use poseidon_circuit::{RATE, prove_poseidon, round_up_to_simd_lanes};
use stwo::core::channel::KeccakChannel;
use stwo::core::fields::m31::BaseField;
use stwo::core::fields::qm31::SecureField;
use stwo::core::fri::FriConfig;
use stwo::core::pcs::PcsConfig;
use stwo::core::poly::circle::CanonicCoset;
use stwo::core::vcs::keccak_merkle::KeccakMerkleChannel;
use stwo::core::ColumnVec;
use stwo::prover::backend::simd::SimdBackend;
use stwo::prover::backend::Column;
use stwo::prover::poly::circle::{CircleEvaluation, PolyOps};
use stwo::prover::poly::BitReversedOrder;
use stwo::prover::{prove, CommitmentSchemeProver};
use stwo_constraint_framework::TraceLocationAllocator;

fn dump_trace_to_file(
    trace: &ColumnVec<CircleEvaluation<SimdBackend, BaseField, BitReversedOrder>>,
    n_rows: usize,
    n_columns: usize,
    filename: &str,
) {
    let mut output = String::new();

    output.push_str("=== Wide Fibonacci Trace Dump ===\n\n");
    output.push_str(&format!("Structure: {} columns (HORIZONTAL)\n", n_columns));
    output.push_str(&format!(
        "Each row contains: f(0) to f({})\n",
        n_columns - 1
    ));
    output.push_str(&format!("Total rows: {}\n\n", n_rows));

    // Header
    output.push_str(&format!("{:<8}", "Row"));
    for i in 0..n_columns.min(10) {
        output.push_str(&format!("{:<12}", format!("f({})", i)));
    }
    if n_columns > 10 {
        output.push_str("  ...");
    }
    output.push_str("\n");
    output.push_str(&format!("{}\n", "-".repeat(100)));

    // Data rows
    for row in 0..n_rows {
        output.push_str(&format!("{:<8}", row));
        for col in 0..n_columns.min(10) {
            let val = trace[col].values.at(row);
            output.push_str(&format!("{:<12}", val.0));
        }
        if n_columns > 10 {
            output.push_str(&format!("  ...  {}", trace[n_columns - 1].values.at(row).0));
        }
        output.push_str("\n");
    }

    fs::write(filename, output).expect("Failed to write trace dump");
}

fn main() {
    println!("=== STARK Prover - poseidon uacias ===\n");

    // Parse command line arguments
    let args: Vec<String> = env::args().collect();

    let dump_trace = args.iter().any(|arg| arg == "--dump-trace");
    let log_n_rows = 7; // 128 rows
    let n_real_messages = 127; // 127 active messages, 1 padding row
    let config = PcsConfig {
        pow_bits: 10,
        fri_config: FriConfig::new(5, 1, 64),
    };

    // Generate 127 messages
    let messages: Vec<[BaseField; RATE]> = (0..n_real_messages)
        .map(|i| std::array::from_fn(|j| BaseField::from_u32_unchecked((i * RATE + j) as u32)))
        .collect();

    println!(
        "Testing {} messages in {}-row table (1 padding row)",
        n_real_messages,
        1 << log_n_rows
    );
    println!(
        "Note: {} will be rounded to {} for SIMD alignment",
        n_real_messages,
        round_up_to_simd_lanes(n_real_messages)
    );

    // Prove
    let (component, proof) = prove_poseidon(log_n_rows, n_real_messages, messages, config);


    // Generate proof
    println!("✓ Proof generated!");
    println!("  Commitments: {}", proof.commitments.len());
    println!("  Proof size estimate: {} bytes", proof.size_estimate());
    println!();

    // Save proof to JSON
    println!("Saving proof to file...");
    let proof_json = serde_json::to_string_pretty(&proof).expect("Failed to serialize proof");
    fs::write("proof.json", proof_json).expect("Failed to write proof.json");
    println!("✓ Proof saved to proof.json");
    println!(
        "  File size: {} bytes",
        fs::metadata("proof.json").unwrap().len()
    );
    println!();

    // // Save proof metadata
    // println!("Saving proof metadata...");
    // let metadata = serde_json::json!({
    //     "log_n_rows": log_n_rows,
    //     "n_rows": n_rows,
    //     "n_columns": n_columns,
    //     "initial_a": initial_a,
    //     "initial_b": initial_b,
    //     "last_fib_value": last_fib_value.0,
    //     "commitments_count": proof.commitments.len(),
    //     "proof_size_bytes": proof.size_estimate(),
    //     "structure": "horizontal"
    // });

    // fs::write(
    //     "proof_metadata.json",
    //     serde_json::to_string_pretty(&metadata).unwrap(),
    // )
    // .expect("Failed to write proof metadata");

    // println!("✓ Proof metadata saved to proof_metadata.json");
    // println!();
    // println!("Summary:");
    // println!(
    //     "  Structure: HORIZONTAL ({} rows × {} columns)",
    //     n_rows, n_columns
    // );
    // println!(
    //     "  Each row = complete Fibonacci f(0) to f({})",
    //     n_columns - 1
    // );
    // println!("  Last value: f({}) = {}", n_columns - 1, last_fib_value);
    println!();
    println!("✓ Prover completed successfully!");
}
