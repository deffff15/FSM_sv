`timescale 1ns/1ps
package Destroyer;
    typedef enum logic [2:0] {
        LAYER_1   = 3'b000,
        LAYER_2   = 3'b001,
        LAYER_3   = 3'b010,
        LAYER_4   = 3'b011,
        DESTROYED = 3'b100
    } layers;
endpackage

import Destroyer::*;
module Wall #(
    parameter THICKNESS = 5
)(
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    output logic Destroyed
);

    logic [THICKNESS-1:0] wall_s, next_wall_s;
    layers current_l, next_l;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_l <= LAYER_1;
            wall_s    <= '0;
        end
        else if (enable) begin
            current_l <= next_l;
            wall_s    <= next_wall_s;
        end
    end

    always_comb begin
        next_l      = current_l;
        next_wall_s = wall_s;
        case (current_l)

            LAYER_1: begin
                next_l = LAYER_2;
            end

            LAYER_2: begin
                next_l = LAYER_3;
            end

            LAYER_3: begin
                next_l = LAYER_4;
            end

            LAYER_4: begin
                if (wall_s[THICKNESS-1]) begin
                    next_l = DESTROYED;
                end
                else begin
                    next_wall_s = {wall_s[THICKNESS-2:0], 1'b1};
                    next_l      = LAYER_1;
                end
            end

            DESTROYED: begin
                next_l      = DESTROYED;
                next_wall_s = wall_s;
            end

            default: begin
                next_l      = LAYER_1;
                next_wall_s = '0;
            end
        endcase
    end
    always_comb begin
        Destroyed = (current_l == DESTROYED);
    end
endmodule
