`timescale 1ns/1ps
module NfaDetector (
    input  logic clk,
    input  logic rst_n,
    input  logic din,
    output logic matched
);

    logic [2:0] active_states, next_states;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            active_states <= 3'b001;
        else
            active_states <= next_states;
    end

    always_comb begin
        next_states = 3'b001;

        if (active_states[0] && !din)
            next_states[1] = 1'b1;

        if (active_states[1] && din)
            next_states[2] = 1'b1;

        matched = active_states[2];
    end

endmodule
