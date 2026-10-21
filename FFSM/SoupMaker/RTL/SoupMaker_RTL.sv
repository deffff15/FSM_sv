`timescale 1ns/1ps
module SoupMaker (
    input  logic clk,
    input  logic rst_n,
    input  logic start_cooking,
    input  logic water_boiling,
    input  logic cooking_done,
    output logic heater_on,
    output logic add_ingredients,
    output logic soup_ready
);

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        HEATING = 3'b001,
        ADDING_INGREDIENTS = 3'b010,
        COOKING = 3'b011,
        READY = 3'b100
    } soup_state_t;

    soup_state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE:
                if (start_cooking)
                    next_state = HEATING;

            HEATING:
                if (water_boiling)
                    next_state = ADDING_INGREDIENTS;

            ADDING_INGREDIENTS:
                next_state = COOKING;

            COOKING:
                if (cooking_done)
                    next_state = READY;

            READY:
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    assign heater_on = (current_state == HEATING) || (current_state == COOKING);
    assign add_ingredients = (current_state == ADDING_INGREDIENTS);
    assign soup_ready = (current_state == READY);

endmodule
