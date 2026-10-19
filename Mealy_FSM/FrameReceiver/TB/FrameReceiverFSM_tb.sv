`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE,
    M_READ_DATA,
    M_CHECK_STOP
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface frame_if (input logic clk);

    logic rst_n;
    logic frame_valid;
    logic data_bit;
    logic rx_done;
    logic error_flag;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class FrameTxn;

    rand bit rst_n;
    rand bit toggle_valid;
    rand bit data_bit;
    bit      frame_valid;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_toggle_valid {
        toggle_valid dist {1 := 25, 0 := 75};
    }

    constraint c_data_bit {
        data_bit dist {1 := 50, 0 := 50};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class FrameScoreboard;

    model_state_t expected_state      = M_IDLE;
    logic         expected_rx_done    = 1'b0;
    logic         expected_error_flag = 1'b0;
    int checked = 0;
    int errors  = 0;
    int idle_cycles       = 0;
    int read_data_cycles  = 0;
    int check_stop_cycles = 0;
    int rx_done_cycles    = 0;
    int error_flag_cycles = 0;

    function void check(
        input logic rst_n,
        input logic frame_valid,
        input logic data_bit,
        input logic rx_done,
        input logic error_flag
    );

        model_state_t next_state;
        logic         rx_done_next;
        logic         error_flag_next;
        bit           mismatch;
        if (!rst_n) begin
            expected_state      = M_IDLE;
            expected_rx_done    = 1'b0;
            expected_error_flag = 1'b0;
        end
        else begin

            next_state      = expected_state;
            rx_done_next    = 1'b0;
            error_flag_next = 1'b0;

            case (expected_state)

                M_IDLE: begin
                    if (frame_valid)
                        next_state = M_READ_DATA;
                end

                M_READ_DATA: begin
                    if (!frame_valid)
                        next_state = M_CHECK_STOP;
                end

                M_CHECK_STOP: begin
                    if (data_bit)
                        rx_done_next = 1'b1;
                    else
                        error_flag_next = 1'b1;

                    next_state = M_IDLE;
                end

                default: begin
                    next_state = M_IDLE;
                end

            endcase

            expected_state      = next_state;
            expected_rx_done    = rx_done_next;
            expected_error_flag = error_flag_next;

        end

        mismatch = 0;

        if (rx_done !== expected_rx_done)
            mismatch = 1;

        if (error_flag !== expected_error_flag)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t rst_n=%b frame_valid=%b data_bit=%b model_state=%0d rx_done=%b exp=%b error_flag=%b exp=%b",
                         $time, rst_n, frame_valid, data_bit, expected_state,
                         rx_done, expected_rx_done, error_flag, expected_error_flag);
        end
        case (expected_state)
            M_IDLE:       idle_cycles++;
            M_READ_DATA:  read_data_cycles++;
            M_CHECK_STOP: check_stop_cycles++;
            default: ;
        endcase

        if (expected_rx_done)
            rx_done_cycles++;

        if (expected_error_flag)
            error_flag_cycles++;

        checked++;

    endfunction
    function void report();

        $display("======== FRAME SCOREBOARD ===========");
        $display("Cycles checked      : %0d", checked);
        $display("Passed              : %0d", checked - errors);
        $display("Errors              : %0d", errors);
        $display("IDLE cycles         : %0d", idle_cycles);
        $display("READ_DATA cycles    : %0d", read_data_cycles);
        $display("CHECK_STOP cycles   : %0d", check_stop_cycles);
        $display("rx_done pulses      : %0d", rx_done_cycles);
        $display("error_flag pulses   : %0d", error_flag_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class FrameMonitor;

    virtual frame_if vif;
    FrameScoreboard  sb;

    function new(
        virtual frame_if vif,
        FrameScoreboard  sb
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
                vif.frame_valid,
                vif.data_bit,
                vif.rx_done,
                vif.error_flag
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class FrameDriver;

    virtual frame_if vif;
    function new(virtual frame_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n       = 1'b0;
        vif.frame_valid = 1'b0;
        vif.data_bit    = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask
    task drive(FrameTxn tr);

        @(negedge vif.clk);
        vif.rst_n       = tr.rst_n;
        vif.frame_valid = tr.frame_valid;
        vif.data_bit    = tr.data_bit;

    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class FrameGenerator;

    FrameDriver drv;
    int num_txn;
    bit level = 1'b0;

    function new(
        FrameDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        FrameTxn tr;
        repeat (num_txn) begin

            tr = new();

            if (!tr.randomize())
                $fatal(1);
            level          = level ^ tr.toggle_valid;
            tr.frame_valid = level;
            drv.drive(tr);

        end
    endtask

endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class FrameEnvironment;

    FrameGenerator  gen;
    FrameDriver     drv;
    FrameMonitor    mon;
    FrameScoreboard sb;
    virtual frame_if vif;

    function new(
        virtual frame_if vif,
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
module tb_FrameReceiverFSM;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;

    always #5 clk = ~clk;

    frame_if vif(clk);

    FrameReceiverFSM dut (
        .clk         (clk),
        .rst_n       (vif.rst_n),
        .frame_valid (vif.frame_valid),
        .data_bit    (vif.data_bit),
        .rx_done     (vif.rx_done),
        .error_flag  (vif.error_flag)
    );
    FrameEnvironment env;

    initial begin
        $dumpfile("FrameReceiverFSM_waveform.vcd");
        $dumpvars(0, tb_FrameReceiverFSM);
    end

    initial begin

        vif.rst_n       = 1'b0;
        vif.frame_valid = 1'b0;
        vif.data_bit    = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end

endmodule //The last line must be empty so Vs code doesn't give a mistake

