`timescale 1ns/1ps
package Driving;
    typedef enum logic [1:0] {
        ROAD_1 = 2'b00,
        ROAD_2 = 2'b01,
        ROAD_3 = 2'b10,
        ROAD_4 = 2'b11
    } state;
endpackage

import Driving::*;

module Road (
    input  logic clk,
    input  logic rst_n,
    output logic Wy
);

    state current_s, next_s;
    logic [4:0] timer;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_s <= ROAD_1;
            timer     <= 5'd0;
        end else begin
            current_s <= next_s;
            if (current_s != next_s) begin
                timer <= 5'd0;
            end else if (timer != 5'd31) begin
                timer <= timer + 1'b1;
            end
        end
    end

    always_comb begin
        next_s = current_s;
        Wy = 1'b0;
        unique case (current_s)
            ROAD_1: begin
                if (timer[1])
                    next_s = ROAD_2;
            end
            ROAD_2: begin
                if (timer[2])
                    next_s = ROAD_3;
            end
            ROAD_3: begin
                if (timer[3])
                    next_s = ROAD_4;
            end
            ROAD_4: begin
                if (timer[4])
                    Wy = 1'b1;
            end
            default: begin
                next_s = ROAD_1;
            end
        endcase
    end
endmodule
