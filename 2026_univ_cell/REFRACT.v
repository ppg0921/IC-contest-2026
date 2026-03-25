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
    reg [3:0] x_r, x_w, y_r, y_w;
    reg [3:0] x_buf1_r, x_buf2_r, x_buf3_r, x_buf4_r, y_buf1_r, y_buf2_r, y_buf3_r, y_buf4_r;

    reg [3:0] RI_r;
    reg done_r, done_w;

    reg input_busy_r, input_busy_w;
    reg [8:0] addr; // not real register

    wire [11:0] z_x, z_y;
    wire [11:0] LUT_out;
    wire valid;

    assign SRAM_A = addr;
    assign DONE = done_r;
    assign SRAM_WE = 1;

    assign valid = (x_r == 0) && (y_r == 0) && input_busy_w;

    LUT u_LUT (
        .i_clk(CLK), .i_rst_n(~RST), .i_valid(valid),
        .i_X(x_r),
        .i_Y(y_r),
        .i_RI(RI_r),
        .o_result(LUT_out)
    );

    always @(*) begin
        done_w = (&x_buf4_r) && (&y_buf4_r); // x_buf4_r == 15 && y_buf4_r == 15
    end

    always @(*) begin
        input_busy_w = ~input_busy_r;
        x_w = x_r;
        y_w = y_r;
        if (input_busy_r) begin
            x_w = x_r + 1;
        end
        if ((x_r == 15) && input_busy_r) begin
            y_w = y_r + 1;
        end
    end

    always @(*) begin
        if (input_busy_r) begin
            addr = {y_buf3_r, x_buf3_r, ~input_busy_r};
        end
        else begin
            addr = {y_buf4_r, x_buf4_r, ~input_busy_r};
        end
    end

    always @(*) begin
        // if (input_busy_r) begin
        //     SRAM_D = {z_x, 6'b0};
        // end
        // else begin
        //     SRAM_D = {z_y, 6'b0};
        // end
        SRAM_D = {LUT_out, 4'b0};
    end

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
        end
    end

endmodule


