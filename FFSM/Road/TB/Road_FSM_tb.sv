`timescale 1ns / 1ps
import Driving::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface road_if (input logic clk);

    logic rst_n;
    logic Wy;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class RoadTxn;

    rand bit rst_n;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class RoadScoreboard;

    state expected_state = ROAD_1;
    logic [4:0] expected_timer = '0;

    int checked   = 0;
    int errors    = 0;
    int wy_cycles = 0;

    function void check(
        input logic rst_n,
        input logic Wy
    );

        state expected_next;
        logic expected_Wy;

        if (!rst_n) begin
            expected_state = ROAD_1;
            expected_timer = '0;
        end
        else begin

            expected_next = expected_state;

            case (expected_state)
                ROAD_1: begin
                    if (expected_timer[1])
                        expected_next = ROAD_2;
                end
                ROAD_2: begin
                    if (expected_timer[2])
                        expected_next = ROAD_3;
                end
                ROAD_3: begin
                    if (expected_timer[3])
                        expected_next = ROAD_4;
                end
                ROAD_4: begin
                end

                default: begin
                    expected_next = ROAD_1;
                end

            endcase

            if (expected_state != expected_next)
                expected_timer = '0;
            else if (expected_timer != 5'd31)
                expected_timer = expected_timer + 1'b1;

            expected_state = expected_next;
        end

        expected_Wy = (expected_state == ROAD_4) && expected_timer[4];

        if (Wy !== expected_Wy)
            errors++;

        if (expected_Wy)
            wy_cycles++;

        checked++;
    endfunction

    function void report();

        $display("");
        $display("========== ROAD SCOREBOARD ==========");
        $display("Cycles checked : %0d", checked);
        $display("Passed         : %0d", checked - errors);
        $display("Errors         : %0d", errors);
        $display("Wy high cycles : %0d", wy_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class RoadMonitor;
    virtual road_if vif;
    RoadScoreboard sb;

    function new(
        virtual road_if vif,
        RoadScoreboard sb
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
                vif.Wy
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class RoadDriver;

    virtual road_if vif;

    function new(virtual road_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);

        vif.rst_n = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(RoadTxn tr);
        @(negedge vif.clk);
        vif.rst_n = tr.rst_n;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class RoadGenerator;

    RoadDriver drv;
    int num_txn;

    function new(
        RoadDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        RoadTxn tr;
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
class RoadEnvironment;

    RoadGenerator  gen;
    RoadDriver     drv;
    RoadMonitor    mon;
    RoadScoreboard sb;

    virtual road_if vif;

    function new(
        virtual road_if vif,
        int num_txn = 600
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
module tb_Road;

    localparam int NUM_TXN = 600;
    logic clk = 1'b0;

    always #5 clk = ~clk;

    road_if vif(clk);

    Road dut (
        .clk   (clk),
        .rst_n (vif.rst_n),
        .Wy    (vif.Wy)
    );
    RoadEnvironment env;
    initial begin
        $dumpfile("Road_waveform.vcd");
        $dumpvars(0, tb_Road);
    end

    initial begin
        vif.rst_n = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;

    end
    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end
endmodule //The las line must be empty so Vs Code doesn't give a mistake

