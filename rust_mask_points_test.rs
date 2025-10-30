// Test file to generate Rust mask_points output for comparison
use stwo_prover::core::air::{Component, Components};
use stwo_prover::core::circle::CirclePoint;
use stwo_prover::core::fields::qm31::{QM31, SecureField};
use stwo_prover::core::fields::cm31::CM31;
use stwo_prover::core::fields::m31::M31;
use stwo_prover::core::pcs::TreeVec;
use stwo_prover::core::ColumnVec;

// Mock component for testing
#[derive(Debug)]
struct TestComponent {
    tree_idx: usize,
    log_degree_bound: u32,
    mask_offsets: Vec<(isize, usize)>, // (offset, column_idx)
    preprocessed_columns: Vec<usize>,
}

impl Component for TestComponent {
    fn n_constraints(&self) -> usize {
        2 // Mock constraint count
    }

    fn max_constraint_log_degree_bound(&self) -> u32 {
        self.log_degree_bound
    }

    fn trace_log_degree_bounds(&self) -> TreeVec<ColumnVec<u32>> {
        let mut trees = TreeVec::new();
        
        // Tree 0 (preprocessed) - will be overwritten by Components
        trees.push(vec![self.log_degree_bound]);
        
        // Our component tree
        if self.tree_idx > 0 {
            for _ in 1..=self.tree_idx {
                trees.push(vec![self.log_degree_bound]);
            }
        }
        
        trees
    }

    fn mask_points(
        &self,
        point: CirclePoint<SecureField>,
    ) -> TreeVec<ColumnVec<Vec<CirclePoint<SecureField>>>> {
        let mut trees = TreeVec::new();
        
        // Tree 0 (preprocessed) - will be handled by Components
        trees.push(vec![vec![]]); 
        
        // Our component tree
        if self.tree_idx > 0 {
            for _ in 1..=self.tree_idx {
                let mut columns = vec![];
                
                // Group mask offsets by column
                let max_col = self.mask_offsets.iter().map(|(_, col)| *col).max().unwrap_or(0);
                for col_idx in 0..=max_col {
                    let mut column_points = vec![];
                    for &(offset, col) in &self.mask_offsets {
                        if col == col_idx {
                            // Apply offset to get mask point
                            let mask_point = point.clone(); // Simplified - real impl would apply offset
                            column_points.push(mask_point);
                        }
                    }
                    columns.push(column_points);
                }
                
                trees.push(columns);
            }
        }
        
        trees
    }

    fn preprocessed_column_indices(&self) -> ColumnVec<usize> {
        self.preprocessed_columns.clone()
    }

    fn evaluate_constraint_quotients_at_point(
        &self,
        _point: CirclePoint<SecureField>,
        _mask: &TreeVec<ColumnVec<Vec<SecureField>>>,
        _evaluation_accumulator: &mut crate::core::air::accumulation::PointEvaluationAccumulator,
    ) {
        // Mock implementation
    }
}

fn main() {
    println!("=== Rust mask_points Test ===");
    
    // Create the exact OODS point used in Solidity test
    let oods_point = CirclePoint {
        x: QM31::from_u32_unchecked(1728655597, 1463321920, 977285354, 1203130452),
        y: QM31::from_u32_unchecked(432167808, 1897631297, 1056621846, 265487913),
    };
    
    println!("OODS Point:");
    println!("  x: {:?}", oods_point.x);
    println!("  y: {:?}", oods_point.y);
    
    // Create test component matching Solidity test
    let component = TestComponent {
        tree_idx: 1,
        log_degree_bound: 8,
        mask_offsets: vec![(0, 0), (1, 0)], // offset 0 and 1 on column 0
        preprocessed_columns: vec![0], // Column 0 is preprocessed
    };
    
    // Create Components wrapper
    let components = Components {
        components: vec![&component],
        n_preprocessed_columns: 1,
    };
    
    println!("\nComponent Configuration:");
    println!("  tree_idx: {}", component.tree_idx);
    println!("  log_degree_bound: {}", component.log_degree_bound);
    println!("  mask_offsets: {:?}", component.mask_offsets);
    println!("  preprocessed_columns: {:?}", component.preprocessed_columns);
    
    // Execute the exact line from verifier.rs
    let sample_points = components.mask_points(oods_point);
    
    println!("\n=== mask_points Results ===");
    println!("Number of trees: {}", sample_points.len());
    
    let mut total_points = 0;
    for (tree_idx, tree) in sample_points.iter().enumerate() {
        println!("Tree {}: {} columns", tree_idx, tree.len());
        for (col_idx, column) in tree.iter().enumerate() {
            println!("  Column {}: {} points", col_idx, column.len());
            total_points += column.len();
            
            for (point_idx, point) in column.iter().enumerate() {
                println!("    Point {}: x={:?}, y={:?}", point_idx, point.x, point.y);
            }
        }
    }
    
    println!("Total sample points: {}", total_points);
    
    // Test multiple components
    println!("\n=== Multiple Components Test ===");
    
    let component1 = TestComponent {
        tree_idx: 1,
        log_degree_bound: 8,
        mask_offsets: vec![(0, 0), (1, 0), (0, 1)], // 3 mask points
        preprocessed_columns: vec![0],
    };
    
    let component2 = TestComponent {
        tree_idx: 2,
        log_degree_bound: 10,
        mask_offsets: vec![(0, 0), (2, 0)], // 2 mask points
        preprocessed_columns: vec![], // No preprocessed columns
    };
    
    let multi_components = Components {
        components: vec![&component1, &component2],
        n_preprocessed_columns: 1,
    };
    
    let multi_sample_points = multi_components.mask_points(oods_point);
    
    println!("Multiple components - trees: {}", multi_sample_points.len());
    let mut multi_total = 0;
    for (tree_idx, tree) in multi_sample_points.iter().enumerate() {
        println!("Tree {}: {} columns", tree_idx, tree.len());
        for (col_idx, column) in tree.iter().enumerate() {
            println!("  Column {}: {} points", col_idx, column.len());
            multi_total += column.len();
        }
    }
    println!("Multi-component total points: {}", multi_total);
}