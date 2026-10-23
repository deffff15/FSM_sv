`timescale 1ns/1ps
module Deportation (
    input  logic clk,
    input  logic rst_n,
    input  logic next_in_line_i,
    input  logic submit_passport_i,
    output logic stay_approved_o,
    output logic deported_o,
    output logic busy_o
);

    typedef enum logic [1:0] {
        ST_WAIT_FOR_PERSON = 2'b00,
        ST_WAIT_FOR_DOC = 2'b01,
        ST_LOTTERY_DRAW = 2'b10,
        ST_DECISION_OUT = 2'b11
    } office_state_t;

    office_state_t current_state, next_state;

    logic [7:0] a_reg;
    logic decision_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ST_WAIT_FOR_PERSON;
            a_reg <= 8'h5A;
            decision_reg <= 1'b0;
        end else begin
            current_state <= next_state;

            a_reg <= {
                a_reg[6:0], a_reg[7] ^ a_reg[5] ^ a_reg[4] ^ a_reg[3]
            };

            if (current_state == ST_LOTTERY_DRAW)
                decision_reg <= a_reg[0];
        end
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            ST_WAIT_FOR_PERSON:
                if (next_in_line_i)
                    next_state = ST_WAIT_FOR_DOC;

            ST_WAIT_FOR_DOC:
                if (submit_passport_i)
                    next_state = ST_LOTTERY_DRAW;

            ST_LOTTERY_DRAW:
                next_state = ST_DECISION_OUT;

            ST_DECISION_OUT:
                next_state = ST_WAIT_FOR_PERSON;

            default:
                next_state = ST_WAIT_FOR_PERSON;
        endcase
    end

    always_comb begin
        stay_approved_o = 1'b0;
        deported_o      = 1'b0;
        busy_o          = 1'b0;

        case (current_state)
            ST_WAIT_FOR_DOC, ST_LOTTERY_DRAW:
                busy_o = 1'b1;

            ST_DECISION_OUT: begin
                stay_approved_o = decision_reg;
                deported_o = !decision_reg;
            end

            default: ;
        endcase
    end

endmodule
