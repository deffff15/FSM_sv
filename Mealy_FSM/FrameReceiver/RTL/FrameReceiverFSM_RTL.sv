`timescale 1ns/1ps
module FrameReceiverFSM (
    input  logic clk,
    input  logic rst_n,
    input  logic frame_valid,
    input  logic data_bit,
    output logic rx_done,
    output logic error_flag
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        READ_DATA = 2'b01,
        CHECK_STOP = 2'b10
    } state_t;

    state_t current_state, next_state;

    logic rx_done_next;
    logic error_flag_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            rx_done       <= 1'b0;
            error_flag    <= 1'b0;
        end else begin
            current_state <= next_state;
            rx_done       <= rx_done_next;
            error_flag    <= error_flag_next;
        end
    end

    always_comb begin
        next_state      = current_state;
        rx_done_next    = 1'b0;
        error_flag_next = 1'b0;

        unique case (current_state)
            IDLE: begin
                if (frame_valid)
                    next_state = READ_DATA;
            end

            READ_DATA: begin
                if (!frame_valid)
                    next_state = CHECK_STOP;
            end

            CHECK_STOP: begin
                if (data_bit) begin
                    rx_done_next = 1'b1;
                end else begin
                    error_flag_next = 1'b1;
                end

                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
