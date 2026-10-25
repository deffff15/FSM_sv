`timescale 1ns/1ps
module NeighborSimulator(
    input  logic clk,
    input  logic rst_n,
    input  logic start_mowing_i,
    input  logic neighbor_noticed_i,
    output logic shouting_o,
    output logic police_o,
    output logic fight_o,
    output logic grass_mowed_o
);

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        MOWING_1 = 3'b001,
        MOWING_2 = 3'b010,
        MOWING_3 = 3'b011,
        SHOUTING = 3'b100,
        POLICE = 3'b101,
        FIGHT = 3'b110,
        SUCCESS = 3'b111
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE:
                if (start_mowing_i)
                    next_state = MOWING_1;

            MOWING_1:
                next_state = neighbor_noticed_i ? SHOUTING : MOWING_2;

            MOWING_2:
                next_state = neighbor_noticed_i ? POLICE : MOWING_3;

            MOWING_3:
                next_state = neighbor_noticed_i ? FIGHT : SUCCESS;

            SHOUTING, POLICE, FIGHT, SUCCESS:
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    assign shouting_o   = (current_state == SHOUTING);
    assign police_o     = (current_state == POLICE);
    assign fight_o      = (current_state == FIGHT);
    assign grass_mowed_o = (current_state == SUCCESS);

endmodule
