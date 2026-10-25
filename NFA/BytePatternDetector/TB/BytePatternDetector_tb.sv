`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface pattern_if (input logic clk);
    logic       rst_n;
    logic [7:0] data_i;
    logic       pattern_found_o;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class PatternTxn;
    rand bit       rst_n;
    rand bit [7:0] data_i;
    constraint c_rst_n {
        rst_n dist {1 := 199, 0 := 1};
    }
    constraint c_data_i {
        data_i dist {8'hAA := 25, 8'hBB := 25, 8'hCC := 10, 8'hDD := 10, [8'h00:8'hFF] :/ 30};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class PatternScoreboard;
    localparam int S_IDLE   = 0;
    localparam int S_GOT_AA = 1;
    localparam int S_GOT_BB = 2;
    localparam int S_MATCH  = 3;
    logic [3:0] expected_states = 4'b0001;
    int checked = 0;
    int errors  = 0;
    int got_aa_cycles = 0;
    int got_bb_cycles = 0;
    int match_cycles  = 0;
    int match_via_cc  = 0;
    int match_via_dd  = 0;

    function void check(
        input logic       rst_n,
        input logic [7:0] data_i,
        input logic       pattern_found_o
    );
        logic [3:0] next_states;
        logic       expected_pattern_found;
        bit         mismatch;
        if (!rst_n) begin
            expected_states = 4'b0001;
        end
        else begin
            next_states = 4'b0001;
            if (expected_states[S_IDLE] && data_i == 8'hAA)
                next_states[S_GOT_AA] = 1'b1;
            if (expected_states[S_GOT_AA] && data_i == 8'hBB)
                next_states[S_GOT_BB] = 1'b1;
            if (expected_states[S_GOT_BB] && (data_i == 8'hCC || data_i == 8'hDD))
                next_states[S_MATCH] = 1'b1;
            if (expected_states[S_MATCH])
                next_states[S_MATCH] = 1'b0;
            if (next_states[S_MATCH]) begin
                if (data_i == 8'hCC)
                    match_via_cc++;
                else
                    match_via_dd++;
            end
            expected_states = next_states;
        end
        expected_pattern_found = expected_states[S_MATCH];
        mismatch = 0;
        if (pattern_found_o !== expected_pattern_found)
            mismatch = 1;
        if (mismatch)
            errors++;
        if (expected_states[S_GOT_AA])
            got_aa_cycles++;
        if (expected_states[S_GOT_BB])
            got_bb_cycles++;
        if (expected_pattern_found)
            match_cycles++;
        checked++;
    endfunction

    function void report();
        $display("");
        $display("=========== PATTERN RESULTS =========");
        $display("Cycles checked          : %0d", checked);
        $display("Passed                  : %0d", checked - errors);
        $display("Errors                  : %0d", errors);
        $display("-------------------------------------");
        $display("GOT_AA active cycles    : %0d", got_aa_cycles);
        $display("GOT_BB active cycles    : %0d", got_bb_cycles);
        $display("-------------------------------------");
        $display("Pattern found           : %0d", match_cycles);
        $display("  ended with 0xCC       : %0d", match_via_cc);
        $display("  ended with 0xDD       : %0d", match_via_dd);
        $display("-------------------------------------");
        if (errors == 0)
            $display("Result                  : PASSED");
        else
            $display("Result                  : FAILED");
        $display("=====================================");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class PatternMonitor;
    virtual pattern_if vif;
    PatternScoreboard  sb;

    function new(
        virtual pattern_if vif,
        PatternScoreboard  sb
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
                vif.data_i,
                vif.pattern_found_o
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class PatternDriver;
    virtual pattern_if vif;

    function new(virtual pattern_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n  = 1'b0;
        vif.data_i = 8'h00;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(PatternTxn tr);
        @(negedge vif.clk);
        vif.rst_n  = tr.rst_n;
        vif.data_i = tr.data_i;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class PatternGenerator;
    PatternDriver drv;
    int num_txn;

    function new(
        PatternDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        PatternTxn tr;
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
class PatternEnvironment;
    PatternGenerator  gen;
    PatternDriver     drv;
    PatternMonitor    mon;
    PatternScoreboard sb;
    virtual pattern_if vif;

    function new(
        virtual pattern_if vif,
        int num_txn = 30000
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
            $fatal(1);
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_BytePatternDetector;
    localparam int NUM_TXN = 30000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    pattern_if vif(clk);

    BytePatternDetector dut (
        .clk             (clk),
        .rst_n           (vif.rst_n),
        .data_i          (vif.data_i),
        .pattern_found_o (vif.pattern_found_o)
    );
    PatternEnvironment env;

    initial begin
        $dumpfile("BytePatternDetector_waveform.vcd");
        $dumpvars(0, tb_BytePatternDetector);
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.data_i = 8'h00;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1);
    end
endmodule //The last line must be empty so vscode doesn't give a mistake

