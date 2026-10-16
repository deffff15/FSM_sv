`timescale 1ns / 1ps
import Destroyer::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface wall_if #(parameter int THICKNESS = 5) (input logic clk);

    logic rst_n;
    logic enable;
    logic Destroyed;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class WallTxn;

    rand bit enable;

    constraint c_enable {
        enable dist {1 := 80, 0 := 20};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class WallScoreboard #(parameter int THICKNESS = 5);

    layers expected_state = LAYER_1;
    logic [THICKNESS-1:0] expected_wall = '0;

    int checked = 0;
    int errors  = 0;

    function void check(
        input logic rst_n,
        input logic enable,
        input logic Destroyed
    );
        logic expected_destroyed;

        if (!rst_n) begin
            expected_state = LAYER_1;
            expected_wall  = '0;
        end
        else if (enable) begin

            case (expected_state)
                LAYER_1: expected_state = LAYER_2;

                LAYER_2: expected_state = LAYER_3;

                LAYER_3: expected_state = LAYER_4;

                LAYER_4: begin
                    if (expected_wall[THICKNESS-1]) begin
                        expected_state = DESTROYED;
                    end
                    else begin
                        expected_wall  = {expected_wall[THICKNESS-2:0], 1'b1};
                        expected_state = LAYER_1;
                    end
                end
                DESTROYED: expected_state = DESTROYED;

                default: begin
                    expected_state = LAYER_1;
                    expected_wall  = '0;
                end
            endcase
        end

        expected_destroyed = (expected_state == DESTROYED);

        if (Destroyed !== expected_destroyed)
            errors++;

        checked++;

    endfunction

    function void reset();
        expected_state = LAYER_1;
        expected_wall  = '0;
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class WallMonitor #(parameter int THICKNESS = 5);

    virtual wall_if #(THICKNESS) vif;
    WallScoreboard #(THICKNESS) sb;

    function new(
        virtual wall_if #(THICKNESS) vif,
        WallScoreboard #(THICKNESS) sb
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
                vif.Destroyed
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class WallDriver #(parameter int THICKNESS = 5);

    virtual wall_if #(THICKNESS) vif;

    function new(virtual wall_if #(THICKNESS) vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);

        vif.rst_n  = 1'b0;
        vif.enable = 1'b0;

        repeat (2) @(negedge vif.clk);

        vif.rst_n = 1'b1;
    endtask

    task drive(WallTxn tr);

        @(negedge vif.clk);

        vif.enable = tr.enable;

    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class WallGenerator #(parameter int THICKNESS = 5);

    WallDriver #(THICKNESS) drv;
    int num_txn;

    function new(
        WallDriver #(THICKNESS) drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        WallTxn tr;

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
class WallEnvironment #(parameter int THICKNESS = 5);

    WallGenerator  #(THICKNESS) gen;
    WallDriver     #(THICKNESS) drv;
    WallMonitor    #(THICKNESS) mon;
    WallScoreboard #(THICKNESS) sb;

    virtual wall_if #(THICKNESS) vif;

    function new(
        virtual wall_if #(THICKNESS) vif,
        int num_txn = 150
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

        if (sb.errors != 0)
            $fatal(1);
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_Wall;

    localparam int THICKNESS = 5;
    localparam int NUM_TXN   = 150;

    logic clk = 1'b0;

    always #5 clk = ~clk;

    wall_if #(THICKNESS) vif(clk);

    Wall #(
        .THICKNESS(THICKNESS)
    ) dut (
        .clk       (clk),
        .rst_n     (vif.rst_n),
        .enable    (vif.enable),
        .Destroyed (vif.Destroyed)
    );

    WallEnvironment #(THICKNESS) env;

    initial begin
        $dumpfile("Wall_waveform.vcd");
        $dumpvars(0, tb_Wall);
    end

    initial begin

        vif.rst_n  = 1'b0;
        vif.enable = 1'b0;

        env = new(vif, NUM_TXN);

        env.drv.reset();

        env.run();

        $finish;
    end
    initial begin
        #1ms;
        $fatal(1);
    end
endmodule //The last line must be empty so VS code doesn't give a endmodule

