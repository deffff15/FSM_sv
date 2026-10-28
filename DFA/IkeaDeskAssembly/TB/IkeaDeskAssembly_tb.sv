`timescale 1ns/1ps

typedef enum int {I_BOXED, I_MANUAL, I_LEGS, I_TOP, I_CRISIS, I_FINISHED} ikea_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface ikea_if (input logic clk);
    logic rst_n;
    logic unboxed;
    logic legs;
    logic missing;
    logic mounted;
    logic ready;
    logic rage;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, unboxed, legs, missing, mounted, ready, rage;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class IkeaTxn;
    rand bit rst_n;
    rand bit unboxed;
    rand bit legs;
    rand bit missing;
    rand bit mounted;

    int rst_w     = 20;
    int unboxed_w = 400;
    int legs_w    = 300;
    int missing_w = 100;
    int mounted_w = 300;

    logic ready;
    logic rage;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,     1'b1 := 1000 - rst_w};
        unboxed dist {1'b1 := unboxed_w, 1'b0 := 1000 - unboxed_w};
        legs    dist {1'b1 := legs_w,    1'b0 := 1000 - legs_w};
        missing dist {1'b1 := missing_w, 1'b0 := 1000 - missing_w};
        mounted dist {1'b1 := mounted_w, 1'b0 := 1000 - mounted_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class IkeaScoreboard;
    ikea_e st;
    bit    from_top;

    int checked          = 0;
    int errors           = 0;
    int unboxes          = 0;
    int manual_passes    = 0;
    int legs_done        = 0;
    int top_done         = 0;
    int crisis_legs      = 0;
    int crisis_top       = 0;
    int crisis_exits     = 0;
    int back_from_top    = 0;
    int exit_with_inputs = 0;
    int missing_prio_legs = 0;
    int missing_prio_top = 0;
    int boxed_waits      = 0;
    int legs_waits       = 0;
    int top_waits        = 0;
    int crisis_waits     = 0;
    int finished_waits   = 0;
    int ignored_unboxed  = 0;
    int ignored_legs     = 0;
    int ignored_top      = 0;
    int ignored_missing  = 0;
    int ignored_manual   = 0;
    int resets_mid       = 0;
    int resets_crisis    = 0;
    int resets_after_end = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st       = I_BOXED;
        from_top = 0;
    endfunction

    function void step_model(IkeaTxn tr);
        ikea_e next_st;

        next_st = st;

        if (tr.unboxed && st != I_BOXED)
            ignored_unboxed++;
        if (tr.legs && st != I_LEGS)
            ignored_legs++;
        if (tr.mounted && st != I_TOP)
            ignored_top++;
        if (tr.missing && (st == I_BOXED || st == I_MANUAL || st == I_FINISHED))
            ignored_missing++;
        if (st == I_MANUAL && (tr.unboxed || tr.legs || tr.missing || tr.mounted))
            ignored_manual++;

        case (st)
            I_BOXED: begin
                if (tr.unboxed) begin
                    next_st = I_MANUAL;
                    unboxes++;
                end
                else
                    boxed_waits++;
            end

            I_MANUAL: begin
                next_st = I_LEGS;
                manual_passes++;
            end

            I_LEGS: begin
                if (tr.missing) begin
                    next_st  = I_CRISIS;
                    from_top = 0;
                    crisis_legs++;
                    if (tr.legs) missing_prio_legs++;
                end
                else if (tr.legs) begin
                    next_st = I_TOP;
                    legs_done++;
                end
                else
                    legs_waits++;
            end

            I_TOP: begin
                if (tr.missing) begin
                    next_st  = I_CRISIS;
                    from_top = 1;
                    crisis_top++;
                    if (tr.mounted) missing_prio_top++;
                end
                else if (tr.mounted) begin
                    next_st = I_FINISHED;
                    top_done++;
                end
                else
                    top_waits++;
            end

            I_CRISIS: begin
                if (!tr.missing) begin
                    next_st = I_LEGS;
                    crisis_exits++;
                    if (from_top) back_from_top++;
                    if (tr.legs || tr.mounted) exit_with_inputs++;
                end
                else
                    crisis_waits++;
            end

            I_FINISHED: begin
                next_st = I_FINISHED;
                finished_waits++;
            end

            default: next_st = I_BOXED;
        endcase

        st = next_st;
    endfunction

    function void check(IkeaTxn tr);
        bit ok = 1;
        bit exp_ready;
        bit exp_rage;

        if (!tr.rst_n) begin
            if (st == I_FINISHED)
                resets_after_end++;
            else if (st == I_CRISIS)
                resets_crisis++;
            else if (st != I_BOXED)
                resets_mid++;
            reset_model();
        end

        exp_ready = (st == I_FINISHED);
        exp_rage  = (st == I_CRISIS);

        if (tr.ready !== exp_ready) begin
            $error("[SB] desk_ready mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.ready, exp_ready, st.name());
            ok = 0;
        end

        if (tr.rage !== exp_rage) begin
            $error("[SB] rage mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.rage, exp_rage, st.name());
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
        $display("unboxed                 : %0d", unboxes);
        $display("manual read             : %0d", manual_passes);
        $display("legs assembled          : %0d", legs_done);
        $display("desks finished          : %0d", top_done);
        $display("crisis from legs        : %0d", crisis_legs);
        $display("crisis from mount top   : %0d", crisis_top);
        $display("crisis exits            : %0d", crisis_exits);
        $display("back to legs from top   : %0d", back_from_top);
        $display("exit with legs/top set  : %0d", exit_with_inputs);
        $display("missing over legs       : %0d", missing_prio_legs);
        $display("missing over top        : %0d", missing_prio_top);
        $display("waiting in boxed        : %0d", boxed_waits);
        $display("waiting in legs         : %0d", legs_waits);
        $display("waiting in mount top    : %0d", top_waits);
        $display("waiting in crisis       : %0d", crisis_waits);
        $display("waiting in finished     : %0d", finished_waits);
        $display("unboxed_i ignored       : %0d", ignored_unboxed);
        $display("legs_assembled ignored  : %0d", ignored_legs);
        $display("top_mounted ignored     : %0d", ignored_top);
        $display("missing_parts ignored   : %0d", ignored_missing);
        $display("inputs ignored in manual: %0d", ignored_manual);
        $display("resets mid-assembly     : %0d", resets_mid);
        $display("resets in crisis        : %0d", resets_crisis);
        $display("resets after end        : %0d", resets_after_end);
        $display("--------------------------------------------");

        if (unboxes == 0 || manual_passes == 0 || legs_done == 0 || top_done == 0)
            $warning("[SB] not every forward step (unbox / manual / legs / top) was reached");
        if (crisis_legs == 0 || crisis_top == 0)
            $warning("[SB] parts crisis was not entered from both legs and mount top");
        if (crisis_exits == 0)
            $warning("[SB] parts crisis was never left");
        if (back_from_top == 0)
            $warning("[SB] crisis entered from mount top was never left (returns to legs)");
        if (exit_with_inputs == 0)
            $warning("[SB] crisis was never left with legs_assembled / top_mounted asserted");
        if (missing_prio_legs == 0 || missing_prio_top == 0)
            $warning("[SB] missing_parts together with legs_assembled / top_mounted was never applied");
        if (boxed_waits == 0 || legs_waits == 0 || top_waits == 0 ||
            crisis_waits == 0 || finished_waits == 0)
            $warning("[SB] waiting in every state was never exercised");
        if (ignored_unboxed == 0 || ignored_legs == 0 || ignored_top == 0 ||
            ignored_missing == 0 || ignored_manual == 0)
            $warning("[SB] ignored inputs were not exercised in every category");
        if (resets_mid == 0)
            $warning("[SB] reset was never applied in the middle of an assembly");
        if (resets_crisis == 0)
            $warning("[SB] reset was never applied during a parts crisis");
        if (resets_after_end == 0)
            $warning("[SB] reset was never applied after the desk was finished");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class IkeaMonitor;
    virtual ikea_if vif;
    IkeaScoreboard  sb;

    function new(virtual ikea_if vif, IkeaScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        IkeaTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.unboxed = vif.mon_cb.unboxed;
            tr.legs    = vif.mon_cb.legs;
            tr.missing = vif.mon_cb.missing;
            tr.mounted = vif.mon_cb.mounted;
            tr.ready   = vif.mon_cb.ready;
            tr.rage    = vif.mon_cb.rage;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class IkeaDriver;
    virtual ikea_if vif;

    function new(virtual ikea_if vif);
        this.vif = vif;
    endfunction

    task drive(IkeaTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.unboxed <= tr.unboxed;
        vif.legs    <= tr.legs;
        vif.missing <= tr.missing;
        vif.mounted <= tr.mounted;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class IkeaGenerator;
    IkeaDriver drv;
    int        num_random;

    function new(IkeaDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit unboxed = 1'b0, bit legs = 1'b0,
              bit missing = 1'b0, bit mounted = 1'b0);
        IkeaTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.unboxed = unboxed;
        tr.legs    = legs;
        tr.missing = missing;
        tr.mounted = mounted;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task build(int boxed_wait, int legs_wait, int top_wait, int cause,
               int crisis_len, bit noisy);
        calm(boxed_wait);
        step(1'b1, 1'b1);
        step(1'b1, noisy, noisy, noisy, noisy);
        calm(legs_wait);

        case (cause)
            1: begin
                step(1'b1, 1'b0, 1'b0, 1'b1);
                repeat (crisis_len) step(1'b1, 1'b0, 1'b0, 1'b1);
                step();
            end
            3: begin
                step(1'b1, 1'b0, 1'b1, 1'b1);
                repeat (crisis_len) step(1'b1, 1'b0, 1'b1, 1'b1);
                step();
            end
            default: ;
        endcase

        step(1'b1, 1'b0, 1'b1);
        calm(top_wait);

        case (cause)
            2: begin
                step(1'b1, 1'b0, 1'b0, 1'b1);
                repeat (crisis_len) step(1'b1, 1'b0, 1'b0, 1'b1);
                step();
                step(1'b1, 1'b0, 1'b1);
            end
            4: begin
                step(1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
                repeat (crisis_len) step(1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
                step();
                step(1'b1, 1'b0, 1'b1);
            end
            5: begin
                step(1'b1, 1'b0, 1'b0, 1'b1);
                repeat (crisis_len) step(1'b1, 1'b0, 1'b0, 1'b1);
                step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
                step(1'b1, 1'b0, 1'b1);
            end
            default: ;
        endcase

        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        repeat (3) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(2);
    endtask

    task to_stage(int s);
        if (s >= 1) step(1'b1, 1'b1);
        if (s >= 2) step();
        if (s >= 3) step(1'b1, 1'b0, 1'b1);
        if (s == 4) step(1'b1, 1'b0, 1'b0, 1'b1);
        if (s == 5) step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (3) step();
        repeat (3) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        calm(2);

        build(0, 0, 0, 0, 0, 1'b0);
        build(2, 2, 2, 0, 0, 1'b1);
        build(1, 1, 1, 1, 1, 1'b0);
        build(1, 1, 1, 1, 3, 1'b0);
        build(0, 0, 0, 2, 1, 1'b0);
        build(2, 1, 2, 2, 4, 1'b1);
        build(1, 1, 1, 3, 2, 1'b0);
        build(1, 1, 1, 4, 2, 1'b0);
        build(1, 1, 1, 5, 2, 1'b0);

        step(1'b1, 1'b1);
        step();
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step();
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step();
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step();
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);
        step(1'b0);
        calm(2);

        repeat (40) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        calm(4);
        step(1'b0);
        calm(2);

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            step(1'b0);
            calm(2);
            build(1, 1, 1, 0, 0, 1'b0);
        end

        step(1'b0, 1'b1);
        calm(2);
        build(1, 1, 1, 1, 1, 1'b0);
    endtask

    task random_run();
        IkeaTxn tr;
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
                    tr.rst_w = 20; tr.unboxed_w = 400; tr.legs_w = 300;
                    tr.missing_w = 100; tr.mounted_w = 300;
                end
                1: begin
                    tr.rst_w = 30; tr.unboxed_w = 500; tr.legs_w = 500;
                    tr.missing_w = 20;  tr.mounted_w = 500;
                end
                2: begin
                    tr.rst_w = 20; tr.unboxed_w = 300; tr.legs_w = 300;
                    tr.missing_w = 300; tr.mounted_w = 300;
                end
                default: begin
                    tr.rst_w = 40; tr.unboxed_w = 300; tr.legs_w = 200;
                    tr.missing_w = 200; tr.mounted_w = 200;
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
class IkeaEnvironment;
    IkeaGenerator  gen;
    IkeaDriver     drv;
    IkeaMonitor    mon;
    IkeaScoreboard sb;

    virtual ikea_if vif;

    function new(virtual ikea_if vif, int num_random = 20000);
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
module tb_IkeaDeskAssembly;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    ikea_if vif (clk);

    IkeaDeskAssembly dut (
        .clk              (clk),
        .rst_n            (vif.rst_n),
        .unboxed_i        (vif.unboxed),
        .legs_assembled_i (vif.legs),
        .missing_parts_i  (vif.missing),
        .top_mounted_i    (vif.mounted),
        .desk_ready_o     (vif.ready),
        .rage_o           (vif.rage)
    );

    IkeaEnvironment env;

    initial begin
        $dumpfile("IkeaDeskAssembly_waveform.vcd");
        $dumpvars(0, tb_IkeaDeskAssembly);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.unboxed = 1'b0;
        vif.legs    = 1'b0;
        vif.missing = 1'b0;
        vif.mounted = 1'b0;

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

