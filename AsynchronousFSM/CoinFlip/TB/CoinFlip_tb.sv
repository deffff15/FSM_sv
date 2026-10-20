`timescale 1ns / 1ps
import CoinPackage::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface coin_if (input logic clk);

    logic       rst_n;
    logic       enable;
    logic       wind;
    logic       throw_force;
    logic [3:0] Wy;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class CoinTxn;

    rand bit rst_n;
    rand bit toggle_enable;
    rand bit wind;
    rand bit throw_force;
    bit      enable;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_toggle_enable {
        toggle_enable dist {1 := 20, 0 := 80};
    }

    constraint c_wind {
        wind dist {1 := 50, 0 := 50};
    }

    constraint c_throw_force {
        throw_force dist {1 := 50, 0 := 50};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class CoinScoreboard;

    coin_state_t expected_state  = ST_IDLE;
    logic [1:0]  expected_random = 2'b00;
    int checked = 0;
    int errors  = 0;
    int idle_cycles     = 0;
    int spinning_cycles = 0;
    int result_cycles   = 0;
    int result_1110     = 0;
    int result_1111     = 0;

    function void check(
        input logic       rst_n,
        input logic       enable,
        input logic       wind,
        input logic       throw_force,
        input logic [3:0] Wy
    );

        coin_state_t next_state;
        logic [1:0]  next_random;
        logic [3:0]  expected_Wy;
        bit          mismatch;
        if (!rst_n) begin
            expected_state  = ST_IDLE;
            expected_random = 2'b00;
        end
        else begin

            next_state  = expected_state;
            next_random = expected_random + {wind, throw_force} + 2'b01;

            case (expected_state)

                ST_IDLE: begin
                    if (enable)
                        next_state = ST_SPINNING;
                end

                ST_SPINNING: begin
                    if (!enable)
                        next_state = ST_RESULT;
                end

                ST_RESULT: begin
                    if (enable)
                        next_state = ST_SPINNING;
                end

                default: begin
                    next_state = ST_IDLE;
                end

            endcase

            expected_state  = next_state;
            expected_random = next_random;

        end
        case (expected_state)

            ST_IDLE: begin
                expected_Wy = 4'b0001;
            end

            ST_SPINNING: begin
                expected_Wy = {2'b01, expected_random};
            end

            ST_RESULT: begin
                expected_Wy = expected_random[0] ? 4'b1110 : 4'b1111;
            end

            default: begin
                expected_Wy = 4'b0001;
            end

        endcase

        mismatch = 0;

        if (Wy !== expected_Wy)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%0d random=%b Wy=%b expected=%b",
                         $time, expected_state, expected_random, Wy, expected_Wy);
        end

        case (expected_state)
            ST_IDLE:     idle_cycles++;
            ST_SPINNING: spinning_cycles++;
            ST_RESULT:   result_cycles++;
            default: ;
        endcase

        if (expected_state == ST_RESULT) begin
            if (expected_Wy == 4'b1110)
                result_1110++;
            else
                result_1111++;
        end

        checked++;

    endfunction
    function void report();
        $display("========== COIN SCOREBOARD ==========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("IDLE cycles       : %0d", idle_cycles);
        $display("SPINNING cycles   : %0d", spinning_cycles);
        $display("RESULT cycles     : %0d", result_cycles);
        $display("Result 1110       : %0d", result_1110);
        $display("Result 1111       : %0d", result_1111);
        $display("=====================================");
    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class CoinMonitor;

    virtual coin_if vif;
    CoinScoreboard  sb;

    function new(
        virtual coin_if vif,
        CoinScoreboard  sb
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
                vif.wind,
                vif.throw_force,
                vif.Wy
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class CoinDriver;

    virtual coin_if vif;
    function new(virtual coin_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n       = 1'b0;
        vif.enable      = 1'b0;
        vif.wind        = 1'b0;
        vif.throw_force = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(CoinTxn tr);
        @(negedge vif.clk);
        vif.rst_n       = tr.rst_n;
        vif.enable      = tr.enable;
        vif.wind        = tr.wind;
        vif.throw_force = tr.throw_force;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class CoinGenerator;

    CoinDriver drv;
    int num_txn;
    bit level = 1'b0;

    function new(
        CoinDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        CoinTxn tr;
        repeat (num_txn) begin

            tr = new();
            if (!tr.randomize())
                $fatal(1);
            level     = level ^ tr.toggle_enable;
            tr.enable = level;
            drv.drive(tr);

        end
    endtask

endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class CoinEnvironment;

    CoinGenerator  gen;
    CoinDriver     drv;
    CoinMonitor    mon;
    CoinScoreboard sb;
    virtual coin_if vif;

    function new(
        virtual coin_if vif,
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
module tb_CoinFlip;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    coin_if vif(clk);

    CoinFlip dut (
        .rst_n       (vif.rst_n),
        .clk         (clk),
        .enable      (vif.enable),
        .wind        (vif.wind),
        .throw_force (vif.throw_force),
        .Wy          (vif.Wy)
    );
    CoinEnvironment env;

    initial begin
        $dumpfile("CoinFlip_waveform.vcd");
        $dumpvars(0, tb_CoinFlip);
    end

    initial begin

        vif.rst_n       = 1'b0;
        vif.enable      = 1'b0;
        vif.wind        = 1'b0;
        vif.throw_force = 1'b0;
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

