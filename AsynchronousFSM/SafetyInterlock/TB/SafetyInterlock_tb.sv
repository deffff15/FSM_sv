`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_SAFE_RUN = 2'b00,
    M_E_STOP   = 2'b01,
    M_CURTAIN  = 2'b11
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface interlock_if (input logic clk);
    logic emergency_btn;
    logic light_curtain;
    logic clutch_engage;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class InterlockTxn;
    rand bit emergency_btn;
    rand bit light_curtain;
    constraint c_emergency_btn {
        emergency_btn dist {1 := 85, 0 := 15};
    }
    constraint c_light_curtain {
        light_curtain dist {1 := 75, 0 := 25};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class InterlockScoreboard;
    model_state_t expected_state = M_E_STOP;
    int checked = 0;
    int errors  = 0;
    int safe_run_cycles      = 0;
    int e_stop_cycles        = 0;
    int curtain_cycles       = 0;
    int clutch_cycles        = 0;
    int e_stop_latched       = 0;

    function model_state_t next_of(
        input model_state_t state,
        input logic         emergency_btn,
        input logic         light_curtain
    );
        model_state_t result;
        result = state;
        case (state)
            M_SAFE_RUN: begin
                if (!emergency_btn)
                    result = M_E_STOP;
                else if (!light_curtain)
                    result = M_CURTAIN;
            end
            M_E_STOP: begin
                if (emergency_btn && light_curtain)
                    result = M_SAFE_RUN;
            end
            M_CURTAIN: begin
                if (!emergency_btn)
                    result = M_E_STOP;
                else if (light_curtain)
                    result = M_SAFE_RUN;
            end
            default: begin
                result = M_E_STOP;
            end
        endcase
        return result;
    endfunction

    function void check(
        input logic emergency_btn,
        input logic light_curtain,
        input logic clutch_engage
    );
        model_state_t next_state;
        logic         expected_clutch_engage;
        bit           mismatch;
        for (int i = 0; i < 8; i++) begin
            next_state = next_of(expected_state, emergency_btn, light_curtain);
            if (next_state == expected_state)
                break;
            expected_state = next_state;
        end
        expected_clutch_engage = (expected_state == M_SAFE_RUN);
        mismatch = 0;
        if (clutch_engage !== expected_clutch_engage)
            mismatch = 1;
        if (mismatch)
            errors++;
        case (expected_state)
            M_SAFE_RUN: safe_run_cycles++;
            M_E_STOP:   e_stop_cycles++;
            M_CURTAIN:  curtain_cycles++;
            default: ;
        endcase
        if (expected_clutch_engage)
            clutch_cycles++;
        if (expected_state == M_E_STOP && emergency_btn)
            e_stop_latched++;
        checked++;
    endfunction

    function void report();
        $display("========= INTERLOCK RESULTS =========");
        $display("Cycles checked          : %0d", checked);
        $display("Passed                  : %0d", checked - errors);
        $display("Errors                  : %0d", errors);
        $display("-------------------------------------");
        $display("SAFE_RUN cycles         : %0d", safe_run_cycles);
        $display("E_STOP cycles           : %0d", e_stop_cycles);
        $display("CURTAIN cycles          : %0d", curtain_cycles);
        $display("-------------------------------------");
        $display("Clutch engaged          : %0d", clutch_cycles);
        $display("E_STOP, button released : %0d", e_stop_latched);
        $display("-------------------------------------");
        if (errors == 0)
            $display("Result                  : PASSED");
        else
            $display("Result                  : FAILED");
        $display("=====================================");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class InterlockMonitor;
    virtual interlock_if vif;
    InterlockScoreboard  sb;

    function new(
        virtual interlock_if vif,
        InterlockScoreboard  sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        forever begin
            @(posedge vif.clk);
            #1;
            sb.check(
                vif.emergency_btn,
                vif.light_curtain,
                vif.clutch_engage
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class InterlockDriver;
    virtual interlock_if vif;

    function new(virtual interlock_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.emergency_btn = 1'b1;
        vif.light_curtain = 1'b1;
        repeat (2) @(negedge vif.clk);
    endtask

    task drive(InterlockTxn tr);
        @(negedge vif.clk);
        vif.emergency_btn = tr.emergency_btn;
        vif.light_curtain = tr.light_curtain;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class InterlockGenerator;
    InterlockDriver drv;
    int num_txn;

    function new(
        InterlockDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        InterlockTxn tr;
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
class InterlockEnvironment;
    InterlockGenerator  gen;
    InterlockDriver     drv;
    InterlockMonitor    mon;
    InterlockScoreboard sb;
    virtual interlock_if vif;

    function new(
        virtual interlock_if vif,
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
        sb.report();
        if (sb.errors != 0)
            $fatal(1);
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_AsyncSafetyInterlock;
    localparam int NUM_TXN = 30000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    interlock_if vif(clk);

    AsyncSafetyInterlock dut (
        .emergency_btn (vif.emergency_btn),
        .light_curtain (vif.light_curtain),
        .clutch_engage (vif.clutch_engage)
    );
    InterlockEnvironment env;

    initial begin
        $dumpfile("AsyncSafetyInterlock_waveform.vcd");
        $dumpvars(0, tb_AsyncSafetyInterlock);
    end

    initial begin
        vif.emergency_btn = 1'b1;
        vif.light_curtain = 1'b1;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1);
    end
endmodule //The last line must be empty so vscode doesn't give a mistake

