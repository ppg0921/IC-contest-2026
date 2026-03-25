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
        SRAM_WE = 1; // default to read
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
                SRAM_WE = 0;
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
                SRAM_WE = 0;
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


