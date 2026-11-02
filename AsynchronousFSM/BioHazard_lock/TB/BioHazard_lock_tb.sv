`timescale 1ns/1ps

typedef enum int {B_VENTILATED, B_CONTAMINATED, B_PURGING, B_EQUALIZING} bio_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface bio_if (input logic clk);
    logic rst_n;
    logic sb;
    logic door;
    logic eq;
    logic pump;
    logic lock;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, sb, door, eq, pump, lock;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class BioTxn;
    rand bit rst_n;
    rand bit sb;
    rand bit door;
    rand bit eq;

    int rst_w  = 30;
    int sb_w   = 300;
    int door_w = 500;
    int eq_w   = 500;

    logic pump;
    logic lock;

    constraint c_ctrl {
        rst_n dist {1'b0 := rst_w,  1'b1 := 1000 - rst_w};
        sb    dist {1'b1 := sb_w,   1'b0 := 1000 - sb_w};
        door  dist {1'b1 := door_w, 1'b0 := 1000 - door_w};
        eq    dist {1'b1 := eq_w,   1'b0 := 1000 - eq_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class BioScoreboard;
    bio_e st;
    bit   prev_r;
    bit   prev_s;
    bit   prev_d;
    bit   prev_e;

    int checked        = 0;
    int errors         = 0;
    int events         = 0;
    int idle_cycles    = 0;
    int enters         = 0;
    int seals          = 0;
    int unbalances     = 0;
    int vents          = 0;
    int vent_idle      = 0;
    int cont_idle      = 0;
    int purge_idle     = 0;
    int eq_idle        = 0;
    int ignored_sb     = 0;
    int ignored_door   = 0;
    int ignored_eq     = 0;
    int stale_states   = 0;
    int resets_cont    = 0;
    int resets_purge   = 0;
    int resets_eq      = 0;
    int reset_idle     = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st     = B_VENTILATED;
        prev_r = 1'b0;
        prev_s = 1'b0;
        prev_d = 1'b0;
        prev_e = 1'b0;
    endfunction

    function bit pending(bio_e s, bit r, bit sbv, bit d, bit e);
        if (!r)
            return (s != B_VENTILATED);
        case (s)
            B_VENTILATED:    return sbv;
            B_CONTAMINATED:  return !d;
            B_PURGING:       return !e;
            B_EQUALIZING:    return e;
            default:         return 1'b1;
        endcase
    endfunction

    function void step_model(BioTxn tr);
        bio_e next_st;

        next_st = st;
        events++;

        if (tr.rst_n) begin
            if (tr.sb != prev_s && st != B_VENTILATED)
                ignored_sb++;
            if (tr.door != prev_d && st != B_CONTAMINATED)
                ignored_door++;
            if (tr.eq != prev_e && st != B_PURGING && st != B_EQUALIZING)
                ignored_eq++;
        end

        if (!tr.rst_n) begin
            case (st)
                B_CONTAMINATED: resets_cont++;
                B_PURGING:      resets_purge++;
                B_EQUALIZING:   resets_eq++;
                default:        reset_idle++;
            endcase
            next_st = B_VENTILATED;
        end
        else begin
            case (st)
                B_VENTILATED: begin
                    if (tr.sb) begin
                        next_st = B_CONTAMINATED;
                        enters++;
                    end
                    else
                        vent_idle++;
                end

                B_CONTAMINATED: begin
                    if (!tr.door) begin
                        next_st = B_PURGING;
                        seals++;
                    end
                    else
                        cont_idle++;
                end

                B_PURGING: begin
                    if (!tr.eq) begin
                        next_st = B_EQUALIZING;
                        unbalances++;
                    end
                    else
                        purge_idle++;
                end

                B_EQUALIZING: begin
                    if (tr.eq) begin
                        next_st = B_VENTILATED;
                        vents++;
                    end
                    else
                        eq_idle++;
                end

                default: next_st = B_VENTILATED;
            endcase
        end

        st = next_st;

        if (pending(st, tr.rst_n, tr.sb, tr.door, tr.eq))
            stale_states++;
    endfunction

    function void check(BioTxn tr);
        bit ok = 1;
        bit exp_pump;
        bit exp_lock;

        if (tr.rst_n != prev_r || tr.sb != prev_s ||
            tr.door != prev_d || tr.eq != prev_e)
            step_model(tr);
        else
            idle_cycles++;

        prev_r = tr.rst_n;
        prev_s = tr.sb;
        prev_d = tr.door;
        prev_e = tr.eq;

        exp_pump = (st == B_PURGING) || (st == B_EQUALIZING);
        exp_lock = (st == B_VENTILATED);

        if (tr.pump !== exp_pump) begin
            $error("[SB] evacuate_pump mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.pump, exp_pump, st.name());
            ok = 0;
        end

        if (tr.lock !== exp_lock) begin
            $error("[SB] inner_lock_release mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.lock, exp_lock, st.name());
            ok = 0;
        end

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked          : %0d", checked);
        $display("errors                  : %0d", errors);
        $display("input change events     : %0d", events);
        $display("cycles without change   : %0d", idle_cycles);
        $display("ventilated -> contam.   : %0d", enters);
        $display("contam. -> purging      : %0d", seals);
        $display("purging -> equalizing   : %0d", unbalances);
        $display("equalizing -> ventilated: %0d", vents);
        $display("event, no change: vent  : %0d", vent_idle);
        $display("event, no change: contam: %0d", cont_idle);
        $display("event, no change: purge : %0d", purge_idle);
        $display("event, no change: equal.: %0d", eq_idle);
        $display("sb_entered change ignored   : %0d", ignored_sb);
        $display("outer_door change ignored   : %0d", ignored_door);
        $display("pressure change ignored     : %0d", ignored_eq);
        $display("pending (stale) states  : %0d", stale_states);
        $display("resets in contaminated  : %0d", resets_cont);
        $display("resets in purging       : %0d", resets_purge);
        $display("resets in equalizing    : %0d", resets_eq);
        $display("resets while ventilated : %0d", reset_idle);
        $display("--------------------------------------------");

        if (enters == 0 || seals == 0 || unbalances == 0 || vents == 0)
            $warning("[SB] a full cycle through all four states was not completed");
        if (vent_idle == 0 || cont_idle == 0 || purge_idle == 0 || eq_idle == 0)
            $warning("[SB] an input change without a transition was not exercised in every state");
        if (ignored_sb == 0 || ignored_door == 0 || ignored_eq == 0)
            $warning("[SB] ignored sb_entered / outer_door_open / pressure_equalized changes were not exercised");
        if (stale_states == 0)
            $warning("[SB] a state with a pending transition (no input event) was never reached");
        if (resets_cont == 0 || resets_purge == 0 || resets_eq == 0)
            $warning("[SB] rst_n was not applied in contaminated / purging / equalizing");
        if (reset_idle == 0)
            $warning("[SB] an input change while rst_n is low was never applied");
        if (idle_cycles == 0)
            $warning("[SB] a cycle without any input change was never applied");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class BioMonitor;
    virtual bio_if vif;
    BioScoreboard  sb;

    function new(virtual bio_if vif, BioScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        BioTxn tr;
        forever begin
            @(vif.mon_cb);
            tr       = new();
            tr.rst_n = vif.mon_cb.rst_n;
            tr.sb    = vif.mon_cb.sb;
            tr.door  = vif.mon_cb.door;
            tr.eq    = vif.mon_cb.eq;
            tr.pump  = vif.mon_cb.pump;
            tr.lock  = vif.mon_cb.lock;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class BioDriver;
    virtual bio_if vif;

    function new(virtual bio_if vif);
        this.vif = vif;
    endfunction

    task drive(BioTxn tr);
        @(negedge vif.clk);
        vif.rst_n <= tr.rst_n;
        vif.sb    <= tr.sb;
        vif.door  <= tr.door;
        vif.eq    <= tr.eq;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class BioGenerator;
    BioDriver drv;
    int       num_random;

    bit lr = 1'b0;
    bit ls = 1'b0;
    bit ld = 1'b0;
    bit le = 1'b0;

    function new(BioDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit sb = 1'b0, bit door = 1'b0, bit eq = 1'b0);
        BioTxn tr;
        tr       = new();
        tr.rst_n = rst_n;
        tr.sb    = sb;
        tr.door  = door;
        tr.eq    = eq;
        lr = rst_n;
        ls = sb;
        ld = door;
        le = eq;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task hold(int n = 1);
        repeat (n) step(lr, ls, ld, le);
    endtask

    task to_stage(int s);
        if (s >= 1) step(1'b1, 1'b1, 1'b1, 1'b1);
        if (s >= 2) step(1'b1, 1'b1, 1'b0, 1'b1);
        if (s >= 3) step(1'b1, 1'b1, 1'b0, 1'b0);
    endtask

    task directed();
        step(1'b0);
        step(1'b0, 1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b0, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        calm(2);

        step(1'b1, 1'b1, 1'b1, 1'b1);
        hold(2);
        step(1'b1, 1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b1, 1'b0, 1'b1);
        hold(2);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b1, 1'b0, 1'b0);
        hold(2);
        step(1'b1, 1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b1, 1'b0, 1'b0);
        step(1'b1, 1'b1, 1'b0, 1'b1);
        hold(3);
        step(1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1, 1'b1, 1'b0);
        hold(1);
        step(1'b1, 1'b1, 1'b0, 1'b0);
        hold(3);
        step(1'b1, 1'b0, 1'b0, 1'b0);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);

        for (int s = 1; s <= 3; s++) begin
            to_stage(s);
            step(1'b0, 1'b1, 1'b1, 1'b1);
            step(1'b0);
            calm(2);
        end

        step(1'b0, 1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b1, 1'b1, 1'b1);
        hold(1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        step(1'b0);
        calm(2);

        step(1'b1, 1'b1, 1'b1, 1'b1);
        hold(10);
        calm(3);
        step(1'b0);
        calm(2);

        repeat (2) begin
            for (int i = 0; i < 16; i++)
                step(i[3], i[2], i[1], i[0]);
            for (int i = 15; i >= 0; i--)
                step(i[3], i[2], i[1], i[0]);
        end
        calm(4);
        step(1'b0);
        calm(2);
    endtask

    task random_run();
        BioTxn tr;
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
                    tr.rst_w = 30; tr.sb_w = 300; tr.door_w = 500; tr.eq_w = 500;
                end
                1: begin
                    tr.rst_w = 10; tr.sb_w = 100; tr.door_w = 300; tr.eq_w = 700;
                end
                2: begin
                    tr.rst_w = 50; tr.sb_w = 500; tr.door_w = 500; tr.eq_w = 500;
                end
                default: begin
                    tr.rst_w = 20; tr.sb_w = 200; tr.door_w = 800; tr.eq_w = 200;
                end
            endcase

            if (!tr.randomize())
                $fatal(1, "[GEN] randomization failed");
            lr = tr.rst_n;
            ls = tr.sb;
            ld = tr.door;
            le = tr.eq;
            drv.drive(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class BioEnvironment;
    BioGenerator  gen;
    BioDriver     drv;
    BioMonitor    mon;
    BioScoreboard sb;

    virtual bio_if vif;

    function new(virtual bio_if vif, int num_random = 20000);
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
module tb_BioHazard_lock;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    bio_if vif (clk);

    BioHazard_lock dut (
        .rst_n              (vif.rst_n),
        .sb_entered         (vif.sb),
        .outer_door_open    (vif.door),
        .pressure_equalized (vif.eq),
        .evacuate_pump      (vif.pump),
        .inner_lock_release (vif.lock)
    );

    BioEnvironment env;

    initial begin
        $dumpfile("BioHazard_lock_waveform.vcd");
        $dumpvars(0, tb_BioHazard_lock);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n = 1'b0;
        vif.sb    = 1'b0;
        vif.door  = 1'b0;
        vif.eq    = 1'b0;

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

