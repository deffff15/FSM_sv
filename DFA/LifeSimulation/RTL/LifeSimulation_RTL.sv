`timescale 1ns/1ps
module LifeSimulator(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       born_i,
    input  logic       career_focus_i,
    input  logic       health_fail_i,
    output logic [6:0] age_o,
    output logic [2:0] phase_o,
    output logic       legacy_left_o
);

    typedef enum logic [2:0] {
        NONEXISTENT = 3'b000,
        CHILDHOOD   = 3'b001,
        CAREER      = 3'b010,
        FAMILY      = 3'b011,
        RETIREMENT  = 3'b100,
        END_OF_LIFE = 3'b101
    } state_t;

    state_t state, next_state;
    logic [6:0] age;

    assign age_o = age;
    assign phase_o = state;
    assign legacy_left_o = (state == END_OF_LIFE) && (age >= 7'd65);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= NONEXISTENT;
            age   <= 7'd0;
        end else begin
            state <= next_state;
            if (state == NONEXISTENT)
                age <= 7'd0;
            else if (state != END_OF_LIFE && age < 7'd120)
                age <= age + 1'b1;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            NONEXISTENT:
                if (born_i) next_state = CHILDHOOD;

            CHILDHOOD:
                if (health_fail_i)
                    next_state = END_OF_LIFE;
                else if (age >= 7'd18)
                    next_state = career_focus_i ? CAREER : FAMILY;

            CAREER, FAMILY:
                if (health_fail_i)
                    next_state = END_OF_LIFE;
                else if (age >= 7'd65)
                    next_state = RETIREMENT;

            RETIREMENT:
                if (health_fail_i || age >= 7'd100)
                    next_state = END_OF_LIFE;

            END_OF_LIFE:
                next_state = END_OF_LIFE;

            default:
                next_state = NONEXISTENT;
        endcase
    end

endmodule
