`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE,
    M_EXERCISE,
    M_SUCCESS,
    M_FAILED
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface pushups_if (input logic clk);
    logic rst_n;
    logic start;
    logic done;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class PushUpsTxn;
    rand bit rst_n;
    rand bit start;
    constraint c_rst_n {
        rst_n dist {1 := 199, 0 := 1};
    }
    constraint c_start {
        start dist {1 := 40, 0 := 60};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard (reference model)
// ---------------------------------------------------------------------------
class PushUpsScoreboard;
    int amount;
    int max_health;

    model_state_t state = M_IDLE;
    int reps   = 0;
    int health = 0;
    int checked = 0;
    int errors  = 0;
    int cnt_idle     = 0;
    int cnt_exercise = 0;
    int cnt_success  = 0;
    int cnt_failed   = 0;
    int cnt_resets   = 0;

    function new(
        int amount,
        int max_health
    );
        this.amount     = amount;
        this.max_health = max_health;
        this.health     = max_health;
    endfunction

    function void check(
        input logic rst_n,
        input logic start,
        input logic done
    );
        model_state_t next_state;
        logic         expected_done;
        if (!rst_n) begin
            state  = M_IDLE;
            reps   = 0;
            health = max_health;
            cnt_resets++;
        end

        expected_done = (state == M_SUCCESS);

        if (done !== expected_done) begin
            errors++;
            if (errors <= 10)
                $display("[%0t] MISMATCH (AMOUNT=%0d MAX_HEALTH=%0d): state=%s done=%b expected=%b",
                         $time, amount, max_health, state.name(), done, expected_done);
        end
        checked++;

        case (state)
            M_IDLE:     cnt_idle++;
            M_EXERCISE: cnt_exercise++;
            M_SUCCESS:  cnt_success++;
            M_FAILED:   cnt_failed++;
        endcase

        if (rst_n) begin
            next_state = state;
            case (state)
                M_IDLE, M_SUCCESS, M_FAILED: begin
                    if (start) begin
                        reps   = 0;
                        health = max_health;
                        if (amount == 0)          next_state = M_SUCCESS;
                        else if (max_health == 0) next_state = M_FAILED;
                        else                      next_state = M_EXERCISE;
                    end
                end
                M_EXERCISE: begin
                    if (health == 0)
                        next_state = M_FAILED;
                    else if (reps + 1 >= amount)
                        next_state = M_SUCCESS;
                    if (health > 0) begin
                        reps   = reps + 1;
                        health = health - 1;
                    end
                end
                default: begin
                    next_state = M_IDLE;
                    reps       = 0;
                    health     = max_health;
                end
            endcase
            state = next_state;
        end
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class PushUpsMonitor;
    virtual pushups_if vif;
    PushUpsScoreboard  sb;

    function new(
        virtual pushups_if vif,
        PushUpsScoreboard  sb
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
                vif.start,
                vif.done
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class PushUpsDriver;
    virtual pushups_if vif;

    function new(virtual pushups_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n = 1'b0;
        vif.start = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(PushUpsTxn tr);
        @(negedge vif.clk);
        vif.rst_n = tr.rst_n;
        vif.start = tr.start;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class PushUpsGenerator;
    PushUpsDriver drv;
    int num_txn;

    function new(
        PushUpsDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        PushUpsTxn tr;
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
class PushUpsEnvironment;
    PushUpsGenerator  gen;
    PushUpsDriver     drv;
    PushUpsMonitor    mon;
    PushUpsScoreboard sb;
    virtual pushups_if vif;
    int amount;
    int max_health;

    function new(
        virtual pushups_if vif,
        int amount,
        int max_health,
        int num_txn = 30000
    );
        this.vif        = vif;
        this.amount     = amount;
        this.max_health = max_health;
        sb  = new(amount, max_health);
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
        $display("[AMOUNT=%0d MAX_HEALTH=%0d] checked=%0d errors=%0d | idle=%0d exercise=%0d success=%0d failed=%0d resets=%0d",
                 amount, max_health, sb.checked, sb.errors,
                 sb.cnt_idle, sb.cnt_exercise, sb.cnt_success, sb.cnt_failed, sb.cnt_resets);
        if (sb.errors != 0)
            $fatal(1);
    endtask
endclass

// ---------------------------------------------------------------------------
// tb
// ---------------------------------------------------------------------------
module tb_Push_Ups #(
    parameter AMOUNT     = 10,
    parameter MAX_HEALTH = 100,
    parameter NUM_TXN    = 30000
)(
    output logic finished
);
    logic clk = 1'b0;
    always #5 clk = ~clk;
    pushups_if vif(clk);

    Push_Ups #(
        .AMOUNT     (AMOUNT),
        .MAX_HEALTH (MAX_HEALTH)
    ) dut (
        .clk   (clk),
        .rst_n (vif.rst_n),
        .start (vif.start),
        .done  (vif.done)
    );
    PushUpsEnvironment env;

    initial begin
        finished   = 1'b0;
        vif.rst_n  = 1'b0;
        vif.start  = 1'b0;
        env = new(vif, AMOUNT, MAX_HEALTH, NUM_TXN);
        env.drv.reset();
        env.run();
        finished = 1'b1;
    end

    initial begin
        #10ms;
        $fatal(1);
    end
endmodule

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_Push_Ups_top;
    logic [5:0] finished;

    tb_Push_Ups #(.AMOUNT(10), .MAX_HEALTH(100)) t0 (.finished(finished[0])); 
    tb_Push_Ups #(.AMOUNT(10), .MAX_HEALTH(5))   t1 (.finished(finished[1])); 
    tb_Push_Ups #(.AMOUNT(0),  .MAX_HEALTH(10))  t2 (.finished(finished[2])); 
    tb_Push_Ups #(.AMOUNT(10), .MAX_HEALTH(0))   t3 (.finished(finished[3])); 
    tb_Push_Ups #(.AMOUNT(1),  .MAX_HEALTH(1))   t4 (.finished(finished[4])); 
    tb_Push_Ups #(.AMOUNT(7),  .MAX_HEALTH(7))   t5 (.finished(finished[5])); 

    initial begin
        $dumpfile("Push_Ups_waveform.vcd");
        $dumpvars(0, tb_Push_Ups_top);
        wait (&finished);
        $display("ALL CONFIGURATIONS PASSED");
        $finish;
    end
endmodule //The last line must be empty so Vs code doesn't give a mistake

