`timescale 1ns/1ps
module DebounceEliminator (
    input  logic clk,
    input  logic rst_n,
    input  logic btn_in,
    output logic btn_out
);

    typedef enum logic [1:0] {
        LOW,
        FILTER_HIGH,
        HIGH,
        FILTER_LOW
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= LOW;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            LOW:
                next_state = btn_in ? FILTER_HIGH : LOW;

            FILTER_HIGH:
                next_state = btn_in ? HIGH : LOW;

            HIGH:
                next_state = btn_in ? HIGH : FILTER_LOW;

            FILTER_LOW:
                next_state = btn_in ? HIGH : LOW;

            default:
                next_state = LOW;
        endcase
    end

    assign btn_out = (current_state == HIGH || current_state == FILTER_LOW);

endmodule
