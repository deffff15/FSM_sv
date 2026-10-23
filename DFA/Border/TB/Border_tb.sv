`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [2:0] {
    M_IDLE           = 3'b000,
    M_CHECK_PASSPORT = 3'b001,
    M_SCAN_BAGGAGE   = 3'b010,
    M_APPROVED       = 3'b011,
    M_DENIED         = 3'b100,
    M_ARRESTED       = 3'b101
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface border_if (input logic clk);
    logic rst_n;
    logic passenger_arrived_i;
    logic has_passport_i;
    logic has_contraband_i;
    logic has_weapons_i;
    logic allow_entry_o;
    logic deny_entry_o;
    logic arrest_o;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class BorderTxn;
    rand bit rst_n;
    rand bit passenger_arrived_i;
    rand bit has_passport_i;
    rand bit has_contraband_i;
    rand bit has_weapons_i;
    constraint c_rst_n {
        rst_n dist {1 := 199, 0 := 1};
    }
    constraint c_passenger_arrived_i {
        passenger_arrived_i dist {1 := 40, 0 := 60};
    }
    constraint c_has_passport_i {
        has_passport_i dist {1 := 80, 0 := 20};
    }
    constraint c_has_contraband_i {
        has_contraband_i dist {1 := 15, 0 := 85};
    }
    constraint c_has_weapons_i {
        has_weapons_i dist {1 := 10, 0 := 90};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class BorderScoreboard;
    model_state_t expected_state = M_IDLE;
    int checked = 0;
    int errors  = 0;

    function void check(
        input logic rst_n,
        input logic passenger_arrived_i,
        input logic has_passport_i,
        input logic has_contraband_i,
        input logic has_weapons_i,
        input logic allow_entry_o,
        input logic deny_entry_o,
        input logic arrest_o
    );
        model_state_t next_state;
        logic         expected_allow_entry;
        logic         expected_deny_entry;
        logic         expected_arrest;
        bit           mismatch;
        if (!rst_n) begin
            expected_state = M_IDLE;
        end
        else begin
            next_state = expected_state;
            case (expected_state)
                M_IDLE: begin
                    if (passenger_arrived_i)
                        next_state = M_CHECK_PASSPORT;
                end
                M_CHECK_PASSPORT: begin
                    if (has_weapons_i)
                        next_state = M_ARRESTED;
                    else if (!has_passport_i)
                        next_state = M_DENIED;
                    else
                        next_state = M_SCAN_BAGGAGE;
                end
                M_SCAN_BAGGAGE: begin
                    if (has_weapons_i || has_contraband_i)
                        next_state = M_ARRESTED;
                    else
                        next_state = M_APPROVED;
                end
                M_APPROVED, M_DENIED, M_ARRESTED: begin
                    next_state = M_IDLE;
                end
                default: begin
                    next_state = M_IDLE;
                end
            endcase
            expected_state = next_state;
        end
        expected_allow_entry = (expected_state == M_APPROVED);
        expected_deny_entry  = (expected_state == M_DENIED);
        expected_arrest      = (expected_state == M_ARRESTED);
        mismatch = 0;
        if (allow_entry_o !== expected_allow_entry)
            mismatch = 1;
        if (deny_entry_o !== expected_deny_entry)
            mismatch = 1;
        if (arrest_o !== expected_arrest)
            mismatch = 1;
        if (mismatch)
            errors++;
        checked++;
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class BorderMonitor;
    virtual border_if vif;
    BorderScoreboard  sb;

    function new(
        virtual border_if vif,
        BorderScoreboard  sb
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
                vif.passenger_arrived_i,
                vif.has_passport_i,
                vif.has_contraband_i,
                vif.has_weapons_i,
                vif.allow_entry_o,
                vif.deny_entry_o,
                vif.arrest_o
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class BorderDriver;
    virtual border_if vif;

    function new(virtual border_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n               = 1'b0;
        vif.passenger_arrived_i = 1'b0;
        vif.has_passport_i      = 1'b0;
        vif.has_contraband_i    = 1'b0;
        vif.has_weapons_i       = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(BorderTxn tr);
        @(negedge vif.clk);
        vif.rst_n               = tr.rst_n;
        vif.passenger_arrived_i = tr.passenger_arrived_i;
        vif.has_passport_i      = tr.has_passport_i;
        vif.has_contraband_i    = tr.has_contraband_i;
        vif.has_weapons_i       = tr.has_weapons_i;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class BorderGenerator;
    BorderDriver drv;
    int num_txn;

    function new(
        BorderDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        BorderTxn tr;
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
class BorderEnvironment;
    BorderGenerator  gen;
    BorderDriver     drv;
    BorderMonitor    mon;
    BorderScoreboard sb;
    virtual border_if vif;

    function new(
        virtual border_if vif,
        int num_txn = 30000
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
module tb_Border;
    localparam int NUM_TXN = 30000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    border_if vif(clk);

    Border dut (
        .clk                 (clk),
        .rst_n               (vif.rst_n),
        .passenger_arrived_i (vif.passenger_arrived_i),
        .has_passport_i      (vif.has_passport_i),
        .has_contraband_i    (vif.has_contraband_i),
        .has_weapons_i       (vif.has_weapons_i),
        .allow_entry_o       (vif.allow_entry_o),
        .deny_entry_o        (vif.deny_entry_o),
        .arrest_o            (vif.arrest_o)
    );
    BorderEnvironment env;

    initial begin
        $dumpfile("Border_waveform.vcd");
        $dumpvars(0, tb_Border);
    end

    initial begin
        vif.rst_n               = 1'b0;
        vif.passenger_arrived_i = 1'b0;
        vif.has_passport_i      = 1'b0;
        vif.has_contraband_i    = 1'b0;
        vif.has_weapons_i       = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1);
    end
endmodule //The last line must be empty so vs code doesn't give a mistake

