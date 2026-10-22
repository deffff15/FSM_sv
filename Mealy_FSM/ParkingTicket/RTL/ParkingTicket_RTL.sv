`timescale 1ns/1ps
module ParkingTicket(
    input logic clk,
    input logic rst_n,
    input logic entered_parking,
    input logic left_parking,
    output logic [3:0] payed,
    output logic [7:0] time_parked
);
    typedef enum logic {
        EMPTY = 1'b0,
        PARKED = 1'b1
    } parking_state_t;

    parking_state_t state, next_state;
    logic [7:0] parked_time;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= EMPTY;
            parked_time <= 8'd0;
        end else begin
            state <= next_state;
            if (state == PARKED && !left_parking) begin
                if (parked_time < 8'hFF)
                    parked_time <= parked_time + 1'b1;
            end else if (entered_parking) begin
                parked_time <= 8'd0;
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            EMPTY: if (entered_parking) next_state = PARKED;
            PARKED: if (left_parking) next_state = EMPTY;
            default: next_state = EMPTY;
        endcase
    end

    always_comb begin
        payed = 4'd0;
        time_parked = 8'd0;
        if (state == PARKED && left_parking) begin
            time_parked = parked_time;
            if (parked_time > 8'd15)
                payed = 4'd15;
            else
                payed = parked_time[3:0];
        end
    end
endmodule
