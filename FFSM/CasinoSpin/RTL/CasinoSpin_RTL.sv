`timescale 1ns/1ps
module CasinoSpin (
    input  logic clk,
    input  logic rst_n,
    input  logic spin_i,
    output logic jackpot_won_o,
    output logic game_lost_o,
    output logic [1:0] current_level_o
);

    typedef enum logic [2:0] {
        ST_IDLE = 3'b000,
        ST_SPIN_LEVEL_1 = 3'b001,
        ST_SPIN_LEVEL_2 = 3'b010,
        ST_SPIN_LEVEL_3 = 3'b011,
        ST_WIN_RESET = 3'b100,
        ST_LOSE_RESET = 3'b101
    } casino_state_t;

    casino_state_t current_state, next_state;
    logic [7:0] lfsr_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ST_IDLE;
            lfsr_reg <= 8'hFE;
        end else begin
            current_state <= next_state;
            lfsr_reg <= {lfsr_reg[6:0], lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3]};
        end
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            ST_IDLE:
                if (spin_i) next_state = ST_SPIN_LEVEL_1;

            ST_SPIN_LEVEL_1:
                next_state = lfsr_reg[0] ? ST_SPIN_LEVEL_2 : ST_LOSE_RESET;

            ST_SPIN_LEVEL_2:
                if (spin_i)
                    next_state = lfsr_reg[0] ? ST_SPIN_LEVEL_3 : ST_LOSE_RESET;

            ST_SPIN_LEVEL_3:
                if (spin_i)
                    next_state = lfsr_reg[0] ? ST_WIN_RESET : ST_LOSE_RESET;

            ST_WIN_RESET, ST_LOSE_RESET:
                next_state = ST_IDLE;

            default:
                next_state = ST_IDLE;
        endcase
    end

    always_comb begin
        jackpot_won_o = (current_state == ST_WIN_RESET);
        game_lost_o = (current_state == ST_LOSE_RESET);
        current_level_o = 2'b00;

        case (current_state)
            ST_SPIN_LEVEL_1: current_level_o = 2'b01;
            ST_SPIN_LEVEL_2: current_level_o = 2'b10;
            ST_SPIN_LEVEL_3: current_level_o = 2'b11;
            default: ;
        endcase
    end

endmodule
