module Mult_16b #(
    parameter WIDTH = 16
  ) (
    input CLK,
    input RST,
    input signed [WIDTH-1:0] a,
    input signed [WIDTH-1:0] b,

    output signed [WIDTH-1:0] result
);  
    reg [WIDTH-1:0] result_r, result_w;
    wire [2*WIDTH-1:0] mult_full_result;
    assign mult_full_result = a * b;
    assign result_w = mult_full_result[2*WIDTH-1-4 -: WIDTH]; // Q4.12 format
    assign result = result_r;

    always @(posedge CLK) begin
        if (RST) begin
            result_r <= 0;
        end else begin
            result_r <= result_w;
        end
    end

endmodule