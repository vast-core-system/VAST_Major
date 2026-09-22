`timescale 1ns/1ps

module memristor_top #(
    parameter integer ROWS = 4,
    parameter integer COLS = 4
)(
    input  logic clk,
    input  logic rst,

    // ============================================================
    // PROGRAMMING INTERFACE
    // ============================================================

    input  logic        load_enable,
    input  logic [1:0]  row_sel,
    input  logic [1:0]  col_sel,
    input  logic [7:0]  weight_data,

    // ============================================================
    // MAC INPUT
    // ============================================================

    input logic [7:0] x [0:ROWS-1],

    // ============================================================
    // MAC OUTPUT
    // ============================================================

    output logic [17:0] y [0:COLS-1],

    // ============================================================
    // STATUS
    // ============================================================

    output logic busy,
    output logic done
);


    // ============================================================
    // CONSTANTS
    // ============================================================

    localparam integer STATE_SCALE = 65536;

    // Q16.16 programming voltages

    localparam signed [31:0] V_UP =
        32'sd19661;       // +0.30 V

    localparam signed [31:0] V_DOWN =
        -32'sd13107;      // -0.20 V

    // Target-state tolerance

    localparam integer STATE_TOLERANCE = 200;


    // ============================================================
    // VTEAM ARRAY
    // ============================================================

    logic signed [31:0] cell_voltage [0:ROWS-1][0:COLS-1];

    logic [31:0] resistance [0:ROWS-1][0:COLS-1];

    logic signed [31:0] current [0:ROWS-1][0:COLS-1];

    logic [31:0] state_var [0:ROWS-1][0:COLS-1];

    logic [1:0] ternary_output [0:ROWS-1][0:COLS-1];


    // ============================================================
    // DIGITAL WEIGHTS USED BY MAC
    // ============================================================

    logic [7:0] w [0:ROWS-1][0:COLS-1];


    // ============================================================
    // PROGRAMMING CONTROL SIGNALS
    // ============================================================

    logic [31:0] target_state;

    logic [31:0] selected_state;

    logic signed [31:0] program_voltage;


    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [1:0] {
        IDLE,
        PROGRAM,
        FINISH
    } state_t;

    state_t state;


    // ============================================================
    // WEIGHT → TARGET STATE
    //
    // weight_data = 0..255
    //
    // target_state = weight_data × 65536 / 255
    // ============================================================

    always_comb begin

        target_state =
            (weight_data * STATE_SCALE) / 255;

        // VTEAM minimum state

        if (target_state < 1)
            target_state = 1;

        // VTEAM maximum state

        if (target_state > 65536)
            target_state = 65536;

    end


    // ============================================================
    // SELECT CURRENT STATE OF SELECTED CELL
    // ============================================================

    always_comb begin

        selected_state =
            state_var[row_sel][col_sel];

    end


    // ============================================================
    // PROGRAMMING VOLTAGE CONTROLLER
    //
    // If state is below target:
    //      +0.30 V
    //
    // If state is above target:
    //      -0.20 V
    //
    // If state is close enough:
    //      0 V
    // ============================================================

    always_comb begin

        program_voltage = 32'sd0;

        if (state == PROGRAM) begin

            if (selected_state + STATE_TOLERANCE
                    < target_state) begin

                program_voltage = V_UP;

            end

            else if (selected_state
                    > target_state + STATE_TOLERANCE) begin

                program_voltage = V_DOWN;

            end

            else begin

                program_voltage = 32'sd0;

            end

        end

    end


    // ============================================================
    // PROGRAMMING FSM
    // ============================================================

    always_ff @(posedge clk) begin

        if (rst) begin

            state <= IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
        end

        else begin

            case (state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------

                IDLE: begin

                    busy <= 1'b0;
                    done <= 1'b0;

                    if (load_enable) begin

                        state <= PROGRAM;
                        busy  <= 1'b1;

                    end

                end


                // ------------------------------------------------
                // PROGRAM
                // ------------------------------------------------

                PROGRAM: begin

                    busy <= 1'b1;
                    done <= 1'b0;

                    // Stop programming once target is reached

                    if ((selected_state
                            + STATE_TOLERANCE >= target_state) &&
                        (selected_state
                            <= target_state + STATE_TOLERANCE)) begin

                        state <= FINISH;

                    end

                end


                // ------------------------------------------------
                // FINISH
                // ------------------------------------------------

                FINISH: begin

                    busy  <= 1'b0;
                    done  <= 1'b1;

                    state <= IDLE;

                end


                // ------------------------------------------------
                // SAFETY
                // ------------------------------------------------

                default: begin

                    state <= IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;

                end

            endcase

        end

    end


    // ============================================================
    // 4-to-16 CELL DECODER
    //
    // Only the selected cell receives program_voltage.
    // All other cells receive 0 V.
    // ============================================================

    genvar r, c;

    generate

        for (r = 0; r < ROWS; r = r + 1) begin : ROW_DECODER

            for (c = 0; c < COLS; c = c + 1) begin : COL_DECODER

                always_comb begin

                    if ((state == PROGRAM) &&
                        (row_sel == r) &&
                        (col_sel == c)) begin

                        cell_voltage[r][c] =
                            program_voltage;

                    end

                    else begin

                        cell_voltage[r][c] =
                            32'sd0;

                    end

                end

            end

        end

    endgenerate


    // ============================================================
    // VTEAM MEMRISTOR ARRAY
    // ============================================================

    generate

        for (r = 0; r < ROWS; r = r + 1) begin : VTEAM_ROWS

            for (c = 0; c < COLS; c = c + 1) begin : VTEAM_COLS

                vteam_memristor memristor_cell (

                    .clk(clk),
                    .rst(rst),

                    .voltage(
                        cell_voltage[r][c]
                    ),

                    .resistance(
                        resistance[r][c]
                    ),

                    .current(
                        current[r][c]
                    ),

                    .state_var(
                        state_var[r][c]
                    ),

                    .ternary_output(
                        ternary_output[r][c]
                    )

                );

            end

        end

    endgenerate


    // ============================================================
    // RESISTANCE → DIGITAL WEIGHT
    //
    // VTEAM resistance equation:
    //
    // R = R_OFF - (R_OFF - R_ON) × w
    //
    // Therefore:
    //
    // w = (R_OFF - R)/(R_OFF - R_ON)
    //
    // Finally:
    //
    // digital_weight = w × 255
    //
    // This ensures that the MAC weight is derived from the
    // actual VTEAM resistance.
    // ============================================================

    function automatic [7:0] resistance_to_weight(
        input logic [31:0] r_value
    );

        integer weight_temp;

        begin

            // -----------------------------------------------
            // OFF state
            // -----------------------------------------------

            if (r_value >= 16000) begin

                resistance_to_weight = 8'd0;

            end

            // -----------------------------------------------
            // ON state
            // -----------------------------------------------

            else if (r_value <= 100) begin

                resistance_to_weight = 8'd255;

            end

            // -----------------------------------------------
            // Intermediate state
            // -----------------------------------------------

            else begin

                weight_temp =
                    ((16000 - r_value) * 255)
                    /
                    (16000 - 100);


                // Saturation

                if (weight_temp < 0)
                    weight_temp = 0;

                if (weight_temp > 255)
                    weight_temp = 255;


                resistance_to_weight =
                    weight_temp[7:0];

            end

        end

    endfunction


    // ============================================================
    // CONVERT ALL VTEAM RESISTANCES INTO MAC WEIGHTS
    // ============================================================

    generate

        for (r = 0; r < ROWS; r = r + 1) begin : WEIGHT_ROWS

            for (c = 0; c < COLS; c = c + 1) begin : WEIGHT_COLS

                always_comb begin

                    w[r][c] =
                        resistance_to_weight(
                            resistance[r][c]
                        );

                end

            end

        end

    endgenerate


    // ============================================================
    // MAC
    //
    // y[i] = Σ x[j] × w[j][i]
    // ============================================================

    crossbar #(
        .I(COLS),
        .J(ROWS)
    ) mac_inst (

        .x(x),
        .w(w),

        .clk(clk),
        .rst(rst),

        .y(y)

    );


endmodule