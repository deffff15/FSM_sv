`timescale 1ns/1ps
module SmartCoop(
    input logic clk,
    input logic rst_n,
    input logic sunrise_i,
    input logic sunset_i,
    input logic limit_switch_i,
    output logic motor_up_o,
    output logic motor_down_o,
    output logic secure_led_o
);

typedef enum logic [1:0] {
    ST_CLOSED = 2'b00,
    ST_OPENING = 2'b01,
    ST_OPEN = 2'b10,
    ST_CLOSING = 2'b11
} state_t;

state_t c_state, n_state;

always_ff@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        c_state <= ST_CLOSED;
    end
    else
    begin
        c_state <= n_state;
    end
end

always_comb
begin
    n_state = c_state;
    motor_up_o = 1'b0;
    motor_down_o = 1'b0;
    secure_led_o = 1'b0;
    unique case(c_state)
    ST_CLOSED : begin
        secure_led_o = 1'b1;
        if(sunrise_i)
        begin
            n_state = ST_OPENING;
        end
    end
    ST_OPENING : begin
        motor_up_o = 1'b1;
        if(limit_switch_i)
        begin
            n_state = ST_OPEN;
        end
    end
    ST_OPEN : begin
        if(sunset_i)
        begin
            n_state = ST_CLOSING;
        end
    end
    ST_CLOSING : begin
        motor_down_o = 1'b1;
        if(limit_switch_i)
        begin
            n_state = ST_CLOSED;
        end
    end
    endcase
end
endmodule
