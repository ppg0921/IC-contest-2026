module Adder_10b #(
  parameter WIDTH = 12
) (
  input [WIDTH-1:0] i_a, i_b,
  output [WIDTH-1:0] o_sum
);
  assign o_sum = i_a + i_b;
endmodule