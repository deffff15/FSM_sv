`timescale 1ns/1ps
module Skydiving(
    input  logic clk,
    input  logic rst_n,
    input  logic green_light,
    input  logic altitude_ok,
    input  logic open_parachute,
    input  logic ground_near,
    output logic red_light,
    output logic in_air,
    output logic opening,
    output logic landed
);

    typedef enum logic [1:0] {
        ON_PLANE = 2'b00,
        IN_AIR = 2'b01,
        ON_GROUND = 2'b10
    } top_state_t;

    typedef enum logic [1:0] {
        FREEFALL = 2'b00,
        OPENING = 2'b01,
        DESCENT = 2'b10
    } sub_state_t;

    top_state_t top_state, top_next;
    sub_state_t sub_state, sub_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_state <= ON_PLANE;
            sub_state <= FREEFALL;
        end else begin
            top_state <= top_next;
            sub_state <= sub_next;
        end
    end

    always_comb begin
        top_next = top_state;
        sub_next = sub_state;

        case (top_state)
            ON_PLANE:
                if (green_light) begin
                    top_next = IN_AIR;
                    sub_next = FREEFALL;
                end

            IN_AIR:
                case (sub_state)
                    FREEFALL:
                        if (open_parachute || altitude_ok)
                            sub_next = OPENING;

                    OPENING:
                        sub_next = DESCENT;

                    DESCENT:
                        if (ground_near)
                            top_next = ON_GROUND;

                    default: sub_next = FREEFALL;
                endcase

            ON_GROUND:
                top_next = ON_PLANE;

            default: begin
                top_next = ON_PLANE;
                sub_next = FREEFALL;
            end
        endcase
    end

    always_comb begin
        red_light = 1'b0;
        in_air    = 1'b0;
        opening   = 1'b0;
        landed    = 1'b0;

        case (top_state)
            ON_PLANE:
                red_light = ~green_light;

            IN_AIR: begin
                in_air = 1'b1;
                opening = (sub_state == OPENING);
            end

            ON_GROUND:
                landed = 1'b1;

            default: ;
        endcase
    end

endmodule
