`timescale 1ns/1ps
module Border (
    input  logic clk,
    input  logic rst_n,
    input  logic passenger_arrived_i,
    input  logic has_passport_i,
    input  logic has_contraband_i,
    input  logic has_weapons_i,
    output logic allow_entry_o,
    output logic deny_entry_o,
    output logic arrest_o
);

    typedef enum logic [2:0] {
        ST_IDLE = 3'b000,
        ST_CHECK_PASSPORT = 3'b001,
        ST_SCAN_BAGGAGE = 3'b010,
        ST_APPROVED = 3'b011,
        ST_DENIED = 3'b100,
        ST_ARRESTED = 3'b101
    } border_state_t;

    border_state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= ST_IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            ST_IDLE:
                if (passenger_arrived_i)
                    next_state = ST_CHECK_PASSPORT;

            ST_CHECK_PASSPORT:
                if (has_weapons_i)
                    next_state = ST_ARRESTED;
                else if (!has_passport_i)
                    next_state = ST_DENIED;
                else
                    next_state = ST_SCAN_BAGGAGE;

            ST_SCAN_BAGGAGE:
                if (has_weapons_i || has_contraband_i)
                    next_state = ST_ARRESTED;
                else
                    next_state = ST_APPROVED;

            ST_APPROVED, ST_DENIED, ST_ARRESTED:
                next_state = ST_IDLE;

            default:
                next_state = ST_IDLE;
        endcase
    end

    always_comb begin
        allow_entry_o = (current_state == ST_APPROVED);
        deny_entry_o  = (current_state == ST_DENIED);
        arrest_o      = (current_state == ST_ARRESTED);
    end

endmodule
