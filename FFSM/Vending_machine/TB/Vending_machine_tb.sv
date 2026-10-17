`timescale 1ns / 1ps
import VendingMachinePkg::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface vending_if (input logic clk);

    logic       rst_n;
    logic       coin_1_pln;
    logic       coin_2_pln;
    logic       cancel;
    logic       dispense_drink;
    logic [1:0] refund_amount;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class VendingTxn;

    rand bit rst_n;
    rand bit coin_1_pln;
    rand bit coin_2_pln;
    rand bit cancel;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_coin_1_pln {
        coin_1_pln dist {1 := 25, 0 := 75};
    }

    constraint c_coin_2_pln {
        coin_2_pln dist {1 := 15, 0 := 85};
    }

    constraint c_cancel {
        cancel dist {1 := 10, 0 := 90};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class VendingScoreboard;

    vending_state_t expected_state = IDLE;

    int checked = 0;
    int errors  = 0;

    int idle_cycles       = 0;
    int credit_1_cycles   = 0;
    int credit_2_cycles   = 0;
    int dispensing_cycles = 0;
    int refund_1_cycles   = 0;
    int refund_2_cycles   = 0;

    function void check(
        input logic       rst_n,
        input logic       coin_1_pln,
        input logic       coin_2_pln,
        input logic       cancel,
        input logic       dispense_drink,
        input logic [1:0] refund_amount
    );
        vending_state_t next_state;
        logic           expected_dispense;
        logic [1:0]     expected_refund;
        bit             mismatch;

        if (!rst_n) begin
            expected_state = IDLE;
        end
        else begin

            next_state = expected_state;

            case (expected_state)

                IDLE: begin
                    if (coin_1_pln)
                        next_state = CREDIT_1;
                    else if (coin_2_pln)
                        next_state = CREDIT_2;
                end

                CREDIT_1: begin
                    if (cancel)
                        next_state = IDLE;
                    else if (coin_1_pln)
                        next_state = CREDIT_2;
                    else if (coin_2_pln)
                        next_state = DISPENSING;
                end

                CREDIT_2: begin
                    if (cancel)
                        next_state = IDLE;
                    else if (coin_1_pln || coin_2_pln)
                        next_state = DISPENSING;
                end

                DISPENSING: begin
                    next_state = IDLE;
                end

                default: begin
                    next_state = IDLE;
                end

            endcase

            expected_state = next_state;

        end
        expected_dispense = 1'b0;
        expected_refund   = 2'd0;

        case (expected_state)

            CREDIT_1: begin
                if (cancel)
                    expected_refund = 2'd1;
            end

            CREDIT_2: begin
                if (cancel)
                    expected_refund = 2'd2;
            end

            DISPENSING: begin
                expected_dispense = 1'b1;
            end

            default: ;

        endcase
        mismatch = 0;

        if (dispense_drink !== expected_dispense)
            mismatch = 1;

        if (refund_amount !== expected_refund)
            mismatch = 1;

        if (mismatch)
            errors++;

        case (expected_state)
            IDLE:       idle_cycles++;
            CREDIT_1:   credit_1_cycles++;
            CREDIT_2:   credit_2_cycles++;
            DISPENSING: dispensing_cycles++;
            default: ;
        endcase

        if (expected_refund == 2'd1)
            refund_1_cycles++;

        if (expected_refund == 2'd2)
            refund_2_cycles++;

        checked++;
        
    endfunction

    function void report();

        $display("");
        $display("========= VENDING SCOREBOARD ========");
        $display("Cycles checked    : %0d", checked);
        $display("Passed            : %0d", checked - errors);
        $display("Errors            : %0d", errors);
        $display("IDLE cycles       : %0d", idle_cycles);
        $display("CREDIT_1 cycles   : %0d", credit_1_cycles);
        $display("CREDIT_2 cycles   : %0d", credit_2_cycles);
        $display("DISPENSING cycles : %0d", dispensing_cycles);
        $display("Refund 1 PLN      : %0d", refund_1_cycles);
        $display("Refund 2 PLN      : %0d", refund_2_cycles);
        $display("=====================================");

    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class VendingMonitor;

    virtual vending_if vif;
    VendingScoreboard  sb;

    function new(
        virtual vending_if vif,
        VendingScoreboard  sb
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
                vif.coin_1_pln,
                vif.coin_2_pln,
                vif.cancel,
                vif.dispense_drink,
                vif.refund_amount
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class VendingDriver;

    virtual vending_if vif;

    function new(virtual vending_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);

        vif.rst_n      = 1'b0;
        vif.coin_1_pln = 1'b0;
        vif.coin_2_pln = 1'b0;
        vif.cancel     = 1'b0;
        repeat (2) @(negedge vif.clk);

        vif.rst_n = 1'b1;

    endtask

    task drive(VendingTxn tr);

        @(negedge vif.clk);

        vif.rst_n      = tr.rst_n;
        vif.coin_1_pln = tr.coin_1_pln;
        vif.coin_2_pln = tr.coin_2_pln;
        vif.cancel     = tr.cancel;

    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class VendingGenerator;

    VendingDriver drv;
    int num_txn;

    function new(
        VendingDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        VendingTxn tr;

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
class VendingEnvironment;

    VendingGenerator  gen;
    VendingDriver     drv;
    VendingMonitor    mon;
    VendingScoreboard sb;

    virtual vending_if vif;

    function new(
        virtual vending_if vif,
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
module tb_VendingMachine;

    localparam int NUM_TXN = 2000;

    logic clk = 1'b0;

    always #5 clk = ~clk;

    vending_if vif(clk);

    VendingMachine dut (
        .clk            (clk),
        .rst_n          (vif.rst_n),
        .coin_1_pln     (vif.coin_1_pln),
        .coin_2_pln     (vif.coin_2_pln),
        .cancel         (vif.cancel),
        .dispense_drink (vif.dispense_drink),
        .refund_amount  (vif.refund_amount)
    );
    VendingEnvironment env;

    initial begin
        $dumpfile("VendingMachine_waveform.vcd");
        $dumpvars(0, tb_VendingMachine);
    end

    initial begin

        vif.rst_n      = 1'b0;
        vif.coin_1_pln = 1'b0;
        vif.coin_2_pln = 1'b0;
        vif.cancel     = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end
    
endmodule //The line must be empty so Vs Code doesn't give a mistake

