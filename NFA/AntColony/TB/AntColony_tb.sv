`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model 
// ---------------------------------------------------------------------------
localparam int M_NEST           = 0;
localparam int M_RETURNING      = 1;
localparam int M_MARKING_TRAIL  = 2;
localparam int M_PANIC          = 3;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface ant_if (input logic clk);

    logic       rst_n;
    logic       food_found_i;
    logic       home_reached_i;
    logic       rain_started_i;
    logic [1:0] colony_activity_o;
    logic       pheromone_active_o;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class AntTxn;

    rand bit rst_n;
    rand bit food_found_i;
    rand bit home_reached_i;
    rand bit rain_started_i;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_food_found_i {
        food_found_i dist {1 := 15, 0 := 85};
    }

    constraint c_home_reached_i {
        home_reached_i dist {1 := 30, 0 := 70};
    }

    constraint c_rain_started_i {
        rain_started_i dist {1 := 10, 0 := 90};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class AntScoreboard;

    logic [3:0] expected_state = 4'b0001;
    int checked = 0;
    int errors  = 0;
    int act_00_cycles      = 0;
    int act_01_cycles      = 0;
    int act_10_cycles      = 0;
    int act_11_cycles      = 0;
    int pheromone_cycles   = 0;
    int panic_cycles       = 0;
    int food_events        = 0;
    int home_events        = 0;
    int rain_events        = 0;
    int reset_cycles       = 0;

    function void check(
        input logic       rst_n,
        input logic       food_found_i,
        input logic       home_reached_i,
        input logic       rain_started_i,
        input logic [1:0] colony_activity_o,
        input logic       pheromone_active_o
    );

        logic [3:0] next_state;
        logic [1:0] expected_activity;
        logic       expected_pheromone;
        bit         mismatch;
        if (!rst_n) begin
            expected_state = 4'b0001;
            reset_cycles++;
        end
        else begin

            next_state = 4'b0001;

            if (rain_started_i && !expected_state[M_NEST]) begin
                next_state[M_PANIC] = 1'b1;
            end
            else begin
                if (expected_state[M_NEST] && food_found_i) begin
                    next_state[M_RETURNING]     = 1'b1;
                    next_state[M_MARKING_TRAIL] = 1'b1;
                end

                if (expected_state[M_RETURNING] && !home_reached_i)
                    next_state[M_RETURNING] = 1'b1;

                if (expected_state[M_MARKING_TRAIL] && !home_reached_i)
                    next_state[M_MARKING_TRAIL] = 1'b1;
            end

            if (expected_state[M_PANIC] && !home_reached_i)
                next_state[M_PANIC] = 1'b1;

            if (food_found_i)   food_events++;
            if (home_reached_i) home_events++;
            if (rain_started_i) rain_events++;

            expected_state = next_state;

        end

        expected_pheromone = expected_state[M_MARKING_TRAIL];

        if (expected_state[M_PANIC])
            expected_activity = 2'b10;
        else if (expected_state[M_RETURNING] && expected_state[M_MARKING_TRAIL])
            expected_activity = 2'b11;
        else if (expected_state[M_RETURNING])
            expected_activity = 2'b01;
        else
            expected_activity = 2'b00;

        mismatch = 0;

        if (colony_activity_o !== expected_activity)
            mismatch = 1;

        if (pheromone_active_o !== expected_pheromone)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%b activity=%b/%b pheromone=%b/%b (got/expected)",
                         $time, expected_state,
                         colony_activity_o, expected_activity,
                         pheromone_active_o, expected_pheromone);
        end

        case (expected_activity)
            2'b00: act_00_cycles++;
            2'b01: act_01_cycles++;
            2'b10: act_10_cycles++;
            2'b11: act_11_cycles++;
            default: ;
        endcase

        if (expected_pheromone)        pheromone_cycles++;
        if (expected_state[M_PANIC])   panic_cycles++;

        checked++;

    endfunction
    function void report();
        $display("========== ANT COLONY SCOREBOARD ==========");
        $display("Cycles checked      : %0d", checked);
        $display("Passed              : %0d", checked - errors);
        $display("Errors              : %0d", errors);
        $display("Activity 00 cycles  : %0d", act_00_cycles);
        $display("Activity 01 cycles  : %0d", act_01_cycles);
        $display("Activity 10 cycles  : %0d", act_10_cycles);
        $display("Activity 11 cycles  : %0d", act_11_cycles);
        $display("Pheromone cycles    : %0d", pheromone_cycles);
        $display("PANIC cycles        : %0d", panic_cycles);
        $display("Food events         : %0d", food_events);
        $display("Home events         : %0d", home_events);
        $display("Rain events         : %0d", rain_events);
        $display("Reset cycles        : %0d", reset_cycles);
        if (panic_cycles == 0)
            $display("NOTE: ST_PANIC was never reached");
        $display("===========================================");
    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class AntMonitor;

    virtual ant_if vif;
    AntScoreboard  sb;

    function new(
        virtual ant_if vif,
        AntScoreboard  sb
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
                vif.food_found_i,
                vif.home_reached_i,
                vif.rain_started_i,
                vif.colony_activity_o,
                vif.pheromone_active_o
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class AntDriver;

    virtual ant_if vif;
    function new(virtual ant_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n          = 1'b0;
        vif.food_found_i   = 1'b0;
        vif.home_reached_i = 1'b0;
        vif.rain_started_i = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(AntTxn tr);
        @(negedge vif.clk);
        vif.rst_n          = tr.rst_n;
        vif.food_found_i   = tr.food_found_i;
        vif.home_reached_i = tr.home_reached_i;
        vif.rain_started_i = tr.rain_started_i;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class AntGenerator;

    AntDriver drv;
    int num_txn;

    function new(
        AntDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        AntTxn tr;
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
class AntEnvironment;

    AntGenerator  gen;
    AntDriver     drv;
    AntMonitor    mon;
    AntScoreboard sb;
    virtual ant_if vif;

    function new(
        virtual ant_if vif,
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
module tb_AntColony;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    ant_if vif(clk);

    AntColony dut (
        .clk                (clk),
        .rst_n              (vif.rst_n),
        .food_found_i       (vif.food_found_i),
        .home_reached_i     (vif.home_reached_i),
        .rain_started_i     (vif.rain_started_i),
        .colony_activity_o  (vif.colony_activity_o),
        .pheromone_active_o (vif.pheromone_active_o)
    );
    AntEnvironment env;

    initial begin
        $dumpfile("AntColony_waveform.vcd");
        $dumpvars(0, tb_AntColony);
    end

    initial begin

        vif.rst_n          = 1'b0;
        vif.food_found_i   = 1'b0;
        vif.home_reached_i = 1'b0;
        vif.rain_started_i = 1'b0;
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

