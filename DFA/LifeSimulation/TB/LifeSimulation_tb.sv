`timescale 1ns/1ps

typedef enum int {L_NONEXISTENT, L_CHILDHOOD, L_CAREER, L_FAMILY, L_RETIREMENT, L_END} life_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface life_if (input logic clk);
    logic       rst_n;
    logic       born;
    logic       career;
    logic       fail;
    logic [6:0] age;
    logic [2:0] phase;
    logic       legacy;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, born, career, fail, age, phase, legacy;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class LifeTxn;
    rand bit rst_n;
    rand bit born;
    rand bit career;
    rand bit fail;

    int rst_w    = 10;
    int born_w   = 300;
    int career_w = 500;
    int fail_w   = 5;

    logic [6:0] age;
    logic [2:0] phase;
    logic       legacy;

    constraint c_ctrl {
        rst_n  dist {1'b0 := rst_w,    1'b1 := 1000 - rst_w};
        born   dist {1'b1 := born_w,   1'b0 := 1000 - born_w};
        career dist {1'b1 := career_w, 1'b0 := 1000 - career_w};
        fail   dist {1'b1 := fail_w,   1'b0 := 1000 - fail_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class LifeScoreboard;
    life_e st;
    int    age;

    int checked         = 0;
    int errors          = 0;
    int births          = 0;
    int to_career       = 0;
    int to_family       = 0;
    int to_retire       = 0;
    int deaths_child    = 0;
    int deaths_work     = 0;
    int deaths_retire   = 0;
    int deaths_old      = 0;
    int legacy_deaths   = 0;
    int no_legacy_deaths = 0;
    int edge_legacy     = 0;
    int edge_no_legacy  = 0;
    int fail_prio       = 0;
    int idle_waits      = 0;
    int end_waits       = 0;
    int ignored_born    = 0;
    int ignored_fail    = 0;
    int ignored_career  = 0;
    int resets_mid_life = 0;
    int resets_after_end = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st  = L_NONEXISTENT;
        age = 0;
    endfunction

    function void step_model(LifeTxn tr);
        life_e next_st;
        int    next_age;

        next_st  = st;
        next_age = age;

        if (st == L_NONEXISTENT)
            next_age = 0;
        else if (st != L_END && age < 120)
            next_age = age + 1;

        if (tr.born && st != L_NONEXISTENT)
            ignored_born++;
        if (tr.fail && (st == L_NONEXISTENT || st == L_END))
            ignored_fail++;
        if (tr.career && !(st == L_CHILDHOOD && age >= 18 && !tr.fail))
            ignored_career++;
        if (tr.fail && ((st == L_CHILDHOOD && age >= 18) ||
                        ((st == L_CAREER || st == L_FAMILY) && age >= 65) ||
                        (st == L_RETIREMENT && age >= 100)))
            fail_prio++;
        if (st == L_NONEXISTENT && !tr.born)
            idle_waits++;
        if (st == L_END)
            end_waits++;

        case (st)
            L_NONEXISTENT: begin
                if (tr.born) begin
                    next_st = L_CHILDHOOD;
                    births++;
                end
            end

            L_CHILDHOOD: begin
                if (tr.fail) begin
                    next_st = L_END;
                    deaths_child++;
                end
                else if (age >= 18) begin
                    if (tr.career) begin
                        next_st = L_CAREER;
                        to_career++;
                    end
                    else begin
                        next_st = L_FAMILY;
                        to_family++;
                    end
                end
            end

            L_CAREER, L_FAMILY: begin
                if (tr.fail) begin
                    next_st = L_END;
                    deaths_work++;
                end
                else if (age >= 65) begin
                    next_st = L_RETIREMENT;
                    to_retire++;
                end
            end

            L_RETIREMENT: begin
                if (tr.fail) begin
                    next_st = L_END;
                    deaths_retire++;
                end
                else if (age >= 100) begin
                    next_st = L_END;
                    deaths_old++;
                end
            end

            L_END: next_st = L_END;

            default: next_st = L_NONEXISTENT;
        endcase

        if (next_st == L_END && st != L_END) begin
            if (next_age >= 65) legacy_deaths++;
            else                no_legacy_deaths++;
            if (next_age == 65) edge_legacy++;
            if (next_age == 64) edge_no_legacy++;
        end

        st  = next_st;
        age = next_age;
    endfunction

    function void check(LifeTxn tr);
        bit       ok = 1;
        bit [6:0] exp_age;
        bit [2:0] exp_phase;
        bit       exp_legacy;

        if (!tr.rst_n) begin
            if (st == L_END)
                resets_after_end++;
            else if (st != L_NONEXISTENT)
                resets_mid_life++;
            reset_model();
        end

        exp_age    = age;
        exp_phase  = 3'(st);
        exp_legacy = (st == L_END) && (age >= 65);

        if (tr.age !== exp_age) begin
            $error("[SB] age_o mismatch @ %0t: got %0d, expected %0d (state %s)",
                   $time, tr.age, exp_age, st.name());
            ok = 0;
        end

        if (tr.phase !== exp_phase) begin
            $error("[SB] phase_o mismatch @ %0t: got %0d, expected %0d (state %s)",
                   $time, tr.phase, exp_phase, st.name());
            ok = 0;
        end

        if (tr.legacy !== exp_legacy) begin
            $error("[SB] legacy_left_o mismatch @ %0t: got %0b, expected %0b (state %s, age %0d)",
                   $time, tr.legacy, exp_legacy, st.name(), age);
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
        $display("births                  : %0d", births);
        $display("childhood -> career     : %0d", to_career);
        $display("childhood -> family     : %0d", to_family);
        $display("-> retirement           : %0d", to_retire);
        $display("deaths in childhood     : %0d", deaths_child);
        $display("deaths career/family    : %0d", deaths_work);
        $display("deaths in retirement    : %0d", deaths_retire);
        $display("deaths by old age       : %0d", deaths_old);
        $display("deaths with legacy      : %0d", legacy_deaths);
        $display("deaths without legacy   : %0d", no_legacy_deaths);
        $display("death at age 65 (edge)  : %0d", edge_legacy);
        $display("death at age 64 (edge)  : %0d", edge_no_legacy);
        $display("health_fail over age    : %0d", fail_prio);
        $display("waiting before birth    : %0d", idle_waits);
        $display("waiting in end of life  : %0d", end_waits);
        $display("born_i ignored          : %0d", ignored_born);
        $display("health_fail ignored     : %0d", ignored_fail);
        $display("career_focus ignored    : %0d", ignored_career);
        $display("resets mid-life         : %0d", resets_mid_life);
        $display("resets after end        : %0d", resets_after_end);
        $display("--------------------------------------------");

        if (births == 0)
            $warning("[SB] no life was started");
        if (to_career == 0 || to_family == 0)
            $warning("[SB] not every adult path (career / family) was reached");
        if (to_retire == 0)
            $warning("[SB] retirement was never reached");
        if (deaths_child == 0 || deaths_work == 0 || deaths_retire == 0)
            $warning("[SB] health_fail was not applied in every phase (childhood / career-family / retirement)");
        if (deaths_old == 0)
            $warning("[SB] no life ended by old age (age >= 100)");
        if (legacy_deaths == 0 || no_legacy_deaths == 0)
            $warning("[SB] not every death type (with / without legacy) was reached");
        if (edge_legacy == 0 || edge_no_legacy == 0)
            $warning("[SB] legacy_left boundary (death at age 64 / 65) was not reached");
        if (fail_prio == 0)
            $warning("[SB] health_fail was never applied together with an age threshold");
        if (idle_waits == 0 || end_waits == 0)
            $warning("[SB] waiting before birth or in end of life was never exercised");
        if (ignored_born == 0 || ignored_fail == 0 || ignored_career == 0)
            $warning("[SB] ignored born_i / health_fail / career_focus was never exercised");
        if (resets_mid_life == 0)
            $warning("[SB] reset was never applied in the middle of a life");
        if (resets_after_end == 0)
            $warning("[SB] reset was never applied after the end of life");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class LifeMonitor;
    virtual life_if vif;
    LifeScoreboard  sb;

    function new(virtual life_if vif, LifeScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        LifeTxn tr;
        forever begin
            @(vif.mon_cb);
            tr        = new();
            tr.rst_n  = vif.mon_cb.rst_n;
            tr.born   = vif.mon_cb.born;
            tr.career = vif.mon_cb.career;
            tr.fail   = vif.mon_cb.fail;
            tr.age    = vif.mon_cb.age;
            tr.phase  = vif.mon_cb.phase;
            tr.legacy = vif.mon_cb.legacy;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class LifeDriver;
    virtual life_if vif;

    function new(virtual life_if vif);
        this.vif = vif;
    endfunction

    task drive(LifeTxn tr);
        @(negedge vif.clk);
        vif.rst_n  <= tr.rst_n;
        vif.born   <= tr.born;
        vif.career <= tr.career;
        vif.fail   <= tr.fail;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class LifeGenerator;
    LifeDriver drv;
    int        num_random;

    function new(LifeDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit born = 1'b0, bit career = 1'b0,
              bit fail = 1'b0);
        LifeTxn tr;
        tr        = new();
        tr.rst_n  = rst_n;
        tr.born   = born;
        tr.career = career;
        tr.fail   = fail;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task life(int fail_at, bit career, bit noisy);
        step(1'b1, 1'b1);
        for (int a = 0; a <= 100; a++) begin
            step(1'b1, noisy, career, (a == fail_at));
            if (a == fail_at) break;
        end
        repeat (3) step(1'b1, noisy, career, noisy);
        step(1'b0);
        calm(2);
    endtask

    task to_stage(int s, bit career);
        step(1'b1, 1'b1);
        if (s >= 2) calm(10);
        if (s >= 3) calm(8);
        if (s >= 4) step(1'b1, 1'b0, career);
        if (s >= 5) calm(47);
        if (s >= 6) calm(35);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (3) step();
        repeat (3) step(1'b1, 1'b0, 1'b1, 1'b1);
        calm(2);

        life(-1, 1'b1, 1'b0);
        life(-1, 1'b0, 1'b1);

        life(0,   1'b1, 1'b0);
        life(5,   1'b0, 1'b0);
        life(17,  1'b0, 1'b0);
        life(18,  1'b1, 1'b0);
        life(19,  1'b0, 1'b0);
        life(30,  1'b1, 1'b0);
        life(63,  1'b0, 1'b0);
        life(64,  1'b1, 1'b0);
        life(65,  1'b0, 1'b1);
        life(66,  1'b1, 1'b0);
        life(99,  1'b0, 1'b0);
        life(100, 1'b1, 1'b0);

        to_stage(6, 1'b1);
        repeat (40) step(1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(2);

        for (int s = 1; s <= 6; s++) begin
            to_stage(s, (s % 2) != 0);
            step(1'b0);
            calm(2);
            life(20, (s % 2) != 0, 1'b0);
        end

        step(1'b0, 1'b1);
        calm(2);
        life(-1, 1'b1, 1'b1);
    endtask

    task random_run();
        LifeTxn tr;
        int style = 0;
        int left  = 0;

        repeat (num_random) begin
            if (left == 0) begin
                style = $urandom_range(0, 3);
                left  = 200;
            end
            left--;

            tr = new();
            case (style)
                0: begin
                    tr.rst_w = 8;  tr.born_w = 300; tr.career_w = 500; tr.fail_w = 5;
                end
                1: begin
                    tr.rst_w = 15; tr.born_w = 300; tr.career_w = 300; tr.fail_w = 30;
                end
                2: begin
                    tr.rst_w = 4;  tr.born_w = 500; tr.career_w = 800; tr.fail_w = 2;
                end
                default: begin
                    tr.rst_w = 10; tr.born_w = 100; tr.career_w = 100; tr.fail_w = 10;
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
class LifeEnvironment;
    LifeGenerator  gen;
    LifeDriver     drv;
    LifeMonitor    mon;
    LifeScoreboard sb;

    virtual life_if vif;

    function new(virtual life_if vif, int num_random = 20000);
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
module tb_LifeSimulator;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    life_if vif (clk);

    LifeSimulator dut (
        .clk            (clk),
        .rst_n          (vif.rst_n),
        .born_i         (vif.born),
        .career_focus_i (vif.career),
        .health_fail_i  (vif.fail),
        .age_o          (vif.age),
        .phase_o        (vif.phase),
        .legacy_left_o  (vif.legacy)
    );

    LifeEnvironment env;

    initial begin
        $dumpfile("LifeSimulator_waveform.vcd");
        $dumpvars(0, tb_LifeSimulator);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.born   = 1'b0;
        vif.career = 1'b0;
        vif.fail   = 1'b0;

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
