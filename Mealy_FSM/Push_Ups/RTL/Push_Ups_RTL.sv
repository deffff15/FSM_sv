`timescale 1ns/1ps
module Push_Ups #(
    parameter AMOUNT = 10,
    parameter MAX_HEALTH = 100
)(
    input logic clk,
    input logic rst_n,
    input logic start,
    output logic done
);
    typedef enum logic [1:0] {IDLE, EXERCISE, SUCCESS, FAILED} state_t;
    state_t state, next_state;

    localparam COUNT_W = (AMOUNT < 1) ? 1 : $clog2(AMOUNT + 1);
    localparam HEALTH_W = (MAX_HEALTH < 1) ? 1 : $clog2(MAX_HEALTH + 1);

    logic [COUNT_W-1:0] reps;
    logic [HEALTH_W-1:0] health;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            reps <= '0;
            health <= MAX_HEALTH;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    if (start) begin
                        reps <= '0;
                        health <= MAX_HEALTH;
                    end
                end
                EXERCISE: begin
                    if (health > 0) begin
                        reps <= reps + 1'b1;
                        health <= health - 1'b1;
                    end
                end
                SUCCESS, FAILED: begin
                    if (start) begin
                        reps <= '0;
                        health <= MAX_HEALTH;
                    end
                end
                default: begin
                    reps <= '0;
                    health <= MAX_HEALTH;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    if (AMOUNT == 0) next_state = SUCCESS;
                    else if (MAX_HEALTH == 0) next_state = FAILED;
                    else next_state = EXERCISE;
                end
            end
            EXERCISE: begin
                if (health == 0) next_state = FAILED;
                else if (reps + 1'b1 >= AMOUNT) next_state = SUCCESS;
            end
            SUCCESS, FAILED: begin
                if (start) begin
                    if (AMOUNT == 0) next_state = SUCCESS;
                    else if (MAX_HEALTH == 0) next_state = FAILED;
                    else next_state = EXERCISE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    assign done = (state == SUCCESS);
endmodule
