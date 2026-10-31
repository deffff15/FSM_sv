`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface shark_if (input logic clk);
    logic       rst_n;
    logic       blood;
    logic       prey;
    logic       orca;
    logic       healed;
    logic [1:0] status;
    logic       alert;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, blood, prey, orca, healed, status, alert;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class SharkTxn;
    rand bit rst_n;
    rand bit blood;
    rand bit prey;
    rand bit orca;
    rand bit healed;

    int rst_w   = 10;
    int blood_w = 100;
    int prey_w  = 150;
    int orca_w  = 30;
    int heal_w  = 100;

    logic [1:0] status;
    logic       alert;

    constraint c_ctrl {
        rst_n  dist {1'b0 := rst_w,   1'b1 := 1000 - rst_w};
        blood  dist {1'b1 := blood_w, 1'b0 := 1000 - blood_w};
        prey   dist {1'b1 := prey_w,  1'b0 := 1000 - prey_w};
        orca   dist {1'b1 := orca_w,  1'b0 := 1000 - orca_w};
        healed dist {1'b1 := heal_w,  1'b0 := 1000 - heal_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------

class SharkScoreboard;
    bit hunt;
    bit evalr;
    bit inj;

    int checked        = 0;
    int errors         = 0;
    int hunts          = 0;
    int blood_hunting  = 0;
    int blood_prio     = 0;
    int blood_orca     = 0;
    int blood_inj      = 0;
    int catches        = 0;
    int orca_hunt      = 0;
    int orca_swim      = 0;
    int orca_inj       = 0;
    int heals          = 0;
    int orca_heal      = 0;
    int heal_ignored   = 0;
    int prey_ignored   = 0;
    int swim_idle      = 0;
    int hunt_waits     = 0;
    int inj_waits      = 0;
    int out_00         = 0;
    int out_10         = 0;
    int out_11         = 0;
    int out_11_inj     = 0;
    int resets_hunt    = 0;
    int resets_inj     = 0;
    int resets_both    = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        hunt  = 1'b0;
        evalr = 1'b0;
        inj   = 1'b0;
    endfunction

    function void step_model(SharkTxn tr);
        bit n_hunt;
        bit n_evalr;
        bit n_inj;

        if (tr.blood && !hunt)
            hunts++;
        if (tr.blood && hunt)
            blood_hunting++;
        if (tr.blood && tr.prey && hunt)
            blood_prio++;
        if (tr.blood && tr.orca)
            blood_orca++;
        if (tr.blood && inj)
            blood_inj++;
        if (hunt && tr.prey && !tr.blood && !tr.orca)
            catches++;
        if (tr.orca && hunt && !tr.blood)
            orca_hunt++;
        if (tr.orca && !hunt && !inj)
            orca_swim++;
        if (tr.orca && inj)
            orca_inj++;
        if (inj && tr.healed && !tr.orca)
            heals++;
        if (inj && tr.healed && tr.orca)
            orca_heal++;
        if (tr.healed && !inj)
            heal_ignored++;
        if (tr.prey && !hunt)
            prey_ignored++;
        if (!hunt && !inj && !tr.blood && !tr.orca)
            swim_idle++;
        if (hunt && !tr.blood && !tr.prey && !tr.orca)
            hunt_waits++;
        if (inj && !tr.orca && !tr.healed)
            inj_waits++;

        n_hunt  = tr.blood || (hunt  && !tr.orca && !tr.prey);
        n_evalr = tr.blood || (evalr && !tr.orca && !tr.prey);
        n_inj   = tr.orca  || (inj   && !tr.healed);

        hunt  = n_hunt;
        evalr = n_evalr;
        inj   = n_inj;
    endfunction

    function void check(SharkTxn tr);
        bit       ok = 1;
        bit [1:0] exp_status;
        bit       exp_alert;

        if (!tr.rst_n) begin
            if (hunt && inj)  resets_both++;
            else if (hunt)    resets_hunt++;
            else if (inj)     resets_inj++;
            reset_model();
        end

        exp_alert = evalr || inj;
        if (hunt && evalr)  exp_status = 2'b11;
        else if (inj)       exp_status = 2'b10;
        else if (hunt)      exp_status = 2'b01;
        else                exp_status = 2'b00;

        if (exp_status == 2'b00) out_00++;
        if (exp_status == 2'b10) out_10++;
        if (exp_status == 2'b11) begin
            out_11++;
            if (inj) out_11_inj++;
        end

        if (tr.status !== exp_status) begin
            $error("[SB] shark_status mismatch @ %0t: got %b, expected %b (hunt %0b, eval %0b, injured %0b)",
                   $time, tr.status, exp_status, hunt, evalr, inj);
            ok = 0;
        end

        if (tr.alert !== exp_alert) begin
            $error("[SB] danger_alert mismatch @ %0t: got %0b, expected %0b (hunt %0b, eval %0b, injured %0b)",
                   $time, tr.alert, exp_alert, hunt, evalr, inj);
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
        $display("hunts started           : %0d", hunts);
        $display("blood while hunting     : %0d", blood_hunting);
        $display("blood over prey caught  : %0d", blood_prio);
        $display("blood together with orca: %0d", blood_orca);
        $display("blood while injured     : %0d", blood_inj);
        $display("prey caught (hunt ends) : %0d", catches);
        $display("orca during hunt        : %0d", orca_hunt);
        $display("orca while swimming     : %0d", orca_swim);
        $display("orca while injured      : %0d", orca_inj);
        $display("healed                  : %0d", heals);
        $display("orca over healed        : %0d", orca_heal);
        $display("healed ignored          : %0d", heal_ignored);
        $display("prey caught ignored     : %0d", prey_ignored);
        $display("waiting, swimming       : %0d", swim_idle);
        $display("waiting, hunting        : %0d", hunt_waits);
        $display("waiting, injured        : %0d", inj_waits);
        $display("status 00 cycles        : %0d", out_00);
        $display("status 10 cycles        : %0d", out_10);
        $display("status 11 cycles        : %0d", out_11);
        $display("status 11 and injured   : %0d", out_11_inj);
        $display("resets while hunting    : %0d", resets_hunt);
        $display("resets while injured    : %0d", resets_inj);
        $display("resets hunting+injured  : %0d", resets_both);
        $display("--------------------------------------------");

        if (hunts == 0 || catches == 0)
            $warning("[SB] a hunt was not both started and ended by prey_caught");
        if (blood_hunting == 0 || blood_prio == 0)
            $warning("[SB] blood while hunting / blood together with prey_caught was never applied");
        if (blood_orca == 0 || blood_inj == 0)
            $warning("[SB] blood together with orca / blood while injured was never applied");
        if (orca_hunt == 0 || orca_swim == 0 || orca_inj == 0)
            $warning("[SB] orca_attack was not applied while hunting / swimming / injured");
        if (heals == 0 || orca_heal == 0)
            $warning("[SB] healing or orca_attack together with healed was never applied");
        if (heal_ignored == 0 || prey_ignored == 0)
            $warning("[SB] ignored healed / prey_caught was never exercised");
        if (swim_idle == 0 || hunt_waits == 0 || inj_waits == 0)
            $warning("[SB] waiting while swimming / hunting / injured was never exercised");
        if (out_00 == 0 || out_10 == 0 || out_11 == 0 || out_11_inj == 0)
            $warning("[SB] not every status output (00 / 10 / 11 / 11 while injured) was seen");
        if (resets_hunt == 0 || resets_inj == 0 || resets_both == 0)
            $warning("[SB] reset was not applied while hunting / injured / both");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class SharkMonitor;
    virtual shark_if vif;
    SharkScoreboard  sb;

    function new(virtual shark_if vif, SharkScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        SharkTxn tr;
        forever begin
            @(vif.mon_cb);
            tr        = new();
            tr.rst_n  = vif.mon_cb.rst_n;
            tr.blood  = vif.mon_cb.blood;
            tr.prey   = vif.mon_cb.prey;
            tr.orca   = vif.mon_cb.orca;
            tr.healed = vif.mon_cb.healed;
            tr.status = vif.mon_cb.status;
            tr.alert  = vif.mon_cb.alert;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class SharkDriver;
    virtual shark_if vif;

    function new(virtual shark_if vif);
        this.vif = vif;
    endfunction

    task drive(SharkTxn tr);
        @(negedge vif.clk);
        vif.rst_n  <= tr.rst_n;
        vif.blood  <= tr.blood;
        vif.prey   <= tr.prey;
        vif.orca   <= tr.orca;
        vif.healed <= tr.healed;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class SharkGenerator;
    SharkDriver drv;
    int         num_random;

    function new(SharkDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit blood = 1'b0, bit prey = 1'b0,
              bit orca = 1'b0, bit healed = 1'b0);
        SharkTxn tr;
        tr        = new();
        tr.rst_n  = rst_n;
        tr.blood  = blood;
        tr.prey   = prey;
        tr.orca   = orca;
        tr.healed = healed;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task to_stage(int s);
        if (s == 1) step(1'b1, 1'b1);
        if (s == 2) step(1'b1, 1'b0, 1'b0, 1'b1);
        if (s == 3) step(1'b1, 1'b1, 1'b0, 1'b1);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        calm(3);

        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1);
        calm(3);
        step(1'b1, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1);
        step(1'b1, 1'b1);
        calm(2);
        step(1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1, 1'b0, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b1);
        calm(2);

        repeat (20) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);

        for (int s = 1; s <= 3; s++) begin
            to_stage(s);
            step(1'b0);
            calm(2);
            step(1'b1, 1'b1);
            calm(2);
            step(1'b1, 1'b0, 1'b1);
            calm(2);
        end

        step(1'b0, 1'b1, 1'b1, 1'b1, 1'b1);
        calm(2);
        step(1'b1, 1'b1);
        calm(2);
        step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        calm(2);
    endtask

    task random_run();
        SharkTxn tr;
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
                    tr.rst_w = 10; tr.blood_w = 100; tr.prey_w = 150;
                    tr.orca_w = 30; tr.heal_w = 100;
                end
                1: begin
                    tr.rst_w = 10; tr.blood_w = 200; tr.prey_w = 50;
                    tr.orca_w = 20; tr.heal_w = 50;
                end
                2: begin
                    tr.rst_w = 10; tr.blood_w = 100; tr.prey_w = 100;
                    tr.orca_w = 100; tr.heal_w = 100;
                end
                default: begin
                    tr.rst_w = 20; tr.blood_w = 50; tr.prey_w = 300;
                    tr.orca_w = 10; tr.heal_w = 300;
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
class SharkEnvironment;
    SharkGenerator  gen;
    SharkDriver     drv;
    SharkMonitor    mon;
    SharkScoreboard sb;

    virtual shark_if vif;

    function new(virtual shark_if vif, int num_random = 20000);
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
module tb_SharksLife;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    shark_if vif (clk);

    SharksLife dut (
        .clk              (clk),
        .rst_n            (vif.rst_n),
        .blood_detected_i (vif.blood),
        .prey_caught_i    (vif.prey),
        .orca_attack_i    (vif.orca),
        .healed_i         (vif.healed),
        .shark_status_o   (vif.status),
        .danger_alert_o   (vif.alert)
    );

    SharkEnvironment env;

    initial begin
        $dumpfile("SharksLife_waveform.vcd");
        $dumpvars(0, tb_SharksLife);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.blood  = 1'b0;
        vif.prey   = 1'b0;
        vif.orca   = 1'b0;
        vif.healed = 1'b0;

        repeat (2) @(negedge clk);

        env = new(vif);
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "[TB] timeout");
    end
endmodule //The last line must be empty so vs code doesn't give a mistake

