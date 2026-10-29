`timescale 1ns/1ps

typedef enum int {W_DIRTY, W_SOAKING, W_SCRUB, W_CLEAN} wash_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface wash_if (input logic clk);
    logic water;
    logic brush;
    logic clean;
    logic valve;
    logic motor;
    logic led;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input water, brush, clean, valve, motor, led;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class WashTxn;
    rand bit water;
    rand bit brush;
    rand bit clean;

    int water_w = 500;
    int brush_w = 500;
    int clean_w = 200;

    logic valve;
    logic motor;
    logic led;

    constraint c_ctrl {
        water dist {1'b1 := water_w, 1'b0 := 1000 - water_w};
        brush dist {1'b1 := brush_w, 1'b0 := 1000 - brush_w};
        clean dist {1'b1 := clean_w, 1'b0 := 1000 - clean_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class WashScoreboard;
    wash_e st;
    bit    prev_w;
    bit    prev_b;
    bit    prev_c;

    int checked       = 0;
    int errors        = 0;
    int events        = 0;
    int idle_cycles   = 0;
    int soaks         = 0;
    int soak_aborts   = 0;
    int scrubs        = 0;
    int scrub_backs   = 0;
    int cleans        = 0;
    int clean_resets  = 0;
    int brush_prio    = 0;
    int clean_prio    = 0;
    int stale_states  = 0;
    int dirty_idle    = 0;
    int soak_idle     = 0;
    int scrub_idle    = 0;
    int clean_idle    = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st     = W_DIRTY;
        prev_w = 1'b0;
        prev_b = 1'b0;
        prev_c = 1'b0;
    endfunction

    function bit pending(wash_e s, bit w, bit b, bit c);
        case (s)
            W_DIRTY:   return w;
            W_SOAKING: return b || !w;
            W_SCRUB:   return c || !b;
            W_CLEAN:   return !w && !b && !c;
            default:   return 1'b1;
        endcase
    endfunction

    function void step_model(WashTxn tr);
        wash_e next_st;

        next_st = st;
        events++;

        case (st)
            W_DIRTY: begin
                if (tr.water) begin
                    next_st = W_SOAKING;
                    soaks++;
                end
                else
                    dirty_idle++;
            end

            W_SOAKING: begin
                if (tr.brush) begin
                    next_st = W_SCRUB;
                    scrubs++;
                    if (!tr.water) brush_prio++;
                end
                else if (!tr.water) begin
                    next_st = W_DIRTY;
                    soak_aborts++;
                end
                else
                    soak_idle++;
            end

            W_SCRUB: begin
                if (tr.clean) begin
                    next_st = W_CLEAN;
                    cleans++;
                    if (!tr.brush) clean_prio++;
                end
                else if (!tr.brush) begin
                    next_st = W_SOAKING;
                    scrub_backs++;
                end
                else
                    scrub_idle++;
            end

            W_CLEAN: begin
                if (!tr.water && !tr.brush && !tr.clean) begin
                    next_st = W_DIRTY;
                    clean_resets++;
                end
                else
                    clean_idle++;
            end

            default: next_st = W_DIRTY;
        endcase

        st = next_st;

        if (pending(st, tr.water, tr.brush, tr.clean))
            stale_states++;
    endfunction

    function void check(WashTxn tr);
        bit ok = 1;
        bit exp_valve;
        bit exp_motor;
        bit exp_led;

        if (tr.water != prev_w || tr.brush != prev_b || tr.clean != prev_c)
            step_model(tr);
        else
            idle_cycles++;

        prev_w = tr.water;
        prev_b = tr.brush;
        prev_c = tr.clean;

        exp_valve = (st == W_SOAKING);
        exp_motor = (st == W_SCRUB);
        exp_led   = (st == W_CLEAN);

        if (tr.valve !== exp_valve) begin
            $error("[SB] valve_open mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.valve, exp_valve, st.name());
            ok = 0;
        end

        if (tr.motor !== exp_motor) begin
            $error("[SB] scrub_motor mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.motor, exp_motor, st.name());
            ok = 0;
        end

        if (tr.led !== exp_led) begin
            $error("[SB] ready_led mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.led, exp_led, st.name());
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
        $display("dirty -> soaking        : %0d", soaks);
        $display("soaking -> dirty        : %0d", soak_aborts);
        $display("soaking -> scrub        : %0d", scrubs);
        $display("scrub -> soaking        : %0d", scrub_backs);
        $display("scrub -> clean          : %0d", cleans);
        $display("clean -> dirty          : %0d", clean_resets);
        $display("brush over !water       : %0d", brush_prio);
        $display("clean over !brush       : %0d", clean_prio);
        $display("pending (stale) states  : %0d", stale_states);
        $display("event, no change: dirty : %0d", dirty_idle);
        $display("event, no change: soak  : %0d", soak_idle);
        $display("event, no change: scrub : %0d", scrub_idle);
        $display("event, no change: clean : %0d", clean_idle);
        $display("--------------------------------------------");

        if (soaks == 0 || scrubs == 0 || cleans == 0)
            $warning("[SB] not every forward transition (soak / scrub / clean) was reached");
        if (soak_aborts == 0 || scrub_backs == 0 || clean_resets == 0)
            $warning("[SB] not every backward transition (abort / back to soak / reset) was reached");
        if (brush_prio == 0)
            $warning("[SB] brush_active together with !water_soak was never applied while soaking");
        if (clean_prio == 0)
            $warning("[SB] stone_clean together with !brush_active was never applied while scrubbing");
        if (stale_states == 0)
            $warning("[SB] a state with a pending transition (no input event) was never reached");
        if (dirty_idle == 0 || soak_idle == 0 || scrub_idle == 0 || clean_idle == 0)
            $warning("[SB] an input change without a transition was not exercised in every state");
        if (idle_cycles == 0)
            $warning("[SB] a cycle without any input change was never applied");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class WashMonitor;
    virtual wash_if vif;
    WashScoreboard  sb;

    function new(virtual wash_if vif, WashScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        WashTxn tr;
        forever begin
            @(vif.mon_cb);
            tr       = new();
            tr.water = vif.mon_cb.water;
            tr.brush = vif.mon_cb.brush;
            tr.clean = vif.mon_cb.clean;
            tr.valve = vif.mon_cb.valve;
            tr.motor = vif.mon_cb.motor;
            tr.led   = vif.mon_cb.led;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class WashDriver;
    virtual wash_if vif;

    function new(virtual wash_if vif);
        this.vif = vif;
    endfunction

    task drive(WashTxn tr);
        @(negedge vif.clk);
        vif.water <= tr.water;
        vif.brush <= tr.brush;
        vif.clean <= tr.clean;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class WashGenerator;
    WashDriver drv;
    int        num_random;

    bit lw = 1'b0;
    bit lb = 1'b0;
    bit lc = 1'b0;

    function new(WashDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit water = 1'b0, bit brush = 1'b0, bit clean = 1'b0);
        WashTxn tr;
        tr       = new();
        tr.water = water;
        tr.brush = brush;
        tr.clean = clean;
        lw = water;
        lb = brush;
        lc = clean;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task hold(int n = 1);
        repeat (n) step(lw, lb, lc);
    endtask

    task directed();
        calm(3);

        step(1'b0, 1'b1, 1'b0);
        step(1'b0, 1'b0, 1'b1);
        step(1'b0, 1'b1, 1'b1);
        calm(2);

        step(1'b1, 1'b0, 1'b0);
        hold(2);
        step(1'b1, 1'b1, 1'b0);
        hold(2);
        step(1'b1, 1'b1, 1'b1);
        hold(2);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b0);
        step(1'b0, 1'b0, 1'b1);
        calm(1);
        hold(2);

        step(1'b1, 1'b0, 1'b0);
        hold(2);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b0);
        step(1'b1, 1'b1, 1'b0);
        hold(2);
        step(1'b0, 1'b1, 1'b0);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b0);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        step(1'b0, 1'b1, 1'b0);
        step(1'b0, 1'b0, 1'b1);
        hold(2);
        calm(1);

        step(1'b0, 1'b1, 1'b0);
        step(1'b1, 1'b1, 1'b0);
        hold(3);
        step(1'b1, 1'b1, 1'b1);
        hold(2);
        step(1'b1, 1'b0, 1'b1);
        hold(2);
        calm(1);

        step(1'b1, 1'b1, 1'b1);
        hold(10);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        repeat (6) begin
            step(1'b1, 1'b1, 1'b0);
            step(1'b1, 1'b0, 1'b0);
        end
        calm(1);

        repeat (2) begin
            for (int i = 0; i < 8; i++)
                step(i[0], i[1], i[2]);
            for (int i = 7; i >= 0; i--)
                step(i[0], i[1], i[2]);
        end
        calm(4);
    endtask

    task random_run();
        WashTxn tr;
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
                    tr.water_w = 500; tr.brush_w = 500; tr.clean_w = 200;
                end
                1: begin
                    tr.water_w = 700; tr.brush_w = 700; tr.clean_w = 100;
                end
                2: begin
                    tr.water_w = 300; tr.brush_w = 300; tr.clean_w = 300;
                end
                default: begin
                    tr.water_w = 600; tr.brush_w = 300; tr.clean_w = 500;
                end
            endcase

            if (!tr.randomize())
                $fatal(1, "[GEN] randomization failed");
            lw = tr.water;
            lb = tr.brush;
            lc = tr.clean;
            drv.drive(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class WashEnvironment;
    WashGenerator  gen;
    WashDriver     drv;
    WashMonitor    mon;
    WashScoreboard sb;

    virtual wash_if vif;

    function new(virtual wash_if vif, int num_random = 20000);
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
module tb_StoneWasher;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    wash_if vif (clk);

    StoneWasher dut (
        .water_soak   (vif.water),
        .brush_active (vif.brush),
        .stone_clean  (vif.clean),
        .valve_open   (vif.valve),
        .scrub_motor  (vif.motor),
        .ready_led    (vif.led)
    );

    WashEnvironment env;

    initial begin
        $dumpfile("StoneWasher_waveform.vcd");
        $dumpvars(0, tb_StoneWasher);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.water = 1'b0;
        vif.brush = 1'b0;
        vif.clean = 1'b0;

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

