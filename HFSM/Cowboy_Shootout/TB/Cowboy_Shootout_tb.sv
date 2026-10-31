`timescale 1ns/1ps

typedef enum int {C_PREPARING, C_WALKING, C_SHOOTING, C_CHEATER} cow_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface cow_if (input logic clk);
    logic       rst_n;
    logic       p1;
    logic       p2;
    logic       signal;
    logic [1:0] winner;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, p1, p2, signal, winner;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class CowTxn;
    rand bit rst_n;
    rand bit p1;
    rand bit p2;

    int rst_w = 20;
    int p1_w  = 20;
    int p2_w  = 20;

    logic       signal;
    logic [1:0] winner;

    constraint c_ctrl {
        rst_n dist {1'b0 := rst_w, 1'b1 := 1000 - rst_w};
        p1    dist {1'b1 := p1_w,  1'b0 := 1000 - p1_w};
        p2    dist {1'b1 := p2_w,  1'b0 := 1000 - p2_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class CowScoreboard;
    cow_e       st;
    bit [15:0]  counter;
    bit         s1;
    bit         s2;

    int checked          = 0;
    int errors           = 0;
    int walks            = 0;
    int starts           = 0;
    int cheat_prep       = 0;
    int cheat_walk       = 0;
    int cheat_prio_prep  = 0;
    int cheat_prio_walk  = 0;
    int trig_p1          = 0;
    int trig_p2          = 0;
    int trig_both        = 0;
    int p1_wins          = 0;
    int p2_wins          = 0;
    int ties             = 0;
    int late_shots       = 0;
    int prep_waits       = 0;
    int walk_waits       = 0;
    int shoot_waits      = 0;
    int sh_none          = 0;
    int sh_p1            = 0;
    int sh_p2            = 0;
    int sh_both_latched  = 0;
    int chw_p1           = 0;
    int chw_p2           = 0;
    int chw_both         = 0;
    int chw_idle         = 0;
    int resets_prep      = 0;
    int resets_walk      = 0;
    int resets_shoot     = 0;
    int resets_cheater   = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st      = C_PREPARING;
        counter = 16'd0;
        s1      = 1'b0;
        s2      = 1'b0;
    endfunction

    function void note_trigger(CowTxn tr);
        if (tr.p1 && tr.p2) trig_both++;
        else if (tr.p1)     trig_p1++;
        else                trig_p2++;
    endfunction

    function void step_model(CowTxn tr);
        cow_e      next_st;
        bit [15:0] next_cnt;
        bit        next_s1;
        bit        next_s2;
        bit        any_shot;

        next_st  = st;
        next_cnt = counter;
        next_s1  = s1;
        next_s2  = s2;
        any_shot = tr.p1 || tr.p2;

        if (st != C_CHEATER)
            next_cnt = counter + 1'b1;

        case (st)
            C_PREPARING: begin
                if (any_shot) begin
                    next_st = C_CHEATER;
                    cheat_prep++;
                    note_trigger(tr);
                    if (counter >= 16'd5) cheat_prio_prep++;
                end
                else if (counter >= 16'd5) begin
                    next_st = C_WALKING;
                    walks++;
                end
                else
                    prep_waits++;
            end

            C_WALKING: begin
                if (any_shot) begin
                    next_st = C_CHEATER;
                    cheat_walk++;
                    note_trigger(tr);
                    if (counter >= 16'd15) cheat_prio_walk++;
                end
                else if (counter >= 16'd15) begin
                    next_st = C_SHOOTING;
                    starts++;
                end
                else
                    walk_waits++;
            end

            C_SHOOTING: begin
                if (tr.p1 && !s1 && !s2) next_s1 = 1'b1;
                if (tr.p2 && !s1 && !s2) next_s2 = 1'b1;

                if (!s1 && !s2) begin
                    if (tr.p1 && tr.p2) ties++;
                    else if (tr.p1)     p1_wins++;
                    else if (tr.p2)     p2_wins++;
                    else                shoot_waits++;
                end
                else if (any_shot)
                    late_shots++;
            end

            C_CHEATER: next_st = C_CHEATER;

            default: next_st = C_PREPARING;
        endcase

        st      = next_st;
        counter = next_cnt;
        s1      = next_s1;
        s2      = next_s2;
    endfunction

    function void check(CowTxn tr);
        bit       ok = 1;
        bit       exp_signal;
        bit [1:0] exp_winner;

        if (!tr.rst_n) begin
            case (st)
                C_PREPARING: if (counter != 0) resets_prep++;
                C_WALKING:   resets_walk++;
                C_SHOOTING:  resets_shoot++;
                C_CHEATER:   resets_cheater++;
                default: ;
            endcase
            reset_model();
        end

        exp_signal = (st == C_SHOOTING);
        exp_winner = 2'b00;

        if (st == C_SHOOTING) begin
            if (s1)      exp_winner = 2'b01;
            else if (s2) exp_winner = 2'b10;

            if (s1)      sh_p1++;
            else if (s2) sh_p2++;
            else         sh_none++;
            if (s1 && s2) sh_both_latched++;
        end
        else if (st == C_CHEATER) begin
            if (tr.p1)      exp_winner = 2'b10;
            else if (tr.p2) exp_winner = 2'b01;

            if (tr.p1 && tr.p2) chw_both++;
            else if (tr.p1)     chw_p1++;
            else if (tr.p2)     chw_p2++;
            else                chw_idle++;
        end

        if (tr.signal !== exp_signal) begin
            $error("[SB] shoot_signal mismatch @ %0t: got %0b, expected %0b (state %s, counter %0d)",
                   $time, tr.signal, exp_signal, st.name(), counter);
            ok = 0;
        end

        if (tr.winner !== exp_winner) begin
            $error("[SB] winner mismatch @ %0t: got %0b, expected %0b (state %s, s1 %0b, s2 %0b)",
                   $time, tr.winner, exp_winner, st.name(), s1, s2);
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
        $display("preparing -> walking    : %0d", walks);
        $display("walking -> shooting     : %0d", starts);
        $display("cheat while preparing   : %0d", cheat_prep);
        $display("cheat while walking     : %0d", cheat_walk);
        $display("cheat at counter 5      : %0d", cheat_prio_prep);
        $display("cheat at counter 15     : %0d", cheat_prio_walk);
        $display("cheat by p1 only        : %0d", trig_p1);
        $display("cheat by p2 only        : %0d", trig_p2);
        $display("cheat by both           : %0d", trig_both);
        $display("p1 shot first           : %0d", p1_wins);
        $display("p2 shot first           : %0d", p2_wins);
        $display("both shot together      : %0d", ties);
        $display("shots after winner      : %0d", late_shots);
        $display("waiting in preparing    : %0d", prep_waits);
        $display("waiting in walking      : %0d", walk_waits);
        $display("waiting in shooting     : %0d", shoot_waits);
        $display("shooting, no winner     : %0d", sh_none);
        $display("shooting, p1 wins       : %0d", sh_p1);
        $display("shooting, p2 wins       : %0d", sh_p2);
        $display("shooting, s1 and s2 set : %0d", sh_both_latched);
        $display("cheater, p1 shoots      : %0d", chw_p1);
        $display("cheater, p2 shoots      : %0d", chw_p2);
        $display("cheater, both shoot     : %0d", chw_both);
        $display("cheater, nobody shoots  : %0d", chw_idle);
        $display("resets in preparing     : %0d", resets_prep);
        $display("resets in walking       : %0d", resets_walk);
        $display("resets in shooting      : %0d", resets_shoot);
        $display("resets in cheater       : %0d", resets_cheater);
        $display("--------------------------------------------");

        if (walks == 0 || starts == 0)
            $warning("[SB] not every phase change (preparing / walking / shooting) was reached");
        if (cheat_prep == 0 || cheat_walk == 0)
            $warning("[SB] cheating was not exercised in both preparing and walking");
        if (cheat_prio_prep == 0 || cheat_prio_walk == 0)
            $warning("[SB] a shot on the last edge of preparing / walking (counter 5 / 15) was never applied");
        if (trig_p1 == 0 || trig_p2 == 0 || trig_both == 0)
            $warning("[SB] cheating by p1 only / p2 only / both was not exercised");
        if (p1_wins == 0 || p2_wins == 0 || ties == 0)
            $warning("[SB] not every shootout result (p1 / p2 / both together) was reached");
        if (late_shots == 0)
            $warning("[SB] a shot after the winner was decided was never applied");
        if (prep_waits == 0 || walk_waits == 0 || shoot_waits == 0)
            $warning("[SB] waiting in preparing / walking / shooting was never exercised");
        if (sh_none == 0 || sh_p1 == 0 || sh_p2 == 0 || sh_both_latched == 0)
            $warning("[SB] not every winner output in shooting (none / p1 / p2 / s1 and s2 set) was seen");
        if (chw_p1 == 0 || chw_p2 == 0 || chw_both == 0 || chw_idle == 0)
            $warning("[SB] not every winner output in cheater (p1 / p2 / both / none shooting) was seen");
        if (resets_prep == 0 || resets_walk == 0 || resets_shoot == 0 || resets_cheater == 0)
            $warning("[SB] reset was not applied in every state");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class CowMonitor;
    virtual cow_if vif;
    CowScoreboard  sb;

    function new(virtual cow_if vif, CowScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        CowTxn tr;
        forever begin
            @(vif.mon_cb);
            tr        = new();
            tr.rst_n  = vif.mon_cb.rst_n;
            tr.p1     = vif.mon_cb.p1;
            tr.p2     = vif.mon_cb.p2;
            tr.signal = vif.mon_cb.signal;
            tr.winner = vif.mon_cb.winner;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class CowDriver;
    virtual cow_if vif;

    function new(virtual cow_if vif);
        this.vif = vif;
    endfunction

    task drive(CowTxn tr);
        @(negedge vif.clk);
        vif.rst_n <= tr.rst_n;
        vif.p1    <= tr.p1;
        vif.p2    <= tr.p2;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class CowGenerator;
    CowDriver drv;
    int       num_random;

    function new(CowDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit p1 = 1'b0, bit p2 = 1'b0);
        CowTxn tr;
        tr       = new();
        tr.rst_n = rst_n;
        tr.p1    = p1;
        tr.p2    = p2;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task race(int delay, int mode);
        step(1'b0);
        calm(16);
        calm(delay);
        case (mode)
            0: step(1'b1, 1'b1, 1'b0);
            1: step(1'b1, 1'b0, 1'b1);
            2: step(1'b1, 1'b1, 1'b1);
            3: begin
                step(1'b1, 1'b1, 1'b0);
                step(1'b1, 1'b0, 1'b1);
            end
            4: begin
                step(1'b1, 1'b0, 1'b1);
                step(1'b1, 1'b1, 1'b0);
            end
            default: ;
        endcase
        calm(2);
        repeat (2) step(1'b1, 1'b1, 1'b1);
        calm(2);
    endtask

    task cheat(int when, int who);
        step(1'b0);
        calm(when);
        step(1'b1, (who != 1), (who != 0));
        calm(1);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b1, 1'b1);
        calm(2);
    endtask

    task to_stage(int s);
        step(1'b0);
        if (s == 1) calm(3);
        if (s == 2) calm(10);
        if (s == 3) begin
            calm(16);
            step(1'b1, 1'b1, 1'b0);
            calm(2);
        end
        if (s == 4) begin
            calm(2);
            step(1'b1, 1'b0, 1'b1);
            calm(2);
        end
    endtask

    task directed();
        step(1'b0);
        step(1'b0, 1'b1, 1'b1);

        race(0, 0);
        race(0, 1);
        race(0, 2);
        race(3, 3);
        race(1, 4);
        race(5, 5);
        race(10, 0);

        cheat(0, 0);
        cheat(1, 1);
        cheat(3, 2);
        cheat(4, 0);
        cheat(5, 0);
        cheat(5, 1);
        cheat(5, 2);
        cheat(6, 1);
        cheat(10, 2);
        cheat(14, 0);
        cheat(15, 0);
        cheat(15, 1);
        cheat(15, 2);

        for (int s = 1; s <= 4; s++) begin
            to_stage(s);
            step(1'b0, 1'b1, 1'b1);
            race(0, s % 4);
        end

        step(1'b0, 1'b1, 1'b1);
        calm(2);
        race(2, 2);
    endtask

    task random_run();
        CowTxn tr;
        int style = 0;
        int left  = 0;

        repeat (num_random) begin
            if (left == 0) begin
                style = $urandom_range(0, 3);
                left  = 40;
            end
            left--;

            tr = new();
            case (style)
                0: begin
                    tr.rst_w = 20; tr.p1_w = 20;  tr.p2_w = 20;
                end
                1: begin
                    tr.rst_w = 10; tr.p1_w = 5;   tr.p2_w = 5;
                end
                2: begin
                    tr.rst_w = 30; tr.p1_w = 100; tr.p2_w = 100;
                end
                default: begin
                    tr.rst_w = 20; tr.p1_w = 40;  tr.p2_w = 10;
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
class CowEnvironment;
    CowGenerator  gen;
    CowDriver     drv;
    CowMonitor    mon;
    CowScoreboard sb;

    virtual cow_if vif;

    function new(virtual cow_if vif, int num_random = 20000);
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
module tb_Cowboy_Shootout;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    cow_if vif (clk);

    Cowboy_Shootout dut (
        .rst_n        (vif.rst_n),
        .clk          (clk),
        .shoot_p1     (vif.p1),
        .shoot_p2     (vif.p2),
        .shoot_signal (vif.signal),
        .winner       (vif.winner)
    );

    CowEnvironment env;

    initial begin
        $dumpfile("Cowboy_Shootout_waveform.vcd");
        $dumpvars(0, tb_Cowboy_Shootout);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n = 1'b0;
        vif.p1    = 1'b0;
        vif.p2    = 1'b0;

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

