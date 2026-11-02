`timescale 1ns/1ps
module AntColony(
    input  logic clk,
    input  logic rst_n,
    input  logic food_found_i,
    input  logic home_reached_i,
    input  logic rain_started_i,
    output logic [1:0] colony_activity_o,
    output logic pheromone_active_o
);

    localparam int ST_NEST = 0;
    localparam int ST_RETURNING = 1;
    localparam int ST_MARKING_TRAIL = 2;
    localparam int ST_PANIC = 3;

    logic [3:0] current_states, next_states;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_states <= 4'b0001;
        else
            current_states <= next_states;
    end
    always_comb begin
        next_states = 4'b0001;

        if (rain_started_i && !current_states[ST_NEST]) begin
            next_states[ST_PANIC] = 1'b1;
        end else begin
            if (current_states[ST_NEST] && food_found_i) begin
                next_states[ST_RETURNING] = 1'b1;
                next_states[ST_MARKING_TRAIL] = 1'b1;
            end

            if (current_states[ST_RETURNING] && !home_reached_i)
                next_states[ST_RETURNING] = 1'b1;

            if (current_states[ST_MARKING_TRAIL] && !home_reached_i)
                next_states[ST_MARKING_TRAIL] = 1'b1;
        end

        if (current_states[ST_PANIC] && !home_reached_i)
            next_states[ST_PANIC] = 1'b1;
    end
    always_comb begin
        pheromone_active_o = current_states[ST_MARKING_TRAIL];

        if (current_states[ST_PANIC])
            colony_activity_o = 2'b10;
        else if (current_states[ST_RETURNING] && current_states[ST_MARKING_TRAIL])
            colony_activity_o = 2'b11;
        else if (current_states[ST_RETURNING])
            colony_activity_o = 2'b01;
        else
            colony_activity_o = 2'b00;
    end
endmodule
