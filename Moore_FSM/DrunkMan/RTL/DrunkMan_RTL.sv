`timescale 1ns/1ps
package DrunkPackage;
    typedef enum logic [1:0] {
        ST_SOBER  = 2'b00,
        ST_TIPSY  = 2'b01,
        ST_DRUNK  = 2'b10,
        ST_WASTED = 2'b11
    } drunk_state_t;
endpackage

import DrunkPackage::*;

module DrunkMan #(
    parameter int unsigned amount = 10
)(
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    input  logic [amount-1:0] How_drunk,
    output logic [amount-1:0] promile,
    output logic [1:0] behavior
);

    drunk_state_t current_s, next_s;
    logic [amount-1:0] internal_alcohol_reg;
    localparam logic [amount-1:0] PROG_TIPSY  = 2**(amount-2);
    localparam logic [amount-1:0] PROG_DRUNK  = 2**(amount-1);
    localparam logic [amount-1:0] PROG_WASTED = PROG_DRUNK + PROG_TIPSY;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_s <= ST_SOBER;
            internal_alcohol_reg <= '0;
        end else if (enable) begin
            current_s <= next_s;
            internal_alcohol_reg <= How_drunk;
        end
    end

    always_comb begin
        if (internal_alcohol_reg < PROG_TIPSY)
            next_s = ST_SOBER;
        else if (internal_alcohol_reg < PROG_DRUNK)
            next_s = ST_TIPSY;
        else if (internal_alcohol_reg < PROG_WASTED)
            next_s = ST_DRUNK;
        else
            next_s = ST_WASTED;
    end

    always_comb begin
        case (current_s)
            ST_SOBER:  behavior = 2'b00;
            ST_TIPSY:  behavior = 2'b01;
            ST_DRUNK:  behavior = 2'b10;
            ST_WASTED: behavior = 2'b11;
            default:   behavior = 2'b00;
        endcase
    end

    assign promile = internal_alcohol_reg;

endmodule
