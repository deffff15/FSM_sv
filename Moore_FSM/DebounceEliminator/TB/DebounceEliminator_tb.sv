`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_LOW,
    M_FILTER_HIGH,
    M_HIGH,
    M_FILTER_LOW
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface debounce_if (input logic clk);

    logic rst_n;
    logic btn_in;
    logic btn_out;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class DebounceTxn;

    rand bit rst_n;
    rand bit toggle;
    bit      btn_in;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_toggle {
        toggle dist {1 := 30, 0 := 70};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class DebounceScoreboard;

    model_state_t expected_state = M_LOW;

    int checked = 0;
    int errors  = 0;
    int low_cycles         = 0;
    int filter_high_cycles = 0;
    int high_cycles        = 0;
    int filter_low_cycles  = 0;
    int out_high_cycles    = 0;

    function void check(
        input logic rst_n,
        input logic btn_in,
        input logic btn_out
    );

        model_state_t next_state;
        logic         expected_out;

        if (!rst_n) begin
            expected_state = M_LOW;
        end
        else begin

            next_state = expected_state;
            case (expected_state)

                M_LOW: begin
                    next_state = btn_in ? M_FILTER_HIGH : M_LOW;
                end

                M_FILTER_HIGH: begin
                    next_state = btn_in ? M_HIGH : M_LOW;
                end

                M_HIGH: begin
                    next_state = btn_in ? M_HIGH : M_FILTER_LOW;
                end

                M_FILTER_LOW: begin
                    next_state = btn_in ? M_HIGH : M_LOW;
                end

                default: begin
                    next_state = M_LOW;
                end

            endcase

            expected_state = next_state;
        end

        expected_out = (expected_state == M_HIGH) || (expected_state == M_FILTER_LOW);

        if (btn_out !== expected_out)
            errors++;
        case (expected_state)
            M_LOW:         low_cycles++;
            M_FILTER_HIGH: filter_high_cycles++;
            M_HIGH:        high_cycles++;
            M_FILTER_LOW:  filter_low_cycles++;
            default: ;
        endcase

        if (expected_out)
            out_high_cycles++;

        checked++;

    endfunction

    function void report();
    
        $display("========= DEBOUNCE SCOREBOARD =======");
        $display("Cycles checked     : %0d", checked);
        $display("Passed             : %0d", checked - errors);
        $display("Errors             : %0d", errors);
        $display("LOW cycles         : %0d", low_cycles);
        $display("FILTER_HIGH cycles : %0d", filter_high_cycles);
        $display("HIGH cycles        : %0d", high_cycles);
        $display("FILTER_LOW cycles  : %0d", filter_low_cycles);
        $display("btn_out high       : %0d", out_high_cycles);
        $display("=====================================");

    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class DebounceMonitor;

    virtual debounce_if vif;
    DebounceScoreboard  sb;

    function new(
        virtual debounce_if vif,
        DebounceScoreboard  sb
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
                vif.btn_in,
                vif.btn_out
            );
        end

    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class DebounceDriver;

    virtual debounce_if vif;
    function new(virtual debounce_if vif);
        this.vif = vif;
    endfunction

    task reset();

        @(negedge vif.clk);
        vif.rst_n  = 1'b0;
        vif.btn_in = 1'b0;

        repeat (2) @(negedge vif.clk);

        vif.rst_n = 1'b1;

    endtask

    task drive(DebounceTxn tr);

        @(negedge vif.clk);

        vif.rst_n  = tr.rst_n;
        vif.btn_in = tr.btn_in;

    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class DebounceGenerator;

    DebounceDriver drv;
    int num_txn;
    bit level = 1'b0;

    function new(
        DebounceDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        DebounceTxn tr;

        repeat (num_txn) begin

            tr = new();

            if (!tr.randomize())
                $fatal(1);

            level      = level ^ tr.toggle;
            tr.btn_in  = level;

            drv.drive(tr);

        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class DebounceEnvironment;

    DebounceGenerator  gen;
    DebounceDriver     drv;
    DebounceMonitor    mon;
    DebounceScoreboard sb;

    virtual debounce_if vif;

    function new(
        virtual debounce_if vif,
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
module tb_DebounceEliminator;

    localparam int NUM_TXN = 2000;
    logic clk = 1'b0;

    always #5 clk = ~clk;

    debounce_if vif(clk);

    DebounceEliminator dut (
        .clk     (clk),
        .rst_n   (vif.rst_n),
        .btn_in  (vif.btn_in),
        .btn_out (vif.btn_out)
    );

    DebounceEnvironment env;

    initial begin
        $dumpfile("DebounceEliminator_waveform.vcd");
        $dumpvars(0, tb_DebounceEliminator);
    end

    initial begin

        vif.rst_n  = 1'b0;
        vif.btn_in = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;

    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end

endmodule //The last line must be empty so Vs Code doesn't give a endmodule

