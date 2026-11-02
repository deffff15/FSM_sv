`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model 
// ---------------------------------------------------------------------------
localparam int M_SECURE               = 0;
localparam int M_MONITOR_EXFILTRATION = 1;
localparam int M_MONITOR_PRIVILEGES   = 2;
localparam int M_BREACH_CONFIRMED     = 3;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface cyber_if (input logic clk);

    logic       rst_n;
    logic       port_scan_detected_i;
    logic       bulk_data_transfer_i;
    logic       root_brute_force_i;
    logic       admin_override_i;
    logic [1:0] threat_level_o;
    logic       firewall_block_o;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class CyberTxn;

    rand bit rst_n;
    rand bit port_scan_detected_i;
    rand bit bulk_data_transfer_i;
    rand bit root_brute_force_i;
    rand bit admin_override_i;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_port_scan_detected_i {
        port_scan_detected_i dist {1 := 20, 0 := 80};
    }

    constraint c_bulk_data_transfer_i {
        bulk_data_transfer_i dist {1 := 15, 0 := 85};
    }

    constraint c_root_brute_force_i {
        root_brute_force_i dist {1 := 15, 0 := 85};
    }

    constraint c_admin_override_i {
        admin_override_i dist {1 := 15, 0 := 85};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class CyberScoreboard;

    logic [3:0] expected_state = 4'b0001;
    int checked = 0;
    int errors  = 0;
    int level_00_cycles    = 0;
    int level_01_cycles    = 0;
    int level_10_cycles    = 0;
    int level_11_cycles    = 0;
    int block_cycles       = 0;
    int breach_entries     = 0;
    int scan_events        = 0;
    int bulk_events        = 0;
    int root_events        = 0;
    int admin_events       = 0;
    int reset_cycles       = 0;

    function void check(
        input logic       rst_n,
        input logic       port_scan_detected_i,
        input logic       bulk_data_transfer_i,
        input logic       root_brute_force_i,
        input logic       admin_override_i,
        input logic [1:0] threat_level_o,
        input logic       firewall_block_o
    );

        logic [3:0] next_state;
        logic [1:0] expected_threat;
        logic       expected_block;
        bit         mismatch;
        if (!rst_n) begin
            expected_state = 4'b0001;
            reset_cycles++;
        end
        else begin

            next_state = 4'b0001;

            if (expected_state[M_BREACH_CONFIRMED] && !admin_override_i) begin
                next_state[M_BREACH_CONFIRMED] = 1'b1;
            end
            else begin
                if (expected_state[M_SECURE] && port_scan_detected_i) begin
                    next_state[M_MONITOR_EXFILTRATION] = 1'b1;
                    next_state[M_MONITOR_PRIVILEGES]   = 1'b1;
                end

                if (expected_state[M_MONITOR_EXFILTRATION]) begin
                    if (bulk_data_transfer_i)
                        next_state[M_BREACH_CONFIRMED] = 1'b1;
                    else
                        next_state[M_MONITOR_EXFILTRATION] = 1'b1;
                end

                if (expected_state[M_MONITOR_PRIVILEGES]) begin
                    if (root_brute_force_i)
                        next_state[M_BREACH_CONFIRMED] = 1'b1;
                    else
                        next_state[M_MONITOR_PRIVILEGES] = 1'b1;
                end
            end

            if (port_scan_detected_i) scan_events++;
            if (bulk_data_transfer_i) bulk_events++;
            if (root_brute_force_i)   root_events++;
            if (admin_override_i)     admin_events++;

            if (next_state[M_BREACH_CONFIRMED] && !expected_state[M_BREACH_CONFIRMED])
                breach_entries++;

            expected_state = next_state;

        end

        expected_threat = 2'b00;
        expected_block  = 1'b0;

        if (expected_state[M_BREACH_CONFIRMED]) begin
            expected_threat = 2'b11;
            expected_block  = 1'b1;
        end
        else if (expected_state[M_MONITOR_EXFILTRATION] &&
                 expected_state[M_MONITOR_PRIVILEGES]) begin
            expected_threat = 2'b10;
        end
        else if (expected_state[M_MONITOR_EXFILTRATION] ||
                 expected_state[M_MONITOR_PRIVILEGES]) begin
            expected_threat = 2'b01;
        end

        mismatch = 0;

        if (threat_level_o !== expected_threat)
            mismatch = 1;

        if (firewall_block_o !== expected_block)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%b threat=%b/%b block=%b/%b (got/expected)",
                         $time, expected_state,
                         threat_level_o, expected_threat,
                         firewall_block_o, expected_block);
        end

        case (expected_threat)
            2'b00: level_00_cycles++;
            2'b01: level_01_cycles++;
            2'b10: level_10_cycles++;
            2'b11: level_11_cycles++;
            default: ;
        endcase

        if (expected_block) block_cycles++;

        checked++;

    endfunction
    function void report();
        $display("========== CYBER ATTACK SCOREBOARD ==========");
        $display("Cycles checked      : %0d", checked);
        $display("Passed              : %0d", checked - errors);
        $display("Errors              : %0d", errors);
        $display("Threat 00 cycles    : %0d", level_00_cycles);
        $display("Threat 01 cycles    : %0d", level_01_cycles);
        $display("Threat 10 cycles    : %0d", level_10_cycles);
        $display("Threat 11 cycles    : %0d", level_11_cycles);
        $display("Firewall block cyc. : %0d", block_cycles);
        $display("Breach entries      : %0d", breach_entries);
        $display("Port scan events    : %0d", scan_events);
        $display("Bulk transfer events: %0d", bulk_events);
        $display("Root brute events   : %0d", root_events);
        $display("Admin override evts : %0d", admin_events);
        $display("Reset cycles        : %0d", reset_cycles);
        if (level_00_cycles == 0 || level_01_cycles == 0 ||
            level_10_cycles == 0 || level_11_cycles == 0)
            $display("NOTE: not all threat levels were reached");
        $display("=============================================");
    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class CyberMonitor;

    virtual cyber_if vif;
    CyberScoreboard  sb;

    function new(
        virtual cyber_if vif,
        CyberScoreboard  sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction
    task run();

        forever begin
            @(posedge vif.clk);
            #1;

            sb.check(
                vif.rst_n,
                vif.port_scan_detected_i,
                vif.bulk_data_transfer_i,
                vif.root_brute_force_i,
                vif.admin_override_i,
                vif.threat_level_o,
                vif.firewall_block_o
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class CyberDriver;

    virtual cyber_if vif;
    function new(virtual cyber_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n                = 1'b0;
        vif.port_scan_detected_i = 1'b0;
        vif.bulk_data_transfer_i = 1'b0;
        vif.root_brute_force_i   = 1'b0;
        vif.admin_override_i     = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(CyberTxn tr);
        @(negedge vif.clk);
        vif.rst_n                = tr.rst_n;
        vif.port_scan_detected_i = tr.port_scan_detected_i;
        vif.bulk_data_transfer_i = tr.bulk_data_transfer_i;
        vif.root_brute_force_i   = tr.root_brute_force_i;
        vif.admin_override_i     = tr.admin_override_i;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class CyberGenerator;

    CyberDriver drv;
    int num_txn;

    function new(
        CyberDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        CyberTxn tr;
        repeat (num_txn) begin

            tr = new();
            if (!tr.randomize())
                $fatal(1);
            drv.drive(tr);

        end
    endtask

endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class CyberEnvironment;

    CyberGenerator  gen;
    CyberDriver     drv;
    CyberMonitor    mon;
    CyberScoreboard sb;
    virtual cyber_if vif;

    function new(
        virtual cyber_if vif,
        int num_txn = 2000
    );

        this.vif = vif;
        sb  = new();
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_txn);

    endfunction

    task run();

        fork
            mon.run();
        join_none
        gen.run();
        repeat (3) @(posedge vif.clk);
        #2;

        sb.report();

        if (sb.errors != 0)
            $fatal(1, "TEST FAILED: %0d errors", sb.errors);
        else
            $display("TEST PASSED");

    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_AI_CyberAttack;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    cyber_if vif(clk);

    AI_CyberAttack dut (
        .clk                  (clk),
        .rst_n                (vif.rst_n),
        .port_scan_detected_i (vif.port_scan_detected_i),
        .bulk_data_transfer_i (vif.bulk_data_transfer_i),
        .root_brute_force_i   (vif.root_brute_force_i),
        .admin_override_i     (vif.admin_override_i),
        .threat_level_o       (vif.threat_level_o),
        .firewall_block_o     (vif.firewall_block_o)
    );
    CyberEnvironment env;

    initial begin
        $dumpfile("AI_CyberAttack_waveform.vcd");
        $dumpvars(0, tb_AI_CyberAttack);
    end

    initial begin

        vif.rst_n                = 1'b0;
        vif.port_scan_detected_i = 1'b0;
        vif.bulk_data_transfer_i = 1'b0;
        vif.root_brute_force_i   = 1'b0;
        vif.admin_override_i     = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;

    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end

endmodule //The last line must be empty so Vs code doesn't give a mistake

