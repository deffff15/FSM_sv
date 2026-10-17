`timescale 1ns/1ps
package PhonePackage;
    typedef enum logic [1:0] {POWERED_OFF=2'b00, LOCKED=2'b01, UNLOCKED=2'b10} super_state_t;
    typedef enum logic {DEEP_SLEEP=1'b0, AOD=1'b1} locked_state_t;
    typedef enum logic {HOME=1'b0, GAME=1'b1} unlocked_state_t;
endpackage

import PhonePackage::*;
module SmartPhoneFSM(
    input logic clk, rst_n,
    input logic battery_critical,
    input logic power_button,
    input logic unlock_success,
    input logic launch_game,
    input logic exit_to_menu,
    output logic screen_on, gpu_high_power, phone_off
);

    super_state_t current_super, next_super;
    locked_state_t current_locked, next_locked;
    unlocked_state_t current_unlocked, next_unlocked;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_super <= LOCKED;
            current_locked <= DEEP_SLEEP;
            current_unlocked <= HOME;
        end else begin
            current_super <= next_super;
            current_locked <= next_locked;
            current_unlocked <= next_unlocked;
        end
    end

    always_comb begin
        next_super = current_super;
        next_locked = current_locked;
        next_unlocked = current_unlocked;
        screen_on = 1'b0;
        gpu_high_power = 1'b0;
        phone_off = 1'b0;

        if (battery_critical) begin
            next_super = POWERED_OFF;
            phone_off = 1'b1;
        end else begin
            case (current_super)
                POWERED_OFF: begin
                    phone_off = 1'b1;
                    if (power_button) begin
                        next_super = LOCKED;
                        next_locked = AOD;
                    end
                end

                LOCKED: begin
                    screen_on = (current_locked == AOD);
                    if (unlock_success) begin
                        next_super = UNLOCKED;
                        next_unlocked = HOME;
                    end else if (power_button) begin
                        next_locked = (current_locked == AOD) ? DEEP_SLEEP : AOD;
                    end
                end

                UNLOCKED: begin
                    screen_on = 1'b1;
                    if (power_button) begin
                        next_super = LOCKED;
                        next_locked = AOD;
                    end else begin
                        case (current_unlocked)
                            HOME: if (launch_game) next_unlocked = GAME;
                            GAME: begin
                                gpu_high_power = 1'b1;
                                if (exit_to_menu) next_unlocked = HOME;
                            end
                            default: next_unlocked = HOME;
                        endcase
                    end
                end

                default: begin
                    next_super = POWERED_OFF;
                    phone_off = 1'b1;
                end
            endcase
        end
    end
endmodule
