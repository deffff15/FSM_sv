`timescale 1ns/1ps

typedef enum int {T_OFF, T_HEATING, T_BATHING, T_DRYING, T_EMERGENCY} top_state_e;
typedef enum int {SB_RINSING, SB_SOAPING, SB_FINAL_RINSE} sub_state_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface shower_if (input logic clk);
    logic rst_n;
    logic start;
    logic temp_ok;
    logic soaped;
    logic scald;
    logic valve;
    logic soap;
    logic dryer;
    logic alarm;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, start, temp_ok, soaped, scald, valve, soap, dryer, alarm;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class ShowerTxn;
    rand bit rst_n;
    rand bit start;
    rand bit temp_ok;
    rand bit soaped;
    rand bit scald;

    int rst_w    = 2;
    int start_w  = 300;
    int temp_w   = 400;
    int soaped_w = 400;
    int scald_w  = 2;

    logic valve;
    logic soap;
    logic dryer;
    logic alarm;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,    1'b1 := 1000 - rst_w};
        start   dist {1'b1 := start_w,  1'b0 := 1000 - start_w};
        temp_ok dist {1'b1 := temp_w,   1'b0 := 1000 - temp_w};
        soaped  dist {1'b1 := soaped_w, 1'b0 := 1000 - soaped_w};
        scald   dist {1'b1 := scald_w,  1'b0 := 1000 - scald_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class ShowerScoreboard;
    top_state_e top;
    sub_state_e sub;
    int         dry_cnt;

    int checked           = 0;
    int errors            = 0;
    int showers           = 0;
    int em_heating        = 0;
    int em_rinsing        = 0;
    int em_soaping        = 0;
    int em_final          = 0;
    int em_drying         = 0;
    int em_held           = 0;
    int em_released       = 0;
    int ignored_scald     = 0;
    int ignored_inputs    = 0;
    int heat_waits        = 0;
    int soap_waits        = 0;
    int resets_mid_shower = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        top     = T_OFF;
        sub     = SB_RINSING;
        dry_cnt = 0;
    endfunction

    function void step_model(ShowerTxn tr);
        top_state_e next_top;
        sub_state_e next_sub;
        int         next_cnt;

        next_top = top;
        next_sub = sub;
        next_cnt = (top == T_DRYING) ? ((dry_cnt + 1) & 3) : 0;

        if (tr.start   && top != T_OFF)     ignored_inputs++;
        if (tr.temp_ok && top != T_HEATING) ignored_inputs++;
        if (tr.soaped  && !(top == T_BATHING && sub == SB_SOAPING)) ignored_inputs++;

        if (tr.scald && top != T_OFF) begin
            next_top = T_EMERGENCY;
            case (top)
                T_HEATING:   em_heating++;
                T_DRYING:    em_drying++;
                T_EMERGENCY: em_held++;
                T_BATHING: begin
                    case (sub)
                        SB_RINSING: em_rinsing++;
                        SB_SOAPING: em_soaping++;
                        default:    em_final++;
                    endcase
                end
                default: ;
            endcase
        end
        else begin
            if (tr.scald) ignored_scald++;

            case (top)
                T_OFF: begin
                    if (tr.start) next_top = T_HEATING;
                end

                T_HEATING: begin
                    if (tr.temp_ok) begin
                        next_top = T_BATHING;
                        next_sub = SB_RINSING;
                    end
                    else
                        heat_waits++;
                end

                T_BATHING: begin
                    case (sub)
                        SB_RINSING: next_sub = SB_SOAPING;
                        SB_SOAPING: begin
                            if (tr.soaped)
                                next_sub = SB_FINAL_RINSE;
                            else
                                soap_waits++;
                        end
                        SB_FINAL_RINSE: next_top = T_DRYING;
                        default: next_sub = SB_RINSING;
                    endcase
                end

                T_DRYING: begin
                    if (dry_cnt == 3) begin
                        next_top = T_OFF;
                        showers++;
                    end
                end

                T_EMERGENCY: begin
                    next_top = T_OFF;
                    em_released++;
                end

                default: next_top = T_OFF;
            endcase
        end

        top     = next_top;
        sub     = next_sub;
        dry_cnt = next_cnt;
    endfunction

    function void check(ShowerTxn tr);
        bit ok = 1;
        bit exp_valve;
        bit exp_soap;
        bit exp_dryer;
        bit exp_alarm;

        if (!tr.rst_n) begin
            if (top != T_OFF) resets_mid_shower++;
            reset_model();
        end

        exp_valve = (top == T_HEATING) ||
                    ((top == T_BATHING) && (sub == SB_RINSING || sub == SB_FINAL_RINSE));
        exp_soap  = (top == T_BATHING) && (sub == SB_SOAPING);
        exp_dryer = (top == T_DRYING);
        exp_alarm = (top == T_EMERGENCY);

        if (tr.valve !== exp_valve) begin
            $error("[SB] valve_open_o mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.valve, exp_valve, top.name(), sub.name());
            ok = 0;
        end

        if (tr.soap !== exp_soap) begin
            $error("[SB] soap_dispenser_o mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.soap, exp_soap, top.name(), sub.name());
            ok = 0;
        end

        if (tr.dryer !== exp_dryer) begin
            $error("[SB] air_dryer_o mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.dryer, exp_dryer, top.name(), sub.name());
            ok = 0;
        end

        if (tr.alarm !== exp_alarm) begin
            $error("[SB] alarm_led_o mismatch @ %0t: got %0b, expected %0b (state %s/%s)",
                   $time, tr.alarm, exp_alarm, top.name(), sub.name());
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
        $display("showers completed       : %0d", showers);
        $display("scald in HEATING        : %0d", em_heating);
        $display("scald in RINSING        : %0d", em_rinsing);
        $display("scald in SOAPING        : %0d", em_soaping);
        $display("scald in FINAL_RINSE    : %0d", em_final);
        $display("scald in DRYING         : %0d", em_drying);
        $display("emergency held cycles   : %0d", em_held);
        $display("emergency released      : %0d", em_released);
        $display("scald ignored (OFF)     : %0d", ignored_scald);
        $display("other ignored inputs    : %0d", ignored_inputs);
        $display("waiting for temp_ok     : %0d", heat_waits);
        $display("waiting for soaped_up   : %0d", soap_waits);
        $display("resets mid-shower       : %0d", resets_mid_shower);
        $display("--------------------------------------------");

        if (showers == 0)
            $warning("[SB] no shower was completed");
        if (em_heating == 0 || em_rinsing == 0 || em_soaping == 0 || em_final == 0 || em_drying == 0)
            $warning("[SB] emergency was not reached from every stage");
        if (em_held == 0 || em_released == 0 || ignored_scald == 0)
            $warning("[SB] held, released or ignored emergency was never exercised");
        if (heat_waits == 0 || soap_waits == 0 || ignored_inputs == 0)
            $warning("[SB] waiting or ignored inputs were never exercised");
        if (resets_mid_shower == 0)
            $warning("[SB] reset was never applied in the middle of a shower");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class ShowerMonitor;
    virtual shower_if vif;
    ShowerScoreboard  sb;

    function new(virtual shower_if vif, ShowerScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        ShowerTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.start   = vif.mon_cb.start;
            tr.temp_ok = vif.mon_cb.temp_ok;
            tr.soaped  = vif.mon_cb.soaped;
            tr.scald   = vif.mon_cb.scald;
            tr.valve   = vif.mon_cb.valve;
            tr.soap    = vif.mon_cb.soap;
            tr.dryer   = vif.mon_cb.dryer;
            tr.alarm   = vif.mon_cb.alarm;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class ShowerDriver;
    virtual shower_if vif;

    function new(virtual shower_if vif);
        this.vif = vif;
    endfunction

    task drive(ShowerTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.start   <= tr.start;
        vif.temp_ok <= tr.temp_ok;
        vif.soaped  <= tr.soaped;
        vif.scald   <= tr.scald;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class ShowerGenerator;
    ShowerDriver drv;
    int          num_random;

    function new(ShowerDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit start = 1'b0, bit temp_ok = 1'b0,
              bit soaped = 1'b0, bit scald = 1'b0);
        ShowerTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.start   = start;
        tr.temp_ok = temp_ok;
        tr.soaped  = soaped;
        tr.scald   = scald;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task shower(int heat_wait = 1, int soap_wait = 1);
        step(1'b1, 1'b1);
        calm(heat_wait);
        step(1'b1, 1'b0, 1'b1);
        step();
        calm(soap_wait);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step();
        calm(6);
    endtask

    task to_stage(int s);
        step(1'b1, 1'b1);
        if (s >= 2) step(1'b1, 1'b0, 1'b1);
        if (s >= 3) step();
        if (s >= 4) step(1'b1, 1'b0, 1'b0, 1'b1);
        if (s >= 5) step();
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (3) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b0);
        repeat (4) step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(2);

        shower(0, 0);
        shower(1, 1);
        shower(4, 5);

        repeat (60) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b0);
        calm(8);

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            repeat (3) step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            calm(3);
            shower(1, 1);
        end

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            calm(3);
            shower(1, 1);
        end

        to_stage(5);
        calm(3);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(3);
        shower(1, 1);

        to_stage(2);
        repeat (4) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b1, 1'b1, 1'b1, 1'b0);
        calm(10);

        to_stage(3);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step();
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        calm(3);
        shower(1, 1);

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            step(1'b0);
            calm(2);
            shower(1, 1);
        end

        to_stage(2);
        step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        step(1'b0);
        calm(2);
        shower(1, 1);

        to_stage(5);
        calm(2);
        step(1'b0);
        calm(2);
        shower(1, 1);
    endtask

    task random_run();
        ShowerTxn tr;
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
                    tr.start_w = 300; tr.temp_w = 400; tr.soaped_w = 400; tr.scald_w = 2;
                end
                1: begin
                    tr.start_w = 300; tr.temp_w = 80;  tr.soaped_w = 100; tr.scald_w = 5;
                end
                2: begin
                    tr.start_w = 300; tr.temp_w = 400; tr.soaped_w = 400; tr.scald_w = 40;
                end
                default: begin
                    tr.start_w = 600; tr.temp_w = 700; tr.soaped_w = 700; tr.scald_w = 10;
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
class ShowerEnvironment;
    ShowerGenerator  gen;
    ShowerDriver     drv;
    ShowerMonitor    mon;
    ShowerScoreboard sb;

    virtual shower_if vif;

    function new(virtual shower_if vif, int num_random = 20000);
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
module tb_SmartShower;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    shower_if vif (clk);

    SmartShower dut (
        .clk                (clk),
        .rst_n              (vif.rst_n),
        .start_shower_i     (vif.start),
        .temp_ok_i          (vif.temp_ok),
        .soaped_up_i        (vif.soaped),
        .scald_protection_i (vif.scald),
        .valve_open_o       (vif.valve),
        .soap_dispenser_o   (vif.soap),
        .air_dryer_o        (vif.dryer),
        .alarm_led_o        (vif.alarm)
    );

    ShowerEnvironment env;

    initial begin
        $dumpfile("SmartShower_waveform.vcd");
        $dumpvars(0, tb_SmartShower);
        #10us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.start   = 1'b0;
        vif.temp_ok = 1'b0;
        vif.soaped  = 1'b0;
        vif.scald   = 1'b0;

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

