`timescale 1ns/1ps

package Fighter_paczka;
    typedef enum logic [1:0] {
        START  = 2'b00,
        FIGHT  = 2'b01,
        FINISH = 2'b10
    } stany;

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        ATTACK  = 2'b01,
        DEFENSE = 2'b10
    } akcje;
endpackage

module Fighter #(
    parameter logic [3:0] MAX_HP = 4'd10,
    parameter logic [3:0] DAMAGE = 4'd1
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    input  logic       finish,
    input  logic [1:0] player1_attack_defense,
    input  logic [1:0] player2_attack_defense,
    output logic [3:0] player1_hp,
    output logic [3:0] player2_hp,
    output logic [1:0] Wy_winner
);
    import Fighter_paczka::*;

    localparam int ATK_BIT = 1;
    localparam int DEF_BIT = 0;
    localparam logic [1:0] NO_WINNER = 2'b00;
    localparam logic [1:0] P1_WINS   = 2'b01;
    localparam logic [1:0] P2_WINS   = 2'b10;
    localparam logic [1:0] DRAW      = 2'b11;

    stany current_s, next_s;
    akcje player1_action, player2_action;
    logic [1:0] player1_prev, player2_prev;
    logic p1_attack_rise, p1_defense_rise;
    logic p2_attack_rise, p2_defense_rise;
    logic player1_attack_event, player2_attack_event;
    logic player1_defending, player2_defending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_s <= START;
        else
            current_s <= next_s;
    end

    always_comb begin
        next_s = current_s;

        case (current_s)
            START: if (start) next_s = FIGHT;
            FIGHT: if (finish || player1_hp == 0 || player2_hp == 0)
                       next_s = FINISH;
            FINISH: next_s = FINISH;
            default: next_s = START;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            player1_prev <= 2'b00;
            player2_prev <= 2'b00;
        end
        else if (current_s != FIGHT || finish ||
                 player1_hp == 0 || player2_hp == 0) begin
            player1_prev <= 2'b00;
            player2_prev <= 2'b00;
        end
        else begin
            player1_prev <= player1_attack_defense;
            player2_prev <= player2_attack_defense;
        end
    end

    assign p1_attack_rise  = player1_attack_defense[ATK_BIT] & ~player1_prev[ATK_BIT];
    assign p1_defense_rise = player1_attack_defense[DEF_BIT] & ~player1_prev[DEF_BIT];
    assign p2_attack_rise  = player2_attack_defense[ATK_BIT] & ~player2_prev[ATK_BIT];
    assign p2_defense_rise = player2_attack_defense[DEF_BIT] & ~player2_prev[DEF_BIT];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            player1_action <= IDLE;
            player2_action <= IDLE;
        end
        else if (current_s != FIGHT || finish ||
                 player1_hp == 0 || player2_hp == 0) begin
            player1_action <= IDLE;
            player2_action <= IDLE;
        end
        else begin
            if (player1_attack_defense == 2'b00)
                player1_action <= IDLE;
            else if (player1_action == IDLE) begin
                if (p1_attack_rise)
                    player1_action <= ATTACK;
                else if (p1_defense_rise)
                    player1_action <= DEFENSE;
            end

            if (player2_attack_defense == 2'b00)
                player2_action <= IDLE;
            else if (player2_action == IDLE) begin
                if (p2_attack_rise)
                    player2_action <= ATTACK;
                else if (p2_defense_rise)
                    player2_action <= DEFENSE;
            end
        end
    end

    assign player1_attack_event = (current_s == FIGHT) && !finish &&
                                 (player1_hp != 0) && (player2_hp != 0) &&
                                 (player1_action == IDLE) && p1_attack_rise;
    assign player2_attack_event = (current_s == FIGHT) && !finish &&
                                 (player1_hp != 0) && (player2_hp != 0) &&
                                 (player2_action == IDLE) && p2_attack_rise;

    assign player1_defending = (player1_action == DEFENSE) ||
                               ((player1_action == IDLE) && p1_defense_rise &&
                                !p1_attack_rise);
    assign player2_defending = (player2_action == DEFENSE) ||
                               ((player2_action == IDLE) && p2_defense_rise &&
                                !p2_attack_rise);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            player1_hp <= MAX_HP;
            player2_hp <= MAX_HP;
        end
        else if (current_s == START) begin
            player1_hp <= MAX_HP;
            player2_hp <= MAX_HP;
        end
        else if (current_s == FIGHT && !finish &&
                 player1_hp != 0 && player2_hp != 0) begin
            if (player1_attack_event && !player2_defending) begin
                if (player2_hp <= DAMAGE)
                    player2_hp <= 4'd0;
                else
                    player2_hp <= player2_hp - DAMAGE;
            end

            if (player2_attack_event && !player1_defending) begin
                if (player1_hp <= DAMAGE)
                    player1_hp <= 4'd0;
                else
                    player1_hp <= player1_hp - DAMAGE;
            end
        end
    end

    always_comb begin
        Wy_winner = NO_WINNER;

        if (current_s == FINISH) begin
            if (player1_hp > player2_hp)
                Wy_winner = P1_WINS;
            else if (player2_hp > player1_hp)
                Wy_winner = P2_WINS;
            else
                Wy_winner = DRAW;
        end
    end
endmodule
