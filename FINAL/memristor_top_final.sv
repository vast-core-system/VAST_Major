module memristor_top #(
    parameter ROWS = 4,
    parameter COLS = 4
)(
    input  logic  clk,
    input  logic  rst,
    input  logic  load_weights,

    // Write port
    input  logic               wr_en,
    input  logic        [4:0]  wr_addr,
    input  logic signed [8:0]  wr_data,

    // Read port
    input  logic [$clog2(COLS)-1:0] y_sel,
    output logic signed [18:0] y_data,

    // Status
    output logic               busy,
    output logic               done
);

    localparam logic signed [17:0] TOL = 18'sd100;
    localparam int NCELL = ROWS * COLS;
    logic [NCELL-1:0] pulse_pending;

    typedef enum logic [1:0] {
        IDLE,
        PROGRAM,
        WAIT_WEIGHT,
        FINISH
    } state_t;

    state_t state;

    // -------------------------------------------------
    // Input storage
    // -------------------------------------------------

    logic signed [7:0] weights [0:ROWS-1][0:COLS-1];
    logic signed [8:0] x [0:ROWS-1];

    // -------------------------------------------------
    // Input write logic
    // -------------------------------------------------

  always_ff @(posedge clk) begin
    if (wr_en && !busy) begin

        if (wr_addr[4]) begin
            if (wr_addr[1:0] < ROWS)
                x[wr_addr[1:0]] <= wr_data;
        end
        else begin
            for (int r = 0; r < ROWS; r++) begin
                for (int c = 0; c < COLS; c++) begin
                    if (wr_addr[3:0] == r*COLS+c) begin

                        if ((wr_data >= -9'sd128) && (wr_data <=  9'sd127))
                            weights[r][c] <= $signed(wr_data[7:0]);

                    end
                end
            end
        end

    end
end
    // -------------------------------------------------
    // Per-cell programming
    // -------------------------------------------------

    logic [16:0] state_var [0:ROWS-1][0:COLS-1];

    logic [13:0] resistance [0:ROWS-1][0:COLS-1];

    logic signed [7:0] w_reg [0:ROWS-1][0:COLS-1];

    logic [NCELL-1:0] cell_ready;

    // -------------------------------------------------
    // Registered resistance-to-weight pipeline
    // -------------------------------------------------

    for (genvar r = 0; r < ROWS; r++) begin : G_ROW

        for (genvar c = 0; c < COLS; c++) begin : G_COL

            logic [13:0] resistance_pipe;
            logic [13:0] d_pipe;

            logic [23:0] part_a_pipe;
            logic [23:0] part_b_pipe;

            // Stage 1: Register resistance
            always_ff @(posedge clk or posedge rst) begin
                if (rst)
                    resistance_pipe <= 14'd14410;
                else
                    resistance_pipe <= resistance[r][c];
            end

            // Stage 2: Calculate d = 16000 - resistance
            always_ff @(posedge clk or posedge rst) begin
                if (rst)
                    d_pipe <= 14'd1590;
                else
                    d_pipe <= 14'd16000 - resistance_pipe;
            end

            // Stage 3: Calculate partial shift-add sums
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    part_a_pipe <= 24'd1653600;
                    part_b_pipe <= 24'd19080;
                end
                else begin
                    part_a_pipe <=
                        (24'(d_pipe) << 10) +
                        (24'(d_pipe) << 4);

                    part_b_pipe <=
                        (24'(d_pipe) << 3) +
                        (24'(d_pipe) << 2);
                end
            end

            
            // Stage 4: Final addition, rounding and weight register
            always_ff @(posedge clk or posedge rst) begin
                    if (rst)
                             w_reg[r][c] <= 8'sd25;
                    else
                             w_reg[r][c] <= (part_a_pipe + part_b_pipe + 24'd32768) >> 16;
                    end
        end
    end

    // -------------------------------------------------
    // Memristor programming and pulse generation
    // -------------------------------------------------

    for (genvar r = 0; r < ROWS; r++) begin : P_ROW

        for (genvar c = 0; c < COLS; c++) begin : P_COL

            logic [16:0] target;
            logic signed [17:0] err;

            logic pulse_up;
            logic pulse_down;

            logic pulse_up_reg;
            logic pulse_down_reg;

            // Target state from input weight
            assign target = {1'b0, weights[r][c], weights[r][c]} | 17'(weights[r][c] == 8'd0);

            // State error
            assign err = $signed({1'b0, state_var[r][c]}) - $signed({1'b0, target});

            // Cell ready detection
            assign cell_ready[r*COLS+c] =(err <= TOL) && (err >= -TOL);
 
            // Combinational programming conditions
            assign pulse_up = (state == PROGRAM) && !cell_ready[r*COLS+c] && (err < 0);

            assign pulse_down = (state == PROGRAM) && !cell_ready[r*COLS+c] && (err >= 0);
            
            assign pulse_pending[r*COLS+c] = pulse_up_reg | pulse_down_reg;

            // Registered programming pulses
            always_ff @(posedge clk or posedge rst) begin

                if (rst) begin
                    pulse_up_reg   <= 1'b0;
                    pulse_down_reg <= 1'b0;
                end
                else begin
                    pulse_up_reg   <= pulse_up;
                    pulse_down_reg <= pulse_down;
                end

            end

            // VTEAM instance
            vteam_memristor memristor_inst (
                .clk        (clk),
                .rst        (rst),
                .V_OFF      (pulse_up_reg),
                .V_ON       (pulse_down_reg),
                .state_var  (state_var[r][c]),
                .resistance (resistance[r][c])
            );

        end
    end

    // -------------------------------------------------
    // Crossbar MAC
    // -------------------------------------------------

    logic signed [18:0] mac_y [0:COLS-1];

    crossbar #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) mac_inst (
        .x(x),
        .w(w_reg),
        .y(mac_y)
    );

    // -------------------------------------------------
    // FSM
    // -------------------------------------------------

    logic [2:0] weight_wait_count;

    assign busy = (state != IDLE);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            state            <= IDLE;
            done             <= 1'b0;
            weight_wait_count <= 3'd0;
        end
        else begin

            done <= (state == FINISH);

            case (state)

                IDLE: begin
                    weight_wait_count <= 3'd0;

                    if (load_weights)
                        state <= PROGRAM;
                end

               PROGRAM: begin
                    if ((&cell_ready) && !(|pulse_pending)) begin
                                state <= WAIT_WEIGHT;
                                weight_wait_count <= 3'd0;
                    end 
                end

                WAIT_WEIGHT: begin
                    if (weight_wait_count == 3'd4) begin
                        state <= FINISH;
                    end
                    else begin
                        weight_wait_count <=
                            weight_wait_count + 1'b1;
                    end
                end

                FINISH: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase

        end
    end

    // -------------------------------------------------
    // Result capture and read mux
    // -------------------------------------------------

    logic signed [18:0] y_reg [0:COLS-1];

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            y_data <= 19'sd0;

            for (int c = 0; c < COLS; c++)
                y_reg[c] <= 19'sd0;

        end
        else begin

            if (state == FINISH) begin
                for (int c = 0; c < COLS; c++)
                    y_reg[c] <= mac_y[c];
            end

            y_data <= y_reg[y_sel];

        end
    end

endmodule
