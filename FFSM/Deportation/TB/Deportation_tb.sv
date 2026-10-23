`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_WAIT_FOR_PERSON = 2'b00,
    M_WAIT_FOR_DOC    = 2'b01,
    M_LOTTERY_DRAW    = 2'b10,
    M_DECISION_OUT    = 2'b11
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface deportation_if (input logic clk);
    logic rst_n;
    logic next_in_line_i;
    logic submit_passport_i;
    logic stay_approved_o;
    logic deported_o;
    logic busy_o;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class DeportationTxn;
    rand bit rst_n;
    rand bit next_in_line_i;
    rand bit submit_passport_i;
    constraint c_rst_n {
        rst_n dist {1 := 199, 0 := 1};
    }
    constraint c_next_in_line_i {
        next_in_line_i dist {1 := 40, 0 := 60};
    }
    constraint c_submit_passport_i {
        submit_passport_i dist {1 := 40, 0 := 60};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class DeportationScoreboard;
    model_state_t expected_state    = M_WAIT_FOR_PERSON;
    logic [7:0]   expected_a_reg    = 8'h5A;
    logic         expected_decision = 1'b0;
    int checked = 0;
    int errors  = 0;
    int wait_person_cycles = 0;
    int wait_doc_cycles    = 0;
    int lottery_cycles     = 0;
    int decision_cycles    = 0;
    int busy_cycles        = 0;
    int approved_cycles    = 0;
    int deported_cycles    = 0;

    function void check(
        input logic rst_n,
        input logic next_in_line_i,
        input logic submit_passport_i,
        input logic stay_approved_o,
        input logic deported_o,
        input logic busy_o
    );
        model_state_t next_state;
        logic         expected_stay_approved;
        logic         expected_deported;
        logic         expected_busy;
        bit           mismatch;
        if (!rst_n) begin
            expected_state    = M_WAIT_FOR_PERSON;
            expected_a_reg    = 8'h5A;
            expected_decision = 1'b0;
        end
        else begin
            next_state = expected_state;
            case (expected_state)
                M_WAIT_FOR_PERSON: begin
                    if (next_in_line_i)
                        next_state = M_WAIT_FOR_DOC;
                end
                M_WAIT_FOR_DOC: begin
                    if (submit_passport_i)
                        next_state = M_LOTTERY_DRAW;
                end
                M_LOTTERY_DRAW: begin
                    next_state = M_DECISION_OUT;
                end
                M_DECISION_OUT: begin
                    next_state = M_WAIT_FOR_PERSON;
                end
                default: begin
                    next_state = M_WAIT_FOR_PERSON;
                end
            endcase
            if (expected_state == M_LOTTERY_DRAW)
                expected_decision = expected_a_reg[0];
            expected_a_reg = {expected_a_reg[6:0],
                              expected_a_reg[7] ^ expected_a_reg[5] ^ expected_a_reg[4] ^ expected_a_reg[3]};
            expected_state = next_state;
        end
        expected_stay_approved = 1'b0;
        expected_deported      = 1'b0;
        expected_busy          = 1'b0;
        case (expected_state)
            M_WAIT_FOR_DOC, M_LOTTERY_DRAW: begin
                expected_busy = 1'b1;
            end
            M_DECISION_OUT: begin
                expected_stay_approved = expected_decision;
                expected_deported      = !expected_decision;
            end
            default: ;
        endcase
        mismatch = 0;
        if (stay_approved_o !== expected_stay_approved)
            mismatch = 1;
        if (deported_o !== expected_deported)
            mismatch = 1;
        if (busy_o !== expected_busy)
            mismatch = 1;
        if (mismatch)
            errors++;
        case (expected_state)
            M_WAIT_FOR_PERSON: wait_person_cycles++;
            M_WAIT_FOR_DOC:    wait_doc_cycles++;
            M_LOTTERY_DRAW:    lottery_cycles++;
            M_DECISION_OUT:    decision_cycles++;
            default: ;
        endcase
        if (expected_busy)
            busy_cycles++;
        if (expected_stay_approved)
            approved_cycles++;
        if (expected_deported)
            deported_cycles++;
        checked++;
    endfunction

    function void report();
        $display("");
        $display("========= DEPORTATION RESULTS =======");
        $display("Cycles checked          : %0d", checked);
        $display("Passed                  : %0d", checked - errors);
        $display("Errors                  : %0d", errors);
        $display("-------------------------------------");
        $display("WAIT_FOR_PERSON cycles  : %0d", wait_person_cycles);
        $display("WAIT_FOR_DOC cycles     : %0d", wait_doc_cycles);
        $display("LOTTERY_DRAW cycles     : %0d", lottery_cycles);
        $display("DECISION_OUT cycles     : %0d", decision_cycles);
        $display("-------------------------------------");
        $display("Busy cycles             : %0d", busy_cycles);
        $display("Stay approved           : %0d", approved_cycles);
        $display("Deported                : %0d", deported_cycles);
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
class DeportationMonitor;
    virtual deportation_if vif;
    DeportationScoreboard  sb;

    function new(
        virtual deportation_if vif,
        DeportationScoreboard  sb
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
                vif.next_in_line_i,
                vif.submit_passport_i,
                vif.stay_approved_o,
                vif.deported_o,
                vif.busy_o
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class DeportationDriver;
    virtual deportation_if vif;

    function new(virtual deportation_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n             = 1'b0;
        vif.next_in_line_i    = 1'b0;
        vif.submit_passport_i = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(DeportationTxn tr);
        @(negedge vif.clk);
        vif.rst_n             = tr.rst_n;
        vif.next_in_line_i    = tr.next_in_line_i;
        vif.submit_passport_i = tr.submit_passport_i;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class DeportationGenerator;
    DeportationDriver drv;
    int num_txn;

    function new(
        DeportationDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        DeportationTxn tr;
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
class DeportationEnvironment;
    DeportationGenerator  gen;
    DeportationDriver     drv;
    DeportationMonitor    mon;
    DeportationScoreboard sb;
    virtual deportation_if vif;

    function new(
        virtual deportation_if vif,
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
module tb_Deportation;
    localparam int NUM_TXN = 30000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    deportation_if vif(clk);

    Deportation dut (
        .clk               (clk),
        .rst_n             (vif.rst_n),
        .next_in_line_i    (vif.next_in_line_i),
        .submit_passport_i (vif.submit_passport_i),
        .stay_approved_o   (vif.stay_approved_o),
        .deported_o        (vif.deported_o),
        .busy_o            (vif.busy_o)
    );
    DeportationEnvironment env;

    initial begin
        $dumpfile("Deportation_waveform.vcd");
        $dumpvars(0, tb_Deportation);
    end

    initial begin
        vif.rst_n             = 1'b0;
        vif.next_in_line_i    = 1'b0;
        vif.submit_passport_i = 1'b0;
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

