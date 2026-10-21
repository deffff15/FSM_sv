`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [2:0] {
    M_IDLE,
    M_HEATING,
    M_ADDING_INGREDIENTS,
    M_COOKING,
    M_READY
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface soup_if (input logic clk);

    logic rst_n;
    logic start_cooking;
    logic water_boiling;
    logic cooking_done;
    logic heater_on;
    logic add_ingredients;
    logic soup_ready;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class SoupTxn;

    rand bit rst_n;
    rand bit start_cooking;
    rand bit water_boiling;
    rand bit cooking_done;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_start_cooking {
        start_cooking dist {1 := 30, 0 := 70};
    }

    constraint c_water_boiling {
        water_boiling dist {1 := 30, 0 := 70};
    }

    constraint c_cooking_done {
        cooking_done dist {1 := 20, 0 := 80};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class SoupScoreboard;

    model_state_t expected_state = M_IDLE;

    int checked = 0;
    int errors  = 0;
    int idle_cycles    = 0;
    int heating_cycles = 0;
    int adding_cycles  = 0;
    int cooking_cycles = 0;
    int ready_cycles   = 0;
    int heater_cycles  = 0;

    function void check(
        input logic rst_n,
        input logic start_cooking,
        input logic water_boiling,
        input logic cooking_done,
        input logic heater_on,
        input logic add_ingredients,
        input logic soup_ready
    );

        model_state_t next_state;
        logic         expected_heater_on;
        logic         expected_add_ingredients;
        logic         expected_soup_ready;
        bit           mismatch;
        if (!rst_n) begin
            expected_state = M_IDLE;
        end
        else begin

            next_state = expected_state;

            case (expected_state)

                M_IDLE: begin
                    if (start_cooking)
                        next_state = M_HEATING;
                end

                M_HEATING: begin
                    if (water_boiling)
                        next_state = M_ADDING_INGREDIENTS;
                end

                M_ADDING_INGREDIENTS: begin
                    next_state = M_COOKING;
                end

                M_COOKING: begin
                    if (cooking_done)
                        next_state = M_READY;
                end

                M_READY: begin
                    next_state = M_IDLE;
                end

                default: begin
                    next_state = M_IDLE;
                end

            endcase

            expected_state = next_state;

        end
        expected_heater_on       = (expected_state == M_HEATING) || (expected_state == M_COOKING);
        expected_add_ingredients = (expected_state == M_ADDING_INGREDIENTS);
        expected_soup_ready      = (expected_state == M_READY);

        mismatch = 0;

        if (heater_on !== expected_heater_on)
            mismatch = 1;

        if (add_ingredients !== expected_add_ingredients)
            mismatch = 1;

        if (soup_ready !== expected_soup_ready)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%0d heater=%b exp=%b add=%b exp=%b ready=%b exp=%b",
                         $time, expected_state, heater_on, expected_heater_on,
                         add_ingredients, expected_add_ingredients,
                         soup_ready, expected_soup_ready);
        end
        case (expected_state)
            M_IDLE:               idle_cycles++;
            M_HEATING:            heating_cycles++;
            M_ADDING_INGREDIENTS: adding_cycles++;
            M_COOKING:            cooking_cycles++;
            M_READY:              ready_cycles++;
            default: ;
        endcase

        if (expected_heater_on)
            heater_cycles++;

        checked++;

    endfunction

    function void report();

        $display("========== SOUP SCOREBOARD ==========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("IDLE cycles       : %0d", idle_cycles);
        $display("HEATING cycles    : %0d", heating_cycles);
        $display("ADDING cycles     : %0d", adding_cycles);
        $display("COOKING cycles    : %0d", cooking_cycles);
        $display("READY cycles      : %0d", ready_cycles);
        $display("Heater on cycles  : %0d", heater_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class SoupMonitor;

    virtual soup_if vif;
    SoupScoreboard  sb;

    function new(
        virtual soup_if vif,
        SoupScoreboard  sb
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
                vif.start_cooking,
                vif.water_boiling,
                vif.cooking_done,
                vif.heater_on,
                vif.add_ingredients,
                vif.soup_ready
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class SoupDriver;

    virtual soup_if vif;
    function new(virtual soup_if vif);
        this.vif = vif;
    endfunction
    task reset();

        @(negedge vif.clk);
        vif.rst_n         = 1'b0;
        vif.start_cooking = 1'b0;
        vif.water_boiling = 1'b0;
        vif.cooking_done  = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask
    task drive(SoupTxn tr);

        @(negedge vif.clk);
        vif.rst_n         = tr.rst_n;
        vif.start_cooking = tr.start_cooking;
        vif.water_boiling = tr.water_boiling;
        vif.cooking_done  = tr.cooking_done;

    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class SoupGenerator;

    SoupDriver drv;
    int num_txn;
    function new(
        SoupDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        SoupTxn tr;
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
class SoupEnvironment;

    SoupGenerator  gen;
    SoupDriver     drv;
    SoupMonitor    mon;
    SoupScoreboard sb;
    virtual soup_if vif;

    function new(
        virtual soup_if vif,
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
module tb_SoupMaker;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    soup_if vif(clk);

    SoupMaker dut (
        .clk             (clk),
        .rst_n           (vif.rst_n),
        .start_cooking   (vif.start_cooking),
        .water_boiling   (vif.water_boiling),
        .cooking_done    (vif.cooking_done),
        .heater_on       (vif.heater_on),
        .add_ingredients (vif.add_ingredients),
        .soup_ready      (vif.soup_ready)
    );
    SoupEnvironment env;

    initial begin
        $dumpfile("SoupMaker_waveform.vcd");
        $dumpvars(0, tb_SoupMaker);
    end

    initial begin

        vif.rst_n         = 1'b0;
        vif.start_cooking = 1'b0;
        vif.water_boiling = 1'b0;
        vif.cooking_done  = 1'b0;
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

