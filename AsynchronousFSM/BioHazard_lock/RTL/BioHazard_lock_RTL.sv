`timescale 1ns/1ps
module BioHazard_lock(
    input  logic rst_n,
    input  logic sb_entered,
    input  logic outer_door_open,
    input  logic pressure_equalized,
    output logic evacuate_pump,
    output logic inner_lock_release
);

    typedef enum logic [1:0] {
        ST_VENTILATED   = 2'b00, 
        ST_CONTAMINATED = 2'b01, 
        ST_PURGING      = 2'b11, 
        ST_EQUALIZING   = 2'b10  
    } state_t;

    state_t current_s;

    always_comb begin
        if (!rst_n) begin
            current_s = ST_VENTILATED;
        end else begin
            current_s = current_s;

            case (current_s) 
                ST_VENTILATED: begin
                    if (sb_entered) begin
                        current_s = ST_CONTAMINATED;
                    end
                end
                
                ST_CONTAMINATED: begin
                    if (!outer_door_open) begin
                        current_s = ST_PURGING;
                    end
                end
                
                ST_PURGING: begin
                    if (!pressure_equalized) begin
                        current_s = ST_EQUALIZING;
                    end
                end
                
                ST_EQUALIZING: begin
                    if (pressure_equalized) begin
                        current_s = ST_VENTILATED;
                    end
                end
                default: current_s = ST_VENTILATED;
            endcase
        end
    end

    always_comb begin
        evacuate_pump = 1'b0;
        inner_lock_release = 1'b0;

        case (current_s)
            ST_VENTILATED: begin
                inner_lock_release = 1'b1; 
            end
            ST_CONTAMINATED: begin
            end
            ST_PURGING: begin
                evacuate_pump = 1'b1; 
            end
            ST_EQUALIZING: begin
                evacuate_pump = 1'b1; 
            end
        endcase
    end
endmodule

