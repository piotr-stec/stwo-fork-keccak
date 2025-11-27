// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SecureCirclePoly.sol";
import "../fields/QM31Field.sol";
import "../core/CirclePoint.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


/**
 * @title SecurePolyTest
 * @notice Exact mirror of the Rust test_secure_circle_poly_single_coord
 * @dev Tests identical polynomial coefficients and evaluation point as Rust version
 */
contract SecurePolyTest is Test {
    using QM31Field for QM31Field.QM31;

    /**
     * @notice Mirror of Rust test_secure_circle_poly_single_coord
     * @dev Uses identical coefficients:
     *      - coeffs0: [1,3,2,4,1,3,2,4,1,3,2,4,1,3,2,4] (16 elements)
     *      - coeffs1: [17,22,2323,1212] (4 elements)
     *      - coeffs2: [2323,22,1212,1212,2323,22,1212,1212] (8 elements)
     *      - coeffs3: [17,22,2323,1212] (4 elements)
     *      Point: (x=5, y=8)
     */
    function test_secure_circle_poly_single_coord() public {
        console.log("=== Rust Mirror Test: test_secure_circle_poly_single_coord ===");
        
        // First coordinate: 16 elements [1,2,3,4]
        uint32[] memory coeffs0 = new uint32[](4);
        coeffs0[0] = 1;
        coeffs0[1] = 2;
        coeffs0[2] = 3;
        coeffs0[3] = 4;


        // Second coordinate: 4 elements [17,22,2323,1212]
        uint32[] memory coeffs1 = new uint32[](4);
        coeffs1[0] = 17;
        coeffs1[1] = 22;
        coeffs1[2] = 2323;
        coeffs1[3] = 1212;

        // Third coordinate: 8 elements [2323,22,1212,1212,2323,22,1212,1212]
        uint32[] memory coeffs2 = new uint32[](4);
        coeffs2[0] = 2323;
        coeffs2[1] = 22;
        coeffs2[2] = 1212;
        coeffs2[3] = 1212;
   

        // Fourth coordinate: 4 elements [17,22,2323,1212]
        uint32[] memory coeffs3 = new uint32[](4);
        coeffs3[0] = 17;
        coeffs3[1] = 22;
        coeffs3[2] = 2323;
        coeffs3[3] = 1212;

        console.log("Creating SecureCirclePoly with coefficients:");
        console.log("coeffs0 length:", coeffs0.length);
        console.log("coeffs1 length:", coeffs1.length);
        console.log("coeffs2 length:", coeffs2.length);
        console.log("coeffs3 length:", coeffs3.length);

        // Create SecureCirclePoly
        SecureCirclePoly.SecurePoly memory poly = SecureCirclePoly.createSecurePoly(
            coeffs0, coeffs1, coeffs2, coeffs3
        );

        // Test point (x=5, y=8) - identical to Rust test
        CirclePoint.Point memory point = CirclePoint.Point({
            x: QM31Field.fromM31(5, 0, 0, 0),
            y: QM31Field.fromM31(8, 0, 0, 0)
        });

        console.log("Evaluating at point (5, 8)");
        uint256 startGas = gasleft();
        // Evaluate polynomial at point
        QM31Field.QM31 memory result = SecureCirclePoly.evalAtPoint(poly, point);
        uint256 endGas = gasleft();
        console.log("Gas used for evaluation:", startGas - endGas);

        console.log("=== Evaluation Results ===");
        console.log("Result components:");
        console.log("first.real:", result.first.real);
        console.log("first.imag:", result.first.imag);
        console.log("second.real:", result.second.real);
        console.log("second.imag:", result.second.imag);
    }


}