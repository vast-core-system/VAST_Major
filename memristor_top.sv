`timescale 1ns/1ps

module memristor_top #(
    parameter integer ROWS = 4,   //Fixed parameters for 4x4 matrix
    parameter integer COLS = 4
)(
    input  logic clk,
    input  logic rst,


    input  logic        load_enable,  // Logic signal to indicate when a memristor can be programmed with a particular weight
    input  logic [1:0]  row_sel,  //Used to choose row of specific memmristor
    input  logic [1:0]  col_sel,  //Used to choose column of specific memmristor
    input  logic [7:0]  weight_data,  //8-bit weight data, comes from the NN, to program the memristor


    input logic [7:0] x [0:ROWS-1],  //Input matrix for MAC computation


    output logic [17:0] y [0:COLS-1],  //Output matrix for post-MAC computation


    output logic busy,  // busy, done -> Internal FSM signals to indicate when a memristor is being programmed, and when it is finished
    output logic done
);


    localparam integer STATE_SCALE = 65536;  // Scale-down factor for Q16.16 representation

    // Q16.16 programming voltages

    localparam signed [31:0] V_UP =
    32'sd19661;       // +0.30 V -> Used when state variable (w) value to be increased while programming

    localparam signed [31:0] V_DOWN =
    -32'sd13107;      // -0.20 V -> Used when state variable (w) value to be decreased while programming


    localparam integer STATE_TOLERANCE = 200; //Tolerance value for target state, converts to 0.00305175781

    // If programmed state, is within this limit of target state, we can stop programming


   // VTEAM memristor inputs and outputs
    
    logic signed [31:0] cell_voltage [0:ROWS-1][0:COLS-1]; // Memristor voltages

    logic [31:0] resistance [0:ROWS-1][0:COLS-1]; // Memristance

    logic signed [31:0] current [0:ROWS-1][0:COLS-1]; // Memristor current

    logic [31:0] state_var [0:ROWS-1][0:COLS-1]; // State variable 'w' values

    logic [1:0] ternary_output [0:ROWS-1][0:COLS-1];  //Quantised ternary state matrix


    logic [7:0] w [0:ROWS-1][0:COLS-1]; //Weight matrix

    logic [31:0] target_state;  //Target state variable value

    logic [31:0] selected_state;  //Current selected state value

    logic signed [31:0] program_voltage;  // Programming voltage value to be chose (+0.3/-0.2 V), depending on weight to be programmed


    typedef enum logic [1:0] {
        IDLE,
        PROGRAM,
        FINISH
    } state_t;  // FSM states: IDLE-> PROGRAM -> FINISH -> IDLE

    state_t state;


    always_comb begin

        target_state =
        (weight_data * STATE_SCALE) / 255; //Target state mapping logic -> (I/p weight * 65536)/255

        // Bounds the VTEAM state to it's minimum value

        if (target_state < 1)
            target_state = 1;

        // Bounds the VTEAM state to it's maximum value -> Ensures valid logic as defined in VTEAM model


        if (target_state > 65536)
            target_state = 65536;

    end


    // Choosing the memristor to be programmed and fetching it's current state

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
                < target_state) begin  // Checking whether selected state is less than target state, if TRUE -> apply V_UP = +0.30 V

                program_voltage = V_UP;

            end

            else if (selected_state
                > target_state + STATE_TOLERANCE) begin  // Checking whether selected state is more than target state, if TRUE -> apply V_DOWN = -0.20 V

                program_voltage = V_DOWN;

            end

            else begin

                program_voltage = 32'sd0;  // If within tolerance, no need to change state value, program_voltage = 0 V

            end

        end

    end


  // Sequential block, changes happen on clock edge

    always_ff @(posedge clk) begin

        if (rst) begin
// Default state is IDLE, if rst = 1, FSM starts at that state
            state <= IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
        end

        else begin

            case (state)
                // Initial state -> IDLE, both busy and done = 0 (No programming happening)

                IDLE: begin

                    busy <= 1'b0;
                    done <= 1'b0;

                    if (load_enable) begin  // Load_enable indicates that memristor is to be programmed

                        state <= PROGRAM; // FSM transitions to PROGRAM state
                        busy  <= 1'b1; // busy is enabled

                    end

                end


                PROGRAM: begin

                    busy <= 1'b1; 
                    done <= 1'b0;

                    // Logic to check whether memristor has reached target_state or not
                    if ((selected_state
                            + STATE_TOLERANCE >= target_state) &&
                        (selected_state
                            <= target_state + STATE_TOLERANCE)) begin

                        state <= FINISH; //Once programming is done, the FSM transitions to FINISH

                    end

                end


                // ------------------------------------------------
                // FINISH
                // ------------------------------------------------

                FINISH: begin

                    busy  <= 1'b0;
                    done  <= 1'b1; // Done signal is raised

                    state <= IDLE; // FSM transitions back to IDLE, to wait for the next memristor to be programmed

                end

                // Default state -> IDLE

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


    //VTEAM memristor array instantiation

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


// Maps memristor resistance to the MAC weights

    function automatic [7:0] resistance_to_weight(
        input logic [31:0] r_value
    );

        integer weight_temp;

        begin


            if (r_value >= 16000) begin

                resistance_to_weight = 8'd0; // If resistance value is >= R_OFF, weight = 0

            end

            else if (r_value <= 100) begin

                resistance_to_weight = 8'd255;  // If resistance value is <= R_ON, weight = 255
 

            end
            
            else begin

                weight_temp =
                    ((16000 - r_value) * 255)
                    /
                    (16000 - 100);
                // Calculated for intermediate states using, ((R_OFF - R) * 255)/(R_OFF - R_ON)

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



    generate

        for (r = 0; r < ROWS; r = r + 1) begin : WEIGHT_ROWS

            for (c = 0; c < COLS; c = c + 1) begin : WEIGHT_COLS

                always_comb begin

                    w[r][c] =
                        resistance_to_weight(
                            resistance[r][c]
                        );  
                    // Maps memristance to weights, for each of the 16 memristors in the VTEAM array

                end

            end

        end

    endgenerate

//MAC instantiation

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
