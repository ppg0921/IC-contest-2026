`timescale 1ns/1ps

module tb_LUT;

  logic        i_clk;
  logic        i_rst_n;
  logic        i_valid;
  logic [3:0]  i_RI;
  logic [3:0]  i_X;
  logic [3:0]  i_Y;
  logic [9:0]  o_result;

  // DUT
  LUT dut (
    .i_clk    (i_clk),
    .i_rst_n  (i_rst_n),
    .i_valid  (i_valid),
    .i_RI     (i_RI),
    .i_X      (i_X),
    .i_Y      (i_Y),
    .o_result (o_result)
  );

  // Clock generation: 10ns period
  initial begin
    i_clk = 1'b0;
    forever #5 i_clk = ~i_clk;
  end

  // Stimulus
  initial begin
    // init
    i_rst_n = 1'b0;
    i_valid = 1'b0;
    i_RI    = 4'd2;
    i_X     = 4'd0;
    i_Y     = 4'd0;

    // hold reset for a few cycles
    repeat (3) @(negedge i_clk);
    i_rst_n = 1'b1;

    // wait one more cycle
    @(negedge i_clk);
    i_valid = 1'b1;

    // random input for 50 cycles
    repeat (50) begin
      @(negedge i_clk);
      i_X  <= $urandom_range(0, 15);
      i_Y  <= $urandom_range(0, 15);
      i_RI <= $urandom_range(2, 15);
    end

    // stop driving
    @(negedge i_clk);
    i_valid <= 1'b0;
    i_X     <= 4'd0;
    i_Y     <= 4'd0;
    i_RI    <= 4'd2;

    repeat (10) @(posedge i_clk);
    $finish;
  end

  // Monitor output
  initial begin
    $display(" time   rst_n valid  RI   X   Y   | result");
    $display("------------------------------------------------");
    forever begin
      @(posedge i_clk);
      $display("%5t    %0b     %0b    %2d  %2d  %2d  | %4d",
               $time, i_rst_n, i_valid, i_RI, i_X, i_Y, o_result);
    end
  end

endmodule