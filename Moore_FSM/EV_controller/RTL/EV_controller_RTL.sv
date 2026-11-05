`timescale 1ns/1ps
module EV_controller(
    input logic clk,
    input logic rst_n,
    input logic card_valid_i,
    input logic plug_connected_i,
    input logic temp_critical_i,
    input logic charge_complete_i,
    output logic lock_motor_o,
    output logic contactor_en_o,
    output logic [1:0] fan_speed_o,
    output logic [1:0] status_led_o
);

    typedef enum logic [2:0] {
        ST_STANDBY = 3'b000,
        ST_WAIT_FOR_PLUG = 3'b001,
        ST_LOCKING = 3'b010,
        ST_CHARGING = 3'b011,
        ST_UNLOCKING = 3'b100,
        ST_EMERGENCY = 3'b101
    } state_t;

    state_t current_s, next_s;
    logic [4:0] timer;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_s <= ST_STANDBY;
            timer <= 5'd0;
        end else begin
            current_s <= next_s;

            if (current_s == ST_WAIT_FOR_PLUG || current_s == ST_LOCKING || current_s == ST_UNLOCKING)
                timer <= timer + 1'b1;
            else
                timer <= 5'd0;
        end
    end

    always_comb begin
        next_s = current_s;

        case (current_s)
            ST_STANDBY: begin
                if (card_valid_i)
                    next_s = ST_WAIT_FOR_PLUG;
            end

            ST_WAIT_FOR_PLUG: begin
                if (plug_connected_i)
                    next_s = ST_LOCKING;
                else if (timer >= 5'd20)
                    next_s = ST_STANDBY;
            end

            ST_LOCKING: begin
                if (timer >= 5'd3)
                    next_s = ST_CHARGING;
            end

            ST_CHARGING: begin
                if (temp_critical_i || !plug_connected_i)
                    next_s = ST_EMERGENCY;
                else if (charge_complete_i)
                    next_s = ST_UNLOCKING;
            end

            ST_UNLOCKING: begin
                if (timer >= 5'd3)
                    next_s = ST_STANDBY;
            end

            ST_EMERGENCY: begin
                next_s = ST_EMERGENCY;
            end

            default: next_s = ST_STANDBY;
        endcase
    end

    always_comb begin
        lock_motor_o = 1'b0;
        contactor_en_o = 1'b0;
        fan_speed_o = 2'b00;
        status_led_o = 2'b00;

        case (current_s)
            ST_STANDBY: begin
                status_led_o = 2'b00;
            end

            ST_WAIT_FOR_PLUG: begin
                status_led_o = 2'b00;
            end

            ST_LOCKING: begin
                lock_motor_o = 1'b1;
                status_led_o = 2'b01;
            end

            ST_CHARGING: begin
                lock_motor_o = 1'b1;
                contactor_en_o = 1'b1;
                fan_speed_o = 2'b01;
                status_led_o = 2'b01;
            end

            ST_UNLOCKING: begin
                lock_motor_o = 1'b0;
                contactor_en_o = 1'b0;
                fan_speed_o = 2'b10;
                status_led_o = 2'b01;
            end

            ST_EMERGENCY: begin
                lock_motor_o = 1'b0;
                contactor_en_o = 1'b0;
                fan_speed_o = 2'b10;
                status_led_o = 2'b10;
            end
        endcase
    end

endmodule

