`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE,
    M_DATA_READY,
    M_WAIT_FOR_RESET
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface handshake_if (input logic clk);

    logic rst_n;
    logic req;
    logic s_ready;
    logic ack;
    logic data_valid;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class HandshakeTxn;

    rand bit rst_n;
    rand bit toggle_req;
    rand bit s_ready;
    bit      req;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_toggle_req {
        toggle_req dist {1 := 20, 0 := 80};
    }

    constraint c_s_ready {
        s_ready dist {1 := 30, 0 := 70};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class HandshakeScoreboard;

    model_state_t expected_state = M_IDLE;

    int checked = 0;
    int errors  = 0;
    int idle_cycles            = 0;
    int data_ready_cycles      = 0;
    int wait_for_reset_cycles  = 0;
    int ack_cycles             = 0;
    int wait_held_req_low      = 0;

    function model_state_t next_of(
        input model_state_t state,
        input logic         req,
        input logic         s_ready
    );

        model_state_t result;
        result = state;
        case (state)

            M_IDLE: begin
                if (req)
                    result = M_DATA_READY;
            end

            M_DATA_READY: begin
                if (s_ready)
                    result = M_WAIT_FOR_RESET;
            end

            M_WAIT_FOR_RESET: begin
                if (!req)
                    result = M_IDLE;
            end

            default: begin
                result = M_IDLE;
            end

        endcase
        return result;

    endfunction

    function void check(
        input logic rst_n,
        input logic req,
        input logic s_ready,
        input logic ack,
        input logic data_valid
    );
        model_state_t next_state;
        logic         expected_ack;
        logic         expected_data_valid;
        bit           mismatch;

        if (!rst_n) begin
            expected_state = M_IDLE;
        end
        else begin

            for (int i = 0; i < 8; i++) begin

                if (!(req || s_ready || (expected_state == M_WAIT_FOR_RESET)))
                    break;

                next_state = next_of(expected_state, req, s_ready);

                if (next_state == expected_state)
                    break;

                expected_state = next_state;

            end

        end

        expected_ack        = (expected_state == M_DATA_READY);
        expected_data_valid = (expected_state == M_DATA_READY);

        mismatch = 0;

        if (ack !== expected_ack)
            mismatch = 1;

        if (data_valid !== expected_data_valid)
            mismatch = 1;

        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t rst_n=%b req=%b s_ready=%b model_state=%0d ack=%b expected_ack=%b",
                         $time, rst_n, req, s_ready, expected_state, ack, expected_ack);
        end

        case (expected_state)
            M_IDLE:           idle_cycles++;
            M_DATA_READY:     data_ready_cycles++;
            M_WAIT_FOR_RESET: wait_for_reset_cycles++;
            default: ;
        endcase

        if (expected_ack)
            ack_cycles++;

        if ((expected_state == M_WAIT_FOR_RESET) && !req && !s_ready)
            wait_held_req_low++;

        checked++;

    endfunction

    function void report();

        $display("======== HANDSHAKE SCOREBOARD =======");
        $display("Cycles checked          : %0d", checked);
        $display("Passed                  : %0d", checked - errors);
        $display("Errors                  : %0d", errors);
        $display("IDLE cycles             : %0d", idle_cycles);
        $display("DATA_READY cycles       : %0d", data_ready_cycles);
        $display("WAIT_FOR_RESET cycles   : %0d", wait_for_reset_cycles);
        $display("ack high cycles         : %0d", ack_cycles);
        $display("WAIT held, req=0 cycles : %0d", wait_held_req_low);
        $display("=====================================");

    endfunction

endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class HandshakeMonitor;

    virtual handshake_if vif;
    HandshakeScoreboard  sb;

    function new(
        virtual handshake_if vif,
        HandshakeScoreboard  sb
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
                vif.req,
                vif.s_ready,
                vif.ack,
                vif.data_valid
            );
        end

    endtask

endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class HandshakeDriver;

    virtual handshake_if vif;
    function new(virtual handshake_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n   = 1'b0;
        vif.req     = 1'b0;
        vif.s_ready = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;

    endtask

    task drive(HandshakeTxn tr);

        @(negedge vif.clk);
        vif.rst_n   = tr.rst_n;
        vif.req     = tr.req;
        vif.s_ready = tr.s_ready;

    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class HandshakeGenerator;

    HandshakeDriver drv;
    int num_txn;
    bit level = 1'b0;

    function new(
        HandshakeDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        HandshakeTxn tr;
        repeat (num_txn) begin

            tr = new();

            if (!tr.randomize())
                $fatal(1);

            level  = level ^ tr.toggle_req;
            tr.req = level;

            drv.drive(tr);

        end
    endtask

endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class HandshakeEnvironment;

    HandshakeGenerator  gen;
    HandshakeDriver     drv;
    HandshakeMonitor    mon;
    HandshakeScoreboard sb;
    virtual handshake_if vif;

    function new(
        virtual handshake_if vif,
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
module tb_HandshakeController;

    localparam int NUM_TXN = 2000;

    logic clk = 1'b0;

    always #5 clk = ~clk;

    handshake_if vif(clk);

    HandshakeController dut (
        .rst_n      (vif.rst_n),
        .req        (vif.req),
        .s_ready    (vif.s_ready),
        .ack        (vif.ack),
        .data_valid (vif.data_valid)
    );
    HandshakeEnvironment env;

    initial begin
        $dumpfile("HandshakeController_waveform.vcd");
        $dumpvars(0, tb_HandshakeController);
    end

    initial begin

        vif.rst_n   = 1'b0;
        vif.req     = 1'b0;
        vif.s_ready = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;

    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end

endmodule //The last line must be empty so VsCode doesn't give a mistake
