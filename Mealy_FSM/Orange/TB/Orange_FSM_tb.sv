`timescale 1ns/1ps
import Pomarancza_pkg::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface pomarancza_if (input logic clk);
    logic       rst_n;
    logic [1:0] maturity;
    logic [1:0] color;
    logic [1:0] taste;
    logic [2:0] who_can_eat;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, maturity, color, taste, who_can_eat;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class PomaranczaTxn;
    rand bit [1:0] maturity;
    rand bit [1:0] color;
    rand bit [1:0] taste;
    logic [2:0]    who_can_eat;

    constraint c_maturity {
        maturity dist {2'b00 := 13, 2'b01 := 60, 2'b10 := 13, 2'b11 := 14};
    }

    constraint c_color {
        color dist {2'b00 := 13, 2'b01 := 60, 2'b10 := 13, 2'b11 := 14};
    }

    constraint c_taste {
        taste dist {2'b00 := 40, 2'b01 := 40, 2'b10 := 10, 2'b11 := 10};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class PomaranczaScoreboard;
    stan state = CHECK;

    int checked     = 0;
    int errors      = 0;
    int check_cnt   = 0;
    int good_cnt    = 0;
    int sour_cnt    = 0;
    int bad_cnt     = 0;

    function void check(PomaranczaTxn tr);
        logic [2:0] expected;
        bit ok      = 1;
        bit good_in = (tr.maturity == 2'b01 && tr.color == 2'b01 && tr.taste == 2'b01);
        bit sour_in = (tr.maturity == 2'b01 && tr.color == 2'b01 && tr.taste == 2'b00);
        bit bad_in  = (tr.maturity != 2'b01 || tr.color != 2'b01 || tr.taste == 2'b10);

        case (state)
            GOOD:    expected = 3'b111;
            SOUR:    expected = 3'b110;
            default: expected = 3'b000;
        endcase

        if (tr.who_can_eat !== expected) begin
            $error("[SB] who_can_eat mismatch @ %0t (state %s): got %b, expected %b",
                   $time, state.name(), tr.who_can_eat, expected);
            ok = 0;
        end

        case (state)
            CHECK: check_cnt++;
            GOOD:  good_cnt++;
            SOUR:  sour_cnt++;
            BAD:   bad_cnt++;
        endcase

        case (state)
            CHECK:   state = good_in ? GOOD : sour_in ? SOUR : BAD;
            GOOD:    state = good_in ? GOOD : CHECK;
            SOUR:    state = sour_in ? SOUR : CHECK;
            BAD:     state = bad_in  ? BAD  : CHECK;
            default: state = CHECK;
        endcase

        checked++;

        if (!ok)
            errors++;
    endfunction

    function void reset();
        state = CHECK;
    endfunction

    function void report();
        $display("---------- Pomarancza scoreboard -----------");
        $display("cycles checked : %0d", checked);
        $display("errors         : %0d", errors);
        $display("cycles in CHECK: %0d", check_cnt);
        $display("cycles in GOOD : %0d", good_cnt);
        $display("cycles in SOUR : %0d", sour_cnt);
        $display("cycles in BAD  : %0d", bad_cnt);
        $display("--------------------------------------------");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class PomaranczaMonitor;
    virtual pomarancza_if vif;
    PomaranczaScoreboard sb;

    function new(
        virtual pomarancza_if vif,
        PomaranczaScoreboard sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        PomaranczaTxn tr;

        forever begin
            @(vif.mon_cb);

            if (!vif.mon_cb.rst_n) begin
                sb.reset();
            end
            else begin
                tr = new();
                tr.maturity    = vif.mon_cb.maturity;
                tr.color       = vif.mon_cb.color;
                tr.taste       = vif.mon_cb.taste;
                tr.who_can_eat = vif.mon_cb.who_can_eat;

                sb.check(tr);
            end
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class PomaranczaDriver;
    virtual pomarancza_if vif;

    function new(virtual pomarancza_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n    <= 1'b0;
        vif.maturity <= 2'b00;
        vif.color    <= 2'b00;
        vif.taste    <= 2'b00;

        repeat (2) @(negedge vif.clk);
        vif.rst_n <= 1'b1;
    endtask

    task drive(PomaranczaTxn tr);
        @(negedge vif.clk);
        vif.maturity <= tr.maturity;
        vif.color    <= tr.color;
        vif.taste    <= tr.taste;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class PomaranczaGenerator;
    PomaranczaDriver drv;
    int num_txn;

    function new(PomaranczaDriver drv, int num_txn);
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task send(bit [1:0] m, bit [1:0] c, bit [1:0] t);
        PomaranczaTxn tr;

        tr = new();
        tr.maturity = m;
        tr.color    = c;
        tr.taste    = t;

        drv.drive(tr);
    endtask

    task run();
        PomaranczaTxn tr;

        send(2'b01, 2'b01, 2'b01);
        send(2'b01, 2'b01, 2'b01);
        send(2'b01, 2'b01, 2'b01);
        send(2'b00, 2'b00, 2'b00);

        send(2'b01, 2'b01, 2'b00);
        send(2'b01, 2'b01, 2'b00);
        send(2'b01, 2'b01, 2'b00);
        send(2'b10, 2'b01, 2'b00);

        send(2'b11, 2'b11, 2'b11);
        send(2'b00, 2'b01, 2'b01);
        send(2'b01, 2'b01, 2'b10);
        send(2'b01, 2'b01, 2'b01);
        send(2'b01, 2'b01, 2'b01);

        send(2'b01, 2'b01, 2'b01);
        drv.reset();

        repeat (num_txn) begin
            tr = new();

            if (!tr.randomize())
                $fatal(1, "[GEN] Randomization failed");

            drv.drive(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class PomaranczaEnvironment;
    PomaranczaGenerator  gen;
    PomaranczaDriver     drv;
    PomaranczaMonitor    mon;
    PomaranczaScoreboard sb;

    virtual pomarancza_if vif;

    function new(
        virtual pomarancza_if vif,
        int num_txn = 200
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

        drv.reset();
        gen.run();

        repeat (2) @(posedge vif.clk);
        #2;
        sb.report();

        if (sb.errors != 0)
            $fatal(1, "[ENV] TEST FAILED (%0d errors)", sb.errors);
        else
            $display("[ENV] TEST PASSED");
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_pomarancza;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    pomarancza_if vif(clk);

    Pomarancza dut (
        .clk         (clk),
        .rst_n       (vif.rst_n),
        .maturity    (vif.maturity),
        .color       (vif.color),
        .taste       (vif.taste),
        .who_can_eat (vif.who_can_eat)
    );

    PomaranczaEnvironment env;

    initial begin
        $dumpfile("pomarancza_waveform.vcd");
        $dumpvars(0, tb_pomarancza);
    end

    initial begin
        vif.rst_n    = 1'b0;
        vif.maturity = 2'b00;
        vif.color    = 2'b00;
        vif.taste    = 2'b00;

        env = new(vif, 200);
        env.run();

        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "[TB] Timeout");
    end

endmodule // Last line must be empty so VS Code doesn't give a mistake

