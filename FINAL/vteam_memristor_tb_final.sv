
`timescale 1ns/1ps

module tb_vteam_memristor;

    logic clk;
    logic rst;
    logic V_OFF;
    logic V_ON;

    logic [16:0] state_var;
    logic [13:0] resistance;

    integer errors;
    integer old_state;
    integer expected_state;
    integer delta;
    integer expected_R;

    // DUT
    vteam_memristor dut (
        .clk(clk),
        .rst(rst),
        .V_OFF(V_OFF),
        .V_ON(V_ON),
        .state_var(state_var),
        .resistance(resistance)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Expected resistance using the DUT's separate truncation
    function automatic integer calc_R(input integer w);
        integer wi;
        begin
            wi = 65536 - w;
            calc_R = (100*w)/65536 + (16000*wi)/65536;
        end
    endfunction

    initial begin

        errors = 0;
        rst = 0;
        V_OFF = 0;
        V_ON = 0;

        $display("\n===== VTEAM FUNCTIONAL TEST =====");

        // 1. RESET
        #2 rst = 1;
        #1;

        if (state_var == 6554)
            $display("PASS: Reset");
        else begin
            $display("FAIL: Reset");
            errors = errors + 1;
        end

        expected_R = calc_R(6554);
        if (resistance == expected_R)
            $display("PASS: Initial resistance = %0d", resistance);
        else begin
            $display("FAIL: Initial resistance");
            errors = errors + 1;
        end

        @(negedge clk);
        rst = 0;

        // 2. RETENTION: OFF=0, ON=0
        old_state = state_var;

        @(negedge clk);
        V_OFF = 0;
        V_ON = 0;

        @(posedge clk);
        #1;

        if (state_var == old_state)
            $display("PASS: Retention");
        else begin
            $display("FAIL: Retention");
            errors = errors + 1;
        end

        // 3. OFF PULSE: state must increase
        @(negedge clk);
        old_state = state_var;
        delta = $signed(dut.dw_up(state_var));
        expected_state = old_state + delta;

        V_OFF = 1;
        V_ON = 0;

        @(posedge clk);
        #1;

        if (state_var == expected_state)
            $display("PASS: OFF pulse, state = %0d", state_var);
        else begin
            $display("FAIL: OFF pulse");
            errors = errors + 1;
        end

        // 4. ON PULSE: state must decrease
        @(negedge clk);
        old_state = state_var;
        delta = $signed(dut.dw_down(state_var));
        expected_state = old_state + delta;

        V_OFF = 0;
        V_ON = 1;

        @(posedge clk);
        #1;

        if (state_var == expected_state)
            $display("PASS: ON pulse, state = %0d", state_var);
        else begin
            $display("FAIL: ON pulse");
            errors = errors + 1;
        end

        // 5. BOTH HIGH: OFF has priority
        @(negedge clk);
        old_state = state_var;
        delta = $signed(dut.dw_up(state_var));
        expected_state = old_state + delta;

        V_OFF = 1;
        V_ON = 1;

        @(posedge clk);
        #1;

        if (state_var == expected_state)
            $display("PASS: OFF priority");
        else begin
            $display("FAIL: OFF priority");
            errors = errors + 1;
        end

        // 6. UPPER SATURATION
        @(negedge clk);
        V_OFF = 1;
        V_ON = 0;

        repeat (800) @(posedge clk);
        #1;

        if (state_var == 65536)
            $display("PASS: Upper saturation");
        else begin
            $display("FAIL: Upper saturation, state = %0d", state_var);
            errors = errors + 1;
        end

        // 7. LOWER SATURATION
        @(negedge clk);
        V_OFF = 0;
        V_ON = 1;

        repeat (500) @(posedge clk);
        #1;

        if (state_var == 1)
            $display("PASS: Lower saturation");
        else begin
            $display("FAIL: Lower saturation, state = %0d", state_var);
            errors = errors + 1;
        end

        // 8. RESISTANCE CHECK AT LOWER STATE
        expected_R = calc_R(1);

        if (resistance == expected_R)
            $display("PASS: Resistance at minimum state = %0d", resistance);
        else begin
            $display("FAIL: Resistance at minimum state");
            errors = errors + 1;
        end

        // 9. ASYNCHRONOUS RESET DURING OPERATION
        #2 rst = 1;
        #1;

        if (state_var == 6554)
            $display("PASS: Asynchronous reset");
        else begin
            $display("FAIL: Asynchronous reset");
            errors = errors + 1;
        end

        // Final result
        V_OFF = 0;
        V_ON = 0;

        $display("\n==============================");

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED TESTS = %0d", errors);

        $display("==============================\n");

        $finish;
    end

endmodule
