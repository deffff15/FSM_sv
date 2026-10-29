`timescale 1ns/1ps

typedef enum int {W_INSIDE, W_DRESSING, W_AT_DOOR, W_OUTSIDE} walk_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface walk_if (input logic clk);
    logic dress;
    logic door;
    logic keys;
    logic light;
    logic lock;
    logic outside;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input dress, door, keys, light, lock, outside;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class WalkTxn;
    rand bit dress;
    rand bit door;
    rand bit keys;

    int dress_w = 500;
    int door_w  = 400;
    int keys_w  = 100;

    logic light;
    logic lock;
    logic outside;

    constraint c_ctrl {
        dress dist {1'b1 := dress_w, 1'b0 := 1000 - dress_w};
        door  dist {1'b1 := door_w,  1'b0 := 1000 - door_w};
        keys  dist {1'b1 := keys_w,  1'b0 := 1000 - keys_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class WalkScoreboard;
    walk_e st;
    bit    prev_d;
    bit    prev_o;
    bit    prev_k;

    int checked        = 0;
    int errors         = 0;
    int events         = 0;
    int idle_cycles    = 0;
    int dress_ups      = 0;
    int dress_aborts   = 0;
    int to_door        = 0;
    int door_prio      = 0;
    int keys_back      = 0;
    int keys_prio      = 0;
    int to_outside     = 0;
    int homes          = 0;
    int stale_states   = 0;
    int inside_idle    = 0;
    int dress_idle     = 0;
    int door_idle      = 0;
    int out_idle       = 0;
    int lock_on        = 0;
    int lock_blocked   = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st     = W_INSIDE;
        prev_d = 1'b0;
        prev_o = 1'b0;
        prev_k = 1'b0;
    endfunction

    function bit pending(walk_e s, bit d, bit o, bit k);
        case (s)
            W_INSIDE:   return d;
            W_DRESSING: return o || !d;
            W_AT_DOOR:  return k || !o;
            W_OUTSIDE:  return !d && !o;
            default:    return 1'b1;
        endcase
    endfunction

    function void step_model(WalkTxn tr);
        walk_e next_st;

        next_st = st;
        events++;

        case (st)
            W_INSIDE: begin
                if (tr.dress) begin
                    next_st = W_DRESSING;
                    dress_ups++;
                end
                else
                    inside_idle++;
            end

            W_DRESSING: begin
                if (tr.door) begin
                    next_st = W_AT_DOOR;
                    to_door++;
                    if (!tr.dress) door_prio++;
                end
                else if (!tr.dress) begin
                    next_st = W_INSIDE;
                    dress_aborts++;
                end
                else
                    dress_idle++;
            end

            W_AT_DOOR: begin
                if (tr.keys) begin
                    next_st = W_DRESSING;
                    keys_back++;
                    if (!tr.door) keys_prio++;
                end
                else if (!tr.door) begin
                    next_st = W_OUTSIDE;
                    to_outside++;
                end
                else
                    door_idle++;
            end

            W_OUTSIDE: begin
                if (!tr.dress && !tr.door) begin
                    next_st = W_INSIDE;
                    homes++;
                end
                else
                    out_idle++;
            end

            default: next_st = W_INSIDE;
        endcase

        st = next_st;

        if (pending(st, tr.dress, tr.door, tr.keys))
            stale_states++;
    endfunction

    function void check(WalkTxn tr);
        bit ok = 1;
        bit exp_light;
        bit exp_lock;
        bit exp_outside;

        if (tr.dress != prev_d || tr.door != prev_o || tr.keys != prev_k)
            step_model(tr);
        else
            idle_cycles++;

        prev_d = tr.dress;
        prev_o = tr.door;
        prev_k = tr.keys;

        exp_light   = (st == W_DRESSING) || (st == W_AT_DOOR);
        exp_lock    = (st == W_AT_DOOR) && !tr.keys;
        exp_outside = (st == W_OUTSIDE);

        if (st == W_AT_DOOR) begin
            if (tr.keys) lock_blocked++;
            else         lock_on++;
        end

        if (tr.light !== exp_light) begin
            $error("[SB] hall_light mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.light, exp_light, st.name());
            ok = 0;
        end

        if (tr.lock !== exp_lock) begin
            $error("[SB] lock_release mismatch @ %0t: got %0b, expected %0b (state %s, keys_missing %0b)",
                   $time, tr.lock, exp_lock, st.name(), tr.keys);
            ok = 0;
        end

        if (tr.outside !== exp_outside) begin
            $error("[SB] outside_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.outside, exp_outside, st.name());
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
        $display("inside -> dressing      : %0d", dress_ups);
        $display("dressing -> inside      : %0d", dress_aborts);
        $display("dressing -> at door     : %0d", to_door);
        $display("door over !get_dressed  : %0d", door_prio);
        $display("at door -> dressing     : %0d", keys_back);
        $display("keys over !door_opened  : %0d", keys_prio);
        $display("at door -> outside      : %0d", to_outside);
        $display("outside -> inside       : %0d", homes);
        $display("pending (stale) states  : %0d", stale_states);
        $display("event, no change: inside: %0d", inside_idle);
        $display("event, no change: dress : %0d", dress_idle);
        $display("event, no change: door  : %0d", door_idle);
        $display("event, no change: outside: %0d", out_idle);
        $display("lock released at door   : %0d", lock_on);
        $display("lock blocked (keys)     : %0d", lock_blocked);
        $display("--------------------------------------------");

        if (dress_ups == 0 || to_door == 0 || to_outside == 0 || homes == 0)
            $warning("[SB] not every forward transition (dress / door / outside / home) was reached");
        if (dress_aborts == 0 || keys_back == 0)
            $warning("[SB] not every backward transition (abort dressing / keys missing) was reached");
        if (door_prio == 0)
            $warning("[SB] door_opened together with !get_dressed was never applied while dressing");
        if (keys_prio == 0)
            $warning("[SB] keys_missing together with !door_opened was never applied at the door");
        if (stale_states == 0)
            $warning("[SB] a state with a pending transition (no input event) was never reached");
        if (inside_idle == 0 || dress_idle == 0 || door_idle == 0 || out_idle == 0)
            $warning("[SB] an input change without a transition was not exercised in every state");
        if (idle_cycles == 0)
            $warning("[SB] a cycle without any input change was never applied");
        if (lock_on == 0 || lock_blocked == 0)
            $warning("[SB] lock_release was not seen both released and blocked by keys_missing");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class WalkMonitor;
    virtual walk_if vif;
    WalkScoreboard  sb;

    function new(virtual walk_if vif, WalkScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        WalkTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.dress   = vif.mon_cb.dress;
            tr.door    = vif.mon_cb.door;
            tr.keys    = vif.mon_cb.keys;
            tr.light   = vif.mon_cb.light;
            tr.lock    = vif.mon_cb.lock;
            tr.outside = vif.mon_cb.outside;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class WalkDriver;
    virtual walk_if vif;

    function new(virtual walk_if vif);
        this.vif = vif;
    endfunction

    task drive(WalkTxn tr);
        @(negedge vif.clk);
        vif.dress <= tr.dress;
        vif.door  <= tr.door;
        vif.keys  <= tr.keys;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class WalkGenerator;
    WalkDriver drv;
    int        num_random;

    bit ld = 1'b0;
    bit lo = 1'b0;
    bit lk = 1'b0;

    function new(WalkDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit dress = 1'b0, bit door = 1'b0, bit keys = 1'b0);
        WalkTxn tr;
        tr       = new();
        tr.dress = dress;
        tr.door  = door;
        tr.keys  = keys;
        ld = dress;
        lo = door;
        lk = keys;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task hold(int n = 1);
        repeat (n) step(ld, lo, lk);
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
        step(1'b1, 1'b0, 1'b0);
        hold(2);
        step(1'b1, 1'b1, 1'b0);
        step(1'b0, 1'b1, 1'b0);
        step(1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b0, 1'b0);
        hold(2);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        step(1'b0, 1'b1, 1'b0);
        step(1'b0, 1'b1, 1'b1);
        step(1'b0, 1'b1, 1'b0);
        step(1'b0, 1'b0, 1'b0);
        hold(2);
        step(1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b0, 1'b0);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b1, 1'b1);
        hold(3);
        step(1'b1, 1'b1, 1'b0);
        step(1'b0, 1'b1, 1'b0);
        step(1'b0, 1'b0, 1'b0);
        hold(2);
        step(1'b0, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1, 1'b1);
        hold(10);
        calm(1);

        step(1'b1, 1'b0, 1'b0);
        repeat (6) begin
            step(1'b1, 1'b1, 1'b0);
            step(1'b1, 1'b1, 1'b1);
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
        WalkTxn tr;
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
                    tr.dress_w = 500; tr.door_w = 400; tr.keys_w = 100;
                end
                1: begin
                    tr.dress_w = 700; tr.door_w = 600; tr.keys_w = 50;
                end
                2: begin
                    tr.dress_w = 300; tr.door_w = 300; tr.keys_w = 300;
                end
                default: begin
                    tr.dress_w = 600; tr.door_w = 300; tr.keys_w = 200;
                end
            endcase

            if (!tr.randomize())
                $fatal(1, "[GEN] randomization failed");
            ld = tr.dress;
            lo = tr.door;
            lk = tr.keys;
            drv.drive(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class WalkEnvironment;
    WalkGenerator  gen;
    WalkDriver     drv;
    WalkMonitor    mon;
    WalkScoreboard sb;

    virtual walk_if vif;

    function new(virtual walk_if vif, int num_random = 20000);
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
module tb_WalkSimulator;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    walk_if vif (clk);

    WalkSimulator dut (
        .get_dressed  (vif.dress),
        .door_opened  (vif.door),
        .keys_missing (vif.keys),
        .hall_light   (vif.light),
        .lock_release (vif.lock),
        .outside_o    (vif.outside)
    );

    WalkEnvironment env;

    initial begin
        $dumpfile("WalkSimulator_waveform.vcd");
        $dumpvars(0, tb_WalkSimulator);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.dress = 1'b0;
        vif.door  = 1'b0;
        vif.keys  = 1'b0;

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

