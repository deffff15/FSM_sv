`timescale 1ns/1ps
module SmartShower(
    input  logic clk,
    input  logic rst_n,
    input  logic start_shower_i,
    input  logic temp_ok_i,
    input  logic soaped_up_i,
    input  logic scald_protection_i,
    output logic valve_open_o,
    output logic soap_dispenser_o,
    output logic air_dryer_o,
    output logic alarm_led_o
);

    typedef enum logic [2:0] {
        OFF = 3'b000,
        HEATING = 3'b001,
        BATHING = 3'b010,
        DRYING = 3'b011,
        EMERGENCY = 3'b100
    } top_state_t;

    typedef enum logic [1:0] {
        RINSING = 2'b00,
        SOAPING = 2'b01,
        FINAL_RINSE = 2'b10
    } sub_state_t;

    top_state_t top_state, top_next;
    sub_state_t sub_state, sub_next;
    logic [1:0] dryer_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_state   <= OFF;
            sub_state   <= RINSING;
            dryer_count <= '0;
        end else begin
            top_state <= top_next;
            sub_state <= sub_next;

            if (top_state == DRYING)
                dryer_count <= dryer_count + 1'b1;
            else
                dryer_count <= '0;
        end
    end

    always_comb begin
        top_next = top_state;
        sub_next = sub_state;

        if (scald_protection_i && top_state != OFF)
            top_next = EMERGENCY;
        else begin
            case (top_state)
                OFF:
                    if (start_shower_i)
                        top_next = HEATING;

                HEATING:
                    if (temp_ok_i) begin
                        top_next = BATHING;
                        sub_next = RINSING;
                    end

                BATHING:
                    case (sub_state)
                        RINSING:
                            sub_next = SOAPING;

                        SOAPING:
                            if (soaped_up_i)
                                sub_next = FINAL_RINSE;

                        FINAL_RINSE:
                            top_next = DRYING;

                        default:
                            sub_next = RINSING;
                    endcase

                DRYING:
                    if (dryer_count == 2'd3)
                        top_next = OFF;

                EMERGENCY:
                    if (!scald_protection_i)
                        top_next = OFF;

                default:
                    top_next = OFF;
            endcase
        end
    end

    always_comb begin
        valve_open_o     = 1'b0;
        soap_dispenser_o = 1'b0;
        air_dryer_o      = 1'b0;
        alarm_led_o      = 1'b0;

        case (top_state)
            HEATING:
                valve_open_o = 1'b1;

            BATHING: begin
                if (sub_state == RINSING || sub_state == FINAL_RINSE)
                    valve_open_o = 1'b1;

                if (sub_state == SOAPING)
                    soap_dispenser_o = 1'b1;
            end

            DRYING:
                air_dryer_o = 1'b1;

            EMERGENCY:
                alarm_led_o = 1'b1;

            default: ;
        endcase
    end

endmodule
