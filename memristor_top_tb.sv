`timescale 1ns/1ps

module memristor_top_tb;

    parameter ROWS = 4;
    parameter COLS = 4;

    // --------------------------------------------------
    // Clock and reset
    // --------------------------------------------------
    logic clk;
    logic rst;

    // --------------------------------------------------
    // Programming interface
    // --------------------------------------------------
    logic        load_enable;
    logic [1:0]  row_sel;
    logic [1:0]  col_sel;
    logic [7:0]  weight_data;

    // --------------------------------------------------
    // MAC input/output
    // --------------------------------------------------
    logic [7:0]  x [0:ROWS-1];
    logic [17:0] y [0:COLS-1];

    // --------------------------------------------------
    // Status
    // --------------------------------------------------
    logic busy;
    logic done;

    // --------------------------------------------------
    // DUT
    // --------------------------------------------------
    memristor_top #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) dut (
        .clk(clk),
        .rst(rst),

        .load_enable(load_enable),
        .row_sel(row_sel),
        .col_sel(col_sel),
        .weight_data(weight_data),

        .x(x),
        .y(y),

        .busy(busy),
        .done(done)
    );

    // --------------------------------------------------
    // Clock: 10 ns period
    // --------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // --------------------------------------------------
    // Time display
    // --------------------------------------------------
    initial begin
        $timeformat(-9, 2, " ns", 12);
    end

    // --------------------------------------------------
    // Reset task
    // --------------------------------------------------
    task reset_dut;
        begin
            rst = 1'b1;
            load_enable = 1'b0;

            row_sel = 2'd0;
            col_sel = 2'd0;
            weight_data = 8'd0;

            for (integer i = 0; i < ROWS; i = i + 1)
                x[i] = 8'd0;

            repeat (3) @(posedge clk);

            rst = 1'b0;

            @(posedge clk);

            $display("\n========================================");
            $display("RESET COMPLETE");
            $display("========================================\n");
        end
    endtask


    // --------------------------------------------------
    // Program one cell
    // --------------------------------------------------
    task program_cell(
        input integer row,
        input integer col,
        input integer weight
    );

        integer timeout;

        begin

            $display("----------------------------------------");
            $display("Programming M[%0d][%0d] = %0d",
                     row, col, weight);

            // Set programming inputs while safely away
            // from the active clock edge.
            @(negedge clk);

            row_sel     = row[1:0];
            col_sel     = col[1:0];
            weight_data = weight[7:0];

            load_enable = 1'b1;

            // Hold load_enable for one clock
            @(posedge clk);

            @(negedge clk);
            load_enable = 1'b0;

            // Wait until programming finishes
            timeout = 0;

            while (!done && timeout < 1000000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 1000000) begin
                $display("ERROR: Programming timeout!");
            end
            else begin

                // Give signals one delta/cycle to settle
                @(negedge clk);

                $display("Programming complete.");
                $display("  Cell       = M[%0d][%0d]", row, col);
                $display("  Target     = %0d", weight);
                $display("  State      = %0d",
                         dut.state_var[row][col]);
                $display("  Resistance = %0d",
                         dut.resistance[row][col]);
                $display("  Digital w  = %0d",
                         dut.w[row][col]);
            end

            $display("----------------------------------------\n");

        end

    endtask


    // --------------------------------------------------
    // Display complete weight matrix
    // --------------------------------------------------
    task display_weights;

        integer r;
        integer c;

        begin

            $display("\n========================================");
            $display("DIGITAL WEIGHT MATRIX");
            $display("========================================");

            for (r = 0; r < ROWS; r = r + 1) begin

                $write("[ ");

                for (c = 0; c < COLS; c = c + 1) begin
                    $write("%0d ", dut.w[r][c]);
                end

                $write("]\n");

            end

            $display("========================================\n");

        end

    endtask


    // --------------------------------------------------
    // Display MAC internal signals
    // --------------------------------------------------
    task display_mac_signals;

        integer i;

        begin

            $display("\n========================================");
            $display("MAC DEBUG");
            $display("========================================");

            $display("INPUT VECTOR:");

            for (i = 0; i < ROWS; i = i + 1)
                $display("  x[%0d] = %0d", i, x[i]);

            $display("\nWEIGHTS:");

            for (i = 0; i < ROWS; i = i + 1)
                $display("  w row %0d = %0d %0d %0d %0d",
                         i,
                         dut.w[i][0],
                         dut.w[i][1],
                         dut.w[i][2],
                         dut.w[i][3]);

            $display("\nACCUMULATOR:");

            for (i = 0; i < COLS; i = i + 1)
                $display("  accumulator[%0d] = %0d",
                         i,
                         dut.mac_inst.accumulator[i]);

            $display("\nOUTPUT:");

            for (i = 0; i < COLS; i = i + 1)
                $display("  y[%0d] = %0d",
                         i,
                         y[i]);

            $display("========================================\n");

        end

    endtask


    // --------------------------------------------------
    // MAC-only test
    // --------------------------------------------------
    task mac_test;

        integer i;

        begin

            $display("\n");
            $display("########################################");
            $display("# MAC TEST");
            $display("########################################");

            // --------------------------------------------------
            // Set input vector
            // --------------------------------------------------
            // IMPORTANT:
            // Set x on the falling edge so that it is stable
            // before the next rising edge.
            // --------------------------------------------------

            @(negedge clk);

            x[0] = 8'd10;
            x[1] = 8'd20;
            x[2] = 8'd30;
            x[3] = 8'd40;

            $display("Input vector:");
            $display("x = [%0d, %0d, %0d, %0d]",
                     x[0], x[1], x[2], x[3]);

            // --------------------------------------------------
            // Wait for combinational MAC to calculate
            // --------------------------------------------------
            #1;

            $display("\nMAC accumulator BEFORE clock:");

            for (i = 0; i < COLS; i = i + 1)
                $display("accumulator[%0d] = %0d",
                         i,
                         dut.mac_inst.accumulator[i]);

            // --------------------------------------------------
            // Rising edge registers accumulator into y
            // --------------------------------------------------
            @(posedge clk);

            #1;

            $display("\nMAC output AFTER clock:");

            for (i = 0; i < COLS; i = i + 1)
                $display("y[%0d] = %0d", i, y[i]);

            // --------------------------------------------------
            // Detailed debug
            // --------------------------------------------------
            display_mac_signals;

            $display("########################################");
            $display("# END MAC TEST");
            $display("########################################\n");

        end

    endtask


    // --------------------------------------------------
    // Main test
    // --------------------------------------------------
    initial begin

        // Initial values
        rst          = 1'b0;
        load_enable  = 1'b0;
        row_sel      = 2'd0;
        col_sel      = 2'd0;
        weight_data  = 8'd0;

        for (integer i = 0; i < ROWS; i = i + 1)
            x[i] = 8'd0;


        // ==================================================
        // TEST 1: RESET
        // ==================================================

        reset_dut;


        // ==================================================
        // TEST 2: CHECK MAC BEFORE ANY PROGRAMMING
        // ==================================================
        //
        // All VTEAM cells start around w = 25.
        // Therefore the MAC should NOT produce zero.
        //
        // Approximate expected:
        //
        // y = 10*25 + 20*25 + 30*25 + 40*25
        //   = 2500
        //
        // ==================================================

        $display("\n");
        $display("========================================");
        $display("TEST 2: MAC WITH INITIAL WEIGHTS");
        $display("========================================");

        mac_test;


        // ==================================================
        // TEST 3: PROGRAM M00 = 100
        // ==================================================

        program_cell(0, 0, 100);


        // ==================================================
        // TEST 4: PROGRAM M12 = 200
        // ==================================================

        program_cell(1, 2, 200);


        // ==================================================
        // TEST 5: REPROGRAM M00 = 50
        // ==================================================

        program_cell(0, 0, 50);


        // ==================================================
        // TEST 6: PROGRAM M22 = 1
        // ==================================================

        program_cell(2, 2, 1);


        // ==================================================
        // TEST 7: DISPLAY FINAL WEIGHTS
        // ==================================================

        display_weights;


        // ==================================================
        // TEST 8: MAC WITH PROGRAMMED WEIGHTS
        // ==================================================

        mac_test;


        // ==================================================
        // END
        // ==================================================

        $display("\n========================================");
        $display("ALL TESTS COMPLETE");
        $display("========================================");

        #20;

        $finish;

    end

endmodule