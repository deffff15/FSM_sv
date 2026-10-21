`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [2:0] {
    M_IDLE,
    M_TAKING_ORDER,
    M_WAITING_FOR_PAYMENT,
    M_WAITING_FOR_PICKUP,
    M_CANCELLING_ORDER
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface drive_thru_if (input logic clk);

    logic rst_n;
    logic car_arrived;
    logic order_confirmed;
    logic payment_completed;
    logic food_collected;
    logic car_departed;
    logic speaker_on;
    logic payment_terminal_on;
    logic order_ready;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class DriveThruTxn;

    rand bit rst_n;
    rand bit car_arrived;
    rand bit order_confirmed;
    rand bit payment_completed;
    rand bit food_collected;
    rand bit car_departed;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_car_arrived {
        car_arrived dist {1 := 30, 0 := 70};
    }

    constraint c_order_confirmed {
        order_confirmed dist {1 := 30, 0 := 70};
    }

    constraint c_payment_completed {
        payment_completed dist {1 := 30, 0 := 70};
    }

    constraint c_food_collected {
        food_collected dist {1 := 30, 0 := 70};
    }

    constraint c_car_departed {
        car_departed dist {1 := 10, 0 := 90};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class DriveThruScoreboard;

    model_state_t expected_state = M_IDLE;

    int checked = 0;
    int errors  = 0;
    int idle_cycles       = 0;
    int taking_cycles     = 0;
    int payment_cycles    = 0;
    int pickup_cycles     = 0;
    int cancelling_cycles = 0;

    function void check(
        input logic rst_n,
        input logic car_arrived,
        input logic order_confirmed,
        input logic payment_completed,
        input logic food_collected,
        input logic car_departed,
        input logic speaker_on,
        input logic payment_terminal_on,
        input logic order_ready
    );

        model_state_t next_state;
        logic         expected_speaker_on;
        logic         expected_payment_terminal_on;
        logic         expected_order_ready;
        bit           mismatch;
        if (!rst_n) begin
            expected_state = M_IDLE;
        end
        else begin

            next_state = expected_state;

            case (expected_state)

                M_IDLE: begin
                    if (car_arrived)
                        next_state = M_TAKING_ORDER;
                end

                M_TAKING_ORDER: begin
                    if (car_departed)
                        next_state = M_CANCELLING_ORDER;
                    else if (order_confirmed)
                        next_state = M_WAITING_FOR_PAYMENT;
                end

                M_WAITING_FOR_PAYMENT: begin
                    if (car_departed)
                        next_state = M_CANCELLING_ORDER;
                    else if (payment_completed)
                        next_state = M_WAITING_FOR_PICKUP;
                end

                M_WAITING_FOR_PICKUP: begin
                    if (food_collected)
                        next_state = M_IDLE;
                end

                M_CANCELLING_ORDER: begin
                    next_state = M_IDLE;
                end

                default: begin
                    next_state = M_IDLE;
                end

            endcase

            expected_state = next_state;

        end
        expected_speaker_on          = (expected_state == M_TAKING_ORDER);
        expected_payment_terminal_on = (expected_state == M_WAITING_FOR_PAYMENT);
        expected_order_ready         = (expected_state == M_WAITING_FOR_PICKUP);
        mismatch = 0;

        if (speaker_on !== expected_speaker_on)
            mismatch = 1;

        if (payment_terminal_on !== expected_payment_terminal_on)
            mismatch = 1;

        if (order_ready !== expected_order_ready)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%0d speaker=%b exp=%b terminal=%b exp=%b ready=%b exp=%b",
                         $time, expected_state, speaker_on, expected_speaker_on,
                         payment_terminal_on, expected_payment_terminal_on,
                         order_ready, expected_order_ready);
        end
        case (expected_state)
            M_IDLE:                idle_cycles++;
            M_TAKING_ORDER:        taking_cycles++;
            M_WAITING_FOR_PAYMENT: payment_cycles++;
            M_WAITING_FOR_PICKUP:  pickup_cycles++;
            M_CANCELLING_ORDER:    cancelling_cycles++;
            default: ;
        endcase
        checked++;

    endfunction
    function void report();

        $display("======== DRIVE THRU SCOREBOARD ======");
        $display("Cycles checked       : %0d", checked);
        $display("Passed               : %0d", checked - errors);
        $display("Errors               : %0d", errors);
        $display("IDLE cycles          : %0d", idle_cycles);
        $display("TAKING_ORDER cycles  : %0d", taking_cycles);
        $display("WAIT_PAYMENT cycles  : %0d", payment_cycles);
        $display("WAIT_PICKUP cycles   : %0d", pickup_cycles);
        $display("CANCELLING cycles    : %0d", cancelling_cycles);
        $display("=====================================");

    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class DriveThruMonitor;

    virtual drive_thru_if vif;
    DriveThruScoreboard   sb;
    function new(
        virtual drive_thru_if vif,
        DriveThruScoreboard   sb
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
                vif.car_arrived,
                vif.order_confirmed,
                vif.payment_completed,
                vif.food_collected,
                vif.car_departed,
                vif.speaker_on,
                vif.payment_terminal_on,
                vif.order_ready
            );
        end

    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class DriveThruDriver;

    virtual drive_thru_if vif;
    function new(virtual drive_thru_if vif);
        this.vif = vif;
    endfunction
    task reset();

        @(negedge vif.clk);
        vif.rst_n             = 1'b0;
        vif.car_arrived       = 1'b0;
        vif.order_confirmed   = 1'b0;
        vif.payment_completed = 1'b0;
        vif.food_collected    = 1'b0;
        vif.car_departed      = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask
    task drive(DriveThruTxn tr);
        @(negedge vif.clk);
        vif.rst_n             = tr.rst_n;
        vif.car_arrived       = tr.car_arrived;
        vif.order_confirmed   = tr.order_confirmed;
        vif.payment_completed = tr.payment_completed;
        vif.food_collected    = tr.food_collected;
        vif.car_departed      = tr.car_departed;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class DriveThruGenerator;

    DriveThruDriver drv;
    int num_txn;
    function new(
        DriveThruDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        DriveThruTxn tr;
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
class DriveThruEnvironment;

    DriveThruGenerator  gen;
    DriveThruDriver     drv;
    DriveThruMonitor    mon;
    DriveThruScoreboard sb;
    virtual drive_thru_if vif;

    function new(
        virtual drive_thru_if vif,
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
module tb_DriveThru;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    drive_thru_if vif(clk);

    DriveThru dut (
        .clk                 (clk),
        .rst_n               (vif.rst_n),
        .car_arrived         (vif.car_arrived),
        .order_confirmed     (vif.order_confirmed),
        .payment_completed   (vif.payment_completed),
        .food_collected      (vif.food_collected),
        .car_departed        (vif.car_departed),
        .speaker_on          (vif.speaker_on),
        .payment_terminal_on (vif.payment_terminal_on),
        .order_ready         (vif.order_ready)
    );
    DriveThruEnvironment env;

    initial begin
        $dumpfile("DriveThru_waveform.vcd");
        $dumpvars(0, tb_DriveThru);
    end

    initial begin
        vif.rst_n             = 1'b0;
        vif.car_arrived       = 1'b0;
        vif.order_confirmed   = 1'b0;
        vif.payment_completed = 1'b0;
        vif.food_collected    = 1'b0;
        vif.car_departed      = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;
    end
    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end

endmodule //The last line must be empty so Vscode doesn't give a mistake

