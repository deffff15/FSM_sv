`timescale 1ns/1ps
module WalkSimulator (
    input logic get_dressed,
    input logic door_opened,
    input logic keys_missing,
    output logic hall_light,
    output logic lock_release,
    output logic outside_o
);
    typedef enum logic [1:0] {
        ST_INSIDE = 2'b00,
        ST_DRESSING = 2'b01,
        ST_AT_DOOR = 2'b11,
        ST_OUTSIDE = 2'b10
    } walk_state_t;

    walk_state_t current_state;

    always_comb begin
        current_state = current_state;
        case (current_state)
            ST_INSIDE: begin
                if (get_dressed)
                    current_state = ST_DRESSING;
            end
            ST_DRESSING: begin
                if (door_opened)
                    current_state = ST_AT_DOOR;
                else if (!get_dressed)
                    current_state = ST_INSIDE;
            end
            ST_AT_DOOR: begin
                if (keys_missing)
                    current_state = ST_DRESSING;
                else if (!door_opened)
                    current_state = ST_OUTSIDE;
            end
            ST_OUTSIDE: begin
                if (!get_dressed && !door_opened)
                    current_state = ST_INSIDE;
            end
            default: current_state = ST_INSIDE;
        endcase
    end

    assign hall_light = (current_state == ST_DRESSING) || (current_state == ST_AT_DOOR);
    assign lock_release = (current_state == ST_AT_DOOR) && (!keys_missing);
    assign outside_o = (current_state == ST_OUTSIDE);
endmodule
