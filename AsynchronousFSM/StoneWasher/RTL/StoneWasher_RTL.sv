`timescale 1ns/1ps
module StoneWasher (
    input logic water_soak,
    input logic brush_active,
    input logic stone_clean,
    output logic valve_open,
    output logic scrub_motor,
    output logic ready_led
);
    typedef enum logic [1:0] {
        ST_DIRTY = 2'b00,
        ST_SOAKING = 2'b01,
        ST_SCRUB = 2'b11,
        ST_CLEAN = 2'b10
    } state_t;

    state_t current_state;

    always_comb begin
        current_state = current_state;
        case (current_state)
            ST_DIRTY: if (water_soak)
                current_state = ST_SOAKING;
            ST_SOAKING: begin
                if (brush_active)
                    current_state = ST_SCRUB;
                else if (!water_soak)
                    current_state = ST_DIRTY;
            end
            ST_SCRUB: begin
                if (stone_clean)
                    current_state = ST_CLEAN;
                else if (!brush_active)
                    current_state = ST_SOAKING;
            end
            ST_CLEAN: if (!water_soak && !brush_active && !stone_clean)
                current_state = ST_DIRTY;
            default: current_state = ST_DIRTY;
        endcase
    end

    assign valve_open = (current_state == ST_SOAKING);
    assign scrub_motor = (current_state == ST_SCRUB);
    assign ready_led = (current_state == ST_CLEAN);
endmodule
