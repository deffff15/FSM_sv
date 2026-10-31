`timescale 1ns/1ps
module Cowboy_Shootout(
    input  logic        rst_n,
    input  logic        clk,
    input  logic        shoot_p1,
    input  logic        shoot_p2,
    output logic        shoot_signal,
    output logic [1:0]  winner
);

    typedef enum logic [1:0] {
        PREPARING = 2'b00,
        WALKING   = 2'b01,
        SHOOTING  = 2'b10,
        CHEATER   = 2'b11
    } state;

    state c_state, n_state;
    logic [15:0] counter;
    logic s1, s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_state <= PREPARING;
            counter <= 16'd0;
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            c_state <= n_state;

            if (c_state == PREPARING || c_state == WALKING || c_state == SHOOTING)
                counter <= counter + 1'b1;

            if (c_state == SHOOTING) begin
                if (shoot_p1 && !s1 && !s2)
                    s1 <= 1'b1;

                if (shoot_p2 && !s1 && !s2)
                    s2 <= 1'b1;
            end
        end
    end

    always_comb begin
        n_state = c_state;

        unique case (c_state)
            PREPARING: begin
                if (shoot_p1 || shoot_p2)
                    n_state = CHEATER;
                else if (counter >= 16'd5)
                    n_state = WALKING;
            end

            WALKING: begin
                if (shoot_p1 || shoot_p2)
                    n_state = CHEATER;
                else if (counter >= 16'd15)
                    n_state = SHOOTING;
            end

            SHOOTING: begin
                n_state = SHOOTING;
            end

            CHEATER: begin
                n_state = CHEATER;
            end

            default: n_state = PREPARING;
        endcase
    end

    always_comb begin
        winner = 2'b00;
        shoot_signal = 1'b0;

        case (c_state)
            SHOOTING: begin
                shoot_signal = 1'b1;

                if (s1)
                    winner = 2'b01;
                else if (s2)
                    winner = 2'b10;
            end

            CHEATER: begin
                if (shoot_p1)
                    winner = 2'b10;
                else if (shoot_p2)
                    winner = 2'b01;
            end

            default: ;
        endcase
    end

endmodule
