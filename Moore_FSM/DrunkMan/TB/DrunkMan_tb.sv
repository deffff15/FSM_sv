`timescale 1ns / 1ps
import DrunkPackage::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface drunk_if #(parameter int AMOUNT = 10) (input logic clk);

    logic              rst_n;
    logic              enable;
    logic [AMOUNT-1:0] How_drunk;
    logic [AMOUNT-1:0] promile;
    logic [1:0]        behavior;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class DrunkTxn #(parameter int AMOUNT = 10);

    rand bit              rst_n;
    rand bit              enable;
    rand bit [AMOUNT-1:0] how_drunk;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_enable {
        enable dist {1 := 70, 0 := 30};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class DrunkScoreboard #(parameter int AMOUNT = 10);

    localparam logic [AMOUNT-1:0] PROG_TIPSY  = 2**(AMOUNT-2);
    localparam logic [AMOUNT-1:0] PROG_DRUNK  = 2**(AMOUNT-1);
    localparam logic [AMOUNT-1:0] PROG_WASTED = PROG_DRUNK + PROG_TIPSY;
    drunk_state_t      expected_state = ST_SOBER;
    logic [AMOUNT-1:0] expected_alcohol = '0;

    int checked = 0;
    int errors  = 0;
    int enabled_cycles  = 0;
    int disabled_cycles = 0;
    int sober_cycles    = 0;
    int tipsy_cycles    = 0;
    int drunk_cycles    = 0;
    int wasted_cycles   = 0;
    function drunk_state_t classify(
        input logic [AMOUNT-1:0] value
    );

        drunk_state_t result;
        if (value < PROG_TIPSY)
            result = ST_SOBER;
        else if (value < PROG_DRUNK)
            result = ST_TIPSY;
        else if (value < PROG_WASTED)
            result = ST_DRUNK;
        else
            result = ST_WASTED;

        return result;

    endfunction

    function void check(
        input logic              rst_n,
        input logic              enable,
        input logic [AMOUNT-1:0] how_drunk,
        input logic [AMOUNT-1:0] promile,
        input logic [1:0]        behavior
    );

        logic [1:0] expected_behavior;
        bit         mismatch;
        if (!rst_n) begin
            expected_state   = ST_SOBER;
            expected_alcohol = '0;
        end
        else if (enable) begin
            expected_state   = classify(expected_alcohol);
            expected_alcohol = how_drunk;
        end

        expected_behavior = expected_state;

        mismatch = 0;

        if (promile !== expected_alcohol)
            mismatch = 1;

        if (behavior !== expected_behavior)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t enable=%b model_state=%0d promile=%0d exp=%0d behavior=%b exp=%b",
                         $time, enable, expected_state, promile, expected_alcohol,
                         behavior, expected_behavior);
        end

        if (enable)
            enabled_cycles++;
        else
            disabled_cycles++;

        case (expected_state)
            ST_SOBER:  sober_cycles++;
            ST_TIPSY:  tipsy_cycles++;
            ST_DRUNK:  drunk_cycles++;
            ST_WASTED: wasted_cycles++;
            default: ;
        endcase
        checked++;

    endfunction
    function void report();

        $display("========== DRUNK SCOREBOARD =========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("Enable cycles     : %0d", enabled_cycles);
        $display("Disabled cycles   : %0d", disabled_cycles);
        $display("SOBER cycles      : %0d", sober_cycles);
        $display("TIPSY cycles      : %0d", tipsy_cycles);
        $display("DRUNK cycles      : %0d", drunk_cycles);
        $display("WASTED cycles     : %0d", wasted_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class DrunkMonitor #(parameter int AMOUNT = 10);

    virtual drunk_if #(AMOUNT) vif;
    DrunkScoreboard #(AMOUNT)  sb;

    function new(
        virtual drunk_if #(AMOUNT) vif,
        DrunkScoreboard #(AMOUNT)  sb
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
                vif.enable,
                vif.How_drunk,
                vif.promile,
                vif.behavior
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class DrunkDriver #(parameter int AMOUNT = 10);

    virtual drunk_if #(AMOUNT) vif;
    function new(virtual drunk_if #(AMOUNT) vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n     = 1'b0;
        vif.enable    = 1'b0;
        vif.How_drunk = '0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(DrunkTxn #(AMOUNT) tr);
        @(negedge vif.clk);
        vif.rst_n     = tr.rst_n;
        vif.enable    = tr.enable;
        vif.How_drunk = tr.how_drunk;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class DrunkGenerator #(parameter int AMOUNT = 10);

    DrunkDriver #(AMOUNT) drv;
    int num_txn;

    function new(
        DrunkDriver #(AMOUNT) drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction
    task run();

        DrunkTxn #(AMOUNT) tr;
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
class DrunkEnvironment #(parameter int AMOUNT = 10);

    DrunkGenerator #(AMOUNT)  gen;
    DrunkDriver    #(AMOUNT)  drv;
    DrunkMonitor   #(AMOUNT)  mon;
    DrunkScoreboard #(AMOUNT) sb;
    virtual drunk_if #(AMOUNT) vif;

    function new(
        virtual drunk_if #(AMOUNT) vif,
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
module tb_DrunkMan;

    localparam int AMOUNT  = 10;
    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    drunk_if #(AMOUNT) vif(clk);

    DrunkMan #(
        .amount(AMOUNT)
    ) dut (
        .clk       (clk),
        .rst_n     (vif.rst_n),
        .enable    (vif.enable),
        .How_drunk (vif.How_drunk),
        .promile   (vif.promile),
        .behavior  (vif.behavior)
    );
    DrunkEnvironment #(AMOUNT) env;

    initial begin
        $dumpfile("DrunkMan_waveform.vcd");
        $dumpvars(0, tb_DrunkMan);
    end

    initial begin

        vif.rst_n     = 1'b0;
        vif.enable    = 1'b0;
        vif.How_drunk = '0;
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

