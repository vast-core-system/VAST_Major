`timescale 1ns/1ps

// Multiply and accumulate (MAC) unit for computing final output matrix, y
// Uses weights mapped from memristor module and performs calculations

module crossbar_mac(
    input [7:0] x [0:3],  //Input matrix x, 4 elements, 8-bit width each
    input [7:0] w [0:3][0:3], //Weight matrix w, 4x4 matrix, 8-bit width each
    input clk,
    input rst,
    output logic [17:0] y [0:3] //Output matrix y, 4 elements, 18-bit width each 
);

    // Intermediate product variable, used in loops while calculating product, 16-bit width
reg [15:0] product [0:3];
reg [17:0] accumulator [0:3];
    // Intermediate accumulator variable, while computing final output, 18-bit width


    parameter I = 4;  //Fixed variable to iterate across rows 
parameter J = 4;  //Fixed variable to iterate across columns
    integer i = 0, j = 0, k = 0;  //Loop variables, initialized to 0 (prevents garbage values)


    // Combinational block, re-computed immediately on change of inputs (in this case any input)
always@(*) begin
        for (i = 0; i < I; i=i+1) begin
            accumulator[i] = 18'b0;  //Initializing accumalator to 0
            product[i] = 16'b0;  //Initializing product to 0
            //Both are done to prevent any residual values from previous computations
        for (j = 0; j < J; j=j+1) begin
            product[i] = x[j] * w[j][i];  //Matrix multiplication logic (Eg. x0 * w00) -> Iterates down the column for w, and over rows for x
            accumulator[i] = accumulator[i] + product[i]; //Adds succesive multiplication operations
            //(x0 * w00) + (x1 * w01) + (x2 * w02) + (x3 * w03) = accumulator[0]
        end
        end

    
end

//Clocked block, will only assign the value of accumulator to y only on posedge clk

always@(posedge clk)begin
  if(rst)begin
    for (k = 0; k < I; k=k+1) begin
      y[k] <= 18'b0;
        // When rst = 1, set all values of y = {0, 0, 0, 0}
    end
  end
  else begin
    for (k = 0; k < I; k=k+1) begin
        y[k] <= accumulator[k];  // Only of posedge clk, forward the value of accumulator to y
    end
  end
end
  
endmodule
