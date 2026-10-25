`timescale 1ns/1ps
module AsyncSafetyInterlock(
    input  logic emergency_btn,
    input  logic light_curtain,
    output logic clutch_engage
);

    typedef enum logic [1:0] {
        SAFE_RUN = 2'b00,
        E_STOP   = 2'b01,
        CURTAIN  = 2'b11
    } state_t;

    state_t current_state, next_state;

    always_comb begin
        next_state = current_state;

        case (current_state)
            SAFE_RUN: begin
                if (!emergency_btn)
                    next_state = E_STOP;
                else if (!light_curtain)
                    next_state = CURTAIN;
            end

            E_STOP:
                if (emergency_btn && light_curtain)
                    next_state = SAFE_RUN;

            CURTAIN: begin
                if (!emergency_btn)
                    next_state = E_STOP;
                else if (light_curtain)
                    next_state = SAFE_RUN;
            end

            default:
                next_state = E_STOP;
        endcase
    end

    always_comb
        current_state = next_state;

    assign clutch_engage = (current_state == SAFE_RUN);

endmodule
