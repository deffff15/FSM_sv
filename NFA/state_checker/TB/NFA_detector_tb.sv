`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface nfa_if (input logic clk);

    logic rst_n;
    logic din;
    logic matched;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class NfaTxn;

    rand bit rst_n;
    rand bit din;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_din {
        din dist {1 := 50, 0 := 50};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class NfaScoreboard;

    logic [2:0] expected_active = 3'b001;
    int checked = 0;
    int errors  = 0;
    int state_0_cycles = 0;
    int state_1_cycles = 0;
    int state_2_cycles = 0;
    int matched_cycles = 0;

    function void check(
        input logic rst_n,
        input logic din,
        input logic matched
    );

        logic [2:0] next_active;
        logic       expected_matched;

        if (!rst_n) begin
            expected_active = 3'b001;
        end
        else begin

            next_active = 3'b001;

            if (expected_active[0] && !din)
                next_active[1] = 1'b1;

            if (expected_active[1] && din)
                next_active[2] = 1'b1;

            expected_active = next_active;

        end

        expected_matched = expected_active[2];

        if (matched !== expected_matched)
            errors++;

        if (expected_active[0])
            state_0_cycles++;

        if (expected_active[1])
            state_1_cycles++;

        if (expected_active[2])
            state_2_cycles++;

        if (expected_matched)
            matched_cycles++;

        checked++;

    endfunction

    function void report();

        $display("");
        $display("=========== NFA SCOREBOARD ==========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("State 0 active    : %0d", state_0_cycles);
        $display("State 1 active    : %0d", state_1_cycles);
        $display("State 2 active    : %0d", state_2_cycles);
        $display("Matched cycles    : %0d", matched_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class NfaMonitor;

    virtual nfa_if vif;
    NfaScoreboard  sb;

    function new(
        virtual nfa_if vif,
        NfaScoreboard  sb
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
                vif.din,
                vif.matched
            );
        end
    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class NfaDriver;

    virtual nfa_if vif;

    function new(virtual nfa_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n = 1'b0;
        vif.din   = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(NfaTxn tr);

        @(negedge vif.clk);
        vif.rst_n = tr.rst_n;
        vif.din   = tr.din;

    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class NfaGenerator;

    NfaDriver drv;
    int num_txn;

    function new(
        NfaDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        NfaTxn tr;

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
class NfaEnvironment;

    NfaGenerator  gen;
    NfaDriver     drv;
    NfaMonitor    mon;
    NfaScoreboard sb;

    virtual nfa_if vif;

    function new(
        virtual nfa_if vif,
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
module tb_NfaDetector;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    nfa_if vif(clk);

    NfaDetector dut (
        .clk     (clk),
        .rst_n   (vif.rst_n),
        .din     (vif.din),
        .matched (vif.matched)
    );
    NfaEnvironment env;

    initial begin
        $dumpfile("NfaDetector_waveform.vcd");
        $dumpvars(0, tb_NfaDetector);
    end

    initial begin

        vif.rst_n = 1'b0;
        vif.din   = 1'b0;
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

