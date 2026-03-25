module REFRACT(
    input  wire        CLK,
    input  wire        RST,
    input  wire [3:0]  RI,   
    output reg  [8:0]  SRAM_A,
    output reg  [15:0] SRAM_D,
    input  wire [15:0] SRAM_Q,
    output reg         SRAM_WE,
    output reg         DONE
);

    reg [3:0] state_r, state_w;

    localparam S_GX_PRE_IN = 0;
    localparam S_GX_WAIT = 1;
    localparam S_GY_PRE_IN = 2;
    localparam S_GY_WAIT = 3;
    localparam S_Z_CALC = 4;
    localparam S_RATIO_CALC = 5;
    localparam S_Z_X_GX = 6;
    localparam S_ZGX_X_RATIO = 7;
    localparam S_NUM_P_X = 8;
    localparam S_Z_X_GY = 9;
    localparam S_ZGY_X_RATIO = 10;
    localparam S_NUM_P_Y = 11;
    localparam S_Y_OUTPUT = 12;
    localparam S_DONE = 13;




    reg [3:0] x_r, x_w, y_r, y_w;
    reg [15:0] final_result_r, final_result_w;
    reg [3:0] x_buf1_r, x_buf2_r, x_buf3_r, x_buf4_r, y_buf1_r, y_buf2_r, y_buf3_r, y_buf4_r;
    reg [3:0] g_xy_input_r, g_xy_input_w;
    reg [15:0] m8_x_r, m8_x_w, m8_y_r, m8_y_w;
    reg signed [15:0] po7_x_r, po7_x_w, po7_y_r, po7_y_w;
    reg signed [15:0] Z_r, Z_w;
    reg g_input_valid_r, g_input_valid_w;
    reg [2:0] wait_counter_r, wait_counter_w;
    reg signed [15:0] ratio_r, ratio_w;
    reg signed [15:0] mult16_a, mult16_b;
    reg signed [15:0] sub16_a, sub16_b;
    wire signed [15:0] mult16_result;
    wire signed [15:0] ratio_output;
    wire signed [15:0] sub16_result;


    reg [3:0] RI_r;
    reg done_r, done_w;

    reg input_busy_r, input_busy_w;
    reg [8:0] addr; // not real register

    wire [11:0] z_x, z_y;
    wire [11:0] LUT_out;
    wire valid;
    wire g_output_valid;
    wire [15:0] g_m8;
    wire [15:0] g_x_y;
    wire [15:0] Z_output;

    assign SRAM_A = addr;
    assign DONE = done_r;

    assign valid = (x_r == 0) && (y_r == 0) && input_busy_w;

    // LUT u_LUT (
    //     .i_clk(CLK), .i_rst_n(~RST), .i_valid(valid),
    //     .i_X(x_r),
    //     .i_Y(y_r),
    //     .i_RI(RI_r),
    //     .o_result(LUT_out)
    // );

    g u_g7 (
        .CLK(CLK), .RST(RST), .x_or_y(g_xy_input_r), .i_valid(g_input_valid_r),
        .o_valid(g_output_valid), .o_m8(g_m8), .g_x_y(g_x_y)
    );

    Z u_Z (
        .CLK(CLK), .RST(RST), .m8_x({m8_x_r[3:0], 12'b0}), .m8_y({m8_y_r[3:0], 12'b0}), .po7_x(po7_x_r), .po7_y(po7_y_r),
        .o_z(Z_output)
    );

    Mult_16b u_mult16 (
        .CLK(CLK), .RST(RST),
        .a(mult16_a),
        .b(mult16_b),
        .result(mult16_result)
    );

    Ratio u_ratio (
        .gx((po7_x_r << 1)), .gy((po7_y_r << 1)), .RI(RI_r), 
        .ratio(ratio_output)
    );

    Substractor_16b u_sub16 (
        .i_a(sub16_a), .i_b(sub16_b), .o_diff(sub16_result)
    );

    always @(*) begin
        state_w = state_r;
        g_xy_input_w = g_xy_input_r;
        g_input_valid_w = 0;
        m8_x_w = m8_x_r;
        m8_y_w = m8_y_r;
        po7_x_w = po7_x_r;
        po7_y_w = po7_y_r;
        Z_w = Z_r;
        wait_counter_w = wait_counter_r;
        mult16_a = 0;
        mult16_b = 0;
        ratio_w = ratio_r;
        sub16_a = 0;
        sub16_b = 0;
        x_w = x_r;
        y_w = y_r;
        final_result_w = final_result_r;
        done_w = done_r;
        addr = 0;
        SRAM_WE = 0; // default to read
        SRAM_D = 0;
        case (state_r)
            S_GX_PRE_IN: begin
                g_input_valid_w = 1;
                g_xy_input_w = x_r;
                state_w = S_GX_WAIT;
            end
            S_GX_WAIT: begin
                if (g_output_valid) begin
                    m8_x_w = g_m8;
                    po7_x_w = g_x_y;
                    g_input_valid_w = 1;
                    g_xy_input_w = y_r;
                    state_w = S_GY_WAIT;
                end
            end
            S_GY_WAIT: begin
                if (g_output_valid) begin
                    m8_y_w = g_m8;
                    po7_y_w = g_x_y;
                    state_w = S_Z_CALC;
                    wait_counter_w = 0;
                end
            end
            S_Z_CALC: begin
                if (wait_counter_r == 2) begin
                    Z_w = Z_output;
                    ratio_w = ratio_output;
                    state_w = S_Z_X_GX;
                    wait_counter_w = 0;
                end else begin
                    wait_counter_w = wait_counter_r + 1;
                end
            end
            S_Z_X_GX: begin
                mult16_a = Z_r;
                mult16_b = (po7_x_r << 1);
                state_w = S_ZGX_X_RATIO;
            end
            S_ZGX_X_RATIO: begin
                mult16_a = mult16_result;
                mult16_b = ratio_r;
                state_w = S_Z_X_GY;
            end
            S_Z_X_GY: begin
                sub16_a = {x_r, 12'b0};
                sub16_b = mult16_result;
                final_result_w = sub16_result;
                mult16_a = Z_r;
                mult16_b = (po7_y_r << 1);
                state_w = S_ZGY_X_RATIO;
            end
            S_ZGY_X_RATIO: begin

                mult16_a = mult16_result;
                mult16_b = ratio_r;
                state_w = S_NUM_P_Y;
                addr = {y_r, x_r, 1'b0};
                SRAM_D = final_result_r;
                SRAM_WE = 1;
            end
            S_NUM_P_Y: begin
                sub16_a = {y_r, 12'b0};
                sub16_b = mult16_result;
                final_result_w = sub16_result;
                state_w = S_Y_OUTPUT;
            end
            S_Y_OUTPUT: begin
                if (x_r == 15 && y_r == 15) begin
                    state_w = S_DONE;
                end else begin
                    state_w = S_GX_PRE_IN;
                    if (x_r == 15) begin
                        x_w = 0;
                        y_w = y_r + 1;
                    end else begin
                        x_w = x_r + 1;
                    end
                end
                addr = {y_r, x_r, 1'b1};
                SRAM_D = final_result_r;
                SRAM_WE = 1;
            end
            S_DONE: begin
                done_w = 1;
            end
        endcase
    end

    // always @(*) begin
    //     done_w = (&x_buf4_r) && (&y_buf4_r); // x_buf4_r == 15 && y_buf4_r == 15
    // end

    // always @(*) begin
    //     input_busy_w = ~input_busy_r;
    //     x_w = x_r;
    //     y_w = y_r;
    //     if (input_busy_r) begin
    //         x_w = x_r + 1;
    //     end
    //     if ((x_r == 15) && input_busy_r) begin
    //         y_w = y_r + 1;
    //     end
    // end

    // always @(*) begin
    //     if (input_busy_r) begin
    //         addr = {y_buf3_r, x_buf3_r, ~input_busy_r};
    //     end
    //     else begin
    //         addr = {y_buf4_r, x_buf4_r, ~input_busy_r};
    //     end
    // end

    // always @(*) begin
    //     // if (input_busy_r) begin
    //     //     SRAM_D = {z_x, 6'b0};
    //     // end
    //     // else begin
    //     //     SRAM_D = {z_y, 6'b0};
    //     // end
    //     SRAM_D = {LUT_out, 4'b0};
    // end

    // LUT module
    //input: x_r, y_r, RI_r
    //output: z_x, z_y

    //

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            x_r <= 0;
            y_r <= 0;
            x_buf1_r <= 0;
            x_buf2_r <= 0;
            x_buf3_r <= 0;
            x_buf4_r <= 0;
            y_buf1_r <= 0;
            y_buf2_r <= 0;
            y_buf3_r <= 0;
            y_buf4_r <= 0;
            RI_r <= RI;
            done_r <= 0;
            input_busy_r <= 0;
            g_xy_input_r <= 0;
            g_input_valid_r <= 0;
            m8_x_r <= 0;
            m8_y_r <= 0;
            po7_x_r <= 0;
            po7_y_r <= 0;
            Z_r <= 0;
            wait_counter_r <= 0;
            ratio_r <= 0;
            final_result_r <= 0;
            state_r <= S_GX_PRE_IN;
        end
        else begin
            x_r <= x_w;
            y_r <= y_w;
            RI_r <= RI;
            x_buf1_r <= x_r;
            x_buf2_r <= x_buf1_r;
            x_buf3_r <= x_buf2_r;
            x_buf4_r <= x_buf3_r;
            y_buf1_r <= y_r;
            y_buf2_r <= y_buf1_r;
            y_buf3_r <= y_buf2_r;
            y_buf4_r <= y_buf3_r;
            done_r <= done_w;
            input_busy_r <= input_busy_w;
            g_xy_input_r <= g_xy_input_w;
            g_input_valid_r <= g_input_valid_w;
            m8_x_r <= m8_x_w;
            m8_y_r <= m8_y_w;
            po7_x_r <= po7_x_w;
            po7_y_r <= po7_y_w;
            Z_r <= Z_w;
            wait_counter_r <= wait_counter_w;
            ratio_r <= ratio_w;
            final_result_r <= final_result_w;
            state_r <= state_w;

        end
    end

endmodule

module g(
    input CLK,
    input RST,
    input [3:0] x_or_y,
    input i_valid,

    output o_valid,
    output [15:0] o_m8,
    output [15:0] g_x_y
);
    reg signed [15:0] m8_r, m8_w;

    reg signed [31:0] mult_a, mult_b;
    reg signed [31:0] mult_result_r;
    wire signed [31:0] mult_result_w;

    reg [2:0] state_r, state_w;

    localparam S_M8 = 0;
    localparam S_P2 = 1;
    localparam S_P3 = 2;
    localparam S_P4 = 3;
    localparam S_P5 = 4;
    localparam S_P6 = 5;
    localparam S_P7 = 6;
    localparam S_OUTPUT = 7;

    assign o_valid = (state_r == S_OUTPUT);
    assign g_x_y = mult_result_r[24:9];
    assign o_m8 = m8_r;

    always @(*) begin
        m8_w = m8_r;
        mult_a = 0;
        mult_b = 0;
        case (state_r)
            S_M8: begin
                m8_w = $signed({1'b0, x_or_y}) - 8;
            end
            S_P2: begin
                mult_a = m8_r;
                mult_b = m8_r;
            end
            S_P3, S_P4, S_P5, S_P6, S_P7: begin
                mult_a = mult_result_r;
                mult_b = m8_r;
            end
        endcase
    end

    Mult u_mult(
        .a(mult_a),
        .b(mult_b),
        .result(mult_result_w)
    );

    always @(*) begin
        state_w = state_r;
        case (state_r)
            S_M8: begin
                if (i_valid) begin
                    state_w = S_P2;
                end
            end
            S_P2: begin
                state_w = S_P3;
            end
            S_P3: begin
                state_w = S_P4;
            end
            S_P4: begin
                state_w = S_P5;
            end
            S_P5: begin
                state_w = S_P6;
            end
            S_P6: begin
                state_w = S_P7;
            end
            S_P7: begin
                state_w = S_OUTPUT;
            end
            S_OUTPUT: begin
                state_w = S_M8;
            end
        endcase
    end

    

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            state_r <= S_M8;
            m8_r <= 0;
            mult_result_r <= 0;
        end else begin
            state_r <= state_w;
            m8_r <= m8_w;
            mult_result_r <= mult_result_w;
        end
    end
endmodule

module Z(
    input CLK,
    input RST,
    input signed [15:0] m8_x, // Q4.12
    input signed [15:0] m8_y,
    input signed [15:0] po7_x,
    input signed [15:0] po7_y,

    output [15:0] o_z
);
    reg signed [31:0] mult_result_x_w, mult_result_y_w;
    reg signed [15:0] mult_result_x_r, mult_result_y_r;
    reg signed [15:0] z_r, z_w;

    assign o_z = z_r;

    always @(*) begin
        mult_result_x_w = po7_x * (m8_x >> 3);
        mult_result_y_w = po7_y * (m8_y >> 3);
    end

    always @(*) begin
        z_w = {4'd6, 12'd0} - (mult_result_x_r << 1) - (mult_result_y_r << 1);
    end

    always @(posedge CLK) begin
        if (RST) begin
            mult_result_x_r <= 0;
            mult_result_y_r <= 0;
            z_r <= 0;
        end else begin
            mult_result_x_r <= mult_result_x_w[27:12];
            mult_result_y_r <= mult_result_y_w[27:12];
            z_r <= z_w;
        end
    end
endmodule

module Mult(
    input signed [31:0] a,
    input signed [31:0] b,

    output signed [31:0] result
);
    assign result = a * b;

endmodule

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

module Substractor_16b #(
  parameter WIDTH = 16
) (
  input signed [WIDTH-1:0] i_a, i_b,
  output signed [WIDTH-1:0] o_diff
);
  assign o_diff = i_a + i_b;
endmodule

module Ratio(
    input [15:0] gx, // Q4.12 format
    input [15:0] gy, // Q4.12 format
    input [3:0] RI, //2-15

    output [15:0] ratio // Q4.12 format
);

reg signed [15:0] ratio_lut;

assign ratio = ratio_lut;

always_comb begin
    case ({gx, gy, RI})  // 16 + 16 + 4 = 36-bit key
        // gx = -8192 (Q4.12) = -2.00000000
        {16'shE000, 16'shE000, 4'd 2}: ratio_lut = 16'shFAD5;
        {16'shE000, 16'shE000, 4'd 3}: ratio_lut = 16'shF8B4;
        {16'shE000, 16'shE000, 4'd 4}: ratio_lut = 16'shF753;
        {16'shE000, 16'shE000, 4'd 5}: ratio_lut = 16'shF655;
        {16'shE000, 16'shE000, 4'd 6}: ratio_lut = 16'shF596;
        {16'shE000, 16'shE000, 4'd 7}: ratio_lut = 16'shF4FF;
        {16'shE000, 16'shE000, 4'd 8}: ratio_lut = 16'shF486;
        {16'shE000, 16'shE000, 4'd 9}: ratio_lut = 16'shF422;
        {16'shE000, 16'shE000, 4'd10}: ratio_lut = 16'shF3CE;
        {16'shE000, 16'shE000, 4'd11}: ratio_lut = 16'shF385;
        {16'shE000, 16'shE000, 4'd12}: ratio_lut = 16'shF347;
        {16'shE000, 16'shE000, 4'd13}: ratio_lut = 16'shF312;
        {16'shE000, 16'shE000, 4'd14}: ratio_lut = 16'shF2E3;
        {16'shE000, 16'shE000, 4'd15}: ratio_lut = 16'shF2B9;
        {16'shE000, 16'shF370, 4'd 2}: ratio_lut = 16'shFA2A;
        {16'shE000, 16'shF370, 4'd 3}: ratio_lut = 16'shF7E3;
        {16'shE000, 16'shF370, 4'd 4}: ratio_lut = 16'shF67D;
        {16'shE000, 16'shF370, 4'd 5}: ratio_lut = 16'shF586;
        {16'shE000, 16'shF370, 4'd 6}: ratio_lut = 16'shF4D0;
        {16'shE000, 16'shF370, 4'd 7}: ratio_lut = 16'shF444;
        {16'shE000, 16'shF370, 4'd 8}: ratio_lut = 16'shF3D5;
        {16'shE000, 16'shF370, 4'd 9}: ratio_lut = 16'shF37A;
        {16'shE000, 16'shF370, 4'd10}: ratio_lut = 16'shF330;
        {16'shE000, 16'shF370, 4'd11}: ratio_lut = 16'shF2EF;
        {16'shE000, 16'shF370, 4'd12}: ratio_lut = 16'shF2B9;
        {16'shE000, 16'shF370, 4'd13}: ratio_lut = 16'shF28B;
        {16'shE000, 16'shF370, 4'd14}: ratio_lut = 16'shF262;
        {16'shE000, 16'shF370, 4'd15}: ratio_lut = 16'shF23D;
        {16'shE000, 16'shFBBA, 4'd 2}: ratio_lut = 16'shFA05;
        {16'shE000, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF7B6;
        {16'shE000, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF650;
        {16'shE000, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF55B;
        {16'shE000, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF4A8;
        {16'shE000, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF41E;
        {16'shE000, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF3B2;
        {16'shE000, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF359;
        {16'shE000, 16'shFBBA, 4'd10}: ratio_lut = 16'shF310;
        {16'shE000, 16'shFBBA, 4'd11}: ratio_lut = 16'shF2D1;
        {16'shE000, 16'shFBBA, 4'd12}: ratio_lut = 16'shF29D;
        {16'shE000, 16'shFBBA, 4'd13}: ratio_lut = 16'shF270;
        {16'shE000, 16'shFBBA, 4'd14}: ratio_lut = 16'shF249;
        {16'shE000, 16'shFBBA, 4'd15}: ratio_lut = 16'shF225;
        {16'shE000, 16'shFECE, 4'd 2}: ratio_lut = 16'shFA01;
        {16'shE000, 16'shFECE, 4'd 3}: ratio_lut = 16'shF7B1;
        {16'shE000, 16'shFECE, 4'd 4}: ratio_lut = 16'shF64B;
        {16'shE000, 16'shFECE, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'shFECE, 4'd 6}: ratio_lut = 16'shF4A3;
        {16'shE000, 16'shFECE, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'shFECE, 4'd 8}: ratio_lut = 16'shF3AD;
        {16'shE000, 16'shFECE, 4'd 9}: ratio_lut = 16'shF355;
        {16'shE000, 16'shFECE, 4'd10}: ratio_lut = 16'shF30D;
        {16'shE000, 16'shFECE, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'shFECE, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'shFECE, 4'd13}: ratio_lut = 16'shF26D;
        {16'shE000, 16'shFECE, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'shFECE, 4'd15}: ratio_lut = 16'shF223;
        {16'shE000, 16'shFFC0, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shE000, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shE000, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shE000, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shE000, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shE000, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF354;
        {16'shE000, 16'shFFC0, 4'd10}: ratio_lut = 16'shF30C;
        {16'shE000, 16'shFFC0, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'shFFC0, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'shFFC0, 4'd13}: ratio_lut = 16'shF26C;
        {16'shE000, 16'shFFC0, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'shFFC0, 4'd15}: ratio_lut = 16'shF222;
        {16'shE000, 16'shFFF8, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shE000, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shE000, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shE000, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shE000, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shE000, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF354;
        {16'shE000, 16'shFFF8, 4'd10}: ratio_lut = 16'shF30C;
        {16'shE000, 16'shFFF8, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'shFFF8, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'shFFF8, 4'd13}: ratio_lut = 16'shF26C;
        {16'shE000, 16'shFFF8, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'shFFF8, 4'd15}: ratio_lut = 16'shF222;
        {16'shE000, 16'sh0000, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shE000, 16'sh0000, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shE000, 16'sh0000, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shE000, 16'sh0000, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'sh0000, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shE000, 16'sh0000, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'sh0000, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shE000, 16'sh0000, 4'd 9}: ratio_lut = 16'shF354;
        {16'shE000, 16'sh0000, 4'd10}: ratio_lut = 16'shF30C;
        {16'shE000, 16'sh0000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'sh0000, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'sh0000, 4'd13}: ratio_lut = 16'shF26C;
        {16'shE000, 16'sh0000, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'sh0000, 4'd15}: ratio_lut = 16'shF222;
        {16'shE000, 16'sh0008, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shE000, 16'sh0008, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shE000, 16'sh0008, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shE000, 16'sh0008, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'sh0008, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shE000, 16'sh0008, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'sh0008, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shE000, 16'sh0008, 4'd 9}: ratio_lut = 16'shF354;
        {16'shE000, 16'sh0008, 4'd10}: ratio_lut = 16'shF30C;
        {16'shE000, 16'sh0008, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'sh0008, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'sh0008, 4'd13}: ratio_lut = 16'shF26C;
        {16'shE000, 16'sh0008, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'sh0008, 4'd15}: ratio_lut = 16'shF222;
        {16'shE000, 16'sh0040, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shE000, 16'sh0040, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shE000, 16'sh0040, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shE000, 16'sh0040, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'sh0040, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shE000, 16'sh0040, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'sh0040, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shE000, 16'sh0040, 4'd 9}: ratio_lut = 16'shF354;
        {16'shE000, 16'sh0040, 4'd10}: ratio_lut = 16'shF30C;
        {16'shE000, 16'sh0040, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'sh0040, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'sh0040, 4'd13}: ratio_lut = 16'shF26C;
        {16'shE000, 16'sh0040, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'sh0040, 4'd15}: ratio_lut = 16'shF222;
        {16'shE000, 16'sh0132, 4'd 2}: ratio_lut = 16'shFA01;
        {16'shE000, 16'sh0132, 4'd 3}: ratio_lut = 16'shF7B1;
        {16'shE000, 16'sh0132, 4'd 4}: ratio_lut = 16'shF64B;
        {16'shE000, 16'sh0132, 4'd 5}: ratio_lut = 16'shF555;
        {16'shE000, 16'sh0132, 4'd 6}: ratio_lut = 16'shF4A3;
        {16'shE000, 16'sh0132, 4'd 7}: ratio_lut = 16'shF419;
        {16'shE000, 16'sh0132, 4'd 8}: ratio_lut = 16'shF3AD;
        {16'shE000, 16'sh0132, 4'd 9}: ratio_lut = 16'shF355;
        {16'shE000, 16'sh0132, 4'd10}: ratio_lut = 16'shF30D;
        {16'shE000, 16'sh0132, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shE000, 16'sh0132, 4'd12}: ratio_lut = 16'shF299;
        {16'shE000, 16'sh0132, 4'd13}: ratio_lut = 16'shF26D;
        {16'shE000, 16'sh0132, 4'd14}: ratio_lut = 16'shF246;
        {16'shE000, 16'sh0132, 4'd15}: ratio_lut = 16'shF223;
        {16'shE000, 16'sh0446, 4'd 2}: ratio_lut = 16'shFA05;
        {16'shE000, 16'sh0446, 4'd 3}: ratio_lut = 16'shF7B6;
        {16'shE000, 16'sh0446, 4'd 4}: ratio_lut = 16'shF650;
        {16'shE000, 16'sh0446, 4'd 5}: ratio_lut = 16'shF55B;
        {16'shE000, 16'sh0446, 4'd 6}: ratio_lut = 16'shF4A8;
        {16'shE000, 16'sh0446, 4'd 7}: ratio_lut = 16'shF41E;
        {16'shE000, 16'sh0446, 4'd 8}: ratio_lut = 16'shF3B2;
        {16'shE000, 16'sh0446, 4'd 9}: ratio_lut = 16'shF359;
        {16'shE000, 16'sh0446, 4'd10}: ratio_lut = 16'shF310;
        {16'shE000, 16'sh0446, 4'd11}: ratio_lut = 16'shF2D1;
        {16'shE000, 16'sh0446, 4'd12}: ratio_lut = 16'shF29D;
        {16'shE000, 16'sh0446, 4'd13}: ratio_lut = 16'shF270;
        {16'shE000, 16'sh0446, 4'd14}: ratio_lut = 16'shF249;
        {16'shE000, 16'sh0446, 4'd15}: ratio_lut = 16'shF225;
        {16'shE000, 16'sh0C90, 4'd 2}: ratio_lut = 16'shFA2A;
        {16'shE000, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF7E3;
        {16'shE000, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF67D;
        {16'shE000, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF586;
        {16'shE000, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF4D0;
        {16'shE000, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF444;
        {16'shE000, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF3D5;
        {16'shE000, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF37A;
        {16'shE000, 16'sh0C90, 4'd10}: ratio_lut = 16'shF330;
        {16'shE000, 16'sh0C90, 4'd11}: ratio_lut = 16'shF2EF;
        {16'shE000, 16'sh0C90, 4'd12}: ratio_lut = 16'shF2B9;
        {16'shE000, 16'sh0C90, 4'd13}: ratio_lut = 16'shF28B;
        {16'shE000, 16'sh0C90, 4'd14}: ratio_lut = 16'shF262;
        {16'shE000, 16'sh0C90, 4'd15}: ratio_lut = 16'shF23D;

        // gx = -3216 (Q4.12) = -0.78515625
        {16'shF370, 16'shE000, 4'd 2}: ratio_lut = 16'shFA2A;
        {16'shF370, 16'shE000, 4'd 3}: ratio_lut = 16'shF7E3;
        {16'shF370, 16'shE000, 4'd 4}: ratio_lut = 16'shF67D;
        {16'shF370, 16'shE000, 4'd 5}: ratio_lut = 16'shF586;
        {16'shF370, 16'shE000, 4'd 6}: ratio_lut = 16'shF4D0;
        {16'shF370, 16'shE000, 4'd 7}: ratio_lut = 16'shF444;
        {16'shF370, 16'shE000, 4'd 8}: ratio_lut = 16'shF3D5;
        {16'shF370, 16'shE000, 4'd 9}: ratio_lut = 16'shF37A;
        {16'shF370, 16'shE000, 4'd10}: ratio_lut = 16'shF330;
        {16'shF370, 16'shE000, 4'd11}: ratio_lut = 16'shF2EF;
        {16'shF370, 16'shE000, 4'd12}: ratio_lut = 16'shF2B9;
        {16'shF370, 16'shE000, 4'd13}: ratio_lut = 16'shF28B;
        {16'shF370, 16'shE000, 4'd14}: ratio_lut = 16'shF262;
        {16'shF370, 16'shE000, 4'd15}: ratio_lut = 16'shF23D;
        {16'shF370, 16'shF370, 4'd 2}: ratio_lut = 16'shF8EB;
        {16'shF370, 16'shF370, 4'd 3}: ratio_lut = 16'shF668;
        {16'shF370, 16'shF370, 4'd 4}: ratio_lut = 16'shF507;
        {16'shF370, 16'shF370, 4'd 5}: ratio_lut = 16'shF425;
        {16'shF370, 16'shF370, 4'd 6}: ratio_lut = 16'shF387;
        {16'shF370, 16'shF370, 4'd 7}: ratio_lut = 16'shF312;
        {16'shF370, 16'shF370, 4'd 8}: ratio_lut = 16'shF2B8;
        {16'shF370, 16'shF370, 4'd 9}: ratio_lut = 16'shF271;
        {16'shF370, 16'shF370, 4'd10}: ratio_lut = 16'shF237;
        {16'shF370, 16'shF370, 4'd11}: ratio_lut = 16'shF206;
        {16'shF370, 16'shF370, 4'd12}: ratio_lut = 16'shF1DE;
        {16'shF370, 16'shF370, 4'd13}: ratio_lut = 16'shF1BB;
        {16'shF370, 16'shF370, 4'd14}: ratio_lut = 16'shF19E;
        {16'shF370, 16'shF370, 4'd15}: ratio_lut = 16'shF183;
        {16'shF370, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF892;
        {16'shF370, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF601;
        {16'shF370, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'shF370, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'shF370, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF334;
        {16'shF370, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'shF370, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF272;
        {16'shF370, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF230;
        {16'shF370, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1FB;
        {16'shF370, 16'shFBBA, 4'd11}: ratio_lut = 16'shF1CE;
        {16'shF370, 16'shFBBA, 4'd12}: ratio_lut = 16'shF1A9;
        {16'shF370, 16'shFBBA, 4'd13}: ratio_lut = 16'shF18A;
        {16'shF370, 16'shFBBA, 4'd14}: ratio_lut = 16'shF16F;
        {16'shF370, 16'shFBBA, 4'd15}: ratio_lut = 16'shF157;
        {16'shF370, 16'shFECE, 4'd 2}: ratio_lut = 16'shF887;
        {16'shF370, 16'shFECE, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'shF370, 16'shFECE, 4'd 4}: ratio_lut = 16'shF497;
        {16'shF370, 16'shFECE, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'shF370, 16'shFECE, 4'd 6}: ratio_lut = 16'shF328;
        {16'shF370, 16'shFECE, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'shF370, 16'shFECE, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'shFECE, 4'd 9}: ratio_lut = 16'shF227;
        {16'shF370, 16'shFECE, 4'd10}: ratio_lut = 16'shF1F3;
        {16'shF370, 16'shFECE, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'shFECE, 4'd12}: ratio_lut = 16'shF1A2;
        {16'shF370, 16'shFECE, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'shFECE, 4'd14}: ratio_lut = 16'shF169;
        {16'shF370, 16'shFECE, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF886;
        {16'shF370, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shF370, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF496;
        {16'shF370, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shF370, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF327;
        {16'shF370, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shF370, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF226;
        {16'shF370, 16'shFFC0, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shF370, 16'shFFC0, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'shFFC0, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shF370, 16'shFFC0, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'shFFC0, 4'd14}: ratio_lut = 16'shF168;
        {16'shF370, 16'shFFC0, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF886;
        {16'shF370, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shF370, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF496;
        {16'shF370, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shF370, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF327;
        {16'shF370, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shF370, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF226;
        {16'shF370, 16'shFFF8, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shF370, 16'shFFF8, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'shFFF8, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shF370, 16'shFFF8, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'shFFF8, 4'd14}: ratio_lut = 16'shF168;
        {16'shF370, 16'shFFF8, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'sh0000, 4'd 2}: ratio_lut = 16'shF886;
        {16'shF370, 16'sh0000, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shF370, 16'sh0000, 4'd 4}: ratio_lut = 16'shF496;
        {16'shF370, 16'sh0000, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shF370, 16'sh0000, 4'd 6}: ratio_lut = 16'shF327;
        {16'shF370, 16'sh0000, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shF370, 16'sh0000, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'sh0000, 4'd 9}: ratio_lut = 16'shF226;
        {16'shF370, 16'sh0000, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shF370, 16'sh0000, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'sh0000, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shF370, 16'sh0000, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'sh0000, 4'd14}: ratio_lut = 16'shF168;
        {16'shF370, 16'sh0000, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'sh0008, 4'd 2}: ratio_lut = 16'shF886;
        {16'shF370, 16'sh0008, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shF370, 16'sh0008, 4'd 4}: ratio_lut = 16'shF496;
        {16'shF370, 16'sh0008, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shF370, 16'sh0008, 4'd 6}: ratio_lut = 16'shF327;
        {16'shF370, 16'sh0008, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shF370, 16'sh0008, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'sh0008, 4'd 9}: ratio_lut = 16'shF226;
        {16'shF370, 16'sh0008, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shF370, 16'sh0008, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'sh0008, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shF370, 16'sh0008, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'sh0008, 4'd14}: ratio_lut = 16'shF168;
        {16'shF370, 16'sh0008, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'sh0040, 4'd 2}: ratio_lut = 16'shF886;
        {16'shF370, 16'sh0040, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shF370, 16'sh0040, 4'd 4}: ratio_lut = 16'shF496;
        {16'shF370, 16'sh0040, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shF370, 16'sh0040, 4'd 6}: ratio_lut = 16'shF327;
        {16'shF370, 16'sh0040, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shF370, 16'sh0040, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'sh0040, 4'd 9}: ratio_lut = 16'shF226;
        {16'shF370, 16'sh0040, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shF370, 16'sh0040, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'sh0040, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shF370, 16'sh0040, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'sh0040, 4'd14}: ratio_lut = 16'shF168;
        {16'shF370, 16'sh0040, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'sh0132, 4'd 2}: ratio_lut = 16'shF887;
        {16'shF370, 16'sh0132, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'shF370, 16'sh0132, 4'd 4}: ratio_lut = 16'shF497;
        {16'shF370, 16'sh0132, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'shF370, 16'sh0132, 4'd 6}: ratio_lut = 16'shF328;
        {16'shF370, 16'sh0132, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'shF370, 16'sh0132, 4'd 8}: ratio_lut = 16'shF268;
        {16'shF370, 16'sh0132, 4'd 9}: ratio_lut = 16'shF227;
        {16'shF370, 16'sh0132, 4'd10}: ratio_lut = 16'shF1F3;
        {16'shF370, 16'sh0132, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shF370, 16'sh0132, 4'd12}: ratio_lut = 16'shF1A2;
        {16'shF370, 16'sh0132, 4'd13}: ratio_lut = 16'shF183;
        {16'shF370, 16'sh0132, 4'd14}: ratio_lut = 16'shF169;
        {16'shF370, 16'sh0132, 4'd15}: ratio_lut = 16'shF151;
        {16'shF370, 16'sh0446, 4'd 2}: ratio_lut = 16'shF892;
        {16'shF370, 16'sh0446, 4'd 3}: ratio_lut = 16'shF601;
        {16'shF370, 16'sh0446, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'shF370, 16'sh0446, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'shF370, 16'sh0446, 4'd 6}: ratio_lut = 16'shF334;
        {16'shF370, 16'sh0446, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'shF370, 16'sh0446, 4'd 8}: ratio_lut = 16'shF272;
        {16'shF370, 16'sh0446, 4'd 9}: ratio_lut = 16'shF230;
        {16'shF370, 16'sh0446, 4'd10}: ratio_lut = 16'shF1FB;
        {16'shF370, 16'sh0446, 4'd11}: ratio_lut = 16'shF1CE;
        {16'shF370, 16'sh0446, 4'd12}: ratio_lut = 16'shF1A9;
        {16'shF370, 16'sh0446, 4'd13}: ratio_lut = 16'shF18A;
        {16'shF370, 16'sh0446, 4'd14}: ratio_lut = 16'shF16F;
        {16'shF370, 16'sh0446, 4'd15}: ratio_lut = 16'shF157;
        {16'shF370, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF8EB;
        {16'shF370, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF668;
        {16'shF370, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF507;
        {16'shF370, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF425;
        {16'shF370, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF387;
        {16'shF370, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF312;
        {16'shF370, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF2B8;
        {16'shF370, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF271;
        {16'shF370, 16'sh0C90, 4'd10}: ratio_lut = 16'shF237;
        {16'shF370, 16'sh0C90, 4'd11}: ratio_lut = 16'shF206;
        {16'shF370, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1DE;
        {16'shF370, 16'sh0C90, 4'd13}: ratio_lut = 16'shF1BB;
        {16'shF370, 16'sh0C90, 4'd14}: ratio_lut = 16'shF19E;
        {16'shF370, 16'sh0C90, 4'd15}: ratio_lut = 16'shF183;

        // gx = -1094 (Q4.12) = -0.26708984
        {16'shFBBA, 16'shE000, 4'd 2}: ratio_lut = 16'shFA05;
        {16'shFBBA, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B6;
        {16'shFBBA, 16'shE000, 4'd 4}: ratio_lut = 16'shF650;
        {16'shFBBA, 16'shE000, 4'd 5}: ratio_lut = 16'shF55B;
        {16'shFBBA, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A8;
        {16'shFBBA, 16'shE000, 4'd 7}: ratio_lut = 16'shF41E;
        {16'shFBBA, 16'shE000, 4'd 8}: ratio_lut = 16'shF3B2;
        {16'shFBBA, 16'shE000, 4'd 9}: ratio_lut = 16'shF359;
        {16'shFBBA, 16'shE000, 4'd10}: ratio_lut = 16'shF310;
        {16'shFBBA, 16'shE000, 4'd11}: ratio_lut = 16'shF2D1;
        {16'shFBBA, 16'shE000, 4'd12}: ratio_lut = 16'shF29D;
        {16'shFBBA, 16'shE000, 4'd13}: ratio_lut = 16'shF270;
        {16'shFBBA, 16'shE000, 4'd14}: ratio_lut = 16'shF249;
        {16'shFBBA, 16'shE000, 4'd15}: ratio_lut = 16'shF225;
        {16'shFBBA, 16'shF370, 4'd 2}: ratio_lut = 16'shF892;
        {16'shFBBA, 16'shF370, 4'd 3}: ratio_lut = 16'shF601;
        {16'shFBBA, 16'shF370, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'shFBBA, 16'shF370, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'shFBBA, 16'shF370, 4'd 6}: ratio_lut = 16'shF334;
        {16'shFBBA, 16'shF370, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'shFBBA, 16'shF370, 4'd 8}: ratio_lut = 16'shF272;
        {16'shFBBA, 16'shF370, 4'd 9}: ratio_lut = 16'shF230;
        {16'shFBBA, 16'shF370, 4'd10}: ratio_lut = 16'shF1FB;
        {16'shFBBA, 16'shF370, 4'd11}: ratio_lut = 16'shF1CE;
        {16'shFBBA, 16'shF370, 4'd12}: ratio_lut = 16'shF1A9;
        {16'shFBBA, 16'shF370, 4'd13}: ratio_lut = 16'shF18A;
        {16'shFBBA, 16'shF370, 4'd14}: ratio_lut = 16'shF16F;
        {16'shFBBA, 16'shF370, 4'd15}: ratio_lut = 16'shF157;
        {16'shFBBA, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF823;
        {16'shFBBA, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF57E;
        {16'shFBBA, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF427;
        {16'shFBBA, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF357;
        {16'shFBBA, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2CB;
        {16'shFBBA, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF266;
        {16'shFBBA, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF21B;
        {16'shFBBA, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1E0;
        {16'shFBBA, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1B1;
        {16'shFBBA, 16'shFBBA, 4'd11}: ratio_lut = 16'shF189;
        {16'shFBBA, 16'shFBBA, 4'd12}: ratio_lut = 16'shF169;
        {16'shFBBA, 16'shFBBA, 4'd13}: ratio_lut = 16'shF14D;
        {16'shFBBA, 16'shFBBA, 4'd14}: ratio_lut = 16'shF136;
        {16'shFBBA, 16'shFBBA, 4'd15}: ratio_lut = 16'shF121;
        {16'shFBBA, 16'shFECE, 4'd 2}: ratio_lut = 16'shF814;
        {16'shFBBA, 16'shFECE, 4'd 3}: ratio_lut = 16'shF56C;
        {16'shFBBA, 16'shFECE, 4'd 4}: ratio_lut = 16'shF416;
        {16'shFBBA, 16'shFECE, 4'd 5}: ratio_lut = 16'shF347;
        {16'shFBBA, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'shFBBA, 16'shFECE, 4'd 7}: ratio_lut = 16'shF259;
        {16'shFBBA, 16'shFECE, 4'd 8}: ratio_lut = 16'shF20F;
        {16'shFBBA, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'shFECE, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'shFECE, 4'd11}: ratio_lut = 16'shF180;
        {16'shFBBA, 16'shFECE, 4'd12}: ratio_lut = 16'shF160;
        {16'shFBBA, 16'shFECE, 4'd13}: ratio_lut = 16'shF145;
        {16'shFBBA, 16'shFECE, 4'd14}: ratio_lut = 16'shF12F;
        {16'shFBBA, 16'shFECE, 4'd15}: ratio_lut = 16'shF11A;
        {16'shFBBA, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFBBA, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFBBA, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFBBA, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFBBA, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFBBA, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFBBA, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFBBA, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'shFFC0, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'shFFC0, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFBBA, 16'shFFC0, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFBBA, 16'shFFC0, 4'd13}: ratio_lut = 16'shF144;
        {16'shFBBA, 16'shFFC0, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFBBA, 16'shFFC0, 4'd15}: ratio_lut = 16'shF119;
        {16'shFBBA, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFBBA, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFBBA, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFBBA, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFBBA, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFBBA, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFBBA, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFBBA, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'shFFF8, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'shFFF8, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFBBA, 16'shFFF8, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFBBA, 16'shFFF8, 4'd13}: ratio_lut = 16'shF144;
        {16'shFBBA, 16'shFFF8, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFBBA, 16'shFFF8, 4'd15}: ratio_lut = 16'shF119;
        {16'shFBBA, 16'sh0000, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFBBA, 16'sh0000, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFBBA, 16'sh0000, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFBBA, 16'sh0000, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFBBA, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFBBA, 16'sh0000, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFBBA, 16'sh0000, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFBBA, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'sh0000, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'sh0000, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFBBA, 16'sh0000, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFBBA, 16'sh0000, 4'd13}: ratio_lut = 16'shF144;
        {16'shFBBA, 16'sh0000, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFBBA, 16'sh0000, 4'd15}: ratio_lut = 16'shF119;
        {16'shFBBA, 16'sh0008, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFBBA, 16'sh0008, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFBBA, 16'sh0008, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFBBA, 16'sh0008, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFBBA, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFBBA, 16'sh0008, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFBBA, 16'sh0008, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFBBA, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'sh0008, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'sh0008, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFBBA, 16'sh0008, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFBBA, 16'sh0008, 4'd13}: ratio_lut = 16'shF144;
        {16'shFBBA, 16'sh0008, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFBBA, 16'sh0008, 4'd15}: ratio_lut = 16'shF119;
        {16'shFBBA, 16'sh0040, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFBBA, 16'sh0040, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFBBA, 16'sh0040, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFBBA, 16'sh0040, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFBBA, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFBBA, 16'sh0040, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFBBA, 16'sh0040, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFBBA, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'sh0040, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'sh0040, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFBBA, 16'sh0040, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFBBA, 16'sh0040, 4'd13}: ratio_lut = 16'shF144;
        {16'shFBBA, 16'sh0040, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFBBA, 16'sh0040, 4'd15}: ratio_lut = 16'shF119;
        {16'shFBBA, 16'sh0132, 4'd 2}: ratio_lut = 16'shF814;
        {16'shFBBA, 16'sh0132, 4'd 3}: ratio_lut = 16'shF56C;
        {16'shFBBA, 16'sh0132, 4'd 4}: ratio_lut = 16'shF416;
        {16'shFBBA, 16'sh0132, 4'd 5}: ratio_lut = 16'shF347;
        {16'shFBBA, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'shFBBA, 16'sh0132, 4'd 7}: ratio_lut = 16'shF259;
        {16'shFBBA, 16'sh0132, 4'd 8}: ratio_lut = 16'shF20F;
        {16'shFBBA, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFBBA, 16'sh0132, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFBBA, 16'sh0132, 4'd11}: ratio_lut = 16'shF180;
        {16'shFBBA, 16'sh0132, 4'd12}: ratio_lut = 16'shF160;
        {16'shFBBA, 16'sh0132, 4'd13}: ratio_lut = 16'shF145;
        {16'shFBBA, 16'sh0132, 4'd14}: ratio_lut = 16'shF12F;
        {16'shFBBA, 16'sh0132, 4'd15}: ratio_lut = 16'shF11A;
        {16'shFBBA, 16'sh0446, 4'd 2}: ratio_lut = 16'shF823;
        {16'shFBBA, 16'sh0446, 4'd 3}: ratio_lut = 16'shF57E;
        {16'shFBBA, 16'sh0446, 4'd 4}: ratio_lut = 16'shF427;
        {16'shFBBA, 16'sh0446, 4'd 5}: ratio_lut = 16'shF357;
        {16'shFBBA, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2CB;
        {16'shFBBA, 16'sh0446, 4'd 7}: ratio_lut = 16'shF266;
        {16'shFBBA, 16'sh0446, 4'd 8}: ratio_lut = 16'shF21B;
        {16'shFBBA, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1E0;
        {16'shFBBA, 16'sh0446, 4'd10}: ratio_lut = 16'shF1B1;
        {16'shFBBA, 16'sh0446, 4'd11}: ratio_lut = 16'shF189;
        {16'shFBBA, 16'sh0446, 4'd12}: ratio_lut = 16'shF169;
        {16'shFBBA, 16'sh0446, 4'd13}: ratio_lut = 16'shF14D;
        {16'shFBBA, 16'sh0446, 4'd14}: ratio_lut = 16'shF136;
        {16'shFBBA, 16'sh0446, 4'd15}: ratio_lut = 16'shF121;
        {16'shFBBA, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF892;
        {16'shFBBA, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF601;
        {16'shFBBA, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'shFBBA, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'shFBBA, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF334;
        {16'shFBBA, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'shFBBA, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF272;
        {16'shFBBA, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF230;
        {16'shFBBA, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1FB;
        {16'shFBBA, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1CE;
        {16'shFBBA, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A9;
        {16'shFBBA, 16'sh0C90, 4'd13}: ratio_lut = 16'shF18A;
        {16'shFBBA, 16'sh0C90, 4'd14}: ratio_lut = 16'shF16F;
        {16'shFBBA, 16'sh0C90, 4'd15}: ratio_lut = 16'shF157;

        // gx = -306 (Q4.12) = -0.07470703
        {16'shFECE, 16'shE000, 4'd 2}: ratio_lut = 16'shFA01;
        {16'shFECE, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B1;
        {16'shFECE, 16'shE000, 4'd 4}: ratio_lut = 16'shF64B;
        {16'shFECE, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'shFECE, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A3;
        {16'shFECE, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'shFECE, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AD;
        {16'shFECE, 16'shE000, 4'd 9}: ratio_lut = 16'shF355;
        {16'shFECE, 16'shE000, 4'd10}: ratio_lut = 16'shF30D;
        {16'shFECE, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shFECE, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'shFECE, 16'shE000, 4'd13}: ratio_lut = 16'shF26D;
        {16'shFECE, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'shFECE, 16'shE000, 4'd15}: ratio_lut = 16'shF223;
        {16'shFECE, 16'shF370, 4'd 2}: ratio_lut = 16'shF887;
        {16'shFECE, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'shFECE, 16'shF370, 4'd 4}: ratio_lut = 16'shF497;
        {16'shFECE, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'shFECE, 16'shF370, 4'd 6}: ratio_lut = 16'shF328;
        {16'shFECE, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'shFECE, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'shFECE, 16'shF370, 4'd 9}: ratio_lut = 16'shF227;
        {16'shFECE, 16'shF370, 4'd10}: ratio_lut = 16'shF1F3;
        {16'shFECE, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shFECE, 16'shF370, 4'd12}: ratio_lut = 16'shF1A2;
        {16'shFECE, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'shFECE, 16'shF370, 4'd14}: ratio_lut = 16'shF169;
        {16'shFECE, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'shFECE, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF814;
        {16'shFECE, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56C;
        {16'shFECE, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF416;
        {16'shFECE, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF347;
        {16'shFECE, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'shFECE, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF259;
        {16'shFECE, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20F;
        {16'shFECE, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFECE, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFECE, 16'shFBBA, 4'd11}: ratio_lut = 16'shF180;
        {16'shFECE, 16'shFBBA, 4'd12}: ratio_lut = 16'shF160;
        {16'shFECE, 16'shFBBA, 4'd13}: ratio_lut = 16'shF145;
        {16'shFECE, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12F;
        {16'shFECE, 16'shFBBA, 4'd15}: ratio_lut = 16'shF11A;
        {16'shFECE, 16'shFECE, 4'd 2}: ratio_lut = 16'shF803;
        {16'shFECE, 16'shFECE, 4'd 3}: ratio_lut = 16'shF559;
        {16'shFECE, 16'shFECE, 4'd 4}: ratio_lut = 16'shF403;
        {16'shFECE, 16'shFECE, 4'd 5}: ratio_lut = 16'shF336;
        {16'shFECE, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AE;
        {16'shFECE, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24B;
        {16'shFECE, 16'shFECE, 4'd 8}: ratio_lut = 16'shF202;
        {16'shFECE, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C9;
        {16'shFECE, 16'shFECE, 4'd10}: ratio_lut = 16'shF19C;
        {16'shFECE, 16'shFECE, 4'd11}: ratio_lut = 16'shF176;
        {16'shFECE, 16'shFECE, 4'd12}: ratio_lut = 16'shF157;
        {16'shFECE, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFECE, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFECE, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFECE, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF335;
        {16'shFECE, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'shFECE, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFECE, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFECE, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFECE, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFECE, 16'shFFC0, 4'd11}: ratio_lut = 16'shF175;
        {16'shFECE, 16'shFFC0, 4'd12}: ratio_lut = 16'shF156;
        {16'shFECE, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'shFFC0, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'shFFC0, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFECE, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFECE, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFECE, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF334;
        {16'shFECE, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'shFECE, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFECE, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFECE, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFECE, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFECE, 16'shFFF8, 4'd11}: ratio_lut = 16'shF175;
        {16'shFECE, 16'shFFF8, 4'd12}: ratio_lut = 16'shF156;
        {16'shFECE, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'shFFF8, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'shFFF8, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'sh0000, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFECE, 16'sh0000, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFECE, 16'sh0000, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFECE, 16'sh0000, 4'd 5}: ratio_lut = 16'shF334;
        {16'shFECE, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'shFECE, 16'sh0000, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFECE, 16'sh0000, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFECE, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFECE, 16'sh0000, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFECE, 16'sh0000, 4'd11}: ratio_lut = 16'shF175;
        {16'shFECE, 16'sh0000, 4'd12}: ratio_lut = 16'shF156;
        {16'shFECE, 16'sh0000, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'sh0000, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'sh0000, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'sh0008, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFECE, 16'sh0008, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFECE, 16'sh0008, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFECE, 16'sh0008, 4'd 5}: ratio_lut = 16'shF334;
        {16'shFECE, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'shFECE, 16'sh0008, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFECE, 16'sh0008, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFECE, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFECE, 16'sh0008, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFECE, 16'sh0008, 4'd11}: ratio_lut = 16'shF175;
        {16'shFECE, 16'sh0008, 4'd12}: ratio_lut = 16'shF156;
        {16'shFECE, 16'sh0008, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'sh0008, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'sh0008, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'sh0040, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFECE, 16'sh0040, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFECE, 16'sh0040, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFECE, 16'sh0040, 4'd 5}: ratio_lut = 16'shF335;
        {16'shFECE, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'shFECE, 16'sh0040, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFECE, 16'sh0040, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFECE, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFECE, 16'sh0040, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFECE, 16'sh0040, 4'd11}: ratio_lut = 16'shF175;
        {16'shFECE, 16'sh0040, 4'd12}: ratio_lut = 16'shF156;
        {16'shFECE, 16'sh0040, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'sh0040, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'sh0040, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'sh0132, 4'd 2}: ratio_lut = 16'shF803;
        {16'shFECE, 16'sh0132, 4'd 3}: ratio_lut = 16'shF559;
        {16'shFECE, 16'sh0132, 4'd 4}: ratio_lut = 16'shF403;
        {16'shFECE, 16'sh0132, 4'd 5}: ratio_lut = 16'shF336;
        {16'shFECE, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AE;
        {16'shFECE, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24B;
        {16'shFECE, 16'sh0132, 4'd 8}: ratio_lut = 16'shF202;
        {16'shFECE, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C9;
        {16'shFECE, 16'sh0132, 4'd10}: ratio_lut = 16'shF19C;
        {16'shFECE, 16'sh0132, 4'd11}: ratio_lut = 16'shF176;
        {16'shFECE, 16'sh0132, 4'd12}: ratio_lut = 16'shF157;
        {16'shFECE, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFECE, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'shFECE, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'shFECE, 16'sh0446, 4'd 2}: ratio_lut = 16'shF814;
        {16'shFECE, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56C;
        {16'shFECE, 16'sh0446, 4'd 4}: ratio_lut = 16'shF416;
        {16'shFECE, 16'sh0446, 4'd 5}: ratio_lut = 16'shF347;
        {16'shFECE, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'shFECE, 16'sh0446, 4'd 7}: ratio_lut = 16'shF259;
        {16'shFECE, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20F;
        {16'shFECE, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFECE, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFECE, 16'sh0446, 4'd11}: ratio_lut = 16'shF180;
        {16'shFECE, 16'sh0446, 4'd12}: ratio_lut = 16'shF160;
        {16'shFECE, 16'sh0446, 4'd13}: ratio_lut = 16'shF145;
        {16'shFECE, 16'sh0446, 4'd14}: ratio_lut = 16'shF12F;
        {16'shFECE, 16'sh0446, 4'd15}: ratio_lut = 16'shF11A;
        {16'shFECE, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF887;
        {16'shFECE, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'shFECE, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF497;
        {16'shFECE, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'shFECE, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF328;
        {16'shFECE, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'shFECE, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'shFECE, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF227;
        {16'shFECE, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F3;
        {16'shFECE, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shFECE, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A2;
        {16'shFECE, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'shFECE, 16'sh0C90, 4'd14}: ratio_lut = 16'shF169;
        {16'shFECE, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = -64 (Q4.12) = -0.01562500
        {16'shFFC0, 16'shE000, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shFFC0, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shFFC0, 16'shE000, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shFFC0, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'shFFC0, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shFFC0, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'shFFC0, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shFFC0, 16'shE000, 4'd 9}: ratio_lut = 16'shF354;
        {16'shFFC0, 16'shE000, 4'd10}: ratio_lut = 16'shF30C;
        {16'shFFC0, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shFFC0, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'shFFC0, 16'shE000, 4'd13}: ratio_lut = 16'shF26C;
        {16'shFFC0, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'shFFC0, 16'shE000, 4'd15}: ratio_lut = 16'shF222;
        {16'shFFC0, 16'shF370, 4'd 2}: ratio_lut = 16'shF886;
        {16'shFFC0, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shFFC0, 16'shF370, 4'd 4}: ratio_lut = 16'shF496;
        {16'shFFC0, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shFFC0, 16'shF370, 4'd 6}: ratio_lut = 16'shF327;
        {16'shFFC0, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shFFC0, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'shFFC0, 16'shF370, 4'd 9}: ratio_lut = 16'shF226;
        {16'shFFC0, 16'shF370, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shFFC0, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shFFC0, 16'shF370, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shFFC0, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'shFFC0, 16'shF370, 4'd14}: ratio_lut = 16'shF168;
        {16'shFFC0, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'shFFC0, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFFC0, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFFC0, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFFC0, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFFC0, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFFC0, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFFC0, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFFC0, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFFC0, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFFC0, 16'shFBBA, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFFC0, 16'shFBBA, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFFC0, 16'shFBBA, 4'd13}: ratio_lut = 16'shF144;
        {16'shFFC0, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFFC0, 16'shFBBA, 4'd15}: ratio_lut = 16'shF119;
        {16'shFFC0, 16'shFECE, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFFC0, 16'shFECE, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFFC0, 16'shFECE, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFFC0, 16'shFECE, 4'd 5}: ratio_lut = 16'shF335;
        {16'shFFC0, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'shFFC0, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFFC0, 16'shFECE, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFFC0, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFFC0, 16'shFECE, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFFC0, 16'shFECE, 4'd11}: ratio_lut = 16'shF175;
        {16'shFFC0, 16'shFECE, 4'd12}: ratio_lut = 16'shF156;
        {16'shFFC0, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFFC0, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'shFFC0, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'shFFC0, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF801;
        {16'shFFC0, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFC0, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFC0, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFC0, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFC0, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFC0, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFC0, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFC0, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFC0, 16'shFFC0, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFC0, 16'shFFC0, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFC0, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFC0, 16'shFFC0, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFC0, 16'shFFC0, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFC0, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFC0, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFC0, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFC0, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFC0, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFC0, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFC0, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFC0, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFC0, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFC0, 16'shFFF8, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFC0, 16'shFFF8, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFC0, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFC0, 16'shFFF8, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFC0, 16'shFFF8, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFC0, 16'sh0000, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFC0, 16'sh0000, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFC0, 16'sh0000, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFC0, 16'sh0000, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFC0, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFC0, 16'sh0000, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFC0, 16'sh0000, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFC0, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFC0, 16'sh0000, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFC0, 16'sh0000, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFC0, 16'sh0000, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFC0, 16'sh0000, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFC0, 16'sh0000, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFC0, 16'sh0000, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFC0, 16'sh0008, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFC0, 16'sh0008, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFC0, 16'sh0008, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFC0, 16'sh0008, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFC0, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFC0, 16'sh0008, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFC0, 16'sh0008, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFC0, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFC0, 16'sh0008, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFC0, 16'sh0008, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFC0, 16'sh0008, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFC0, 16'sh0008, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFC0, 16'sh0008, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFC0, 16'sh0008, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFC0, 16'sh0040, 4'd 2}: ratio_lut = 16'shF801;
        {16'shFFC0, 16'sh0040, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFC0, 16'sh0040, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFC0, 16'sh0040, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFC0, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFC0, 16'sh0040, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFC0, 16'sh0040, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFC0, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFC0, 16'sh0040, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFC0, 16'sh0040, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFC0, 16'sh0040, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFC0, 16'sh0040, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFC0, 16'sh0040, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFC0, 16'sh0040, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFC0, 16'sh0132, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFFC0, 16'sh0132, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFFC0, 16'sh0132, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFFC0, 16'sh0132, 4'd 5}: ratio_lut = 16'shF335;
        {16'shFFC0, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'shFFC0, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFFC0, 16'sh0132, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFFC0, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFFC0, 16'sh0132, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFFC0, 16'sh0132, 4'd11}: ratio_lut = 16'shF175;
        {16'shFFC0, 16'sh0132, 4'd12}: ratio_lut = 16'shF156;
        {16'shFFC0, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFFC0, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'shFFC0, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'shFFC0, 16'sh0446, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFFC0, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFFC0, 16'sh0446, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFFC0, 16'sh0446, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFFC0, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFFC0, 16'sh0446, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFFC0, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFFC0, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFFC0, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFFC0, 16'sh0446, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFFC0, 16'sh0446, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFFC0, 16'sh0446, 4'd13}: ratio_lut = 16'shF144;
        {16'shFFC0, 16'sh0446, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFFC0, 16'sh0446, 4'd15}: ratio_lut = 16'shF119;
        {16'shFFC0, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF886;
        {16'shFFC0, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shFFC0, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF496;
        {16'shFFC0, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shFFC0, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF327;
        {16'shFFC0, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shFFC0, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'shFFC0, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF226;
        {16'shFFC0, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shFFC0, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shFFC0, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shFFC0, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'shFFC0, 16'sh0C90, 4'd14}: ratio_lut = 16'shF168;
        {16'shFFC0, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = -8 (Q4.12) = -0.00195312
        {16'shFFF8, 16'shE000, 4'd 2}: ratio_lut = 16'shFA00;
        {16'shFFF8, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'shFFF8, 16'shE000, 4'd 4}: ratio_lut = 16'shF64A;
        {16'shFFF8, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'shFFF8, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'shFFF8, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'shFFF8, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'shFFF8, 16'shE000, 4'd 9}: ratio_lut = 16'shF354;
        {16'shFFF8, 16'shE000, 4'd10}: ratio_lut = 16'shF30C;
        {16'shFFF8, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'shFFF8, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'shFFF8, 16'shE000, 4'd13}: ratio_lut = 16'shF26C;
        {16'shFFF8, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'shFFF8, 16'shE000, 4'd15}: ratio_lut = 16'shF222;
        {16'shFFF8, 16'shF370, 4'd 2}: ratio_lut = 16'shF886;
        {16'shFFF8, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shFFF8, 16'shF370, 4'd 4}: ratio_lut = 16'shF496;
        {16'shFFF8, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shFFF8, 16'shF370, 4'd 6}: ratio_lut = 16'shF327;
        {16'shFFF8, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shFFF8, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'shFFF8, 16'shF370, 4'd 9}: ratio_lut = 16'shF226;
        {16'shFFF8, 16'shF370, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shFFF8, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shFFF8, 16'shF370, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shFFF8, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'shFFF8, 16'shF370, 4'd14}: ratio_lut = 16'shF168;
        {16'shFFF8, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'shFFF8, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFFF8, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFFF8, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFFF8, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFFF8, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFFF8, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFFF8, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFFF8, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFFF8, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFFF8, 16'shFBBA, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFFF8, 16'shFBBA, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFFF8, 16'shFBBA, 4'd13}: ratio_lut = 16'shF144;
        {16'shFFF8, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFFF8, 16'shFBBA, 4'd15}: ratio_lut = 16'shF119;
        {16'shFFF8, 16'shFECE, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFFF8, 16'shFECE, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFFF8, 16'shFECE, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFFF8, 16'shFECE, 4'd 5}: ratio_lut = 16'shF334;
        {16'shFFF8, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'shFFF8, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFFF8, 16'shFECE, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFFF8, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFFF8, 16'shFECE, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFFF8, 16'shFECE, 4'd11}: ratio_lut = 16'shF175;
        {16'shFFF8, 16'shFECE, 4'd12}: ratio_lut = 16'shF156;
        {16'shFFF8, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFFF8, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'shFFF8, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'shFFF8, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFF8, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFF8, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFF8, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFF8, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFF8, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFF8, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFF8, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFF8, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFF8, 16'shFFC0, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFF8, 16'shFFC0, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFF8, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFF8, 16'shFFC0, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFF8, 16'shFFC0, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFF8, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFF8, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFF8, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFF8, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFF8, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFF8, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFF8, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFF8, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFF8, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFF8, 16'shFFF8, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFF8, 16'shFFF8, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFF8, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFF8, 16'shFFF8, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFF8, 16'shFFF8, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFF8, 16'sh0000, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFF8, 16'sh0000, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFF8, 16'sh0000, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFF8, 16'sh0000, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFF8, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFF8, 16'sh0000, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFF8, 16'sh0000, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFF8, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFF8, 16'sh0000, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFF8, 16'sh0000, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFF8, 16'sh0000, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFF8, 16'sh0000, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFF8, 16'sh0000, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFF8, 16'sh0000, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFF8, 16'sh0008, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFF8, 16'sh0008, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFF8, 16'sh0008, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFF8, 16'sh0008, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFF8, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFF8, 16'sh0008, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFF8, 16'sh0008, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFF8, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFF8, 16'sh0008, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFF8, 16'sh0008, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFF8, 16'sh0008, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFF8, 16'sh0008, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFF8, 16'sh0008, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFF8, 16'sh0008, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFF8, 16'sh0040, 4'd 2}: ratio_lut = 16'shF800;
        {16'shFFF8, 16'sh0040, 4'd 3}: ratio_lut = 16'shF555;
        {16'shFFF8, 16'sh0040, 4'd 4}: ratio_lut = 16'shF400;
        {16'shFFF8, 16'sh0040, 4'd 5}: ratio_lut = 16'shF333;
        {16'shFFF8, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'shFFF8, 16'sh0040, 4'd 7}: ratio_lut = 16'shF249;
        {16'shFFF8, 16'sh0040, 4'd 8}: ratio_lut = 16'shF200;
        {16'shFFF8, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'shFFF8, 16'sh0040, 4'd10}: ratio_lut = 16'shF19A;
        {16'shFFF8, 16'sh0040, 4'd11}: ratio_lut = 16'shF174;
        {16'shFFF8, 16'sh0040, 4'd12}: ratio_lut = 16'shF155;
        {16'shFFF8, 16'sh0040, 4'd13}: ratio_lut = 16'shF13B;
        {16'shFFF8, 16'sh0040, 4'd14}: ratio_lut = 16'shF125;
        {16'shFFF8, 16'sh0040, 4'd15}: ratio_lut = 16'shF111;
        {16'shFFF8, 16'sh0132, 4'd 2}: ratio_lut = 16'shF802;
        {16'shFFF8, 16'sh0132, 4'd 3}: ratio_lut = 16'shF557;
        {16'shFFF8, 16'sh0132, 4'd 4}: ratio_lut = 16'shF402;
        {16'shFFF8, 16'sh0132, 4'd 5}: ratio_lut = 16'shF334;
        {16'shFFF8, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'shFFF8, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24A;
        {16'shFFF8, 16'sh0132, 4'd 8}: ratio_lut = 16'shF201;
        {16'shFFF8, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'shFFF8, 16'sh0132, 4'd10}: ratio_lut = 16'shF19B;
        {16'shFFF8, 16'sh0132, 4'd11}: ratio_lut = 16'shF175;
        {16'shFFF8, 16'sh0132, 4'd12}: ratio_lut = 16'shF156;
        {16'shFFF8, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'shFFF8, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'shFFF8, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'shFFF8, 16'sh0446, 4'd 2}: ratio_lut = 16'shF812;
        {16'shFFF8, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56A;
        {16'shFFF8, 16'sh0446, 4'd 4}: ratio_lut = 16'shF414;
        {16'shFFF8, 16'sh0446, 4'd 5}: ratio_lut = 16'shF345;
        {16'shFFF8, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'shFFF8, 16'sh0446, 4'd 7}: ratio_lut = 16'shF258;
        {16'shFFF8, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20E;
        {16'shFFF8, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'shFFF8, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'shFFF8, 16'sh0446, 4'd11}: ratio_lut = 16'shF17F;
        {16'shFFF8, 16'sh0446, 4'd12}: ratio_lut = 16'shF15F;
        {16'shFFF8, 16'sh0446, 4'd13}: ratio_lut = 16'shF144;
        {16'shFFF8, 16'sh0446, 4'd14}: ratio_lut = 16'shF12E;
        {16'shFFF8, 16'sh0446, 4'd15}: ratio_lut = 16'shF119;
        {16'shFFF8, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF886;
        {16'shFFF8, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'shFFF8, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF496;
        {16'shFFF8, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'shFFF8, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF327;
        {16'shFFF8, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'shFFF8, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'shFFF8, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF226;
        {16'shFFF8, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F2;
        {16'shFFF8, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'shFFF8, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A1;
        {16'shFFF8, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'shFFF8, 16'sh0C90, 4'd14}: ratio_lut = 16'shF168;
        {16'shFFF8, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = 0 (Q4.12) = 0.00000000
        {16'sh0000, 16'shE000, 4'd 2}: ratio_lut = 16'shFA00;
        {16'sh0000, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'sh0000, 16'shE000, 4'd 4}: ratio_lut = 16'shF64A;
        {16'sh0000, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'sh0000, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'sh0000, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'sh0000, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'sh0000, 16'shE000, 4'd 9}: ratio_lut = 16'shF354;
        {16'sh0000, 16'shE000, 4'd10}: ratio_lut = 16'shF30C;
        {16'sh0000, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'sh0000, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'sh0000, 16'shE000, 4'd13}: ratio_lut = 16'shF26C;
        {16'sh0000, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'sh0000, 16'shE000, 4'd15}: ratio_lut = 16'shF222;
        {16'sh0000, 16'shF370, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0000, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0000, 16'shF370, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0000, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0000, 16'shF370, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0000, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0000, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0000, 16'shF370, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0000, 16'shF370, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0000, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0000, 16'shF370, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0000, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0000, 16'shF370, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0000, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0000, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0000, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0000, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0000, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0000, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0000, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0000, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0000, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0000, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0000, 16'shFBBA, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0000, 16'shFBBA, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0000, 16'shFBBA, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0000, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0000, 16'shFBBA, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0000, 16'shFECE, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0000, 16'shFECE, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0000, 16'shFECE, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0000, 16'shFECE, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0000, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0000, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0000, 16'shFECE, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0000, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0000, 16'shFECE, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0000, 16'shFECE, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0000, 16'shFECE, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0000, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0000, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0000, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0000, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0000, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0000, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0000, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0000, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0000, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0000, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0000, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0000, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0000, 16'shFFC0, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0000, 16'shFFC0, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0000, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0000, 16'shFFC0, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0000, 16'shFFC0, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0000, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0000, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0000, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0000, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0000, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0000, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0000, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0000, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0000, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0000, 16'shFFF8, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0000, 16'shFFF8, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0000, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0000, 16'shFFF8, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0000, 16'shFFF8, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0000, 16'sh0000, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0000, 16'sh0000, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0000, 16'sh0000, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0000, 16'sh0000, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0000, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0000, 16'sh0000, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0000, 16'sh0000, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0000, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0000, 16'sh0000, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0000, 16'sh0000, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0000, 16'sh0000, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0000, 16'sh0000, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0000, 16'sh0000, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0000, 16'sh0000, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0000, 16'sh0008, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0000, 16'sh0008, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0000, 16'sh0008, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0000, 16'sh0008, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0000, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0000, 16'sh0008, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0000, 16'sh0008, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0000, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0000, 16'sh0008, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0000, 16'sh0008, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0000, 16'sh0008, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0000, 16'sh0008, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0000, 16'sh0008, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0000, 16'sh0008, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0000, 16'sh0040, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0000, 16'sh0040, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0000, 16'sh0040, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0000, 16'sh0040, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0000, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0000, 16'sh0040, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0000, 16'sh0040, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0000, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0000, 16'sh0040, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0000, 16'sh0040, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0000, 16'sh0040, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0000, 16'sh0040, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0000, 16'sh0040, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0000, 16'sh0040, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0000, 16'sh0132, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0000, 16'sh0132, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0000, 16'sh0132, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0000, 16'sh0132, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0000, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0000, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0000, 16'sh0132, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0000, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0000, 16'sh0132, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0000, 16'sh0132, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0000, 16'sh0132, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0000, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0000, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0000, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0000, 16'sh0446, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0000, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0000, 16'sh0446, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0000, 16'sh0446, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0000, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0000, 16'sh0446, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0000, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0000, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0000, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0000, 16'sh0446, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0000, 16'sh0446, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0000, 16'sh0446, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0000, 16'sh0446, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0000, 16'sh0446, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0000, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0000, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0000, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0000, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0000, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0000, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0000, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0000, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0000, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0000, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0000, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0000, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0000, 16'sh0C90, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0000, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = 8 (Q4.12) = 0.00195312
        {16'sh0008, 16'shE000, 4'd 2}: ratio_lut = 16'shFA00;
        {16'sh0008, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'sh0008, 16'shE000, 4'd 4}: ratio_lut = 16'shF64A;
        {16'sh0008, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'sh0008, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'sh0008, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'sh0008, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'sh0008, 16'shE000, 4'd 9}: ratio_lut = 16'shF354;
        {16'sh0008, 16'shE000, 4'd10}: ratio_lut = 16'shF30C;
        {16'sh0008, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'sh0008, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'sh0008, 16'shE000, 4'd13}: ratio_lut = 16'shF26C;
        {16'sh0008, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'sh0008, 16'shE000, 4'd15}: ratio_lut = 16'shF222;
        {16'sh0008, 16'shF370, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0008, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0008, 16'shF370, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0008, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0008, 16'shF370, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0008, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0008, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0008, 16'shF370, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0008, 16'shF370, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0008, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0008, 16'shF370, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0008, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0008, 16'shF370, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0008, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0008, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0008, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0008, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0008, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0008, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0008, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0008, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0008, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0008, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0008, 16'shFBBA, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0008, 16'shFBBA, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0008, 16'shFBBA, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0008, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0008, 16'shFBBA, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0008, 16'shFECE, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0008, 16'shFECE, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0008, 16'shFECE, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0008, 16'shFECE, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0008, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0008, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0008, 16'shFECE, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0008, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0008, 16'shFECE, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0008, 16'shFECE, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0008, 16'shFECE, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0008, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0008, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0008, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0008, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0008, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0008, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0008, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0008, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0008, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0008, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0008, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0008, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0008, 16'shFFC0, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0008, 16'shFFC0, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0008, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0008, 16'shFFC0, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0008, 16'shFFC0, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0008, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0008, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0008, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0008, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0008, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0008, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0008, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0008, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0008, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0008, 16'shFFF8, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0008, 16'shFFF8, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0008, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0008, 16'shFFF8, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0008, 16'shFFF8, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0008, 16'sh0000, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0008, 16'sh0000, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0008, 16'sh0000, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0008, 16'sh0000, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0008, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0008, 16'sh0000, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0008, 16'sh0000, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0008, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0008, 16'sh0000, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0008, 16'sh0000, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0008, 16'sh0000, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0008, 16'sh0000, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0008, 16'sh0000, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0008, 16'sh0000, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0008, 16'sh0008, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0008, 16'sh0008, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0008, 16'sh0008, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0008, 16'sh0008, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0008, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0008, 16'sh0008, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0008, 16'sh0008, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0008, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0008, 16'sh0008, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0008, 16'sh0008, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0008, 16'sh0008, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0008, 16'sh0008, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0008, 16'sh0008, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0008, 16'sh0008, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0008, 16'sh0040, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0008, 16'sh0040, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0008, 16'sh0040, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0008, 16'sh0040, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0008, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0008, 16'sh0040, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0008, 16'sh0040, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0008, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0008, 16'sh0040, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0008, 16'sh0040, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0008, 16'sh0040, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0008, 16'sh0040, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0008, 16'sh0040, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0008, 16'sh0040, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0008, 16'sh0132, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0008, 16'sh0132, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0008, 16'sh0132, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0008, 16'sh0132, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0008, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0008, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0008, 16'sh0132, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0008, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0008, 16'sh0132, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0008, 16'sh0132, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0008, 16'sh0132, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0008, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0008, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0008, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0008, 16'sh0446, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0008, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0008, 16'sh0446, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0008, 16'sh0446, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0008, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0008, 16'sh0446, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0008, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0008, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0008, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0008, 16'sh0446, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0008, 16'sh0446, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0008, 16'sh0446, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0008, 16'sh0446, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0008, 16'sh0446, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0008, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0008, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0008, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0008, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0008, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0008, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0008, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0008, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0008, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0008, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0008, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0008, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0008, 16'sh0C90, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0008, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = 64 (Q4.12) = 0.01562500
        {16'sh0040, 16'shE000, 4'd 2}: ratio_lut = 16'shFA00;
        {16'sh0040, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B0;
        {16'sh0040, 16'shE000, 4'd 4}: ratio_lut = 16'shF64A;
        {16'sh0040, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'sh0040, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A2;
        {16'sh0040, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'sh0040, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AC;
        {16'sh0040, 16'shE000, 4'd 9}: ratio_lut = 16'shF354;
        {16'sh0040, 16'shE000, 4'd10}: ratio_lut = 16'shF30C;
        {16'sh0040, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'sh0040, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'sh0040, 16'shE000, 4'd13}: ratio_lut = 16'shF26C;
        {16'sh0040, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'sh0040, 16'shE000, 4'd15}: ratio_lut = 16'shF222;
        {16'sh0040, 16'shF370, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0040, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0040, 16'shF370, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0040, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0040, 16'shF370, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0040, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0040, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0040, 16'shF370, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0040, 16'shF370, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0040, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0040, 16'shF370, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0040, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0040, 16'shF370, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0040, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0040, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0040, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0040, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0040, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0040, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0040, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0040, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0040, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0040, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0040, 16'shFBBA, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0040, 16'shFBBA, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0040, 16'shFBBA, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0040, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0040, 16'shFBBA, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0040, 16'shFECE, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0040, 16'shFECE, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0040, 16'shFECE, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0040, 16'shFECE, 4'd 5}: ratio_lut = 16'shF335;
        {16'sh0040, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'sh0040, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0040, 16'shFECE, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0040, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0040, 16'shFECE, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0040, 16'shFECE, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0040, 16'shFECE, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0040, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0040, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0040, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0040, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF801;
        {16'sh0040, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0040, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0040, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0040, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0040, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0040, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0040, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0040, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0040, 16'shFFC0, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0040, 16'shFFC0, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0040, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0040, 16'shFFC0, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0040, 16'shFFC0, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0040, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0040, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0040, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0040, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0040, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0040, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0040, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0040, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0040, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0040, 16'shFFF8, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0040, 16'shFFF8, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0040, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0040, 16'shFFF8, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0040, 16'shFFF8, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0040, 16'sh0000, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0040, 16'sh0000, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0040, 16'sh0000, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0040, 16'sh0000, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0040, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0040, 16'sh0000, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0040, 16'sh0000, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0040, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0040, 16'sh0000, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0040, 16'sh0000, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0040, 16'sh0000, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0040, 16'sh0000, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0040, 16'sh0000, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0040, 16'sh0000, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0040, 16'sh0008, 4'd 2}: ratio_lut = 16'shF800;
        {16'sh0040, 16'sh0008, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0040, 16'sh0008, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0040, 16'sh0008, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0040, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0040, 16'sh0008, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0040, 16'sh0008, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0040, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0040, 16'sh0008, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0040, 16'sh0008, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0040, 16'sh0008, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0040, 16'sh0008, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0040, 16'sh0008, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0040, 16'sh0008, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0040, 16'sh0040, 4'd 2}: ratio_lut = 16'shF801;
        {16'sh0040, 16'sh0040, 4'd 3}: ratio_lut = 16'shF555;
        {16'sh0040, 16'sh0040, 4'd 4}: ratio_lut = 16'shF400;
        {16'sh0040, 16'sh0040, 4'd 5}: ratio_lut = 16'shF333;
        {16'sh0040, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AB;
        {16'sh0040, 16'sh0040, 4'd 7}: ratio_lut = 16'shF249;
        {16'sh0040, 16'sh0040, 4'd 8}: ratio_lut = 16'shF200;
        {16'sh0040, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C7;
        {16'sh0040, 16'sh0040, 4'd10}: ratio_lut = 16'shF19A;
        {16'sh0040, 16'sh0040, 4'd11}: ratio_lut = 16'shF174;
        {16'sh0040, 16'sh0040, 4'd12}: ratio_lut = 16'shF155;
        {16'sh0040, 16'sh0040, 4'd13}: ratio_lut = 16'shF13B;
        {16'sh0040, 16'sh0040, 4'd14}: ratio_lut = 16'shF125;
        {16'sh0040, 16'sh0040, 4'd15}: ratio_lut = 16'shF111;
        {16'sh0040, 16'sh0132, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0040, 16'sh0132, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0040, 16'sh0132, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0040, 16'sh0132, 4'd 5}: ratio_lut = 16'shF335;
        {16'sh0040, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'sh0040, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0040, 16'sh0132, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0040, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0040, 16'sh0132, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0040, 16'sh0132, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0040, 16'sh0132, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0040, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0040, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0040, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0040, 16'sh0446, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0040, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0040, 16'sh0446, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0040, 16'sh0446, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0040, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0040, 16'sh0446, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0040, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0040, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0040, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0040, 16'sh0446, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0040, 16'sh0446, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0040, 16'sh0446, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0040, 16'sh0446, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0040, 16'sh0446, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0040, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0040, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0040, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0040, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0040, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0040, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0040, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0040, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0040, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0040, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0040, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0040, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0040, 16'sh0C90, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0040, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = 306 (Q4.12) = 0.07470703
        {16'sh0132, 16'shE000, 4'd 2}: ratio_lut = 16'shFA01;
        {16'sh0132, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B1;
        {16'sh0132, 16'shE000, 4'd 4}: ratio_lut = 16'shF64B;
        {16'sh0132, 16'shE000, 4'd 5}: ratio_lut = 16'shF555;
        {16'sh0132, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A3;
        {16'sh0132, 16'shE000, 4'd 7}: ratio_lut = 16'shF419;
        {16'sh0132, 16'shE000, 4'd 8}: ratio_lut = 16'shF3AD;
        {16'sh0132, 16'shE000, 4'd 9}: ratio_lut = 16'shF355;
        {16'sh0132, 16'shE000, 4'd10}: ratio_lut = 16'shF30D;
        {16'sh0132, 16'shE000, 4'd11}: ratio_lut = 16'shF2CE;
        {16'sh0132, 16'shE000, 4'd12}: ratio_lut = 16'shF299;
        {16'sh0132, 16'shE000, 4'd13}: ratio_lut = 16'shF26D;
        {16'sh0132, 16'shE000, 4'd14}: ratio_lut = 16'shF246;
        {16'sh0132, 16'shE000, 4'd15}: ratio_lut = 16'shF223;
        {16'sh0132, 16'shF370, 4'd 2}: ratio_lut = 16'shF887;
        {16'sh0132, 16'shF370, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'sh0132, 16'shF370, 4'd 4}: ratio_lut = 16'shF497;
        {16'sh0132, 16'shF370, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'sh0132, 16'shF370, 4'd 6}: ratio_lut = 16'shF328;
        {16'sh0132, 16'shF370, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'sh0132, 16'shF370, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0132, 16'shF370, 4'd 9}: ratio_lut = 16'shF227;
        {16'sh0132, 16'shF370, 4'd10}: ratio_lut = 16'shF1F3;
        {16'sh0132, 16'shF370, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0132, 16'shF370, 4'd12}: ratio_lut = 16'shF1A2;
        {16'sh0132, 16'shF370, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0132, 16'shF370, 4'd14}: ratio_lut = 16'shF169;
        {16'sh0132, 16'shF370, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0132, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF814;
        {16'sh0132, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF56C;
        {16'sh0132, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF416;
        {16'sh0132, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF347;
        {16'sh0132, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'sh0132, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF259;
        {16'sh0132, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF20F;
        {16'sh0132, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0132, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0132, 16'shFBBA, 4'd11}: ratio_lut = 16'shF180;
        {16'sh0132, 16'shFBBA, 4'd12}: ratio_lut = 16'shF160;
        {16'sh0132, 16'shFBBA, 4'd13}: ratio_lut = 16'shF145;
        {16'sh0132, 16'shFBBA, 4'd14}: ratio_lut = 16'shF12F;
        {16'sh0132, 16'shFBBA, 4'd15}: ratio_lut = 16'shF11A;
        {16'sh0132, 16'shFECE, 4'd 2}: ratio_lut = 16'shF803;
        {16'sh0132, 16'shFECE, 4'd 3}: ratio_lut = 16'shF559;
        {16'sh0132, 16'shFECE, 4'd 4}: ratio_lut = 16'shF403;
        {16'sh0132, 16'shFECE, 4'd 5}: ratio_lut = 16'shF336;
        {16'sh0132, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2AE;
        {16'sh0132, 16'shFECE, 4'd 7}: ratio_lut = 16'shF24B;
        {16'sh0132, 16'shFECE, 4'd 8}: ratio_lut = 16'shF202;
        {16'sh0132, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1C9;
        {16'sh0132, 16'shFECE, 4'd10}: ratio_lut = 16'shF19C;
        {16'sh0132, 16'shFECE, 4'd11}: ratio_lut = 16'shF176;
        {16'sh0132, 16'shFECE, 4'd12}: ratio_lut = 16'shF157;
        {16'sh0132, 16'shFECE, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'shFECE, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'shFECE, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0132, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0132, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0132, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF335;
        {16'sh0132, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'sh0132, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0132, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0132, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0132, 16'shFFC0, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0132, 16'shFFC0, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0132, 16'shFFC0, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0132, 16'shFFC0, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'shFFC0, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'shFFC0, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0132, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0132, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0132, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0132, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0132, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0132, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0132, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0132, 16'shFFF8, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0132, 16'shFFF8, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0132, 16'shFFF8, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0132, 16'shFFF8, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'shFFF8, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'shFFF8, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'sh0000, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0132, 16'sh0000, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0132, 16'sh0000, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0132, 16'sh0000, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0132, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0132, 16'sh0000, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0132, 16'sh0000, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0132, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0132, 16'sh0000, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0132, 16'sh0000, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0132, 16'sh0000, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0132, 16'sh0000, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'sh0000, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'sh0000, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'sh0008, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0132, 16'sh0008, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0132, 16'sh0008, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0132, 16'sh0008, 4'd 5}: ratio_lut = 16'shF334;
        {16'sh0132, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2AC;
        {16'sh0132, 16'sh0008, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0132, 16'sh0008, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0132, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0132, 16'sh0008, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0132, 16'sh0008, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0132, 16'sh0008, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0132, 16'sh0008, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'sh0008, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'sh0008, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'sh0040, 4'd 2}: ratio_lut = 16'shF802;
        {16'sh0132, 16'sh0040, 4'd 3}: ratio_lut = 16'shF557;
        {16'sh0132, 16'sh0040, 4'd 4}: ratio_lut = 16'shF402;
        {16'sh0132, 16'sh0040, 4'd 5}: ratio_lut = 16'shF335;
        {16'sh0132, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2AD;
        {16'sh0132, 16'sh0040, 4'd 7}: ratio_lut = 16'shF24A;
        {16'sh0132, 16'sh0040, 4'd 8}: ratio_lut = 16'shF201;
        {16'sh0132, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1C8;
        {16'sh0132, 16'sh0040, 4'd10}: ratio_lut = 16'shF19B;
        {16'sh0132, 16'sh0040, 4'd11}: ratio_lut = 16'shF175;
        {16'sh0132, 16'sh0040, 4'd12}: ratio_lut = 16'shF156;
        {16'sh0132, 16'sh0040, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'sh0040, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'sh0040, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'sh0132, 4'd 2}: ratio_lut = 16'shF803;
        {16'sh0132, 16'sh0132, 4'd 3}: ratio_lut = 16'shF559;
        {16'sh0132, 16'sh0132, 4'd 4}: ratio_lut = 16'shF403;
        {16'sh0132, 16'sh0132, 4'd 5}: ratio_lut = 16'shF336;
        {16'sh0132, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2AE;
        {16'sh0132, 16'sh0132, 4'd 7}: ratio_lut = 16'shF24B;
        {16'sh0132, 16'sh0132, 4'd 8}: ratio_lut = 16'shF202;
        {16'sh0132, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1C9;
        {16'sh0132, 16'sh0132, 4'd10}: ratio_lut = 16'shF19C;
        {16'sh0132, 16'sh0132, 4'd11}: ratio_lut = 16'shF176;
        {16'sh0132, 16'sh0132, 4'd12}: ratio_lut = 16'shF157;
        {16'sh0132, 16'sh0132, 4'd13}: ratio_lut = 16'shF13C;
        {16'sh0132, 16'sh0132, 4'd14}: ratio_lut = 16'shF126;
        {16'sh0132, 16'sh0132, 4'd15}: ratio_lut = 16'shF112;
        {16'sh0132, 16'sh0446, 4'd 2}: ratio_lut = 16'shF814;
        {16'sh0132, 16'sh0446, 4'd 3}: ratio_lut = 16'shF56C;
        {16'sh0132, 16'sh0446, 4'd 4}: ratio_lut = 16'shF416;
        {16'sh0132, 16'sh0446, 4'd 5}: ratio_lut = 16'shF347;
        {16'sh0132, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'sh0132, 16'sh0446, 4'd 7}: ratio_lut = 16'shF259;
        {16'sh0132, 16'sh0446, 4'd 8}: ratio_lut = 16'shF20F;
        {16'sh0132, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0132, 16'sh0446, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0132, 16'sh0446, 4'd11}: ratio_lut = 16'shF180;
        {16'sh0132, 16'sh0446, 4'd12}: ratio_lut = 16'shF160;
        {16'sh0132, 16'sh0446, 4'd13}: ratio_lut = 16'shF145;
        {16'sh0132, 16'sh0446, 4'd14}: ratio_lut = 16'shF12F;
        {16'sh0132, 16'sh0446, 4'd15}: ratio_lut = 16'shF11A;
        {16'sh0132, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF887;
        {16'sh0132, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'sh0132, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF497;
        {16'sh0132, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'sh0132, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF328;
        {16'sh0132, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'sh0132, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0132, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF227;
        {16'sh0132, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1F3;
        {16'sh0132, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0132, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A2;
        {16'sh0132, 16'sh0C90, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0132, 16'sh0C90, 4'd14}: ratio_lut = 16'shF169;
        {16'sh0132, 16'sh0C90, 4'd15}: ratio_lut = 16'shF151;

        // gx = 1094 (Q4.12) = 0.26708984
        {16'sh0446, 16'shE000, 4'd 2}: ratio_lut = 16'shFA05;
        {16'sh0446, 16'shE000, 4'd 3}: ratio_lut = 16'shF7B6;
        {16'sh0446, 16'shE000, 4'd 4}: ratio_lut = 16'shF650;
        {16'sh0446, 16'shE000, 4'd 5}: ratio_lut = 16'shF55B;
        {16'sh0446, 16'shE000, 4'd 6}: ratio_lut = 16'shF4A8;
        {16'sh0446, 16'shE000, 4'd 7}: ratio_lut = 16'shF41E;
        {16'sh0446, 16'shE000, 4'd 8}: ratio_lut = 16'shF3B2;
        {16'sh0446, 16'shE000, 4'd 9}: ratio_lut = 16'shF359;
        {16'sh0446, 16'shE000, 4'd10}: ratio_lut = 16'shF310;
        {16'sh0446, 16'shE000, 4'd11}: ratio_lut = 16'shF2D1;
        {16'sh0446, 16'shE000, 4'd12}: ratio_lut = 16'shF29D;
        {16'sh0446, 16'shE000, 4'd13}: ratio_lut = 16'shF270;
        {16'sh0446, 16'shE000, 4'd14}: ratio_lut = 16'shF249;
        {16'sh0446, 16'shE000, 4'd15}: ratio_lut = 16'shF225;
        {16'sh0446, 16'shF370, 4'd 2}: ratio_lut = 16'shF892;
        {16'sh0446, 16'shF370, 4'd 3}: ratio_lut = 16'shF601;
        {16'sh0446, 16'shF370, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'sh0446, 16'shF370, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'sh0446, 16'shF370, 4'd 6}: ratio_lut = 16'shF334;
        {16'sh0446, 16'shF370, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'sh0446, 16'shF370, 4'd 8}: ratio_lut = 16'shF272;
        {16'sh0446, 16'shF370, 4'd 9}: ratio_lut = 16'shF230;
        {16'sh0446, 16'shF370, 4'd10}: ratio_lut = 16'shF1FB;
        {16'sh0446, 16'shF370, 4'd11}: ratio_lut = 16'shF1CE;
        {16'sh0446, 16'shF370, 4'd12}: ratio_lut = 16'shF1A9;
        {16'sh0446, 16'shF370, 4'd13}: ratio_lut = 16'shF18A;
        {16'sh0446, 16'shF370, 4'd14}: ratio_lut = 16'shF16F;
        {16'sh0446, 16'shF370, 4'd15}: ratio_lut = 16'shF157;
        {16'sh0446, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF823;
        {16'sh0446, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF57E;
        {16'sh0446, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF427;
        {16'sh0446, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF357;
        {16'sh0446, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF2CB;
        {16'sh0446, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF266;
        {16'sh0446, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF21B;
        {16'sh0446, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF1E0;
        {16'sh0446, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1B1;
        {16'sh0446, 16'shFBBA, 4'd11}: ratio_lut = 16'shF189;
        {16'sh0446, 16'shFBBA, 4'd12}: ratio_lut = 16'shF169;
        {16'sh0446, 16'shFBBA, 4'd13}: ratio_lut = 16'shF14D;
        {16'sh0446, 16'shFBBA, 4'd14}: ratio_lut = 16'shF136;
        {16'sh0446, 16'shFBBA, 4'd15}: ratio_lut = 16'shF121;
        {16'sh0446, 16'shFECE, 4'd 2}: ratio_lut = 16'shF814;
        {16'sh0446, 16'shFECE, 4'd 3}: ratio_lut = 16'shF56C;
        {16'sh0446, 16'shFECE, 4'd 4}: ratio_lut = 16'shF416;
        {16'sh0446, 16'shFECE, 4'd 5}: ratio_lut = 16'shF347;
        {16'sh0446, 16'shFECE, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'sh0446, 16'shFECE, 4'd 7}: ratio_lut = 16'shF259;
        {16'sh0446, 16'shFECE, 4'd 8}: ratio_lut = 16'shF20F;
        {16'sh0446, 16'shFECE, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'shFECE, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'shFECE, 4'd11}: ratio_lut = 16'shF180;
        {16'sh0446, 16'shFECE, 4'd12}: ratio_lut = 16'shF160;
        {16'sh0446, 16'shFECE, 4'd13}: ratio_lut = 16'shF145;
        {16'sh0446, 16'shFECE, 4'd14}: ratio_lut = 16'shF12F;
        {16'sh0446, 16'shFECE, 4'd15}: ratio_lut = 16'shF11A;
        {16'sh0446, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0446, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0446, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0446, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0446, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0446, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0446, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0446, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'shFFC0, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'shFFC0, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0446, 16'shFFC0, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0446, 16'shFFC0, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0446, 16'shFFC0, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0446, 16'shFFC0, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0446, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0446, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0446, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0446, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0446, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0446, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0446, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0446, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'shFFF8, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'shFFF8, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0446, 16'shFFF8, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0446, 16'shFFF8, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0446, 16'shFFF8, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0446, 16'shFFF8, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0446, 16'sh0000, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0446, 16'sh0000, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0446, 16'sh0000, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0446, 16'sh0000, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0446, 16'sh0000, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0446, 16'sh0000, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0446, 16'sh0000, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0446, 16'sh0000, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'sh0000, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'sh0000, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0446, 16'sh0000, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0446, 16'sh0000, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0446, 16'sh0000, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0446, 16'sh0000, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0446, 16'sh0008, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0446, 16'sh0008, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0446, 16'sh0008, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0446, 16'sh0008, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0446, 16'sh0008, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0446, 16'sh0008, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0446, 16'sh0008, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0446, 16'sh0008, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'sh0008, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'sh0008, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0446, 16'sh0008, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0446, 16'sh0008, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0446, 16'sh0008, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0446, 16'sh0008, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0446, 16'sh0040, 4'd 2}: ratio_lut = 16'shF812;
        {16'sh0446, 16'sh0040, 4'd 3}: ratio_lut = 16'shF56A;
        {16'sh0446, 16'sh0040, 4'd 4}: ratio_lut = 16'shF414;
        {16'sh0446, 16'sh0040, 4'd 5}: ratio_lut = 16'shF345;
        {16'sh0446, 16'sh0040, 4'd 6}: ratio_lut = 16'shF2BC;
        {16'sh0446, 16'sh0040, 4'd 7}: ratio_lut = 16'shF258;
        {16'sh0446, 16'sh0040, 4'd 8}: ratio_lut = 16'shF20E;
        {16'sh0446, 16'sh0040, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'sh0040, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'sh0040, 4'd11}: ratio_lut = 16'shF17F;
        {16'sh0446, 16'sh0040, 4'd12}: ratio_lut = 16'shF15F;
        {16'sh0446, 16'sh0040, 4'd13}: ratio_lut = 16'shF144;
        {16'sh0446, 16'sh0040, 4'd14}: ratio_lut = 16'shF12E;
        {16'sh0446, 16'sh0040, 4'd15}: ratio_lut = 16'shF119;
        {16'sh0446, 16'sh0132, 4'd 2}: ratio_lut = 16'shF814;
        {16'sh0446, 16'sh0132, 4'd 3}: ratio_lut = 16'shF56C;
        {16'sh0446, 16'sh0132, 4'd 4}: ratio_lut = 16'shF416;
        {16'sh0446, 16'sh0132, 4'd 5}: ratio_lut = 16'shF347;
        {16'sh0446, 16'sh0132, 4'd 6}: ratio_lut = 16'shF2BD;
        {16'sh0446, 16'sh0132, 4'd 7}: ratio_lut = 16'shF259;
        {16'sh0446, 16'sh0132, 4'd 8}: ratio_lut = 16'shF20F;
        {16'sh0446, 16'sh0132, 4'd 9}: ratio_lut = 16'shF1D4;
        {16'sh0446, 16'sh0132, 4'd10}: ratio_lut = 16'shF1A6;
        {16'sh0446, 16'sh0132, 4'd11}: ratio_lut = 16'shF180;
        {16'sh0446, 16'sh0132, 4'd12}: ratio_lut = 16'shF160;
        {16'sh0446, 16'sh0132, 4'd13}: ratio_lut = 16'shF145;
        {16'sh0446, 16'sh0132, 4'd14}: ratio_lut = 16'shF12F;
        {16'sh0446, 16'sh0132, 4'd15}: ratio_lut = 16'shF11A;
        {16'sh0446, 16'sh0446, 4'd 2}: ratio_lut = 16'shF823;
        {16'sh0446, 16'sh0446, 4'd 3}: ratio_lut = 16'shF57E;
        {16'sh0446, 16'sh0446, 4'd 4}: ratio_lut = 16'shF427;
        {16'sh0446, 16'sh0446, 4'd 5}: ratio_lut = 16'shF357;
        {16'sh0446, 16'sh0446, 4'd 6}: ratio_lut = 16'shF2CB;
        {16'sh0446, 16'sh0446, 4'd 7}: ratio_lut = 16'shF266;
        {16'sh0446, 16'sh0446, 4'd 8}: ratio_lut = 16'shF21B;
        {16'sh0446, 16'sh0446, 4'd 9}: ratio_lut = 16'shF1E0;
        {16'sh0446, 16'sh0446, 4'd10}: ratio_lut = 16'shF1B1;
        {16'sh0446, 16'sh0446, 4'd11}: ratio_lut = 16'shF189;
        {16'sh0446, 16'sh0446, 4'd12}: ratio_lut = 16'shF169;
        {16'sh0446, 16'sh0446, 4'd13}: ratio_lut = 16'shF14D;
        {16'sh0446, 16'sh0446, 4'd14}: ratio_lut = 16'shF136;
        {16'sh0446, 16'sh0446, 4'd15}: ratio_lut = 16'shF121;
        {16'sh0446, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF892;
        {16'sh0446, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF601;
        {16'sh0446, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'sh0446, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'sh0446, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF334;
        {16'sh0446, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'sh0446, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF272;
        {16'sh0446, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF230;
        {16'sh0446, 16'sh0C90, 4'd10}: ratio_lut = 16'shF1FB;
        {16'sh0446, 16'sh0C90, 4'd11}: ratio_lut = 16'shF1CE;
        {16'sh0446, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1A9;
        {16'sh0446, 16'sh0C90, 4'd13}: ratio_lut = 16'shF18A;
        {16'sh0446, 16'sh0C90, 4'd14}: ratio_lut = 16'shF16F;
        {16'sh0446, 16'sh0C90, 4'd15}: ratio_lut = 16'shF157;

        // gx = 3216 (Q4.12) = 0.78515625
        {16'sh0C90, 16'shE000, 4'd 2}: ratio_lut = 16'shFA2A;
        {16'sh0C90, 16'shE000, 4'd 3}: ratio_lut = 16'shF7E3;
        {16'sh0C90, 16'shE000, 4'd 4}: ratio_lut = 16'shF67D;
        {16'sh0C90, 16'shE000, 4'd 5}: ratio_lut = 16'shF586;
        {16'sh0C90, 16'shE000, 4'd 6}: ratio_lut = 16'shF4D0;
        {16'sh0C90, 16'shE000, 4'd 7}: ratio_lut = 16'shF444;
        {16'sh0C90, 16'shE000, 4'd 8}: ratio_lut = 16'shF3D5;
        {16'sh0C90, 16'shE000, 4'd 9}: ratio_lut = 16'shF37A;
        {16'sh0C90, 16'shE000, 4'd10}: ratio_lut = 16'shF330;
        {16'sh0C90, 16'shE000, 4'd11}: ratio_lut = 16'shF2EF;
        {16'sh0C90, 16'shE000, 4'd12}: ratio_lut = 16'shF2B9;
        {16'sh0C90, 16'shE000, 4'd13}: ratio_lut = 16'shF28B;
        {16'sh0C90, 16'shE000, 4'd14}: ratio_lut = 16'shF262;
        {16'sh0C90, 16'shE000, 4'd15}: ratio_lut = 16'shF23D;
        {16'sh0C90, 16'shF370, 4'd 2}: ratio_lut = 16'shF8EB;
        {16'sh0C90, 16'shF370, 4'd 3}: ratio_lut = 16'shF668;
        {16'sh0C90, 16'shF370, 4'd 4}: ratio_lut = 16'shF507;
        {16'sh0C90, 16'shF370, 4'd 5}: ratio_lut = 16'shF425;
        {16'sh0C90, 16'shF370, 4'd 6}: ratio_lut = 16'shF387;
        {16'sh0C90, 16'shF370, 4'd 7}: ratio_lut = 16'shF312;
        {16'sh0C90, 16'shF370, 4'd 8}: ratio_lut = 16'shF2B8;
        {16'sh0C90, 16'shF370, 4'd 9}: ratio_lut = 16'shF271;
        {16'sh0C90, 16'shF370, 4'd10}: ratio_lut = 16'shF237;
        {16'sh0C90, 16'shF370, 4'd11}: ratio_lut = 16'shF206;
        {16'sh0C90, 16'shF370, 4'd12}: ratio_lut = 16'shF1DE;
        {16'sh0C90, 16'shF370, 4'd13}: ratio_lut = 16'shF1BB;
        {16'sh0C90, 16'shF370, 4'd14}: ratio_lut = 16'shF19E;
        {16'sh0C90, 16'shF370, 4'd15}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'shFBBA, 4'd 2}: ratio_lut = 16'shF892;
        {16'sh0C90, 16'shFBBA, 4'd 3}: ratio_lut = 16'shF601;
        {16'sh0C90, 16'shFBBA, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'sh0C90, 16'shFBBA, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'sh0C90, 16'shFBBA, 4'd 6}: ratio_lut = 16'shF334;
        {16'sh0C90, 16'shFBBA, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'sh0C90, 16'shFBBA, 4'd 8}: ratio_lut = 16'shF272;
        {16'sh0C90, 16'shFBBA, 4'd 9}: ratio_lut = 16'shF230;
        {16'sh0C90, 16'shFBBA, 4'd10}: ratio_lut = 16'shF1FB;
        {16'sh0C90, 16'shFBBA, 4'd11}: ratio_lut = 16'shF1CE;
        {16'sh0C90, 16'shFBBA, 4'd12}: ratio_lut = 16'shF1A9;
        {16'sh0C90, 16'shFBBA, 4'd13}: ratio_lut = 16'shF18A;
        {16'sh0C90, 16'shFBBA, 4'd14}: ratio_lut = 16'shF16F;
        {16'sh0C90, 16'shFBBA, 4'd15}: ratio_lut = 16'shF157;
        {16'sh0C90, 16'shFECE, 4'd 2}: ratio_lut = 16'shF887;
        {16'sh0C90, 16'shFECE, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'sh0C90, 16'shFECE, 4'd 4}: ratio_lut = 16'shF497;
        {16'sh0C90, 16'shFECE, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'sh0C90, 16'shFECE, 4'd 6}: ratio_lut = 16'shF328;
        {16'sh0C90, 16'shFECE, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'sh0C90, 16'shFECE, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'shFECE, 4'd 9}: ratio_lut = 16'shF227;
        {16'sh0C90, 16'shFECE, 4'd10}: ratio_lut = 16'shF1F3;
        {16'sh0C90, 16'shFECE, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'shFECE, 4'd12}: ratio_lut = 16'shF1A2;
        {16'sh0C90, 16'shFECE, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'shFECE, 4'd14}: ratio_lut = 16'shF169;
        {16'sh0C90, 16'shFECE, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'shFFC0, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0C90, 16'shFFC0, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0C90, 16'shFFC0, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0C90, 16'shFFC0, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0C90, 16'shFFC0, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0C90, 16'shFFC0, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0C90, 16'shFFC0, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'shFFC0, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0C90, 16'shFFC0, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0C90, 16'shFFC0, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'shFFC0, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0C90, 16'shFFC0, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'shFFC0, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0C90, 16'shFFC0, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'shFFF8, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0C90, 16'shFFF8, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0C90, 16'shFFF8, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0C90, 16'shFFF8, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0C90, 16'shFFF8, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0C90, 16'shFFF8, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0C90, 16'shFFF8, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'shFFF8, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0C90, 16'shFFF8, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0C90, 16'shFFF8, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'shFFF8, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0C90, 16'shFFF8, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'shFFF8, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0C90, 16'shFFF8, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'sh0000, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0C90, 16'sh0000, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0C90, 16'sh0000, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0C90, 16'sh0000, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0C90, 16'sh0000, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0C90, 16'sh0000, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0C90, 16'sh0000, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'sh0000, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0C90, 16'sh0000, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0C90, 16'sh0000, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'sh0000, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0C90, 16'sh0000, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'sh0000, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0C90, 16'sh0000, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'sh0008, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0C90, 16'sh0008, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0C90, 16'sh0008, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0C90, 16'sh0008, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0C90, 16'sh0008, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0C90, 16'sh0008, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0C90, 16'sh0008, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'sh0008, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0C90, 16'sh0008, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0C90, 16'sh0008, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'sh0008, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0C90, 16'sh0008, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'sh0008, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0C90, 16'sh0008, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'sh0040, 4'd 2}: ratio_lut = 16'shF886;
        {16'sh0C90, 16'sh0040, 4'd 3}: ratio_lut = 16'shF5F2;
        {16'sh0C90, 16'sh0040, 4'd 4}: ratio_lut = 16'shF496;
        {16'sh0C90, 16'sh0040, 4'd 5}: ratio_lut = 16'shF3BC;
        {16'sh0C90, 16'sh0040, 4'd 6}: ratio_lut = 16'shF327;
        {16'sh0C90, 16'sh0040, 4'd 7}: ratio_lut = 16'shF2BA;
        {16'sh0C90, 16'sh0040, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'sh0040, 4'd 9}: ratio_lut = 16'shF226;
        {16'sh0C90, 16'sh0040, 4'd10}: ratio_lut = 16'shF1F2;
        {16'sh0C90, 16'sh0040, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'sh0040, 4'd12}: ratio_lut = 16'shF1A1;
        {16'sh0C90, 16'sh0040, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'sh0040, 4'd14}: ratio_lut = 16'shF168;
        {16'sh0C90, 16'sh0040, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'sh0132, 4'd 2}: ratio_lut = 16'shF887;
        {16'sh0C90, 16'sh0132, 4'd 3}: ratio_lut = 16'shF5F3;
        {16'sh0C90, 16'sh0132, 4'd 4}: ratio_lut = 16'shF497;
        {16'sh0C90, 16'sh0132, 4'd 5}: ratio_lut = 16'shF3BD;
        {16'sh0C90, 16'sh0132, 4'd 6}: ratio_lut = 16'shF328;
        {16'sh0C90, 16'sh0132, 4'd 7}: ratio_lut = 16'shF2BB;
        {16'sh0C90, 16'sh0132, 4'd 8}: ratio_lut = 16'shF268;
        {16'sh0C90, 16'sh0132, 4'd 9}: ratio_lut = 16'shF227;
        {16'sh0C90, 16'sh0132, 4'd10}: ratio_lut = 16'shF1F3;
        {16'sh0C90, 16'sh0132, 4'd11}: ratio_lut = 16'shF1C6;
        {16'sh0C90, 16'sh0132, 4'd12}: ratio_lut = 16'shF1A2;
        {16'sh0C90, 16'sh0132, 4'd13}: ratio_lut = 16'shF183;
        {16'sh0C90, 16'sh0132, 4'd14}: ratio_lut = 16'shF169;
        {16'sh0C90, 16'sh0132, 4'd15}: ratio_lut = 16'shF151;
        {16'sh0C90, 16'sh0446, 4'd 2}: ratio_lut = 16'shF892;
        {16'sh0C90, 16'sh0446, 4'd 3}: ratio_lut = 16'shF601;
        {16'sh0C90, 16'sh0446, 4'd 4}: ratio_lut = 16'shF4A4;
        {16'sh0C90, 16'sh0446, 4'd 5}: ratio_lut = 16'shF3C9;
        {16'sh0C90, 16'sh0446, 4'd 6}: ratio_lut = 16'shF334;
        {16'sh0C90, 16'sh0446, 4'd 7}: ratio_lut = 16'shF2C5;
        {16'sh0C90, 16'sh0446, 4'd 8}: ratio_lut = 16'shF272;
        {16'sh0C90, 16'sh0446, 4'd 9}: ratio_lut = 16'shF230;
        {16'sh0C90, 16'sh0446, 4'd10}: ratio_lut = 16'shF1FB;
        {16'sh0C90, 16'sh0446, 4'd11}: ratio_lut = 16'shF1CE;
        {16'sh0C90, 16'sh0446, 4'd12}: ratio_lut = 16'shF1A9;
        {16'sh0C90, 16'sh0446, 4'd13}: ratio_lut = 16'shF18A;
        {16'sh0C90, 16'sh0446, 4'd14}: ratio_lut = 16'shF16F;
        {16'sh0C90, 16'sh0446, 4'd15}: ratio_lut = 16'shF157;
        {16'sh0C90, 16'sh0C90, 4'd 2}: ratio_lut = 16'shF8EB;
        {16'sh0C90, 16'sh0C90, 4'd 3}: ratio_lut = 16'shF668;
        {16'sh0C90, 16'sh0C90, 4'd 4}: ratio_lut = 16'shF507;
        {16'sh0C90, 16'sh0C90, 4'd 5}: ratio_lut = 16'shF425;
        {16'sh0C90, 16'sh0C90, 4'd 6}: ratio_lut = 16'shF387;
        {16'sh0C90, 16'sh0C90, 4'd 7}: ratio_lut = 16'shF312;
        {16'sh0C90, 16'sh0C90, 4'd 8}: ratio_lut = 16'shF2B8;
        {16'sh0C90, 16'sh0C90, 4'd 9}: ratio_lut = 16'shF271;
        {16'sh0C90, 16'sh0C90, 4'd10}: ratio_lut = 16'shF237;
        {16'sh0C90, 16'sh0C90, 4'd11}: ratio_lut = 16'shF206;
        {16'sh0C90, 16'sh0C90, 4'd12}: ratio_lut = 16'shF1DE;
        {16'sh0C90, 16'sh0C90, 4'd13}: ratio_lut = 16'shF1BB;
        {16'sh0C90, 16'sh0C90, 4'd14}: ratio_lut = 16'shF19E;
        {16'sh0C90, 16'sh0C90, 4'd15}: ratio_lut = 16'shF183;

        default: ratio_lut = 16'sh0000;  // should never hit
    endcase
end

endmodule