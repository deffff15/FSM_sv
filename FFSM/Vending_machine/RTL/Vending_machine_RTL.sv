`timescale 1ns/1ps
package VendingMachinePkg;
    typedef enum logic [1:0] {
        IDLE       = 2'b00, 
        CREDIT_1   = 2'b01, 
        CREDIT_2   = 2'b10, 
        DISPENSING = 2'b11  
    } vending_state_t;
endpackage

import VendingMachinePkg::*;
module VendingMachine (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       coin_1_pln,
    input  logic       coin_2_pln,
    input  logic       cancel,
    output logic       dispense_drink,
    output logic [1:0] refund_amount
);

    vending_state_t current_s;
    vending_state_t next_s;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_s <= IDLE;
        else
            current_s <= next_s;
    end

    always_comb begin
        next_s    = current_s;
        dispense_drink = 1'b0;
        refund_amount  = 2'd0;

        case (current_s)
            IDLE: begin
                if (coin_1_pln)
                    next_s = CREDIT_1;
                else if (coin_2_pln)
                    next_s = CREDIT_2;
            end

            CREDIT_1: begin
                if (cancel) begin
                    refund_amount = 2'd1;
                    next_s = IDLE;
                end
                else if (coin_1_pln)
                    next_s = CREDIT_2;
                else if (coin_2_pln)
                    next_s = DISPENSING;
            end

            CREDIT_2: begin
                if (cancel) begin
                    refund_amount = 2'd2;
                    next_s = IDLE;
                end
                else if (coin_1_pln || coin_2_pln)
                    next_s = DISPENSING;
            end

            DISPENSING: begin
                dispense_drink = 1'b1;
                next_s = IDLE;
            end

            default: begin
                next_s = IDLE;
            end
        endcase
    end
endmodule
