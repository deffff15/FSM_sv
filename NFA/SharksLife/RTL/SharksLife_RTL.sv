`timescale 1ns/1ps
module SharksLife (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       blood_detected_i,
    input  logic       prey_caught_i,
    input  logic       orca_attack_i,
    input  logic       healed_i,
    output logic [1:0] shark_status_o,
    output logic       danger_alert_o
);

    localparam int ST_SWIMMING    = 0;
    localparam int ST_HUNTING     = 1;
    localparam int ST_EVAL_DANGER = 2;
    localparam int ST_INJURED     = 3;

    logic [3:0] current_states, next_states;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_states <= 4'b0001;
        else
            current_states <= next_states;
    end

    always_comb begin
        next_states = 4'b0001;

        if (current_states[ST_SWIMMING]) begin
            if (blood_detected_i) begin
                next_states[ST_HUNTING]     = 1'b1;
                next_states[ST_EVAL_DANGER] = 1'b1;
            end
            if (orca_attack_i)
                next_states[ST_INJURED] = 1'b1;
        end

        if (current_states[ST_HUNTING]) begin
            if (orca_attack_i)
                next_states[ST_INJURED] = 1'b1;
            else if (!prey_caught_i)
                next_states[ST_HUNTING] = 1'b1;
        end

        if (current_states[ST_EVAL_DANGER]) begin
            if (orca_attack_i)
                next_states[ST_INJURED] = 1'b1;
            else if (!prey_caught_i)
                next_states[ST_EVAL_DANGER] = 1'b1;
        end

        if (current_states[ST_INJURED] && !healed_i)
            next_states[ST_INJURED] = 1'b1;
    end

    always_comb begin
        shark_status_o = 2'b00;
        danger_alert_o = 1'b0;

        if (current_states[ST_EVAL_DANGER] || current_states[ST_INJURED])
            danger_alert_o = 1'b1;

        if (current_states[ST_HUNTING] && current_states[ST_EVAL_DANGER])
            shark_status_o = 2'b11;
        else if (current_states[ST_INJURED])
            shark_status_o = 2'b10;
        else if (current_states[ST_HUNTING])
            shark_status_o = 2'b01;
    end

endmodule
