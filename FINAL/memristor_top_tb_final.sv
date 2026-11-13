
`timescale 1ns/1ps

module tb_memristor_top;

    parameter ROWS = 4;
    parameter COLS = 4;

    logic clk;
    logic rst;
    logic load_weights;
    logic wr_en;
    logic [4:0] wr_addr;
    logic signed [8:0] wr_data;

    logic [$clog2(COLS)-1:0] y_sel;
    logic signed [18:0] y_data;
    logic busy, done;

    integer errors;

    integer expected_x [0:3];
    integer expected_w [0:3][0:3];

    // DUT
    memristor_top #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .load_weights(load_weights),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .y_sel(y_sel),
        .y_data(y_data),
        .busy(busy),
        .done(done)
    );

    // Clock: 10 ns
    initial clk = 0;
    always #5 clk = ~clk;

    // Write operation
    task automatic write_data(
        input logic [4:0] address,
        input integer data
    );
        begin
            @(negedge clk);
            wr_en   = 1'b1;
            wr_addr = address;
            wr_data = data;

            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    initial begin

        errors = 0;

        rst = 0;
        wr_en = 0;
        wr_addr = 0;
        wr_data = 0;
        load_weights = 0;
        y_sel = 0;

        // --------------------------------
        // INPUTS AND WEIGHTS
        // --------------------------------

        expected_x[0] = 55;
        expected_x[1] = 32;
        expected_x[2] = 4;
        expected_x[3] = 18;

        expected_w[0][0] = 28;
        expected_w[0][1] = -45;
        expected_w[0][2] = 112;
        expected_w[0][3] = 63;

        expected_w[1][0] = -76;
        expected_w[1][1] = 91;
        expected_w[1][2] = 24;
        expected_w[1][3] = -18;

        expected_w[2][0] = 105;
        expected_w[2][1] = -32;
        expected_w[2][2] = 67;
        expected_w[2][3] = 89;

        expected_w[3][0] = -54;
        expected_w[3][1] = 120;
        expected_w[3][2] = -11;
        expected_w[3][3] = 42;

        // --------------------------------
        // RESET
        // --------------------------------

        #2 rst = 1;
        #20 rst = 0;

        repeat (2) @(negedge clk);

        // --------------------------------
        // WRITE WEIGHTS
        // --------------------------------

        for (int r = 0; r < ROWS; r++) begin
            for (int c = 0; c < COLS; c++) begin
                write_data(
                    r*COLS+c,
                    expected_w[r][c]
                );
            end
        end

        // --------------------------------
        // WRITE INPUT VECTOR
        // --------------------------------

        for (int r = 0; r < ROWS; r++) begin
            write_data(
                5'b10000 | r,
                expected_x[r]
            );
        end

        repeat (2) @(negedge clk);

        // --------------------------------
        // START PROGRAMMING
        // --------------------------------

        load_weights = 1'b1;

        @(negedge clk);
        load_weights = 1'b0;

        // Wait for all memristor cells
        // to finish programming

        wait(done == 1'b1);

        // Allow registered results to settle
        #2;

        // --------------------------------
        // DISPLAY INPUT VECTOR
        // --------------------------------

        $display("\n========== INPUT VECTOR ==========");

        for (int r = 0; r < ROWS; r++)
            $display("X[%0d] = %0d",
                     r, $signed(dut.x[r]));

        // --------------------------------
        // DISPLAY RECONSTRUCTED WEIGHTS
        // --------------------------------

        $display("\n======= RECONSTRUCTED WEIGHTS =======");

        for (int r = 0; r < ROWS; r++) begin

            for (int c = 0; c < COLS; c++) begin

                $write("%0d\t",
                       $signed(dut.w_reg[r][c]));

                if ($signed(dut.w_reg[r][c]) !=
                    expected_w[r][c]) begin

                    errors = errors + 1;

                    $display(
                        "\nWEIGHT ERROR [%0d][%0d]: Expected %0d, Actual %0d",
                        r, c,
                        expected_w[r][c],
                        $signed(dut.w_reg[r][c])
                    );
                end

            end

            $display("");
        end

        // --------------------------------
        // DISPLAY ACTUAL MAC OUTPUTS
        // --------------------------------

        $display("\n========== MAC OUTPUTS ==========");

        for (int c = 0; c < COLS; c++) begin

            $display(
                "Y[%0d] = %0d",
                c,
                $signed(dut.mac_y[c])
            );

        end

        $display("================================");

        // --------------------------------
        // RECONSTRUCTION DEBUG
        // --------------------------------

        $display("\n========== RECONSTRUCTION DEBUG ==========");

        $display("Cell [0][1]: State=%0d Resistance=%0d d=%0d",
            dut.state_var[0][1],
            dut.resistance[0][1],
            dut.G_ROW[0].G_COL[1].d_pipe);

        $display("Cell [0][2]: State=%0d Resistance=%0d d=%0d",
            dut.state_var[0][2],
            dut.resistance[0][2],
            dut.G_ROW[0].G_COL[2].d_pipe);

        $display("Cell [1][0]: State=%0d Resistance=%0d d=%0d",
            dut.state_var[1][0],
            dut.resistance[1][0],
            dut.G_ROW[1].G_COL[0].d_pipe);

        $display("Cell [2][2]: State=%0d Resistance=%0d d=%0d",
            dut.state_var[2][2],
            dut.resistance[2][2],
            dut.G_ROW[2].G_COL[2].d_pipe);

        $display("Cell [3][0]: State=%0d Resistance=%0d d=%0d",
            dut.state_var[3][0],
            dut.resistance[3][0],
            dut.G_ROW[3].G_COL[0].d_pipe);
        
        
       // --------------------------------
       // TARGET VS ACTUAL STATE DEBUG
       // --------------------------------

       $display("\n========== PROGRAMMING ERROR DEBUG ==========");

       $display("Cell [0][1]: Target=%0d Actual=%0d Err=%0d Ready=%b",
           dut.P_ROW[0].P_COL[1].target,
           dut.state_var[0][1],
           dut.P_ROW[0].P_COL[1].err,
           dut.cell_ready[1]);

       $display("Cell [0][2]: Target=%0d Actual=%0d Err=%0d Ready=%b",
           dut.P_ROW[0].P_COL[2].target,
           dut.state_var[0][2],
           dut.P_ROW[0].P_COL[2].err,
           dut.cell_ready[2]);

       $display("Cell [1][0]: Target=%0d Actual=%0d Err=%0d Ready=%b",
           dut.P_ROW[1].P_COL[0].target,
           dut.state_var[1][0],
           dut.P_ROW[1].P_COL[0].err,
           dut.cell_ready[4]);

       $display("Cell [2][2]: Target=%0d Actual=%0d Err=%0d Ready=%b",
           dut.P_ROW[2].P_COL[2].target,
           dut.state_var[2][2],
           dut.P_ROW[2].P_COL[2].err,
           dut.cell_ready[10]);

       $display("Cell [3][0]: Target=%0d Actual=%0d Err=%0d Ready=%b",
           dut.P_ROW[3].P_COL[0].target,
           dut.state_var[3][0],
           dut.P_ROW[3].P_COL[0].err,
           dut.cell_ready[12]);

       $display("=============================================");

        // --------------------------------
        // FINAL RESULT
        // --------------------------------

        $display("\n================================");

        if (errors == 0)
            $display("ALL WEIGHTS RECONSTRUCTED CORRECTLY");
        else
            $display("WEIGHT MISMATCHES = %0d", errors);

        $display("================================\n");

        $finish;

    end

endmodule
