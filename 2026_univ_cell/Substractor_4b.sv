module Substractor_4b #(
  parameter WIDTH = 4
) (
  input [WIDTH-1:0] i_a, i_b,
  output [WIDTH-1:0] o_diff
);
  assign o_diff = i_a - i_b;
endmodule