`timescale 1ns/1ps
module DriveThru (
    input  logic clk,
    input  logic rst_n,
    input  logic car_arrived,
    input  logic order_confirmed,
    input  logic payment_completed,
    input  logic food_collected,
    input  logic car_departed,
    output logic speaker_on,
    output logic payment_terminal_on,
    output logic order_ready
);

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        TAKING_ORDER = 3'b001,
        WAITING_FOR_PAYMENT = 3'b010,
        WAITING_FOR_PICKUP = 3'b011,
        CANCELLING_ORDER = 3'b100
    } drive_thru_state_t;

    drive_thru_state_t current_state, next_state;

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
                if (car_arrived)
                    next_state = TAKING_ORDER;

            TAKING_ORDER:
                if (car_departed)
                    next_state = CANCELLING_ORDER;
                else if (order_confirmed)
                    next_state = WAITING_FOR_PAYMENT;

            WAITING_FOR_PAYMENT:
                if (car_departed)
                    next_state = CANCELLING_ORDER;
                else if (payment_completed)
                    next_state = WAITING_FOR_PICKUP;

            WAITING_FOR_PICKUP:
                if (food_collected)
                    next_state = IDLE;

            CANCELLING_ORDER:
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    assign speaker_on = (current_state == TAKING_ORDER);
    assign payment_terminal_on = (current_state == WAITING_FOR_PAYMENT);
    assign order_ready = (current_state == WAITING_FOR_PICKUP);

endmodule
