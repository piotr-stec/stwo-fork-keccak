use std::marker::PhantomData;
use std::ops::{Deref, DerefMut};

use super::{CircleEvaluation, CirclePoly, PolyOps};
use crate::core::circle::CirclePoint;
use crate::core::fields::m31::BaseField;
use crate::core::fields::qm31::{SecureField, SECURE_EXTENSION_DEGREE};
use crate::core::poly::circle::CircleDomain;
use crate::prover::backend::{ColumnOps, CpuBackend};
use crate::prover::poly::twiddles::TwiddleTree;
use crate::prover::poly::BitReversedOrder;
use crate::prover::secure_column::SecureColumnByCoords;

#[derive(Clone, Debug)]
pub struct SecureCirclePoly<B: ColumnOps<BaseField>>(pub [CirclePoly<B>; SECURE_EXTENSION_DEGREE]);

impl<B: PolyOps> SecureCirclePoly<B> {
    pub fn eval_at_point(&self, point: CirclePoint<SecureField>) -> SecureField {
        SecureField::from_partial_evals(self.eval_columns_at_point(point))
    }

    pub fn eval_columns_at_point(
        &self,
        point: CirclePoint<SecureField>,
    ) -> [SecureField; SECURE_EXTENSION_DEGREE] {
        [
            self[0].eval_at_point(point),
            self[1].eval_at_point(point),
            self[2].eval_at_point(point),
            self[3].eval_at_point(point),
        ]
    }

    pub fn log_size(&self) -> u32 {
        self[0].log_size()
    }

    pub fn evaluate_with_twiddles(
        &self,
        domain: CircleDomain,
        twiddles: &TwiddleTree<B>,
    ) -> SecureEvaluation<B, BitReversedOrder> {
        let polys = self.0.each_ref();
        let columns = polys.map(|poly| poly.evaluate_with_twiddles(domain, twiddles).values);
        SecureEvaluation::new(domain, SecureColumnByCoords { columns })
    }

    pub fn into_coordinate_polys(self) -> [CirclePoly<B>; SECURE_EXTENSION_DEGREE] {
        self.0
    }
}

impl<B: ColumnOps<BaseField>> Deref for SecureCirclePoly<B> {
    type Target = [CirclePoly<B>; SECURE_EXTENSION_DEGREE];

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

/// A [`SecureField`] evaluation defined on a [CircleDomain].
///
/// The evaluation is stored as a column major array of [`SECURE_EXTENSION_DEGREE`] many base field
/// evaluations. The evaluations are ordered according to the [CircleDomain] ordering.
#[derive(Clone)]
pub struct SecureEvaluation<B: ColumnOps<BaseField>, EvalOrder> {
    pub domain: CircleDomain,
    pub values: SecureColumnByCoords<B>,
    _eval_order: PhantomData<EvalOrder>,
}

impl<B: ColumnOps<BaseField>, EvalOrder> SecureEvaluation<B, EvalOrder> {
    pub fn new(domain: CircleDomain, values: SecureColumnByCoords<B>) -> Self {
        assert_eq!(domain.size(), values.len());
        Self {
            domain,
            values,
            _eval_order: PhantomData,
        }
    }

    pub fn into_coordinate_evals(
        self,
    ) -> [CircleEvaluation<B, BaseField, EvalOrder>; SECURE_EXTENSION_DEGREE] {
        let Self { domain, values, .. } = self;
        values.columns.map(|c| CircleEvaluation::new(domain, c))
    }

    pub fn to_cpu(&self) -> SecureEvaluation<CpuBackend, EvalOrder> {
        SecureEvaluation {
            domain: self.domain,
            values: self.values.to_cpu(),
            _eval_order: PhantomData,
        }
    }
}

impl<B: ColumnOps<BaseField>, EvalOrder> Deref for SecureEvaluation<B, EvalOrder> {
    type Target = SecureColumnByCoords<B>;

    fn deref(&self) -> &Self::Target {
        &self.values
    }
}

impl<B: ColumnOps<BaseField>, EvalOrder> DerefMut for SecureEvaluation<B, EvalOrder> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.values
    }
}

impl<B: PolyOps> SecureEvaluation<B, BitReversedOrder> {
    /// Computes a minimal [`SecureCirclePoly`] that evaluates to the same values as this
    /// evaluation, using precomputed twiddles.
    pub fn interpolate_with_twiddles(self, twiddles: &TwiddleTree<B>) -> SecureCirclePoly<B> {
        let domain = self.domain;
        let cols = self.values.columns;
        SecureCirclePoly(cols.map(|c| {
            CircleEvaluation::<B, BaseField, BitReversedOrder>::new(domain, c)
                .interpolate_with_twiddles(twiddles)
        }))
    }
}

impl<EvalOrder> From<CircleEvaluation<CpuBackend, SecureField, EvalOrder>>
    for SecureEvaluation<CpuBackend, EvalOrder>
{
    fn from(evaluation: CircleEvaluation<CpuBackend, SecureField, EvalOrder>) -> Self {
        Self::new(evaluation.domain, evaluation.values.into_iter().collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::circle::CirclePoint;
    use crate::core::fields::m31::BaseField;
    use crate::core::fields::qm31::SecureField;
    use crate::prover::backend::cpu::CpuBackend;
    use crate::prover::poly::circle::CirclePoly;

    #[test]
    fn test_secure_circle_poly_eval_at_point() {
        // Create simple circle polynomials for each coordinate
        // First coordinate: 1 + 2y + 3x + 4xy (coefficients in bit-reversed order: [1, 3, 2, 4])
        let coeffs0: Vec<BaseField> = vec![1, 3, 2, 4].iter().map(|&x| BaseField::from(x)).collect();
        let poly0 = CirclePoly::<CpuBackend>::new(coeffs0);

        // Second coordinate: 5 + 6y (coefficients: [5, 6])
        // let coeffs1: Vec<BaseField> = vec![5, 6].iter().map(|&x| BaseField::from(x)).collect();
        let mut poly1_extended = vec![BaseField::from(5), BaseField::from(6)];
        poly1_extended.resize(4, BaseField::from(0));
        let poly1 = CirclePoly::<CpuBackend>::new(poly1_extended);

        // Third coordinate: 7 (constant, extended to size 4)
        let mut coeffs2 = vec![BaseField::from(7)];
        coeffs2.resize(4, BaseField::from(0));
        let poly2 = CirclePoly::<CpuBackend>::new(coeffs2);

        // Fourth coordinate: 8 + 9y (coefficients: [8, 9], extended to size 4)
        let mut coeffs3 = vec![BaseField::from(8), BaseField::from(9)];
        coeffs3.resize(4, BaseField::from(0));
        let poly3 = CirclePoly::<CpuBackend>::new(coeffs3);

        // Create SecureCirclePoly
        let secure_poly = SecureCirclePoly([poly0, poly1, poly2, poly3]);

        // Test point (x=5, y=8) - same as Solidity test
        let point = CirclePoint{ x: SecureField::from(5), y: SecureField::from(8) };

        // Evaluate using eval_at_point
        let result = secure_poly.eval_at_point(point);

        // Manually compute expected result
        let eval0 = secure_poly[0].eval_at_point(point); // 1 + 2*8 + 3*5 + 4*5*8 = 192
        let eval1 = secure_poly[1].eval_at_point(point); // 5 + 6*8 = 53
        let eval2 = secure_poly[2].eval_at_point(point); // 7
        let eval3 = secure_poly[3].eval_at_point(point); // 8 + 9*8 = 80


        // Create expected result using from_partial_evals
        let expected = SecureField::from_partial_evals([eval0, eval1, eval2, eval3]);

        assert_eq!(result, expected, "SecureCirclePoly eval_at_point should match manual calculation");
    }

    #[test]
    fn test_secure_circle_poly_single_coord() {
        // Test with only first coordinate non-zero
        let coeffs0: Vec<BaseField> = vec![1, 2, 3, 4].iter().map(|&x| BaseField::from(x)).collect();
        let poly0 = CirclePoly::<CpuBackend>::new(coeffs0);

        // Other coordinates are constant zero
        let poly1 = CirclePoly::<CpuBackend>::new(vec![17,22,2323,1212].iter().map(|&x| BaseField::from(x)).collect());
        let poly2 = CirclePoly::<CpuBackend>::new(vec![2323,22,1212, 1212].iter().map(|&x| BaseField::from(x)).collect());
        let poly3 = CirclePoly::<CpuBackend>::new(vec![17,22,2323,1212].iter().map(|&x| BaseField::from(x)).collect());

        let secure_poly = SecureCirclePoly([poly0, poly1, poly2, poly3]);
        println!("SecureCirclePoly with single non-zero coordinate: {:?}", secure_poly);
        // Test point
        let point = CirclePoint{ x: SecureField::from(5), y: SecureField::from(8) };
        let result = secure_poly.eval_at_point(point);

        println!("Result of evaluation: {:?}", result);

    
    }

    #[test]
    fn test_secure_circle_poly_constant() {
        // Test with all coordinates having constant polynomials
        let mut extended_coeffs = vec![BaseField::from(42)];
        extended_coeffs.resize(4, BaseField::from(0)); // Extend to power of 2

        let poly0 = CirclePoly::<CpuBackend>::new(extended_coeffs.clone());
        let poly1 = CirclePoly::<CpuBackend>::new(extended_coeffs.clone());
        let poly2 = CirclePoly::<CpuBackend>::new(extended_coeffs.clone());
        let poly3 = CirclePoly::<CpuBackend>::new(extended_coeffs);

        let secure_poly = SecureCirclePoly([poly0, poly1, poly2, poly3]);

        // Test point - result should be same regardless of point for constant polynomial
        let point = CirclePoint{ x: SecureField::from(100), y: SecureField::from(200) };
        let result = secure_poly.eval_at_point(point);

        let expected = SecureField::from_partial_evals([
            SecureField::from(42),
            SecureField::from(42),
            SecureField::from(42),
            SecureField::from(42)
        ]);

        assert_eq!(result, expected, "Constant polynomial evaluation should be independent of point");
    }

    #[test]
    fn test_secure_circle_poly_identity_point() {
        // Test evaluation at identity point (1, 0)
        let coeffs0: Vec<BaseField> = vec![10, 20, 30, 40].iter().map(|&x| BaseField::from(x)).collect();
        let poly0 = CirclePoly::<CpuBackend>::new(coeffs0);

        let zero_coeffs = vec![BaseField::from(0); 4];
        let poly1 = CirclePoly::<CpuBackend>::new(zero_coeffs.clone());
        let poly2 = CirclePoly::<CpuBackend>::new(zero_coeffs.clone());
        let poly3 = CirclePoly::<CpuBackend>::new(zero_coeffs);

        let secure_poly = SecureCirclePoly([poly0, poly1, poly2, poly3]);

        // Identity point (1, 0)
        let point = CirclePoint{ x: SecureField::from(1), y: SecureField::from(0) };
        let result = secure_poly.eval_at_point(point);

        // For polynomial 10 + 20x + 30y + 40xy at (1, 0):
        // result = 10 + 20*1 + 30*0 + 40*1*0 = 30
        let expected_eval = BaseField::from(10) + BaseField::from(20) * BaseField::from(1);
        let expected = SecureField::from_partial_evals([
            SecureField::from(expected_eval),
            SecureField::from(0),
            SecureField::from(0),
            SecureField::from(0)
        ]);

        println!("Expected eval at identity: {:?}", expected_eval);
        println!("Result at identity: {:?}", result);

        assert_eq!(result, expected, "Evaluation at identity point should match expected");
    }
}
