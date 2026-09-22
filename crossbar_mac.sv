`timescale 1ns/1ps

module crossbar(
    input [7:0] x [0:3],
    input [7:0] w [0:3][0:3],
    input clk,
    input rst,
    output logic [17:0] y [0:3]
);
reg [15:0] product [0:3];
reg [17:0] accumulator [0:3];


parameter I = 4;
parameter J = 4;
integer i = 0, j = 0, k = 0;

always@(*) begin
        for (i = 0; i < I; i=i+1) begin
            accumulator[i] = 18'b0;
            product[i] = 16'b0;
        for (j = 0; j < J; j=j+1) begin
            product[i] = x[j] * w[j][i];
            accumulator[i] = accumulator[i] + product[i];
        end
        end

    
end

always@(posedge clk)begin
  if(rst)begin
    for (k = 0; k < I; k=k+1) begin
      y[k] <= 18'b0;
    end
  end
  else begin
    for (k = 0; k < I; k=k+1) begin
      y[k] <= accumulator[k];
    end
  end
end
  
endmodule