`timescale 1ns/1ps
package Sumo_pkg;
    typedef enum logic [1:0] {
        START,
        FIGHT,
        STOP
    } main_state_t;

    typedef enum logic [1:0] {
        SEARCH,
        ATTACK,
        EVADE
    } fight_state_t;
endpackage

import Sumo_pkg::*;
module SumoFighter (
    input  logic clk,
    input  logic rst_n,
    input  logic start_cmd,
    input  logic stop_cmd,
    input  logic opponent_seen,
    input  logic edge_seen,
    output Sumo_pkg::main_state_t main_state,
    output Sumo_pkg::fight_state_t fight_state,
    output logic [1:0] left_motor,
    output logic [1:0] right_motor
);

    main_state_t main_reg, main_next;
    fight_state_t fight_reg, fight_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            main_reg <= START;
        else
            main_reg <= main_next;
    end

    always_comb begin
        main_next = main_reg;

        case (main_reg)
            START: begin
                if (start_cmd)
                    main_next = FIGHT;
            end

            FIGHT: begin
                if (stop_cmd)
                    main_next = STOP;
            end

            STOP: begin
                if (start_cmd)
                    main_next = FIGHT;
            end

            default: main_next = START;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fight_reg <= SEARCH;
        else if (main_reg != FIGHT)
            fight_reg <= SEARCH;
        else
            fight_reg <= fight_next;
    end

    always_comb begin
        fight_next = fight_reg;

        if (main_reg == FIGHT) begin
            case (fight_reg)
                SEARCH: begin
                    if (edge_seen)
                        fight_next = EVADE;
                    else if (opponent_seen)
                        fight_next = ATTACK;
                end

                ATTACK: begin
                    if (edge_seen)
                        fight_next = EVADE;
                    else if (!opponent_seen)
                        fight_next = SEARCH;
                end

                EVADE: begin
                    if (!edge_seen)
                        fight_next = SEARCH;
                end

                default: fight_next = SEARCH;
            endcase
        end
    end

    always_comb begin
        left_motor  = 2'b00;
        right_motor = 2'b00;

        if (main_reg == FIGHT) begin
            case (fight_reg)
                SEARCH: begin
                    left_motor  = 2'b01;
                    right_motor = 2'b10;
                end

                ATTACK: begin
                    left_motor  = 2'b01;
                    right_motor = 2'b01;
                end

                EVADE: begin
                    left_motor  = 2'b10;
                    right_motor = 2'b10;
                end

                default: begin
                    left_motor  = 2'b00;
                    right_motor = 2'b00;
                end
            endcase
        end
    end
    assign main_state  = main_reg;
    assign fight_state = (main_reg == FIGHT) ? fight_reg : SEARCH;
endmodule
