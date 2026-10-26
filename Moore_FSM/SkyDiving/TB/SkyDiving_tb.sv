`timescale 1ns/1ps

typedef enum int {T_PLANE, T_AIR, T_GROUND} sky_top_e;
typedef enum int {U_FREEFALL, U_OPENING, U_DESCENT} sky_sub_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface sky_if (input logic clk);
    logic rst_n;
    logic green;
    logic alt;
    logic chute;
    logic ground;
    logic red;
    logic in_air;
    logic opening;
    logic landed;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, green, alt, chute, ground, red, in_air, opening, landed;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class SkyTxn;
    rand bit rst_n;
    rand bit green;
    rand bit alt;
    rand bit chute;
    rand bit ground;

    int rst_w    = 2;
    int green_w  = 300;
    int alt_w    = 100;
    int chute_w  = 100;
    int ground_w = 100;

    logic red;
    logic in_air;
    logic opening;
    logic landed;

    constraint c_ctrl {
        rst_n  dist {1'b0 := rst_w,    1'b1 := 1000 - rst_w};
        green  dist {1'b1 := green_w,  1'b0 := 1000 - green_w};
        alt    dist {1'b1 := alt_w,    1'b0 := 1000 - alt_w};
        chute  dist {1'b1 := chute_w,  1'b0 := 1000 - chute_w};
        ground dist {1'b1 := ground_w, 1'b0 := 1000 - ground_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class SkyScoreboard;
    sky_top_e top;
    sky_sub_e sub;

    int checked         = 0;
    int errors          = 0;
    int jumps           = 0;
    int open_by_chute   = 0;
    int open_by_alt     = 0;
    int open_by_both    = 0;
    int fall_waits      = 0;
    int descent_waits   = 0;
    int early_ground    = 0;
    int ignored_green   = 0;
    int ignored_open    = 0;
    int resets_mid_jump = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        top = T_PLANE;
        sub = U_FREEFALL;
    endfunction

    function void step_model(SkyTxn tr);
        sky_top_e next_top;
        sky_sub_e next_sub;

        next_top = top;
        next_sub = sub;

        if (tr.green && top != T_PLANE)
            ignored_green++;
        if ((tr.alt || tr.chute) && !(top == T_AIR && sub == U_FREEFALL))
            ignored_open++;
        if (tr.ground && top == T_AIR && sub != U_DESCENT)
            early_ground++;

        case (top)
            T_PLANE: begin
                if (tr.green) begin
                    next_top = T_AIR;
                    next_sub = U_FREEFALL;
                end
            end

            T_AIR: begin
                case (sub)
                    U_FREEFALL: begin
                        if (tr.chute || tr.alt) begin
                            next_sub = U_OPENING;
                            if (tr.chute && tr.alt) open_by_both++;
                            else if (tr.chute)      open_by_chute++;
                            else                    open_by_alt++;
                        end
                        else
                            fall_waits++;
                    end

                    U_OPENING: next_sub = U_DESCENT;

                    U_DESCENT: begin
                        if (tr.ground) begin
                            next_top = T_GROUND;
                            jumps++;
                        end
                        else
                            descent_waits++;
                    end

                    default: next_sub = U_FREEFALL;
                endcase
            end

            T_GROUND: next_top = T_PLANE;

            default: begin
                next_top = T_PLANE;
                next_sub = U_FREEFALL;
            end
        endcase

        top = next_top;
        sub = next_sub;
    endfunction

    function void check(SkyTxn tr);
        bit ok = 1;
        bit exp_red;
        bit exp_in_air;
        bit exp_opening;
        bit exp_landed;

        if (!tr.rst_n) begin
            if (top != T_PLANE) resets_mid_jump++;
            reset_model();
        end

        exp_red     = (top == T_PLANE) && !tr.green;
        exp_in_air  = (top == T_AIR);
        exp_opening = (top == T_AIR) && (sub == U_OPENING);
        exp_landed  = (top == T_GROUND);

        if (tr.red !== exp_red) begin
            $error("[SB] red_light mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.red, exp_red, top.name(), sub.name());
            ok = 0;
        end

        if (tr.in_air !== exp_in_air) begin
            $error("[SB] in_air mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.in_air, exp_in_air, top.name(), sub.name());
            ok = 0;
        end

        if (tr.opening !== exp_opening) begin
            $error("[SB] opening mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.opening, exp_opening, top.name(), sub.name());
            ok = 0;
        end

        if (tr.landed !== exp_landed) begin
            $error("[SB] landed mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.landed, exp_landed, top.name(), sub.name());
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
        $display("jumps completed         : %0d", jumps);
        $display("opened by parachute     : %0d", open_by_chute);
        $display("opened by altitude      : %0d", open_by_alt);
        $display("opened by both          : %0d", open_by_both);
        $display("waiting in freefall     : %0d", fall_waits);
        $display("waiting in descent      : %0d", descent_waits);
        $display("ground_near too early   : %0d", early_ground);
        $display("green_light ignored     : %0d", ignored_green);
        $display("open request ignored    : %0d", ignored_open);
        $display("resets mid-jump         : %0d", resets_mid_jump);
        $display("--------------------------------------------");

        if (jumps == 0)
            $warning("[SB] no jump was completed");
        if (open_by_chute == 0 || open_by_alt == 0 || open_by_both == 0)
            $warning("[SB] not every opening trigger (parachute / altitude / both) was reached");
        if (early_ground == 0)
            $warning("[SB] ground_near was never asserted before the descent");
        if (ignored_green == 0 || ignored_open == 0)
            $warning("[SB] ignored green_light or open request was never exercised");
        if (resets_mid_jump == 0)
            $warning("[SB] reset was never applied in the middle of a jump");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class SkyMonitor;
    virtual sky_if vif;
    SkyScoreboard  sb;

    function new(virtual sky_if vif, SkyScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        SkyTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.green   = vif.mon_cb.green;
            tr.alt     = vif.mon_cb.alt;
            tr.chute   = vif.mon_cb.chute;
            tr.ground  = vif.mon_cb.ground;
            tr.red     = vif.mon_cb.red;
            tr.in_air  = vif.mon_cb.in_air;
            tr.opening = vif.mon_cb.opening;
            tr.landed  = vif.mon_cb.landed;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class SkyDriver;
    virtual sky_if vif;

    function new(virtual sky_if vif);
        this.vif = vif;
    endfunction

    task drive(SkyTxn tr);
        @(negedge vif.clk);
        vif.rst_n  <= tr.rst_n;
        vif.green  <= tr.green;
        vif.alt    <= tr.alt;
        vif.chute  <= tr.chute;
        vif.ground <= tr.ground;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class SkyGenerator;
    SkyDriver drv;
    int       num_random;

    function new(SkyDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit green = 1'b0, bit alt = 1'b0,
              bit chute = 1'b0, bit ground = 1'b0);
        SkyTxn tr;
        tr        = new();
        tr.rst_n  = rst_n;
        tr.green  = green;
        tr.alt    = alt;
        tr.chute  = chute;
        tr.ground = ground;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task jump(int fall_wait, int descent_wait, int cause);
        step(1'b1, 1'b1);
        calm(fall_wait);
        case (cause)
            0:       step(1'b1, 1'b0, 1'b0, 1'b1);
            1:       step(1'b1, 1'b0, 1'b1, 1'b0);
            default: step(1'b1, 1'b0, 1'b1, 1'b1);
        endcase
        step();
        calm(descent_wait);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        calm(2);
    endtask

    task to_stage(int s);
        step(1'b1, 1'b1);
        if (s >= 2) step(1'b1, 1'b0, 1'b0, 1'b1);
        if (s >= 3) step();
        if (s >= 4) step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (3) step();
        repeat (3) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        calm(2);

        jump(1, 1, 0);
        jump(2, 2, 1);
        jump(0, 0, 2);
        jump(5, 5, 0);

        repeat (40) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        calm(4);

        step(1'b1, 1'b1);
        repeat (3) step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        calm(2);

        step(1'b1, 1'b1);
        repeat (6) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        calm(2);

        for (int s = 1; s <= 4; s++) begin
            to_stage(s);
            step(1'b0);
            calm(2);
            jump(1, 1, 0);
        end

        step(1'b0, 1'b1);
        calm(2);
        jump(1, 1, 1);
    endtask

    task random_run();
        SkyTxn tr;
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
                    tr.green_w = 300; tr.alt_w = 100; tr.chute_w = 100; tr.ground_w = 100;
                end
                1: begin
                    tr.green_w = 300; tr.alt_w = 20;  tr.chute_w = 20;  tr.ground_w = 100;
                end
                2: begin
                    tr.green_w = 300; tr.alt_w = 300; tr.chute_w = 300; tr.ground_w = 300;
                end
                default: begin
                    tr.green_w = 300; tr.alt_w = 80;  tr.chute_w = 80;  tr.ground_w = 600;
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
class SkyEnvironment;
    SkyGenerator  gen;
    SkyDriver     drv;
    SkyMonitor    mon;
    SkyScoreboard sb;

    virtual sky_if vif;

    function new(virtual sky_if vif, int num_random = 20000);
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
module tb_Skydiving;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    sky_if vif (clk);

    Skydiving dut (
        .clk            (clk),
        .rst_n          (vif.rst_n),
        .green_light    (vif.green),
        .altitude_ok    (vif.alt),
        .open_parachute (vif.chute),
        .ground_near    (vif.ground),
        .red_light      (vif.red),
        .in_air         (vif.in_air),
        .opening        (vif.opening),
        .landed         (vif.landed)
    );

    SkyEnvironment env;

    initial begin
        $dumpfile("Skydiving_waveform.vcd");
        $dumpvars(0, tb_Skydiving);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.green  = 1'b0;
        vif.alt    = 1'b0;
        vif.chute  = 1'b0;
        vif.ground = 1'b0;

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

