`timescale 1ns / 1ps

// VTEAM memristor digital model
// This is a digital emulation of a memristor using the VTEAM model.
// The state of the memristor changes according to the applied voltage.
// Q16.16 fixed point representation is used for voltage and state values.

module vteam_memristor (

    input clk,
    input rst,

    // Voltage applied to change the memristor state
    input signed [31:0] voltage,

    // Memristor outputs
    output reg [31:0] resistance,
    output reg signed [31:0] current,
    output reg [31:0] state_var,

    // Ternary representation of the memristor state
    output reg [1:0] ternary_output
);



// VTEAM parameters

// Non-linearity exponents
parameter integer ALPHA_ON  = 2;
parameter integer ALPHA_OFF = 2;

// Voltage switching thresholds
// Values are in Q16.16 format
parameter signed [31:0] V_ON  = -32'd9830;    // -0.15 V
parameter signed [31:0] V_OFF =  32'd13107;   // +0.20 V


// Ternary state reference values
parameter signed [31:0] TERNARY_STATE_0 = 32'd6554;   // 0.1
parameter signed [31:0] TERNARY_STATE_1 = 32'd32768;  // 0.5
parameter signed [31:0] TERNARY_STATE_2 = 32'd52429;  // 0.8


// VTEAM coefficients
parameter signed [31:0] K_ON  = -32'd1311;   // -0.02
parameter signed [31:0] K_OFF =  32'd1311;   // +0.02


// Resistance values
parameter [31:0] R_ON  = 32'd100;
parameter [31:0] R_OFF = 32'd16000;


// Initial state of the memristor
parameter signed [31:0] W_INIT = 32'd6554;   // 0.1


// Internal signals

reg signed [31:0] dw_dt;
reg signed [31:0] window_func;
reg signed [31:0] f_voltage;
reg signed [31:0] w_bounded;

reg signed [63:0] temp_w;


// State limits
parameter signed [31:0] W_MIN = 32'd1;
parameter signed [31:0] W_MAX = 32'd65536;   // 1.0


// VTEAM state update
//-----------------------------------------------------------

always @(posedge clk or posedge rst) begin

    if (rst) begin

        // Set initial memristor state
        state_var <= W_INIT;

        // Calculate initial resistance
        resistance <= ((R_ON * W_INIT) >> 16) + ((R_OFF * (32'd65536 - W_INIT)) >> 16);

        current <= 32'd0;
        dw_dt <= 32'd0;
        w_bounded <= W_INIT;

    end

    else begin

        
        // Calculate voltage dependent part of VTEAM equation
        

        // Negative voltage region
        if ($signed(voltage) <= $signed(V_ON)) begin

            f_voltage = (K_ON * (((((voltage <<< 16) / V_ON) - 32'sd65536) ** ALPHA_ON) >>> 16))>>> 16;

        end

        // Positive voltage region
        else if ($signed(voltage) >= $signed(V_OFF)) begin

            f_voltage = (K_OFF *(((((voltage <<< 16) / V_OFF)- 32'sd65536)** ALPHA_OFF) >>> 16))>>> 16;

        end

        // Between the two thresholds, state does not change
        else begin

            f_voltage = 32'd0;

        end


        
        // Window function
        
        // f(w) = 1 - (2*w - 1)^20
        

        temp_w = (state_var <<< 1) - 32'd65536;

        // Calculate (2*w - 1)^4
        window_func = (temp_w * temp_w) >>> 16;
        window_func = (window_func * window_func) >>> 16;

        // Calculate (2*w - 1)^20
        temp_w = (window_func * window_func) >>> 16;
        temp_w = (temp_w * temp_w) >>> 16;
        temp_w = (temp_w * window_func) >>> 16;

        // Final window function
        window_func = 32'd65536 - temp_w;

        // Calculate change in state
         dw_dt = (f_voltage * window_func) >>> 16;


        
        // Update state
    

        w_bounded = state_var + dw_dt;

        // Keep state within valid range
        if (w_bounded < W_MIN)
            w_bounded = W_MIN;

        else if (w_bounded > W_MAX)
            w_bounded = W_MAX;

        state_var <= w_bounded;


        
        // Calculate resistance
        
        // R = R_ON*w + R_OFF*(1-w)


        resistance <= ((R_ON * w_bounded) >> 16) + ((R_OFF * (32'd65536 - w_bounded)) >> 16);


        
        // Calculate current
        
        // I = V/R
        

        current <= ($signed(voltage) <<< 16) /$signed(resistance);


        
        // Convert state into ternary output


        if (w_bounded <= 32'd19661) begin
            ternary_output <= 2'b00;
        end

        else if (w_bounded <= 32'd39322) begin
            ternary_output <= 2'b01;
        end

        else begin
            ternary_output <= 2'b10;
        end

    end

end

endmodule
