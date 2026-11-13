

// -----------------------------------------------------------------------------
// Crossbar MAC:  y[c] = sum_r x[r] * w[r][c]
//
// Purely combinational. Multipliers are forced into LUT fabric (no DSP slices).
//
// x is signed 9-bit (-256..255) w is signed 8-bit (-128..127), so
//   * one product spans -65280 .. 65025  -> needs 17 signed bits (was 16)
//   * the sum of 4 products spans +/-261120 -> needs 19 signed bits (was 18)
// The 19-bit output y therefore holds the full range with no truncation.
// -----------------------------------------------------------------------------
(* use_dsp = "no" *)
module crossbar #(
    parameter ROWS = 4,
    parameter COLS = 4
)(
    input  logic signed [8:0]  x [ROWS],
    input  logic signed [7:0]  w [ROWS][COLS],   // signed weights -128 to +127
    output logic signed [18:0] y [COLS]
);

    always_comb begin
        for (int c = 0; c < COLS; c++) begin
            logic signed [18:0] acc;
            logic signed [16:0] prod;
            acc = '0;
            for (int r = 0; r < ROWS; r++) begin
                prod = x[r] * w[r][c];
                acc  = acc + 19'(prod);
            end
            y[c] = acc;
        end
    end

endmodule