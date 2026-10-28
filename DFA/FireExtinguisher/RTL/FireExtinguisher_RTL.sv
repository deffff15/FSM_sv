`timescale 1ns/1ps
module FireExtinguisher (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       pin_pulled_i,
    input  logic       aimed_at_base_i,
    input  logic       lever_squeezed_i,
    input  logic       fire_out_of_control_i,
    input  logic       extinguisher_empty_i,
    output logic [2:0] status_o,
    output logic       evacuate_alarm_o
);

    typedef enum logic [2:0] {
        ST_IDLE          = 3'b000,
        ST_READY         = 3'b001,
        ST_AIMED         = 3'b010,
        ST_EXTINGUISHING = 3'b011,
        ST_SUCCESS       = 3'b100,
        ST_EVACUATE      = 3'b101
    } fire_state_t;

    fire_state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= ST_IDLE;
        else current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        if (fire_out_of_control_i && current_state != ST_SUCCESS) begin
            next_state = ST_EVACUATE;
        end else begin
            case (current_state)
                ST_IDLE: begin
                    if (pin_pulled_i) next_state = ST_READY;
                end

                ST_READY: begin
                    if (aimed_at_base_i) next_state = ST_AIMED;
                end

                ST_AIMED: begin
                    if (lever_squeezed_i) next_state = ST_EXTINGUISHING;
                    else if (!aimed_at_base_i) next_state = ST_READY;
                end

                ST_EXTINGUISHING: begin
                    if (extinguisher_empty_i) next_state = ST_EVACUATE;
                    else if (!lever_squeezed_i) next_state = ST_AIMED;
                    else if (!fire_out_of_control_i && !extinguisher_empty_i)
                        next_state = ST_SUCCESS;
                end

                ST_SUCCESS, ST_EVACUATE: next_state = current_state;
                default: next_state = ST_IDLE;
            endcase
        end
    end

    assign status_o = current_state;
    assign evacuate_alarm_o = (current_state == ST_EVACUATE);

endmodule
