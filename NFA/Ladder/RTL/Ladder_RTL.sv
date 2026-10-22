`timescale 1ns/1ps
module ladder (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic step_up,
    input logic broken_rung,
    output logic success
);
    typedef enum logic [3:0] {
        GROUND = 4'b0001,
        RUNG_1 = 4'b0010,
        RUNG_2 = 4'b0100,
        TOP = 4'b1000
    } rung_state_t;

    logic [3:0] state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= GROUND;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        if (start) next_state = GROUND;
        else if (step_up) begin
            next_state = 4'b0000;
            if (state & GROUND) next_state |= RUNG_1;
            if (state & RUNG_1) next_state |= RUNG_2;
            if (state & RUNG_2) begin
                next_state |= TOP;
                if (broken_rung) next_state |= GROUND;
            end
            if (state & TOP) next_state |= TOP;
        end
    end

    assign success = |(state & TOP);
endmodule

