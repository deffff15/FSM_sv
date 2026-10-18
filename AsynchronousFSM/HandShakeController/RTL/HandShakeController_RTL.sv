`timescale 1ns/1ps
module HandshakeController (
    input  logic rst_n,
    input  logic req,
    input  logic s_ready,
    output logic ack,
    output logic data_valid
);

    typedef enum logic [1:0] {
        IDLE,
        DATA_READY,
        WAIT_FOR_RESET
    } state_t;

    state_t current_state, next_state;

    always_latch begin
        if (!rst_n)
            current_state = IDLE;
        else if (req || s_ready || current_state == WAIT_FOR_RESET)
            current_state = next_state;
    end

    always_comb begin
        next_state = current_state;
        ack = 1'b0;
        data_valid = 1'b0;

        case (current_state)
            IDLE: begin
                if (req)
                    next_state = DATA_READY;
            end

            DATA_READY: begin
                ack = 1'b1;
                data_valid = 1'b1;

                if (s_ready)
                    next_state = WAIT_FOR_RESET;
            end

            WAIT_FOR_RESET: begin
                if (!req)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end
endmodule
