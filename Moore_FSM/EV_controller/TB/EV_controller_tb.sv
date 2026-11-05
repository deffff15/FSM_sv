`timescale 1ns/1ps

typedef enum int {E_STANDBY, E_WAIT, E_LOCKING, E_CHARGING, E_UNLOCKING, E_EMERGENCY} ev_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface ev_if (input logic clk);
    logic       rst_n;
    logic       card;
    logic       plug;
    logic       temp;
    logic       complete;
    logic       lock;
    logic       contactor;
    logic [1:0] fan;
    logic [1:0] led;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, card, plug, temp, complete, lock, contactor, fan, led;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class EvTxn;
    rand bit rst_n;
    rand bit card;
    rand bit plug;
    rand bit temp;
    rand bit complete;

    int rst_w      = 10;
    int card_w     = 300;
    int plug_w     = 500;
    int temp_w     = 5;
    int complete_w = 100;

    logic       lock;
    logic       contactor;
    logic [1:0] fan;
    logic [1:0] led;

    constraint c_ctrl {
        rst_n    dist {1'b0 := rst_w,      1'b1 := 1000 - rst_w};
        card     dist {1'b1 := card_w,     1'b0 := 1000 - card_w};
        plug     dist {1'b1 := plug_w,     1'b0 := 1000 - plug_w};
        temp     dist {1'b1 := temp_w,     1'b0 := 1000 - temp_w};
        complete dist {1'b1 := complete_w, 1'b0 := 1000 - complete_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class EvScoreboard;
    ev_e       st;
    bit [4:0]  timer;
    int        dwell;

    int checked          = 0;
    int errors           = 0;
    int starts           = 0;
    int timeouts         = 0;
    int plugs            = 0;
    int plug_prio        = 0;
    int lock1            = 0;
    int lock2            = 0;
    int lock3            = 0;
    int completes        = 0;
    int unlocks          = 0;
    int emerg_temp       = 0;
    int emerg_plug       = 0;
    int emerg_both       = 0;
    int emerg_prio       = 0;
    int standby_waits    = 0;
    int wait_waits       = 0;
    int lock_waits       = 0;
    int charge_waits     = 0;
    int unlock_waits     = 0;
    int emerg_waits      = 0;
    int ignored_card     = 0;
    int ignored_plug     = 0;
    int ignored_temp     = 0;
    int ignored_complete = 0;
    int resets_wait      = 0;
    int resets_lock      = 0;
    int resets_charge    = 0;
    int resets_unlock    = 0;
    int resets_emerg     = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        st    = E_STANDBY;
        timer = 5'd0;
        dwell = 0;
    endfunction

    function void step_model(EvTxn tr);
        ev_e      next_st;
        bit [4:0] next_timer;

        next_st = st;

        if (st == E_WAIT || st == E_LOCKING || st == E_UNLOCKING)
            next_timer = timer + 1'b1;
        else
            next_timer = 5'd0;

        if (tr.card && st != E_STANDBY)
            ignored_card++;
        if (tr.plug && st != E_WAIT && st != E_CHARGING)
            ignored_plug++;
        if (tr.temp && st != E_CHARGING)
            ignored_temp++;
        if (tr.complete && st != E_CHARGING)
            ignored_complete++;

        case (st)
            E_STANDBY: begin
                if (tr.card) begin
                    next_st = E_WAIT;
                    starts++;
                end
                else
                    standby_waits++;
            end

            E_WAIT: begin
                if (tr.plug) begin
                    next_st = E_LOCKING;
                    plugs++;
                    if (timer >= 5'd20) plug_prio++;
                end
                else if (timer >= 5'd20) begin
                    next_st = E_STANDBY;
                    timeouts++;
                end
                else
                    wait_waits++;
            end

            E_LOCKING: begin
                if (timer >= 5'd3) begin
                    next_st = E_CHARGING;
                    if (dwell == 0) lock1++;
                    if (dwell == 1) lock2++;
                    if (dwell == 2) lock3++;
                end
                else
                    lock_waits++;
            end

            E_CHARGING: begin
                if (tr.temp || !tr.plug) begin
                    next_st = E_EMERGENCY;
                    if (tr.temp && tr.plug)       emerg_temp++;
                    else if (!tr.temp && !tr.plug) emerg_plug++;
                    else                          emerg_both++;
                    if (tr.complete) emerg_prio++;
                end
                else if (tr.complete) begin
                    next_st = E_UNLOCKING;
                    completes++;
                end
                else
                    charge_waits++;
            end

            E_UNLOCKING: begin
                if (timer >= 5'd3) begin
                    next_st = E_STANDBY;
                    unlocks++;
                end
                else
                    unlock_waits++;
            end

            E_EMERGENCY: begin
                next_st = E_EMERGENCY;
                emerg_waits++;
            end

            default: next_st = E_STANDBY;
        endcase

        if (next_st != st) dwell = 0;
        else               dwell++;

        st    = next_st;
        timer = next_timer;
    endfunction

    function void check(EvTxn tr);
        bit       ok = 1;
        bit       exp_lock;
        bit       exp_contactor;
        bit [1:0] exp_fan;
        bit [1:0] exp_led;

        if (!tr.rst_n) begin
            case (st)
                E_WAIT:      resets_wait++;
                E_LOCKING:   resets_lock++;
                E_CHARGING:  resets_charge++;
                E_UNLOCKING: resets_unlock++;
                E_EMERGENCY: resets_emerg++;
                default: ;
            endcase
            reset_model();
        end

        exp_lock      = (st == E_LOCKING) || (st == E_CHARGING);
        exp_contactor = (st == E_CHARGING);
        exp_fan       = 2'b00;
        exp_led       = 2'b00;

        if (st == E_CHARGING)    exp_fan = 2'b01;
        if (st == E_UNLOCKING)   exp_fan = 2'b10;
        if (st == E_EMERGENCY)   exp_fan = 2'b10;

        if (st == E_LOCKING)     exp_led = 2'b01;
        if (st == E_CHARGING)    exp_led = 2'b01;
        if (st == E_UNLOCKING)   exp_led = 2'b01;
        if (st == E_EMERGENCY)   exp_led = 2'b10;

        if (tr.lock !== exp_lock) begin
            $error("[SB] lock_motor mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.lock, exp_lock, st.name());
            ok = 0;
        end

        if (tr.contactor !== exp_contactor) begin
            $error("[SB] contactor_en mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.contactor, exp_contactor, st.name());
            ok = 0;
        end

        if (tr.fan !== exp_fan) begin
            $error("[SB] fan_speed mismatch @ %0t: got %b, expected %b (state %s)",
                   $time, tr.fan, exp_fan, st.name());
            ok = 0;
        end

        if (tr.led !== exp_led) begin
            $error("[SB] status_led mismatch @ %0t: got %b, expected %b (state %s)",
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
        $display("card accepted           : %0d", starts);
        $display("wait timeouts           : %0d", timeouts);
        $display("plug connected          : %0d", plugs);
        $display("plug at timeout edge    : %0d", plug_prio);
        $display("locking took 1 cycle    : %0d", lock1);
        $display("locking took 2 cycles   : %0d", lock2);
        $display("locking took 3 cycles   : %0d", lock3);
        $display("charge complete         : %0d", completes);
        $display("unlocked                : %0d", unlocks);
        $display("emergency: temp         : %0d", emerg_temp);
        $display("emergency: plug lost    : %0d", emerg_plug);
        $display("emergency: temp + plug  : %0d", emerg_both);
        $display("emergency over complete : %0d", emerg_prio);
        $display("waiting in standby      : %0d", standby_waits);
        $display("waiting for plug        : %0d", wait_waits);
        $display("waiting in locking      : %0d", lock_waits);
        $display("waiting in charging     : %0d", charge_waits);
        $display("waiting in unlocking    : %0d", unlock_waits);
        $display("waiting in emergency    : %0d", emerg_waits);
        $display("card_valid ignored      : %0d", ignored_card);
        $display("plug ignored            : %0d", ignored_plug);
        $display("temp_critical ignored   : %0d", ignored_temp);
        $display("charge_complete ignored : %0d", ignored_complete);
        $display("resets waiting for plug : %0d", resets_wait);
        $display("resets in locking       : %0d", resets_lock);
        $display("resets in charging      : %0d", resets_charge);
        $display("resets in unlocking     : %0d", resets_unlock);
        $display("resets in emergency     : %0d", resets_emerg);
        $display("--------------------------------------------");

        if (starts == 0 || plugs == 0 || completes == 0 || unlocks == 0)
            $warning("[SB] a full charging session was not completed");
        if (timeouts == 0 || plug_prio == 0)
            $warning("[SB] wait timeout or plug at the timeout edge was never applied");
        if (lock1 == 0 || lock2 == 0 || lock3 == 0)
            $warning("[SB] locking was not seen taking 1, 2 and 3 cycles");
        if (emerg_temp == 0 || emerg_plug == 0 || emerg_both == 0)
            $warning("[SB] not every emergency cause (temp / plug lost / both) was reached");
        if (emerg_prio == 0)
            $warning("[SB] charge_complete together with an emergency cause was never applied");
        if (standby_waits == 0 || wait_waits == 0 || lock_waits == 0 ||
            charge_waits == 0 || unlock_waits == 0 || emerg_waits == 0)
            $warning("[SB] waiting in every state was never exercised");
        if (ignored_card == 0 || ignored_plug == 0 || ignored_temp == 0 || ignored_complete == 0)
            $warning("[SB] ignored card / plug / temp / complete was not exercised");
        if (resets_wait == 0 || resets_lock == 0 || resets_charge == 0 ||
            resets_unlock == 0 || resets_emerg == 0)
            $warning("[SB] reset was not applied in every state");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class EvMonitor;
    virtual ev_if vif;
    EvScoreboard  sb;

    function new(virtual ev_if vif, EvScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        EvTxn tr;
        forever begin
            @(vif.mon_cb);
            tr           = new();
            tr.rst_n     = vif.mon_cb.rst_n;
            tr.card      = vif.mon_cb.card;
            tr.plug      = vif.mon_cb.plug;
            tr.temp      = vif.mon_cb.temp;
            tr.complete  = vif.mon_cb.complete;
            tr.lock      = vif.mon_cb.lock;
            tr.contactor = vif.mon_cb.contactor;
            tr.fan       = vif.mon_cb.fan;
            tr.led       = vif.mon_cb.led;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class EvDriver;
    virtual ev_if vif;

    function new(virtual ev_if vif);
        this.vif = vif;
    endfunction

    task drive(EvTxn tr);
        @(negedge vif.clk);
        vif.rst_n    <= tr.rst_n;
        vif.card     <= tr.card;
        vif.plug     <= tr.plug;
        vif.temp     <= tr.temp;
        vif.complete <= tr.complete;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class EvGenerator;
    EvDriver drv;
    int      num_random;

    function new(EvDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit card = 1'b0, bit plug = 1'b0,
              bit temp = 1'b0, bit complete = 1'b0);
        EvTxn tr;
        tr          = new();
        tr.rst_n    = rst_n;
        tr.card     = card;
        tr.plug     = plug;
        tr.temp     = temp;
        tr.complete = complete;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task session(int wait_len, int charge_len, int outcome);
        step(1'b1, 1'b1);
        calm(wait_len);
        step(1'b1, 1'b0, 1'b1);
        repeat (4) step(1'b1, 1'b0, 1'b1);
        repeat (charge_len) step(1'b1, 1'b0, 1'b1);
        case (outcome)
            0: begin
                step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
                step(1'b1, 1'b1, 1'b0, 1'b1, 1'b1);
                step(1'b1, 1'b1, 1'b1, 1'b1, 1'b0);
                step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
                step(1'b1, 1'b0, 1'b1);
                calm(2);
            end
            1: step(1'b1, 1'b0, 1'b1, 1'b1);
            2: step(1'b1, 1'b0, 1'b0);
            3: step(1'b1, 1'b0, 1'b0, 1'b1);
            4: step(1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
            default: step(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        endcase
        if (outcome != 0) begin
            repeat (3) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
            step(1'b0);
            calm(2);
        end
    endtask

    task to_stage(int s);
        step(1'b1, 1'b1);
        if (s >= 2) step(1'b1, 1'b0, 1'b1);
        if (s >= 3) repeat (3) step(1'b1, 1'b0, 1'b1);
        if (s == 4) step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        if (s == 5) step(1'b1, 1'b0, 1'b1, 1'b1);
    endtask

    task directed();
        step(1'b0);
        step(1'b0, 1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b1);
        calm(3);
        step(1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        calm(2);

        session(0,  0, 0);
        session(1,  1, 0);
        session(2,  2, 0);
        session(5,  0, 0);
        session(19, 3, 0);
        session(20, 0, 0);

        session(2, 2, 1);
        session(2, 2, 2);
        session(2, 0, 3);
        session(2, 0, 4);
        session(2, 0, 5);
        session(0, 0, 1);

        step(1'b1, 1'b1);
        calm(21);
        calm(3);

        repeat (60) step(1'b1, 1'b1);
        calm(3);

        step(1'b1, 1'b1, 1'b1);
        repeat (6) step(1'b1, 1'b0, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        repeat (6) step(1'b1, 1'b0, 1'b1);
        calm(2);

        step(1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
        step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        repeat (8) step(1'b1, 1'b0, 1'b1, 1'b0, 1'b1);
        calm(2);

        repeat (40) step(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(2);

        for (int s = 1; s <= 5; s++) begin
            to_stage(s);
            step(1'b0, 1'b1, 1'b1, 1'b1, 1'b1);
            calm(2);
            session(1, 1, 0);
        end

        step(1'b0, 1'b1, 1'b1, 1'b1, 1'b1);
        calm(2);
        session(3, 2, 0);
    endtask

    task random_run();
        EvTxn tr;
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
                    tr.rst_w = 10; tr.card_w = 300; tr.plug_w = 500;
                    tr.temp_w = 5; tr.complete_w = 100;
                end
                1: begin
                    tr.rst_w = 5;  tr.card_w = 200; tr.plug_w = 800;
                    tr.temp_w = 2; tr.complete_w = 50;
                end
                2: begin
                    tr.rst_w = 10; tr.card_w = 300; tr.plug_w = 300;
                    tr.temp_w = 50; tr.complete_w = 200;
                end
                default: begin
                    tr.rst_w = 20; tr.card_w = 100; tr.plug_w = 600;
                    tr.temp_w = 10; tr.complete_w = 300;
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
class EvEnvironment;
    EvGenerator  gen;
    EvDriver     drv;
    EvMonitor    mon;
    EvScoreboard sb;

    virtual ev_if vif;

    function new(virtual ev_if vif, int num_random = 20000);
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
module tb_EV_controller;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    ev_if vif (clk);

    EV_controller dut (
        .clk               (clk),
        .rst_n             (vif.rst_n),
        .card_valid_i      (vif.card),
        .plug_connected_i  (vif.plug),
        .temp_critical_i   (vif.temp),
        .charge_complete_i (vif.complete),
        .lock_motor_o      (vif.lock),
        .contactor_en_o    (vif.contactor),
        .fan_speed_o       (vif.fan),
        .status_led_o      (vif.led)
    );

    EvEnvironment env;

    initial begin
        $dumpfile("EV_controller_waveform.vcd");
        $dumpvars(0, tb_EV_controller);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n    = 1'b0;
        vif.card     = 1'b0;
        vif.plug     = 1'b0;
        vif.temp     = 1'b0;
        vif.complete = 1'b0;

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

