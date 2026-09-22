`timescale 1ns / 1ps

module vteam_memristor_tb;

    reg clk;
    reg rst;
    reg signed [31:0] voltage;

    wire [31:0] resistance;
    wire [31:0] current;
    wire [31:0] state_var;
    wire [1:0] ternary_output;

    // Internal VTEAM signals
    wire signed [31:0] f_voltage;
    wire signed [31:0] dw_dt;
    wire signed [31:0] window_func;

    // VTEAM memristor instance
    vteam_memristor uut (
        .clk(clk),
        .rst(rst),
        .voltage(voltage),
        .resistance(resistance),
        .current(current),
        .state_var(state_var),
        .ternary_output(ternary_output)
    );

    // Connect internal VTEAM signals
    assign f_voltage = uut.f_voltage;
    assign dw_dt = uut.dw_dt;
    assign window_func = uut.window_func;

    // Clock: 10 ns period
    always #5 clk = ~clk;

    initial begin

        // Initial values
        clk = 0;
        rst = 1;
        voltage = 32'sd0;

        // CASE 1: RESET
        #10;
        rst = 0;

        // CASE 2: 0 V
        voltage = 32'sd0;
        #20;

        // CASE 3: +0.2 V
        // Exactly V_OFF
        voltage = 32'sd13107;
        #20;

        // CASE 4: +0.3 V
        // Above V_OFF
        voltage = 32'sd19661;
        #20;

        // CASE 5: 0 V
        voltage = 32'sd0;
        #20;

        // CASE 6: -0.15 V
        // Exactly V_ON
        voltage = -32'sd9830;
        #20;

        // CASE 7: -0.2 V
        // Below V_ON
        voltage = -32'sd13107;
        #20;

        // CASE 8: 0 V
        voltage = 32'sd0;
        #20;

        // CASE 9: +0.3 V again
        voltage = 32'sd19661;
        #40;

        // CASE 10: -0.2 V again
        voltage = -32'sd13107;
        #40;

        // CASE 11: Return to 0 V
        voltage = 32'sd0;
        #20;

        $finish;

    end

    // Monitor important VTEAM values
    initial begin
        $monitor("Time=%0t ns | V=%0d | State=%0d | R=%0d | I=%0d | f_voltage=%0d | dw_dt=%0d | window=%0d | Ternary=%b",
                 $time,
                 voltage,
                 state_var,
                 resistance,
                 current,
                 f_voltage,
                 dw_dt,
                 window_func,
                 ternary_output);
    end

endmodule