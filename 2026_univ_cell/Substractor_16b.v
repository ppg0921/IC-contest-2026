module Substractor_16b #(
  parameter WIDTH = 16
) (
  input signed [WIDTH-1:0] i_a, i_b,
  output signed [WIDTH-1:0] o_diff
);
  assign o_diff = i_a - i_b;
endmodule