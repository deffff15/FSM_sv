`timescale 1ns/1ps
module Rock_Paper_Scissors #(
    parameter AMOUNT = 3
)(
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [AMOUNT:0] amount_of_rounds,
    input logic [1:0] r_p_s,
    output logic winner,
    output logic loser
);
    localparam logic [1:0] ROCK = 2'b01, PAPER = 2'b10, SCISSORS = 2'b11;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        PLAY = 2'b01,
        EVALUATE = 2'b10, 
        GAME_OVER = 2'b11
    } game_state_t;
    game_state_t state, next_state;

    logic [AMOUNT:0] player_score, ai_score, target_rounds;
    logic [7:0] random_reg;
    logic [1:0] ai_choice;

    always_comb begin
        case (random_reg[1:0])
            2'b10: ai_choice = PAPER;
            2'b11: ai_choice = SCISSORS;
            default: ai_choice = ROCK;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            player_score <= '0;
            ai_score <= '0;
            target_rounds <= '0;
            random_reg <= 8'hA5;
        end else begin
            state <= next_state;
            random_reg <= {random_reg[6:0], random_reg[7] ^ random_reg[5] ^ random_reg[4] ^ random_reg[3]};

            case (state)
                IDLE, GAME_OVER: begin
                    if (start) begin
                        target_rounds <= amount_of_rounds;
                        player_score <= '0;
                        ai_score <= '0;
                    end
                end
                EVALUATE: begin
                    if (r_p_s != ai_choice) begin
                        if ((r_p_s == ROCK && ai_choice == SCISSORS) || (r_p_s == PAPER && ai_choice == ROCK) || (r_p_s == SCISSORS && ai_choice == PAPER))
                            player_score <= player_score + 1'b1;
                        else if (r_p_s == ROCK || r_p_s == PAPER || r_p_s == SCISSORS)
                            ai_score <= ai_score + 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = PLAY;
            PLAY: if (start && (r_p_s == ROCK || r_p_s == PAPER || r_p_s == SCISSORS))
                next_state = EVALUATE;
            EVALUATE: begin
                if (player_score >= target_rounds || ai_score >= target_rounds)
                    next_state = GAME_OVER;
                else
                    next_state = PLAY;
            end
            GAME_OVER: if (start) next_state = PLAY;
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        winner = 1'b0;
        loser = 1'b0;
        if (state == GAME_OVER) begin
            if (player_score > ai_score)
                winner = 1'b1;
            else if (ai_score > player_score)
                loser = 1'b1;
        end
    end
endmodule
