`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE,
    M_GOT_1,
    M_GOT_10,
    M_FOUND_101
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface dfa_if (input logic clk);

    logic rst_n;
    logic din;
    logic detected;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class DfaTxn;

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
class DfaScoreboard;

    model_state_t expected_state = M_IDLE;

    int checked = 0;
    int errors  = 0;
    int idle_cycles      = 0;
    int got_1_cycles     = 0;
    int got_10_cycles    = 0;
    int found_101_cycles = 0;

    function void check(
        input logic rst_n,
        input logic din,
        input logic detected
    );

        model_state_t next_state;
        logic         expected_detected;

        if (!rst_n) begin
            expected_state = M_IDLE;
        end
        else begin

            next_state = expected_state;
            case (expected_state)

                M_IDLE: begin
                    if (din)
                        next_state = M_GOT_1;
                end

                M_GOT_1: begin
                    next_state = din ? M_GOT_1 : M_GOT_10;
                end

                M_GOT_10: begin
                    next_state = din ? M_FOUND_101 : M_IDLE;
                end

                M_FOUND_101: begin
                    next_state = din ? M_GOT_1 : M_IDLE;
                end

                default: begin
                    next_state = M_IDLE;
                end

            endcase

            expected_state = next_state;

        end
        
        expected_detected = (expected_state == M_FOUND_101);

        if (detected !== expected_detected)
            errors++;

        case (expected_state)
            M_IDLE:      idle_cycles++;
            M_GOT_1:     got_1_cycles++;
            M_GOT_10:    got_10_cycles++;
            M_FOUND_101: found_101_cycles++;
            default: ;
        endcase

        checked++;

    endfunction

    function void report();

        $display("");
        $display("=========== DFA SCOREBOARD ==========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("IDLE cycles       : %0d", idle_cycles);
        $display("GOT_1 cycles      : %0d", got_1_cycles);
        $display("GOT_10 cycles     : %0d", got_10_cycles);
        $display("FOUND_101 cycles  : %0d", found_101_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class DfaMonitor;

    virtual dfa_if vif;
    DfaScoreboard  sb;

    function new(
        virtual dfa_if vif,
        DfaScoreboard  sb
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
                vif.detected
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class DfaDriver;

    virtual dfa_if vif;

    function new(virtual dfa_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n = 1'b0;
        vif.din   = 1'b0;

        repeat (2) @(negedge vif.clk);

        vif.rst_n = 1'b1;

    endtask

    task drive(DfaTxn tr);

        @(negedge vif.clk);

        vif.rst_n = tr.rst_n;
        vif.din   = tr.din;

    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class DfaGenerator;

    DfaDriver drv;
    int num_txn;

    function new(
        DfaDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        DfaTxn tr;

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
class DfaEnvironment;

    DfaGenerator  gen;
    DfaDriver     drv;
    DfaMonitor    mon;
    DfaScoreboard sb;

    virtual dfa_if vif;

    function new(
        virtual dfa_if vif,
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
module tb_DfaDetector;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    dfa_if vif(clk);

    DfaDetector dut (
        .clk      (clk),
        .rst_n    (vif.rst_n),
        .din      (vif.din),
        .detected (vif.detected)
    );

    DfaEnvironment env;

    initial begin
        $dumpfile("DfaDetector_waveform.vcd");
        $dumpvars(0, tb_DfaDetector);
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
endmodule //The last line must be empty so VS code doesn't give a mistake

