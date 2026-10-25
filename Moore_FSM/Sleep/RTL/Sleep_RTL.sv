`timescale 1ns/1ps
module SleepSimulator(
    input  logic clk,
    input  logic rst_n,
    input  logic go_to_bed_i,
    input  logic disturbance_i,
    output logic well_rested_o,
    output logic tired_o
);

    typedef enum logic [2:0] {
        AWAKE = 3'b000,
        SLEEP_1 = 3'b001,
        SLEEP_2 = 3'b010,
        SLEEP_3 = 3'b011,
        SLEEP_4 = 3'b100,
        SLEEP_5 = 3'b101,
        WAKING_UP = 3'b110
    } state_t;

    state_t current_state, next_state;

    logic [1:0] disturbance_count;
    logic disturbance_limit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= AWAKE;
            disturbance_count <= 2'd0;
            disturbance_limit <= 1'b0;
        end else begin
            current_state <= next_state;
            if (current_state == AWAKE && go_to_bed_i) begin
                disturbance_count <= 2'd0;
                disturbance_limit <= 1'b0;
            end else if (current_state >= SLEEP_1 && current_state <= SLEEP_5) begin
                if (disturbance_i) begin
                    if (disturbance_count == 2'd2)
                        disturbance_limit <= 1'b1;
                    else
                        disturbance_count <= disturbance_count + 1'b1;
                end
            end
        end
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            AWAKE:    if (go_to_bed_i) next_state = SLEEP_1;
            SLEEP_1:  next_state = SLEEP_2;
            SLEEP_2:  next_state = SLEEP_3;
            SLEEP_3:  next_state = SLEEP_4;
            SLEEP_4:  next_state = SLEEP_5;
            SLEEP_5:  next_state = WAKING_UP;
            WAKING_UP: next_state = AWAKE;
            default:  next_state = AWAKE;
        endcase
    end

    assign well_rested_o = (current_state == WAKING_UP) && !disturbance_limit;
    assign tired_o = (current_state == WAKING_UP) && disturbance_limit;

endmodule
