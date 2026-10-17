`timescale 1ns / 1ps
import Sumo_pkg::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface sumo_if (input logic clk);

    logic         rst_n;
    logic         start_cmd;
    logic         stop_cmd;
    logic         opponent_seen;
    logic         edge_seen;
    main_state_t  main_state;
    fight_state_t fight_state;
    logic [1:0]   left_motor;
    logic [1:0]   right_motor;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class SumoTxn;

    rand bit rst_n;
    rand bit start_cmd;
    rand bit stop_cmd;
    rand bit opponent_seen;
    rand bit edge_seen;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_start_cmd {
        start_cmd dist {1 := 20, 0 := 80};
    }

    constraint c_stop_cmd {
        stop_cmd dist {1 := 5, 0 := 95};
    }

    constraint c_opponent_seen {
        opponent_seen dist {1 := 50, 0 := 50};
    }

    constraint c_edge_seen {
        edge_seen dist {1 := 15, 0 := 85};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class SumoScoreboard;

    main_state_t  expected_main  = START;
    fight_state_t expected_fight = SEARCH;

    int checked = 0;
    int errors  = 0;

    int start_cycles  = 0;
    int fight_cycles  = 0;
    int stop_cycles   = 0;
    int search_cycles = 0;
    int attack_cycles = 0;
    int evade_cycles  = 0;

    function void check(
        input logic         rst_n,
        input logic         start_cmd,
        input logic         stop_cmd,
        input logic         opponent_seen,
        input logic         edge_seen,
        input main_state_t  main_state,
        input fight_state_t fight_state,
        input logic [1:0]   left_motor,
        input logic [1:0]   right_motor
    );

        main_state_t  main_next;
        fight_state_t fight_next;
        fight_state_t expected_fight_state;
        logic [1:0]   expected_left;
        logic [1:0]   expected_right;
        bit           mismatch;

        if (!rst_n) begin
            expected_main  = START;
            expected_fight = SEARCH;
        end
        else begin
            main_next = expected_main;

            case (expected_main)

                START: begin
                    if (start_cmd)
                        main_next = FIGHT;
                end

                FIGHT: begin
                    if (stop_cmd)
                        main_next = STOP;
                end

                STOP: begin
                    if (start_cmd)
                        main_next = FIGHT;
                end

                default: main_next = START;
            endcase

            if (expected_main != FIGHT) begin
                fight_next = SEARCH;
            end
            else begin

                fight_next = expected_fight;

                case (expected_fight)

                    SEARCH: begin
                        if (edge_seen)
                            fight_next = EVADE;
                        else if (opponent_seen)
                            fight_next = ATTACK;
                    end

                    ATTACK: begin
                        if (edge_seen)
                            fight_next = EVADE;
                        else if (!opponent_seen)
                            fight_next = SEARCH;
                    end

                    EVADE: begin
                        if (!edge_seen)
                            fight_next = SEARCH;
                    end

                    default: fight_next = SEARCH;

                endcase
            end
            expected_main  = main_next;
            expected_fight = fight_next;
        end
        expected_fight_state = (expected_main == FIGHT) ? expected_fight : SEARCH;
        expected_left  = 2'b00;
        expected_right = 2'b00;

        if (expected_main == FIGHT) begin

            case (expected_fight)

                SEARCH: begin
                    expected_left  = 2'b01;
                    expected_right = 2'b10;
                end

                ATTACK: begin
                    expected_left  = 2'b01;
                    expected_right = 2'b01;
                end

                EVADE: begin
                    expected_left  = 2'b10;
                    expected_right = 2'b10;
                end

                default: begin
                    expected_left  = 2'b00;
                    expected_right = 2'b00;
                end

            endcase
        end
        mismatch = 0;
        if (main_state !== expected_main)
            mismatch = 1;

        if (fight_state !== expected_fight_state)
            mismatch = 1;

        if (left_motor !== expected_left)
            mismatch = 1;

        if (right_motor !== expected_right)
            mismatch = 1;

        if (mismatch)
            errors++;

        case (expected_main)
            START: start_cycles++;
            FIGHT: fight_cycles++;
            STOP:  stop_cycles++;
            default: ;
        endcase

        if (expected_main == FIGHT) begin
            case (expected_fight)
                SEARCH: search_cycles++;
                ATTACK: attack_cycles++;
                EVADE:  evade_cycles++;
                default: ;
            endcase
        end
        checked++;
    endfunction

    function void report();

        $display("");
        $display("========== SUMO SCOREBOARD ==========");
        $display("Cycles checked : %0d", checked);
        $display("Passed         : %0d", checked - errors);
        $display("Errors         : %0d", errors);
        $display("START cycles   : %0d", start_cycles);
        $display("FIGHT cycles   : %0d", fight_cycles);
        $display("STOP cycles    : %0d", stop_cycles);
        $display("SEARCH cycles  : %0d", search_cycles);
        $display("ATTACK cycles  : %0d", attack_cycles);
        $display("EVADE cycles   : %0d", evade_cycles);
        $display("=====================================");

    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class SumoMonitor;

    virtual sumo_if vif;
    SumoScoreboard  sb;

    function new(
        virtual sumo_if vif,
        SumoScoreboard  sb
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
                vif.start_cmd,
                vif.stop_cmd,
                vif.opponent_seen,
                vif.edge_seen,
                vif.main_state,
                vif.fight_state,
                vif.left_motor,
                vif.right_motor
            );
        end

    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class SumoDriver;

    virtual sumo_if vif;
    function new(virtual sumo_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n         = 1'b0;
        vif.start_cmd     = 1'b0;
        vif.stop_cmd      = 1'b0;
        vif.opponent_seen = 1'b0;
        vif.edge_seen     = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(SumoTxn tr);

        @(negedge vif.clk);
        vif.rst_n         = tr.rst_n;
        vif.start_cmd     = tr.start_cmd;
        vif.stop_cmd      = tr.stop_cmd;
        vif.opponent_seen = tr.opponent_seen;
        vif.edge_seen     = tr.edge_seen;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class SumoGenerator;

    SumoDriver drv;
    int num_txn;

    function new(
        SumoDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        SumoTxn tr;
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
class SumoEnvironment;

    SumoGenerator  gen;
    SumoDriver     drv;
    SumoMonitor    mon;
    SumoScoreboard sb;
    virtual sumo_if vif;

    function new(
        virtual sumo_if vif,
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
module tb_Sumo;

    localparam int NUM_TXN = 2000;

    logic clk = 1'b0;

    always #5 clk = ~clk;

    sumo_if vif(clk);

    SumoFighter dut (
        .clk           (clk),
        .rst_n         (vif.rst_n),
        .start_cmd     (vif.start_cmd),
        .stop_cmd      (vif.stop_cmd),
        .opponent_seen (vif.opponent_seen),
        .edge_seen     (vif.edge_seen),
        .main_state    (vif.main_state),
        .fight_state   (vif.fight_state),
        .left_motor    (vif.left_motor),
        .right_motor   (vif.right_motor)
    );

    SumoEnvironment env;

    initial begin
        $dumpfile("Sumo_waveform.vcd");
        $dumpvars(0, tb_Sumo);
    end

    initial begin

        vif.rst_n         = 1'b0;
        vif.start_cmd     = 1'b0;
        vif.stop_cmd      = 1'b0;
        vif.opponent_seen = 1'b0;
        vif.edge_seen     = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;

    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end
endmodule //The last line must be empty so Vs Code doesn't give a mistake

