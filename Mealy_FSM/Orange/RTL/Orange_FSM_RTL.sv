`timescale 1ns / 1ps
package Pomarancza_pkg;
    typedef enum logic [2:0] {
        CHECK = 3'b000,
        GOOD  = 3'b001,
        SOUR  = 3'b010,
        BAD   = 3'b011
    } stan;
endpackage

import Pomarancza_pkg::*;

module Pomarancza (
    input  logic clk,
    input  logic rst_n,
    input  logic [1:0] maturity,
    input  logic [1:0] color,
    input  logic [1:0] taste,
    output logic [2:0] who_can_eat
);
    stan s_current, s_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s_current <= CHECK;
        else
            s_current <= s_next;
    end

    always_comb begin
        s_next = s_current;;
        unique case(s_current)
            CHECK: begin
                if (maturity == 2'b01 && color == 2'b01 && taste == 2'b01)
                    s_next = GOOD;
                else if (maturity == 2'b01 && color == 2'b01 && taste == 2'b00)
                    s_next = SOUR;
                else
                    s_next = BAD;
            end
            GOOD: begin
                if (maturity == 2'b01 && color == 2'b01 && taste == 2'b01)
                    s_next = GOOD;
                else
                    s_next = CHECK;
            end
            SOUR: begin
                if (maturity == 2'b01 && color == 2'b01 && taste == 2'b00)
                    s_next = SOUR;
                else
                    s_next = CHECK;
            end
            BAD: begin
                if (maturity != 2'b01 || color != 2'b01 || taste == 2'b10)
                    s_next = BAD;
                else
                    s_next = CHECK;
            end
        endcase
    end

    always_comb begin
        case (s_current)

            GOOD: who_can_eat = 3'b111;
            SOUR: who_can_eat = 3'b110;
            BAD:  who_can_eat = 3'b000;
            default: who_can_eat = 3'b000;
        endcase
    end
endmodule
