`timescale 1ns/1ps

typedef enum int {F_IDLE, F_READY, F_AIMED, F_EXTINGUISHING, F_SUCCESS, F_EVACUATE} fire_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface fire_if (input logic clk);
    logic       rst_n;
    logic       pin;
    logic       aim;
    logic       lever;
    logic       ooc;
    logic       empty;
    logic [2:0] status;
    logic       alarm;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, pin, aim, lever, ooc, empty, status, alarm;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class FireTxn;
    rand bit rst_n;
    rand bit pin;
    rand bit aim;
    rand bit lever;
    rand bit ooc;
    rand bit empty;

    int rst_w   = 30;
    int pin_w   = 300;
    int aim_w   = 500;
    int lever_w = 500;
    int ooc_w   = 10;
    int empty_w = 10;

    logic [2:0] status;
    logic       alarm;

    constraint c_ctrl {
        rst_n dist {1'b0 := rst_w,   1'b1 := 1000 - rst_w};
        pin   dist {1'b1 := pin_w,   1'b0 := 1000 - pin_w};
        aim   dist {1'b1 := aim_w,   1'b0 := 1000 - aim_w};
        lever dist {1'b1 := lever_w, 1'b0 := 1000 - lever_w};
        ooc   dist {1'b1 := ooc_w,   1'b0 := 1000 - ooc_w};
        empty dist {1'b1 := empty_w, 1'b0 := 1000 - empty_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class FireScoreboard;
    fire_e st;

    int checked          = 0;
    int errors           = 0;
    int pins             = 0;
    int aims             = 0;
    int squeezes         = 0;
    int aim_lost         = 0;
    int lever_prio       = 0;
    int lever_released   = 0;
    int successes        = 0;
    int empty_evac       = 0;
    int empty_prio       = 0;
    int evac_idle        = 0;
    int evac_ready       = 0;
    int evac_aimed       = 0;
    int evac_ext         = 0;
    int ooc_prio         = 0;
    int ooc_in_success   = 0;
    int ooc_in_evac      = 0;
    int idle_waits       = 0;
    int ready_waits      = 0;
    int aimed_waits      = 0;
    int success_waits    = 0;
    int evac_waits       = 0;
    int ignored_pin      = 0;
    int ignored_lever    = 0;
    int ignored_empty    = 0;
    int resets_mid       = 0;
    int resets_after_end = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st = F_IDLE;
    endfunction

    function void step_model(FireTxn tr);
        fire_e next_st;

        next_st = st;

        if (tr.pin && st != F_IDLE)
            ignored_pin++;
        if (tr.lever && st != F_AIMED && st != F_EXTINGUISHING)
            ignored_lever++;
        if (tr.empty && st != F_EXTINGUISHING)
            ignored_empty++;
        if (tr.ooc && st == F_SUCCESS)
            ooc_in_success++;
        if (tr.ooc && st == F_EVACUATE)
            ooc_in_evac++;
        if (tr.ooc && st != F_SUCCESS && st != F_EVACUATE &&
            (tr.pin || tr.aim || tr.lever || tr.empty))
            ooc_prio++;
        if (st == F_SUCCESS)
            success_waits++;
        if (st == F_EVACUATE)
            evac_waits++;

        if (tr.ooc && st != F_SUCCESS) begin
            next_st = F_EVACUATE;
            if (st == F_IDLE)             evac_idle++;
            if (st == F_READY)            evac_ready++;
            if (st == F_AIMED)            evac_aimed++;
            if (st == F_EXTINGUISHING)    evac_ext++;
        end
        else begin
            case (st)
                F_IDLE: begin
                    if (tr.pin) begin
                        next_st = F_READY;
                        pins++;
                    end
                    else
                        idle_waits++;
                end

                F_READY: begin
                    if (tr.aim) begin
                        next_st = F_AIMED;
                        aims++;
                    end
                    else
                        ready_waits++;
                end

                F_AIMED: begin
                    if (tr.lever) begin
                        next_st = F_EXTINGUISHING;
                        squeezes++;
                        if (!tr.aim) lever_prio++;
                    end
                    else if (!tr.aim) begin
                        next_st = F_READY;
                        aim_lost++;
                    end
                    else
                        aimed_waits++;
                end

                F_EXTINGUISHING: begin
                    if (tr.empty) begin
                        next_st = F_EVACUATE;
                        empty_evac++;
                        if (!tr.lever) empty_prio++;
                    end
                    else if (!tr.lever) begin
                        next_st = F_AIMED;
                        lever_released++;
                    end
                    else begin
                        next_st = F_SUCCESS;
                        successes++;
                    end
                end

                F_SUCCESS, F_EVACUATE: next_st = st;

                default: next_st = F_IDLE;
            endcase
        end

        st = next_st;
    endfunction

    function void check(FireTxn tr);
        bit       ok = 1;
        bit [2:0] exp_status;
        bit       exp_alarm;

        if (!tr.rst_n) begin
            if (st == F_SUCCESS || st == F_EVACUATE)
                resets_after_end++;
            else if (st != F_IDLE)
                resets_mid++;
            reset_model();
        end

        exp_status = 3'(st);
        exp_alarm  = (st == F_EVACUATE);

        if (tr.status !== exp_status) begin
            $error("[SB] status_o mismatch @ %0t: got %0d, expected %0d (state %s)",
                   $time, tr.status, exp_status, st.name());
            ok = 0;
        end

        if (tr.alarm !== exp_alarm) begin
            $error("[SB] evacuate_alarm_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.alarm, exp_alarm, st.name());
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
        $display("pin pulled              : %0d", pins);
        $display("aimed at base           : %0d", aims);
        $display("lever squeezed          : %0d", squeezes);
        $display("aim lost                : %0d", aim_lost);
        $display("lever over lost aim     : %0d", lever_prio);
        $display("lever released          : %0d", lever_released);
        $display("successes               : %0d", successes);
        $display("evacuated: empty        : %0d", empty_evac);
        $display("empty over lever release: %0d", empty_prio);
        $display("evacuated from idle     : %0d", evac_idle);
        $display("evacuated from ready    : %0d", evac_ready);
        $display("evacuated from aimed    : %0d", evac_aimed);
        $display("evacuated from extingu. : %0d", evac_ext);
        $display("fire ooc over inputs    : %0d", ooc_prio);
        $display("fire ooc in success     : %0d", ooc_in_success);
        $display("fire ooc in evacuate    : %0d", ooc_in_evac);
        $display("waiting in idle         : %0d", idle_waits);
        $display("waiting in ready        : %0d", ready_waits);
        $display("waiting in aimed        : %0d", aimed_waits);
        $display("waiting in success      : %0d", success_waits);
        $display("waiting in evacuate     : %0d", evac_waits);
        $display("pin ignored             : %0d", ignored_pin);
        $display("lever ignored           : %0d", ignored_lever);
        $display("empty ignored           : %0d", ignored_empty);
        $display("resets mid-run          : %0d", resets_mid);
        $display("resets after end        : %0d", resets_after_end);
        $display("--------------------------------------------");

        if (pins == 0 || aims == 0 || squeezes == 0)
            $warning("[SB] not every forward step (pin / aim / squeeze) was reached");
        if (successes == 0)
            $warning("[SB] no extinguishing ended in success");
        if (empty_evac == 0)
            $warning("[SB] extinguisher_empty never caused an evacuation");
        if (evac_idle == 0 || evac_ready == 0 || evac_aimed == 0 || evac_ext == 0)
            $warning("[SB] fire_out_of_control did not trigger evacuation from every state");
        if (aim_lost == 0 || lever_released == 0)
            $warning("[SB] aim lost or lever released was never exercised");
        if (lever_prio == 0)
            $warning("[SB] lever_squeezed together with lost aim was never applied while aimed");
        if (empty_prio == 0)
            $warning("[SB] extinguisher_empty together with released lever was never applied");
        if (ooc_prio == 0)
            $warning("[SB] fire_out_of_control together with other inputs was never applied");
        if (ooc_in_success == 0 || ooc_in_evac == 0)
            $warning("[SB] fire_out_of_control in success / evacuate was never applied");
        if (idle_waits == 0 || ready_waits == 0 || aimed_waits == 0 ||
            success_waits == 0 || evac_waits == 0)
            $warning("[SB] waiting in every state was never exercised");
        if (ignored_pin == 0 || ignored_lever == 0 || ignored_empty == 0)
            $warning("[SB] ignored pin / lever / empty was never exercised");
        if (resets_mid == 0)
            $warning("[SB] reset was never applied in the middle of a run");
        if (resets_after_end == 0)
            $warning("[SB] reset was never applied after success or evacuation");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class FireMonitor;
    virtual fire_if vif;
    FireScoreboard  sb;

    function new(virtual fire_if vif, FireScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        FireTxn tr;
        forever begin
            @(vif.mon_cb);
            tr        = new();
            tr.rst_n  = vif.mon_cb.rst_n;
            tr.pin    = vif.mon_cb.pin;
            tr.aim    = vif.mon_cb.aim;
            tr.lever  = vif.mon_cb.lever;
            tr.ooc    = vif.mon_cb.ooc;
            tr.empty  = vif.mon_cb.empty;
            tr.status = vif.mon_cb.status;
            tr.alarm  = vif.mon_cb.alarm;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class FireDriver;
    virtual fire_if vif;

    function new(virtual fire_if vif);
        this.vif = vif;
    endfunction

    task drive(FireTxn tr);
        @(negedge vif.clk);
        vif.rst_n <= tr.rst_n;
        vif.pin   <= tr.pin;
        vif.aim   <= tr.aim;
        vif.lever <= tr.lever;
        vif.ooc   <= tr.ooc;
        vif.empty <= tr.empty;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class FireGenerator;
    FireDriver drv;
    int        num_random;

    function new(FireDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit pin = 1'b0, bit aim = 1'b0,
              bit lever = 1'b0, bit ooc = 1'b0, bit empty = 1'b0);
        FireTxn tr;
        tr        = new();
        tr.rst_n  = rst_n;
        tr.pin    = pin;
        tr.aim    = aim;
        tr.lever  = lever;
        tr.ooc    = ooc;
        tr.empty  = empty;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task attempt(int idle_wait, int ready_wait, int aimed_wait, int outcome);
        calm(idle_wait);
        step(1'b1, 1'b1);
        calm(ready_wait);
        step(1'b1, 1'b0, 1'b1);
        repeat (aimed_wait) step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        case (outcome)
            0: step(1'b1, 1'b0, 1'b1, 1'b1);
            1: step(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1);
            2: step(1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
            3: begin
                step(1'b1, 1'b0, 1'b1);
                step(1'b1, 1'b0, 1'b1, 1'b1);
                step(1'b1, 1'b0, 1'b1, 1'b1);
            end
            4: step(1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
            default: begin
                step(1'b1, 1'b0, 1'b1);
                step();
                step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            end
        endcase
        repeat (3) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(2);
    endtask

    task to_stage(int s);
        if (s >= 1) step(1'b1, 1'b1);
        if (s >= 2) step(1'b1, 1'b0, 1'b1);
        if (s >= 3) step(1'b1, 1'b0, 1'b1, 1'b1);
        if (s == 4) step(1'b1, 1'b0, 1'b1, 1'b1);
        if (s == 5) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1);
    endtask

    task fire(int s, bit all);
        to_stage(s);
        step(1'b1, all, all, all, 1'b1, all);
        repeat (3) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(2);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (3) step();
        repeat (3) step(1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1);
        calm(2);

        attempt(0, 0, 0, 0);
        attempt(2, 2, 2, 1);
        attempt(1, 1, 1, 2);
        attempt(0, 0, 0, 3);
        attempt(3, 3, 3, 4);
        attempt(1, 0, 2, 5);

        step(1'b1, 1'b1);
        repeat (3) step(1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1);
        repeat (3) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b1);
        step(1'b0);
        calm(2);

        step(1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b1);
        step();
        step(1'b1, 1'b0, 1'b1);
        repeat (2) step(1'b1, 1'b0, 1'b1);
        step();
        step();
        step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b1);
        step(1'b0);
        calm(2);

        for (int s = 0; s <= 3; s++) begin
            fire(s, 1'b0);
            fire(s, 1'b1);
        end

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            step(1'b0);
            calm(2);
            attempt(1, 1, 1, 0);
        end

        step(1'b0, 1'b1);
        calm(2);
        attempt(1, 1, 1, 0);
    endtask

    task random_run();
        FireTxn tr;
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
                    tr.rst_w = 30; tr.pin_w = 300; tr.aim_w = 500; tr.lever_w = 500;
                    tr.ooc_w = 10; tr.empty_w = 10;
                end
                1: begin
                    tr.rst_w = 40; tr.pin_w = 400; tr.aim_w = 700; tr.lever_w = 700;
                    tr.ooc_w = 5;  tr.empty_w = 5;
                end
                2: begin
                    tr.rst_w = 30; tr.pin_w = 300; tr.aim_w = 300; tr.lever_w = 300;
                    tr.ooc_w = 50; tr.empty_w = 50;
                end
                default: begin
                    tr.rst_w = 50; tr.pin_w = 500; tr.aim_w = 500; tr.lever_w = 500;
                    tr.ooc_w = 100; tr.empty_w = 100;
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
class FireEnvironment;
    FireGenerator  gen;
    FireDriver     drv;
    FireMonitor    mon;
    FireScoreboard sb;

    virtual fire_if vif;

    function new(virtual fire_if vif, int num_random = 20000);
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
module tb_FireExtinguisher;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    fire_if vif (clk);

    FireExtinguisher dut (
        .clk                   (clk),
        .rst_n                 (vif.rst_n),
        .pin_pulled_i          (vif.pin),
        .aimed_at_base_i       (vif.aim),
        .lever_squeezed_i      (vif.lever),
        .fire_out_of_control_i (vif.ooc),
        .extinguisher_empty_i  (vif.empty),
        .status_o              (vif.status),
        .evacuate_alarm_o      (vif.alarm)
    );

    FireEnvironment env;

    initial begin
        $dumpfile("FireExtinguisher_waveform.vcd");
        $dumpvars(0, tb_FireExtinguisher);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n = 1'b0;
        vif.pin   = 1'b0;
        vif.aim   = 1'b0;
        vif.lever = 1'b0;
        vif.ooc   = 1'b0;
        vif.empty = 1'b0;

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

