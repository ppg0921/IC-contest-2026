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