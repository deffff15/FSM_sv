`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE,
    M_WRITE,
    M_READ,
    M_ERROR
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface fifo_if (input logic clk);

    logic rst_n;
    logic wr_req;
    logic rd_req;
    logic fifo_full;
    logic fifo_empty;
    logic wr_en;
    logic rd_en;
    logic alarm;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class FifoTxn;

    rand bit rst_n;
    rand bit wr_req;
    rand bit rd_req;
    rand bit fifo_full;
    rand bit fifo_empty;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_wr_req {
        wr_req dist {1 := 40, 0 := 60};
    }

    constraint c_rd_req {
        rd_req dist {1 := 40, 0 := 60};
    }

    constraint c_fifo_full {
        fifo_full dist {1 := 25, 0 := 75};
    }

    constraint c_fifo_empty {
        fifo_empty dist {1 := 25, 0 := 75};
    }

    constraint c_full_empty {
        !(fifo_full && fifo_empty);
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class FifoScoreboard;

    model_state_t expected_state = M_IDLE;

    int checked = 0;
    int errors  = 0;
    int idle_cycles  = 0;
    int write_cycles = 0;
    int read_cycles  = 0;
    int error_cycles = 0;

    function void check(
        input logic rst_n,
        input logic wr_req,
        input logic rd_req,
        input logic fifo_full,
        input logic fifo_empty,
        input logic wr_en,
        input logic rd_en,
        input logic alarm
    );

        model_state_t next_state;
        logic         expected_wr_en;
        logic         expected_rd_en;
        logic         expected_alarm;
        bit           mismatch;
        if (!rst_n) begin
            expected_state = M_IDLE;
        end
        else begin

            next_state = expected_state;

            case (expected_state)

                M_IDLE: begin
                    if (wr_req && !fifo_full)
                        next_state = M_WRITE;
                    else if (rd_req && !fifo_empty)
                        next_state = M_READ;
                    else if ((wr_req && fifo_full) || (rd_req && fifo_empty))
                        next_state = M_ERROR;
                end

                M_WRITE: begin
                    if (rd_req && !fifo_empty)
                        next_state = M_READ;
                    else if (wr_req && !fifo_full)
                        next_state = M_WRITE;
                    else
                        next_state = M_IDLE;
                end

                M_READ: begin
                    if (wr_req && !fifo_full)
                        next_state = M_WRITE;
                    else if (rd_req && !fifo_empty)
                        next_state = M_READ;
                    else
                        next_state = M_IDLE;
                end

                M_ERROR: begin
                    if (!wr_req && !rd_req)
                        next_state = M_IDLE;
                end

                default: begin
                    next_state = M_IDLE;
                end

            endcase

            expected_state = next_state;

        end

        expected_wr_en = (expected_state == M_WRITE);
        expected_rd_en = (expected_state == M_READ);
        expected_alarm = (expected_state == M_ERROR);

        mismatch = 0;

        if (wr_en !== expected_wr_en)
            mismatch = 1;

        if (rd_en !== expected_rd_en)
            mismatch = 1;

        if (alarm !== expected_alarm)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%0d wr_en=%b exp=%b rd_en=%b exp=%b alarm=%b exp=%b",
                         $time, expected_state, wr_en, expected_wr_en,
                         rd_en, expected_rd_en, alarm, expected_alarm);
        end
        case (expected_state)
            M_IDLE:  idle_cycles++;
            M_WRITE: write_cycles++;
            M_READ:  read_cycles++;
            M_ERROR: error_cycles++;
            default: ;
        endcase
        checked++;

    endfunction

    function void report();

        $display("========== FIFO SCOREBOARD ==========");
        $display("Cycles checked   : %0d", checked);
        $display("Passed           : %0d", checked - errors);
        $display("Errors           : %0d", errors);
        $display("IDLE cycles      : %0d", idle_cycles);
        $display("WRITE cycles     : %0d", write_cycles);
        $display("READ cycles      : %0d", read_cycles);
        $display("ERROR cycles     : %0d", error_cycles);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class FifoMonitor;

    virtual fifo_if vif;
    FifoScoreboard  sb;
    function new(
        virtual fifo_if vif,
        FifoScoreboard  sb
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
                vif.wr_req,
                vif.rd_req,
                vif.fifo_full,
                vif.fifo_empty,
                vif.wr_en,
                vif.rd_en,
                vif.alarm
            );
        end
    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class FifoDriver;

    virtual fifo_if vif;
    function new(virtual fifo_if vif);
        this.vif = vif;
    endfunction
    task reset();

        @(negedge vif.clk);
        vif.rst_n      = 1'b0;
        vif.wr_req     = 1'b0;
        vif.rd_req     = 1'b0;
        vif.fifo_full  = 1'b0;
        vif.fifo_empty = 1'b1;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask
    task drive(FifoTxn tr);

        @(negedge vif.clk);
        vif.rst_n      = tr.rst_n;
        vif.wr_req     = tr.wr_req;
        vif.rd_req     = tr.rd_req;
        vif.fifo_full  = tr.fifo_full;
        vif.fifo_empty = tr.fifo_empty;

    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class FifoGenerator;

    FifoDriver drv;
    int num_txn;
    function new(
        FifoDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        FifoTxn tr;
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
class FifoEnvironment;

    FifoGenerator  gen;
    FifoDriver     drv;
    FifoMonitor    mon;
    FifoScoreboard sb;
    virtual fifo_if vif;

    function new(
        virtual fifo_if vif,
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
module tb_FifoController;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    fifo_if vif(clk);

    FifoController dut (
        .clk        (clk),
        .rst_n      (vif.rst_n),
        .wr_req     (vif.wr_req),
        .rd_req     (vif.rd_req),
        .fifo_full  (vif.fifo_full),
        .fifo_empty (vif.fifo_empty),
        .wr_en      (vif.wr_en),
        .rd_en      (vif.rd_en),
        .alarm      (vif.alarm)
    );
    FifoEnvironment env;

    initial begin
        $dumpfile("FifoController_waveform.vcd");
        $dumpvars(0, tb_FifoController);
    end

    initial begin

        vif.rst_n      = 1'b0;
        vif.wr_req     = 1'b0;
        vif.rd_req     = 1'b0;
        vif.fifo_full  = 1'b0;
        vif.fifo_empty = 1'b1;
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

