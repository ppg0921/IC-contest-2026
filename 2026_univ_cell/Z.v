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