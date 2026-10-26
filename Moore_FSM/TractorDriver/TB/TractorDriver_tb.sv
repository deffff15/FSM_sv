`timescale 1ns/1ps

typedef enum int {T_GARAGE, T_STARTING, T_FIELD, T_SHUTDOWN} trac_top_e;
typedef enum int {U_PLOWING, U_TURNING} trac_sub_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface trac_if (input logic clk);
    logic rst_n;
    logic start;
    logic row_end;
    logic done;
    logic shut;
    logic glow;
    logic plow;
    logic turning;
    logic beacon;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, start, row_end, done, shut, glow, plow, turning, beacon;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class TracTxn;
    rand bit rst_n;
    rand bit start;
    rand bit row_end;
    rand bit done;
    rand bit shut;

    int rst_w   = 2;
    int start_w = 300;
    int row_w   = 200;
    int done_w  = 50;
    int shut_w  = 200;

    logic glow;
    logic plow;
    logic turning;
    logic beacon;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,   1'b1 := 1000 - rst_w};
        start   dist {1'b1 := start_w, 1'b0 := 1000 - start_w};
        row_end dist {1'b1 := row_w,   1'b0 := 1000 - row_w};
        done    dist {1'b1 := done_w,  1'b0 := 1000 - done_w};
        shut    dist {1'b1 := shut_w,  1'b0 := 1000 - shut_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class TracScoreboard;
    trac_top_e top;
    trac_sub_e sub;

    int checked         = 0;
    int errors          = 0;
    int runs            = 0;
    int starts          = 0;
    int turns           = 0;
    int turn_exits      = 0;
    int turn_waits      = 0;
    int done_ends       = 0;
    int garage_waits    = 0;
    int shut_waits      = 0;
    int done_prio       = 0;
    int done_in_turn    = 0;
    int ignored_start   = 0;
    int ignored_row     = 0;
    int ignored_done    = 0;
    int ignored_shut    = 0;
    int resets_mid_run  = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        top = T_GARAGE;
        sub = U_PLOWING;
    endfunction

    function void step_model(TracTxn tr);
        trac_top_e next_top;
        trac_sub_e next_sub;

        next_top = top;
        next_sub = sub;

        if (tr.start && top != T_GARAGE)
            ignored_start++;
        if (tr.row_end && top != T_FIELD)
            ignored_row++;
        if (tr.done && top != T_FIELD)
            ignored_done++;
        if (tr.shut && top != T_SHUTDOWN)
            ignored_shut++;
        if (tr.done && top == T_FIELD && sub == U_TURNING)
            done_in_turn++;
        if (tr.done && tr.row_end && top == T_FIELD && sub == U_PLOWING)
            done_prio++;

        case (top)
            T_GARAGE: begin
                if (tr.start) begin
                    next_top = T_STARTING;
                    starts++;
                end
                else
                    garage_waits++;
            end

            T_STARTING: begin
                next_top = T_FIELD;
                next_sub = U_PLOWING;
            end

            T_FIELD: begin
                case (sub)
                    U_PLOWING: begin
                        if (tr.done) begin
                            next_top = T_SHUTDOWN;
                            done_ends++;
                        end
                        else if (tr.row_end) begin
                            next_sub = U_TURNING;
                            turns++;
                        end
                    end

                    U_TURNING: begin
                        if (!tr.row_end) begin
                            next_sub = U_PLOWING;
                            turn_exits++;
                        end
                        else
                            turn_waits++;
                    end

                    default: next_sub = U_PLOWING;
                endcase
            end

            T_SHUTDOWN: begin
                if (tr.shut) begin
                    next_top = T_GARAGE;
                    runs++;
                end
                else
                    shut_waits++;
            end

            default: begin
                next_top = T_GARAGE;
                next_sub = U_PLOWING;
            end
        endcase

        top = next_top;
        sub = next_sub;
    endfunction

    function void check(TracTxn tr);
        bit ok = 1;
        bit exp_glow;
        bit exp_plow;
        bit exp_turning;
        bit exp_beacon;

        if (!tr.rst_n) begin
            if (top != T_GARAGE) resets_mid_run++;
            reset_model();
        end

        exp_glow    = (top == T_STARTING);
        exp_plow    = (top == T_FIELD) && (sub == U_PLOWING);
        exp_turning = (top == T_FIELD) && (sub == U_TURNING);
        exp_beacon  = (top == T_FIELD) || (top == T_SHUTDOWN);

        if (tr.glow !== exp_glow) begin
            $error("[SB] glow_plugs mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.glow, exp_glow, top.name(), sub.name());
            ok = 0;
        end

        if (tr.plow !== exp_plow) begin
            $error("[SB] plow_down mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.plow, exp_plow, top.name(), sub.name());
            ok = 0;
        end

        if (tr.turning !== exp_turning) begin
            $error("[SB] turning mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.turning, exp_turning, top.name(), sub.name());
            ok = 0;
        end

        if (tr.beacon !== exp_beacon) begin
            $error("[SB] beacon mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.beacon, exp_beacon, top.name(), sub.name());
            ok = 0;
        end

        if (tr.rst_n) step_model(tr);

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked          : %0d", checked);
        $display("errors                  : %0d", errors);
        $display("runs completed          : %0d", runs);
        $display("engine starts           : %0d", starts);
        $display("row turns started       : %0d", turns);
        $display("row turns finished      : %0d", turn_exits);
        $display("waiting in turn         : %0d", turn_waits);
        $display("field done              : %0d", done_ends);
        $display("waiting in garage       : %0d", garage_waits);
        $display("waiting in shutdown     : %0d", shut_waits);
        $display("field_done over row_end : %0d", done_prio);
        $display("field_done in turn      : %0d", done_in_turn);
        $display("start ignored           : %0d", ignored_start);
        $display("row_end ignored         : %0d", ignored_row);
        $display("field_done ignored      : %0d", ignored_done);
        $display("shutdown ignored        : %0d", ignored_shut);
        $display("resets mid-run          : %0d", resets_mid_run);
        $display("--------------------------------------------");

        if (runs == 0)
            $warning("[SB] no run was completed");
        if (turns == 0 || turn_exits == 0 || turn_waits == 0)
            $warning("[SB] turning was not fully exercised (enter / wait / exit)");
        if (done_ends == 0)
            $warning("[SB] field_done never ended a run");
        if (done_prio == 0)
            $warning("[SB] field_done together with row_end was never applied while plowing");
        if (done_in_turn == 0)
            $warning("[SB] field_done during turning was never applied");
        if (garage_waits == 0 || shut_waits == 0)
            $warning("[SB] waiting in garage or shutdown was never exercised");
        if (ignored_start == 0 || ignored_row == 0 || ignored_done == 0 || ignored_shut == 0)
            $warning("[SB] ignored start / row_end / field_done / shutdown was never exercised");
        if (resets_mid_run == 0)
            $warning("[SB] reset was never applied in the middle of a run");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class TracMonitor;
    virtual trac_if vif;
    TracScoreboard  sb;

    function new(virtual trac_if vif, TracScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        TracTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.start   = vif.mon_cb.start;
            tr.row_end = vif.mon_cb.row_end;
            tr.done    = vif.mon_cb.done;
            tr.shut    = vif.mon_cb.shut;
            tr.glow    = vif.mon_cb.glow;
            tr.plow    = vif.mon_cb.plow;
            tr.turning = vif.mon_cb.turning;
            tr.beacon  = vif.mon_cb.beacon;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class TracDriver;
    virtual trac_if vif;

    function new(virtual trac_if vif);
        this.vif = vif;
    endfunction

    task drive(TracTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.start   <= tr.start;
        vif.row_end <= tr.row_end;
        vif.done    <= tr.done;
        vif.shut    <= tr.shut;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class TracGenerator;
    TracDriver drv;
    int        num_random;

    function new(TracDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit start = 1'b0, bit row_end = 1'b0,
              bit done = 1'b0, bit shut = 1'b0);
        TracTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.start   = start;
        tr.row_end = row_end;
        tr.done    = done;
        tr.shut    = shut;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task shift(int rows, int plow_len, int turn_len, int shut_wait, int cause);
        step(1'b1, 1'b1);
        step();
        repeat (rows) begin
            calm(plow_len);
            repeat (turn_len) step(1'b1, 1'b0, 1'b1);
            step();
        end
        if (cause == 2) begin
            step(1'b1, 1'b0, 1'b1);
            step(1'b1, 1'b0, 1'b1, 1'b1);
            step();
        end
        case (cause)
            1:       step(1'b1, 1'b0, 1'b1, 1'b1);
            default: step(1'b1, 1'b0, 1'b0, 1'b1);
        endcase
        calm(shut_wait);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        calm(2);
    endtask

    task to_stage(int s);
        step(1'b1, 1'b1);
        if (s >= 2) step();
        if (s >= 3) step(1'b1, 1'b0, 1'b1);
        if (s >= 4) step();
        if (s >= 5) step(1'b1, 1'b0, 1'b0, 1'b1);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (3) step();
        repeat (3) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        calm(2);

        shift(1, 1, 1, 1, 0);
        shift(2, 2, 2, 2, 1);
        shift(0, 0, 1, 0, 0);
        shift(3, 3, 3, 5, 2);

        repeat (40) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        calm(4);

        repeat (5) step(1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        repeat (3) step(1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        calm(2);

        step(1'b1, 1'b1);
        step();
        repeat (6) step(1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        step();
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        calm(2);

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            step(1'b0);
            calm(2);
            shift(1, 1, 1, 1, 0);
        end

        step(1'b0, 1'b1);
        calm(2);
        shift(1, 1, 1, 1, 1);
    endtask

    task random_run();
        TracTxn tr;
        int style = 0;
        int left  = 0;

        repeat (num_random) begin
            if (left == 0) begin
                style = $urandom_range(0, 3);
                left  = 40;
            end
            left--;

            tr = new();
            tr.rst_w = 2;
            case (style)
                0: begin
                    tr.start_w = 300; tr.row_w = 200; tr.done_w = 50;  tr.shut_w = 200;
                end
                1: begin
                    tr.start_w = 500; tr.row_w = 100; tr.done_w = 20;  tr.shut_w = 100;
                end
                2: begin
                    tr.start_w = 300; tr.row_w = 300; tr.done_w = 300; tr.shut_w = 300;
                end
                default: begin
                    tr.start_w = 300; tr.row_w = 600; tr.done_w = 100; tr.shut_w = 300;
                end
            endcase

            if (!tr.randomize())
                $fatal(1, "[GEN] randomization failed");
            drv.drive(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class TracEnvironment;
    TracGenerator  gen;
    TracDriver     drv;
    TracMonitor    mon;
    TracScoreboard sb;

    virtual trac_if vif;

    function new(virtual trac_if vif, int num_random = 20000);
        this.vif = vif;
        sb  = new();
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_random);
    endfunction

    task run();
        fork
            mon.run();
        join_none

        gen.directed();
        gen.random_run();

        repeat (2) @(posedge vif.clk);
        #1;
        sb.report();

        if (sb.errors != 0)
            $fatal(1, "[ENV] TEST FAILED (%0d errors)", sb.errors);
        else
            $display("[ENV] TEST PASSED");
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_TractorDriver;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    trac_if vif (clk);

    TractorDriver dut (
        .clk          (clk),
        .rst_n        (vif.rst_n),
        .start_engine (vif.start),
        .row_end      (vif.row_end),
        .field_done   (vif.done),
        .shutdown     (vif.shut),
        .glow_plugs   (vif.glow),
        .plow_down    (vif.plow),
        .turning      (vif.turning),
        .beacon       (vif.beacon)
    );

    TracEnvironment env;

    initial begin
        $dumpfile("TractorDriver_waveform.vcd");
        $dumpvars(0, tb_TractorDriver);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.start   = 1'b0;
        vif.row_end = 1'b0;
        vif.done    = 1'b0;
        vif.shut    = 1'b0;

        repeat (2) @(negedge clk);

        env = new(vif);
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "[TB] timeout");
    end
endmodule //The last line must be empty so vscode doesn't give a mistake

