package CoinPackage;
    typedef enum logic [1:0] {
        ST_IDLE     = 2'b00,
        ST_SPINNING = 2'b01,
        ST_RESULT   = 2'b10
    } coin_state_t;
endpackage

import CoinPackage::*;

module CoinFlip(
    input  logic rst_n,
    input  logic clk,
    input  logic enable,
    input  logic wind,
    input  logic throw_force,
    output logic [3:0] Wy
);

    coin_state_t current_s, next_s;
    logic [1:0] pseudo_random_reg;
    logic [3:0] pos_Wy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pseudo_random_reg <= 2'b00;
            current_s <= ST_IDLE;
        end else begin
            pseudo_random_reg <= pseudo_random_reg + {wind, throw_force} + 2'b01;
            current_s <= next_s;
        end
    end

    always_comb begin
        next_s = current_s;
        pos_Wy = 4'b0000;

        case (current_s)
            ST_IDLE: begin
                pos_Wy = 4'b0001;
                if (enable)
                    next_s = ST_SPINNING;
            end

            ST_SPINNING: begin
                pos_Wy = {2'b01, pseudo_random_reg};
                if (!enable)
                    next_s = ST_RESULT;
            end

            ST_RESULT: begin
                pos_Wy = pseudo_random_reg[0] ? 4'b1110 : 4'b1111;
                if (enable)
                    next_s = ST_SPINNING;
            end

            default: begin
                next_s = ST_IDLE;
                pos_Wy = 4'b0001;
            end
        endcase
    end

    assign Wy = pos_Wy;

endmodule
