`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic {
    M_EMPTY  = 1'b0,
    M_PARKED = 1'b1
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface parking_if (input logic clk);
    logic       rst_n;
    logic       entered_parking;
    logic       left_parking;
    logic [3:0] payed;
    logic [7:0] time_parked;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class ParkingTxn;
    rand bit rst_n;
    rand bit entered_parking;
    rand bit left_parking;
    constraint c_rst_n {
        rst_n dist {1 := 499, 0 := 1};
    }
    constraint c_entered_parking {
        entered_parking dist {1 := 30, 0 := 70};
    }
    constraint c_left_parking {
        left_parking dist {1 := 1, 0 := 99};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class ParkingScoreboard;
    model_state_t expected_state = M_EMPTY;
    logic [7:0]   expected_time  = 8'd0;
    int checked = 0;
    int errors  = 0;
    int empty_cycles      = 0;
    int parked_cycles     = 0;
    int exits             = 0;
    int exits_short       = 0;
    int exits_long        = 0;
    int saturated_cycles  = 0;

    function void check(
        input logic       rst_n,
        input logic       entered_parking,
        input logic       left_parking,
        input logic [3:0] payed,
        input logic [7:0] time_parked
    );
        model_state_t next_state;
        logic [3:0]   expected_payed;
        logic [7:0]   expected_time_parked;
        bit           mismatch;
        if (!rst_n) begin
            expected_state = M_EMPTY;
            expected_time  = 8'd0;
        end
        expected_payed       = 4'd0;
        expected_time_parked = 8'd0;
        if (expected_state == M_PARKED && left_parking) begin
            expected_time_parked = expected_time;
            if (expected_time > 8'd15)
                expected_payed = 4'd15;
            else
                expected_payed = expected_time[3:0];
        end
        mismatch = 0;
        if (payed !== expected_payed)
            mismatch = 1;
        if (time_parked !== expected_time_parked)
            mismatch = 1;
        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%0d left=%b time=%0d payed=%0d exp=%0d time_parked=%0d exp=%0d",
                         $time, expected_state, left_parking, expected_time,
                         payed, expected_payed, time_parked, expected_time_parked);
        end
        if (expected_state == M_PARKED)
            parked_cycles++;
        else
            empty_cycles++;
        if (expected_state == M_PARKED && expected_time == 8'hFF)
            saturated_cycles++;
        if (expected_state == M_PARKED && left_parking) begin
            exits++;
            if (expected_time > 8'd15)
                exits_long++;
            else
                exits_short++;
        end
        if (rst_n) begin
            next_state = expected_state;
            case (expected_state)
                M_EMPTY: begin
                    if (entered_parking)
                        next_state = M_PARKED;
                end
                M_PARKED: begin
                    if (left_parking)
                        next_state = M_EMPTY;
                end
                default: begin
                    next_state = M_EMPTY;
                end
            endcase
            if (expected_state == M_PARKED && !left_parking) begin
                if (expected_time < 8'hFF)
                    expected_time = expected_time + 1'b1;
            end
            else if (entered_parking) begin
                expected_time = 8'd0;
            end
            expected_state = next_state;
        end
        checked++;
    endfunction
    function void report();
        $display("========= PARKING SCOREBOARD ========");
        $display("Cycles checked     : %0d", checked);
        $display("Passed             : %0d", checked - errors);
        $display("Errors             : %0d", errors);
        $display("EMPTY cycles       : %0d", empty_cycles);
        $display("PARKED cycles      : %0d", parked_cycles);
        $display("Exits              : %0d", exits);
        $display("Exits time <= 15   : %0d", exits_short);
        $display("Exits time > 15    : %0d", exits_long);
        $display("Time saturated 255 : %0d", saturated_cycles);
        $display("=====================================");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class ParkingMonitor;
    virtual parking_if vif;
    ParkingScoreboard  sb;

    function new(
        virtual parking_if vif,
        ParkingScoreboard  sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        forever begin
            @(negedge vif.clk);
            #4;
            sb.check(
                vif.rst_n,
                vif.entered_parking,
                vif.left_parking,
                vif.payed,
                vif.time_parked
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class ParkingDriver;
    virtual parking_if vif;

    function new(virtual parking_if vif);
        this.vif = vif;
    endfunction
    task reset();
        @(negedge vif.clk);
        vif.rst_n           = 1'b0;
        vif.entered_parking = 1'b0;
        vif.left_parking    = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask
    task drive(ParkingTxn tr);
        @(negedge vif.clk);
        vif.rst_n           = tr.rst_n;
        vif.entered_parking = tr.entered_parking;
        vif.left_parking    = tr.left_parking;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class ParkingGenerator;
    ParkingDriver drv;
    int num_txn;

    function new(
        ParkingDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction
    task run();
        ParkingTxn tr;
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
class ParkingEnvironment;
    ParkingGenerator  gen;
    ParkingDriver     drv;
    ParkingMonitor    mon;
    ParkingScoreboard sb;
    virtual parking_if vif;

    function new(
        virtual parking_if vif,
        int num_txn = 20000
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
module tb_ParkingTicket;
    localparam int NUM_TXN = 20000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    parking_if vif(clk);

    ParkingTicket dut (
        .clk             (clk),
        .rst_n           (vif.rst_n),
        .entered_parking (vif.entered_parking),
        .left_parking    (vif.left_parking),
        .payed           (vif.payed),
        .time_parked     (vif.time_parked)
    );
    ParkingEnvironment env;

    initial begin
        $dumpfile("ParkingTicket_waveform.vcd");
        $dumpvars(0, tb_ParkingTicket);
    end

    initial begin
        vif.rst_n           = 1'b0;
        vif.entered_parking = 1'b0;
        vif.left_parking    = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "TIMEOUT");
    end
endmodule //The last line must be empty so vscode doesn't give a mistake

