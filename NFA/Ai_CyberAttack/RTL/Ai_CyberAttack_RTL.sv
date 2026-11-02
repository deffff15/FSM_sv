`timescale 1ns/1ps
module AI_CyberAttack (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       port_scan_detected_i,
    input  logic       bulk_data_transfer_i,
    input  logic       root_brute_force_i,
    input  logic       admin_override_i,
    output logic [1:0] threat_level_o,
    output logic       firewall_block_o
);

    localparam int ST_SECURE = 0;
    localparam int ST_MONITOR_EXFILTRATION = 1;
    localparam int ST_MONITOR_PRIVILEGES = 2;
    localparam int ST_BREACH_CONFIRMED = 3;

    logic [3:0] current_states, next_states;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_states <= 4'b0001;
        else
            current_states <= next_states;
    end
    always_comb begin
        next_states = 4'b0001;

        if (current_states[ST_BREACH_CONFIRMED] && !admin_override_i) begin
            next_states[ST_BREACH_CONFIRMED] = 1'b1;
        end else begin
            if (current_states[ST_SECURE] && port_scan_detected_i) begin
                next_states[ST_MONITOR_EXFILTRATION] = 1'b1;
                next_states[ST_MONITOR_PRIVILEGES]   = 1'b1;
            end

            if (current_states[ST_MONITOR_EXFILTRATION]) begin
                if (bulk_data_transfer_i)
                    next_states[ST_BREACH_CONFIRMED] = 1'b1;
                else
                    next_states[ST_MONITOR_EXFILTRATION] = 1'b1;
            end

            if (current_states[ST_MONITOR_PRIVILEGES]) begin
                if (root_brute_force_i)
                    next_states[ST_BREACH_CONFIRMED] = 1'b1;
                else
                    next_states[ST_MONITOR_PRIVILEGES] = 1'b1;
            end
        end
    end

    always_comb begin
        threat_level_o   = 2'b00;
        firewall_block_o = 1'b0;

        if (current_states[ST_BREACH_CONFIRMED]) begin
            threat_level_o   = 2'b11;
            firewall_block_o = 1'b1;
        end else if (current_states[ST_MONITOR_EXFILTRATION] &&
                     current_states[ST_MONITOR_PRIVILEGES]) begin
            threat_level_o = 2'b10;
        end else if (current_states[ST_MONITOR_EXFILTRATION] ||
                     current_states[ST_MONITOR_PRIVILEGES]) begin
            threat_level_o = 2'b01;
        end
    end

endmodule
