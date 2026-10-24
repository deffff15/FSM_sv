`timescale 1ns/1ps
module Quicksand #(
    parameter int MAX_STRUGGLES = 5
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start_i,
    input  logic data_in,
    output logic rescued_o,
    output logic dead_o
);

    localparam int CNT_W = (MAX_STRUGGLES > 1) ? $clog2(MAX_STRUGGLES + 1) : 1;

    typedef enum logic [1:0] {
        ST_SAFE = 2'b00,
        ST_TRAPPED = 2'b01,
        ST_RESCUED = 2'b10,
        ST_DEAD = 2'b11
    } state_t;

    state_t current_state, next_state;

    logic [CNT_W-1:0] struggle_cnt;
    logic [CNT_W-1:0] rescue_timer;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ST_SAFE;
            struggle_cnt  <= '0;
            rescue_timer  <= '0;
        end else begin
            current_state <= next_state;

            case (current_state)
                ST_SAFE, ST_RESCUED, ST_DEAD: begin
                    if (current_state == ST_SAFE && start_i ||current_state != ST_SAFE && start_i) begin
                        struggle_cnt <= '0;
                        rescue_timer <= '0;
                    end
                end

                ST_TRAPPED: begin
                    if (data_in) begin
                        if (struggle_cnt < MAX_STRUGGLES)
                        struggle_cnt <= struggle_cnt + 1'b1;
                        rescue_timer <= '0;
                    end else if (rescue_timer < MAX_STRUGGLES + 1) begin
                        rescue_timer <= rescue_timer + 1'b1;
                    end
                end

                default: begin
                    struggle_cnt <= '0;
                    rescue_timer <= '0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            ST_SAFE:
                if (start_i) next_state = ST_TRAPPED;

            ST_TRAPPED: begin
                if (data_in && struggle_cnt >= MAX_STRUGGLES - 1)
                    next_state = ST_DEAD;
                else if (!data_in && rescue_timer >= struggle_cnt)
                    next_state = ST_RESCUED;
            end

            ST_RESCUED, ST_DEAD:
                if (start_i) next_state = ST_TRAPPED;

            default:
                next_state = ST_SAFE;
        endcase
    end

    assign rescued_o = (current_state == ST_RESCUED);
    assign dead_o = (current_state == ST_DEAD);

endmodule
