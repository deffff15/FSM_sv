`timescale 1ns/1ps
module BytePatternDetector(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data_i,
    output logic       pattern_found_o
);

    localparam int IDLE    = 0;
    localparam int GOT_AA  = 1;
    localparam int GOT_BB  = 2;
    localparam int MATCH   = 3;

    logic [3:0] current_states, next_states;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_states <= 4'b0001;
        else
            current_states <= next_states;
    end

    always_comb begin
        next_states = 4'b0001;

        if (current_states[IDLE] && data_i == 8'hAA)
            next_states[GOT_AA] = 1'b1;

        if (current_states[GOT_AA] && data_i == 8'hBB)
            next_states[GOT_BB] = 1'b1;

        if (current_states[GOT_BB] && (data_i == 8'hCC || data_i == 8'hDD))
            next_states[MATCH] = 1'b1;

        if (current_states[MATCH])
            next_states[MATCH] = 1'b0;
    end

    assign pattern_found_o = current_states[MATCH];

endmodule
