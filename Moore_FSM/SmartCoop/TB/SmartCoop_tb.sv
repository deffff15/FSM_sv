`timescale 1ns/1ps

typedef enum int {C_CLOSED, C_OPENING, C_OPEN, C_CLOSING} coop_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface coop_if (input logic clk);
    logic rst_n;
    logic sunrise;
    logic sunset;
    logic limit;
    logic up;
    logic down;
    logic led;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, sunrise, sunset, limit, up, down, led;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class CoopTxn;
    rand bit rst_n;
    rand bit sunrise;
    rand bit sunset;
    rand bit limit;

    int rst_w     = 10;
    int sunrise_w = 100;
    int sunset_w  = 100;
    int limit_w   = 150;

    logic up;
    logic down;
    logic led;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,     1'b1 := 1000 - rst_w};
        sunrise dist {1'b1 := sunrise_w, 1'b0 := 1000 - sunrise_w};
        sunset  dist {1'b1 := sunset_w,  1'b0 := 1000 - sunset_w};
        limit   dist {1'b1 := limit_w,   1'b0 := 1000 - limit_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class CoopScoreboard;
    coop_e st;
    int    dwell;

    int checked          = 0;
    int errors           = 0;
    int opens_started    = 0;
    int opened           = 0;
    int closes_started   = 0;
    int closed           = 0;
    int quick_open       = 0;
    int quick_close      = 0;
    int closed_waits     = 0;
    int opening_waits    = 0;
    int open_waits       = 0;
    int closing_waits    = 0;
    int ignored_sunrise  = 0;
    int ignored_sunset   = 0;
    int ignored_limit    = 0;
    int sun_both_closed  = 0;
    int sun_both_open    = 0;
    int resets_opening   = 0;
    int resets_open      = 0;
    int resets_closing   = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st    = C_CLOSED;
        dwell = 0;
    endfunction

    function void step_model(CoopTxn tr);
        coop_e next_st;

        next_st = st;

        if (tr.sunrise && st != C_CLOSED)
            ignored_sunrise++;
        if (tr.sunset && st != C_OPEN)
            ignored_sunset++;
        if (tr.limit && (st == C_CLOSED || st == C_OPEN))
            ignored_limit++;
        if (tr.sunrise && tr.sunset && st == C_CLOSED)
            sun_both_closed++;
        if (tr.sunrise && tr.sunset && st == C_OPEN)
            sun_both_open++;

        case (st)
            C_CLOSED: begin
                if (tr.sunrise) begin
                    next_st = C_OPENING;
                    opens_started++;
                end
                else
                    closed_waits++;
            end

            C_OPENING: begin
                if (tr.limit) begin
                    next_st = C_OPEN;
                    opened++;
                    if (dwell == 0) quick_open++;
                end
                else
                    opening_waits++;
            end

            C_OPEN: begin
                if (tr.sunset) begin
                    next_st = C_CLOSING;
                    closes_started++;
                end
                else
                    open_waits++;
            end

            C_CLOSING: begin
                if (tr.limit) begin
                    next_st = C_CLOSED;
                    closed++;
                    if (dwell == 0) quick_close++;
                end
                else
                    closing_waits++;
            end

            default: next_st = C_CLOSED;
        endcase

        if (next_st != st) dwell = 0;
        else               dwell++;
        st = next_st;
    endfunction

    function void check(CoopTxn tr);
        bit ok = 1;
        bit exp_up;
        bit exp_down;
        bit exp_led;

        if (!tr.rst_n) begin
            if (st == C_OPENING)      resets_opening++;
            else if (st == C_OPEN)    resets_open++;
            else if (st == C_CLOSING) resets_closing++;
            reset_model();
        end

        exp_up   = (st == C_OPENING);
        exp_down = (st == C_CLOSING);
        exp_led  = (st == C_CLOSED);

        if (tr.up !== exp_up) begin
            $error("[SB] motor_up mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.up, exp_up, st.name());
            ok = 0;
        end

        if (tr.down !== exp_down) begin
            $error("[SB] motor_down mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.down, exp_down, st.name());
            ok = 0;
        end

        if (tr.led !== exp_led) begin
            $error("[SB] secure_led mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.led, exp_led, st.name());
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
        $display("opening started         : %0d", opens_started);
        $display("opened                  : %0d", opened);
        $display("closing started         : %0d", closes_started);
        $display("closed                  : %0d", closed);
        $display("opened after 1 cycle    : %0d", quick_open);
        $display("closed after 1 cycle    : %0d", quick_close);
        $display("waiting in closed       : %0d", closed_waits);
        $display("waiting in opening      : %0d", opening_waits);
        $display("waiting in open         : %0d", open_waits);
        $display("waiting in closing      : %0d", closing_waits);
        $display("sunrise ignored         : %0d", ignored_sunrise);
        $display("sunset ignored          : %0d", ignored_sunset);
        $display("limit_switch ignored    : %0d", ignored_limit);
        $display("sunrise+sunset in closed: %0d", sun_both_closed);
        $display("sunrise+sunset in open  : %0d", sun_both_open);
        $display("resets while opening    : %0d", resets_opening);
        $display("resets while open       : %0d", resets_open);
        $display("resets while closing    : %0d", resets_closing);
        $display("--------------------------------------------");

        if (opens_started == 0 || opened == 0 || closes_started == 0 || closed == 0)
            $warning("[SB] a full day cycle (open / close) was not completed");
        if (quick_open == 0 || quick_close == 0)
            $warning("[SB] limit_switch in the first cycle of opening / closing was never applied");
        if (closed_waits == 0 || opening_waits == 0 || open_waits == 0 || closing_waits == 0)
            $warning("[SB] waiting in every state was never exercised");
        if (ignored_sunrise == 0 || ignored_sunset == 0 || ignored_limit == 0)
            $warning("[SB] ignored sunrise / sunset / limit_switch was never exercised");
        if (sun_both_closed == 0 || sun_both_open == 0)
            $warning("[SB] sunrise together with sunset was never applied in closed / open");
        if (resets_opening == 0 || resets_open == 0 || resets_closing == 0)
            $warning("[SB] reset was not applied while opening / open / closing");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class CoopMonitor;
    virtual coop_if vif;
    CoopScoreboard  sb;

    function new(virtual coop_if vif, CoopScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        CoopTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.sunrise = vif.mon_cb.sunrise;
            tr.sunset  = vif.mon_cb.sunset;
            tr.limit   = vif.mon_cb.limit;
            tr.up      = vif.mon_cb.up;
            tr.down    = vif.mon_cb.down;
            tr.led     = vif.mon_cb.led;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class CoopDriver;
    virtual coop_if vif;

    function new(virtual coop_if vif);
        this.vif = vif;
    endfunction

    task drive(CoopTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.sunrise <= tr.sunrise;
        vif.sunset  <= tr.sunset;
        vif.limit   <= tr.limit;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class CoopGenerator;
    CoopDriver drv;
    int        num_random;

    function new(CoopDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit sunrise = 1'b0, bit sunset = 1'b0,
              bit limit = 1'b0);
        CoopTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.sunrise = sunrise;
        tr.sunset  = sunset;
        tr.limit   = limit;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task to_stage(int s);
        step(1'b1, 1'b1);
        if (s >= 2) step(1'b1, 1'b0, 1'b0, 1'b1);
        if (s >= 3) step(1'b1, 1'b0, 1'b1);
    endtask

    task day(int open_wait, int day_wait, int close_wait);
        step(1'b1, 1'b1);
        calm(open_wait);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(day_wait);
        step(1'b1, 1'b0, 1'b1);
        calm(close_wait);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        calm(3);
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        calm(2);

        step(1'b1, 1'b1);
        calm(3);
        step(1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(3);
        step(1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1);
        calm(3);
        step(1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1, 1'b1);
        calm(1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b1, 1'b1);
        calm(1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        calm(2);

        day(0, 0, 0);
        day(2, 3, 2);
        day(5, 1, 4);

        repeat (20) step(1'b1, 1'b1, 1'b1, 1'b1);
        calm(2);

        for (int s = 1; s <= 3; s++) begin
            to_stage(s);
            step(1'b0, 1'b1, 1'b1, 1'b1);
            calm(2);
            day(1, 1, 1);
        end

        step(1'b0, 1'b1);
        calm(2);
        day(2, 2, 2);
    endtask

    task random_run();
        CoopTxn tr;
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
                    tr.rst_w = 10; tr.sunrise_w = 100; tr.sunset_w = 100; tr.limit_w = 150;
                end
                1: begin
                    tr.rst_w = 5;  tr.sunrise_w = 300; tr.sunset_w = 300; tr.limit_w = 50;
                end
                2: begin
                    tr.rst_w = 10; tr.sunrise_w = 50;  tr.sunset_w = 50;  tr.limit_w = 300;
                end
                default: begin
                    tr.rst_w = 20; tr.sunrise_w = 200; tr.sunset_w = 200; tr.limit_w = 200;
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
class CoopEnvironment;
    CoopGenerator  gen;
    CoopDriver     drv;
    CoopMonitor    mon;
    CoopScoreboard sb;

    virtual coop_if vif;

    function new(virtual coop_if vif, int num_random = 20000);
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
module tb_SmartCoop;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    coop_if vif (clk);

    SmartCoop dut (
        .clk            (clk),
        .rst_n          (vif.rst_n),
        .sunrise_i      (vif.sunrise),
        .sunset_i       (vif.sunset),
        .limit_switch_i (vif.limit),
        .motor_up_o     (vif.up),
        .motor_down_o   (vif.down),
        .secure_led_o   (vif.led)
    );

    CoopEnvironment env;

    initial begin
        $dumpfile("SmartCoop_waveform.vcd");
        $dumpvars(0, tb_SmartCoop);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.sunrise = 1'b0;
        vif.sunset  = 1'b0;
        vif.limit   = 1'b0;

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

