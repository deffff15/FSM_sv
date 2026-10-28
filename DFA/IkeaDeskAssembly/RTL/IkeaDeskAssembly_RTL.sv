`timescale 1ns/1ps
module IkeaDeskAssembly (
    input  logic clk,
    input  logic rst_n,
    input  logic unboxed_i,
    input  logic legs_assembled_i,
    input  logic missing_parts_i,
    input  logic top_mounted_i,
    output logic desk_ready_o,
    output logic rage_o
);

    typedef enum logic [2:0] {
        ST_BOXED         = 3'b000,
        ST_READ_MANUAL   = 3'b001,
        ST_ASSEMBLE_LEGS = 3'b010,
        ST_MOUNT_TOP     = 3'b011,
        ST_PARTS_CRISIS  = 3'b100,
        ST_FINISHED      = 3'b101
    } ikea_state_t;

    ikea_state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= ST_BOXED;
        else current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            ST_BOXED:
                if (unboxed_i) next_state = ST_READ_MANUAL;

            ST_READ_MANUAL:
                next_state = ST_ASSEMBLE_LEGS;

            ST_ASSEMBLE_LEGS: begin
                if (missing_parts_i) next_state = ST_PARTS_CRISIS;
                else if (legs_assembled_i) next_state = ST_MOUNT_TOP;
            end

            ST_MOUNT_TOP: begin
                if (missing_parts_i) next_state = ST_PARTS_CRISIS;
                else if (top_mounted_i) next_state = ST_FINISHED;
            end

            ST_PARTS_CRISIS:
                if (!missing_parts_i) next_state = ST_ASSEMBLE_LEGS;

            ST_FINISHED:
                next_state = ST_FINISHED;

            default:
                next_state = ST_BOXED;
        endcase
    end

    assign desk_ready_o = (current_state == ST_FINISHED);
    assign rage_o = (current_state == ST_PARTS_CRISIS);

endmodule
