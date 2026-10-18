`timescale 1ns/1ps
module DfaDetector (
    input  logic clk,
    input  logic rst_n,
    input  logic din,
    output logic detected
);

    typedef enum logic [1:0] {
        IDLE,
        GOT_1,
        GOT_10,
        FOUND_101
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        detected = 1'b0;

        case (current_state)
            IDLE: begin
                if (din)
                    next_state = GOT_1;
            end

            GOT_1: begin
                next_state = din ? GOT_1 : GOT_10;
            end

            GOT_10: begin
                next_state = din ? FOUND_101 : IDLE;
            end

            FOUND_101: begin
                detected = 1'b1;
                next_state = din ? GOT_1 : IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule

