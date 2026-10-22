`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model constants
// ---------------------------------------------------------------------------
localparam logic [3:0] M_GROUND = 4'b0001;
localparam logic [3:0] M_RUNG_1 = 4'b0010;
localparam logic [3:0] M_RUNG_2 = 4'b0100;
localparam logic [3:0] M_TOP    = 4'b1000;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface ladder_if (input logic clk);

    logic rst_n;
    logic start;
    logic step_up;
    logic broken_rung;
    logic success;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class LadderTxn;

    rand bit rst_n;
    rand bit start;
    rand bit step_up;
    rand bit broken_rung;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_start {
        start dist {1 := 10, 0 := 90};
    }

    constraint c_step_up {
        step_up dist {1 := 65, 0 := 35};
    }

    constraint c_broken_rung {
        broken_rung dist {1 := 35, 0 := 65};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class LadderScoreboard;

    logic [3:0] expected_state = M_GROUND;
    int checked = 0;
    int errors  = 0;
    int ground_cycles  = 0;
    int rung1_cycles   = 0;
    int rung2_cycles   = 0;
    int top_cycles     = 0;
    int multi_cycles   = 0;
    int broken_events  = 0;
    int start_events   = 0;
    int reset_cycles   = 0;

    function void check(
        input logic rst_n,
        input logic start,
        input logic step_up,
        input logic broken_rung,
        input logic success
    );

        logic [3:0] next_state;
        logic       expected_success;
        bit         mismatch;
        if (!rst_n) begin
            expected_state = M_GROUND;
            reset_cycles++;
        end
        else begin

            next_state = expected_state;

            if (start) begin
                next_state = M_GROUND;
                start_events++;
            end
            else if (step_up) begin
                next_state = {expected_state[3] | expected_state[2],
                              expected_state[1],
                              expected_state[0],
                              expected_state[2] & broken_rung};
                if (expected_state[2] && broken_rung)
                    broken_events++;
            end

            expected_state = next_state;

        end

        expected_success = expected_state[3];

        mismatch = 0;

        if (success !== expected_success)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%b success=%b expected=%b",
                         $time, expected_state, success, expected_success);
        end

        if (expected_state[0]) ground_cycles++;
        if (expected_state[1]) rung1_cycles++;
        if (expected_state[2]) rung2_cycles++;
        if (expected_state[3]) top_cycles++;
        if ($countones(expected_state) > 1) multi_cycles++;

        checked++;

    endfunction
    function void report();
        $display("========== LADDER SCOREBOARD ==========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("GROUND cycles     : %0d", ground_cycles);
        $display("RUNG_1 cycles     : %0d", rung1_cycles);
        $display("RUNG_2 cycles     : %0d", rung2_cycles);
        $display("TOP cycles        : %0d", top_cycles);
        $display("Multi-bit cycles  : %0d", multi_cycles);
        $display("Broken events     : %0d", broken_events);
        $display("Start events      : %0d", start_events);
        $display("Reset cycles      : %0d", reset_cycles);
        $display("=======================================");
    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class LadderMonitor;

    virtual ladder_if vif;
    LadderScoreboard  sb;

    function new(
        virtual ladder_if vif,
        LadderScoreboard  sb
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
                vif.start,
                vif.step_up,
                vif.broken_rung,
                vif.success
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class LadderDriver;

    virtual ladder_if vif;
    function new(virtual ladder_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n       = 1'b0;
        vif.start       = 1'b0;
        vif.step_up     = 1'b0;
        vif.broken_rung = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(LadderTxn tr);
        @(negedge vif.clk);
        vif.rst_n       = tr.rst_n;
        vif.start       = tr.start;
        vif.step_up     = tr.step_up;
        vif.broken_rung = tr.broken_rung;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class LadderGenerator;

    LadderDriver drv;
    int num_txn;

    function new(
        LadderDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        LadderTxn tr;
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
class LadderEnvironment;

    LadderGenerator  gen;
    LadderDriver     drv;
    LadderMonitor    mon;
    LadderScoreboard sb;
    virtual ladder_if vif;

    function new(
        virtual ladder_if vif,
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
module tb_ladder;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    ladder_if vif(clk);

    ladder dut (
        .clk         (clk),
        .rst_n       (vif.rst_n),
        .start       (vif.start),
        .step_up     (vif.step_up),
        .broken_rung (vif.broken_rung),
        .success     (vif.success)
    );
    LadderEnvironment env;

    initial begin
        $dumpfile("ladder_waveform.vcd");
        $dumpvars(0, tb_ladder);
    end

    initial begin

        vif.rst_n       = 1'b0;
        vif.start       = 1'b0;
        vif.step_up     = 1'b0;
        vif.broken_rung = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;

    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end

endmodule //The last line must be empty so Vs code doesn't give a endmodule

