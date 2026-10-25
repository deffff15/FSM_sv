`timescale 1ns/1ps

typedef enum int {S_AWAKE, S_SLEEP1, S_SLEEP2, S_SLEEP3, S_SLEEP4, S_SLEEP5, S_WAKING} sleep_state_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface sleep_if (input logic clk);
    logic rst_n;
    logic bed;
    logic disturb;
    logic well;
    logic tired;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, bed, disturb, well, tired;
    endclocking
endinterface


// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class SleepTxn;
    rand bit rst_n;
    rand bit bed;
    rand bit disturb;

    int rst_w     = 3;
    int bed_w     = 250;
    int disturb_w = 200;

    logic well;
    logic tired;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,     1'b1 := 1000 - rst_w};
        bed     dist {1'b1 := bed_w,     1'b0 := 1000 - bed_w};
        disturb dist {1'b1 := disturb_w, 1'b0 := 1000 - disturb_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class SleepScoreboard;
    sleep_state_e state;
    int           count;
    bit           limit;
    int           night_dist;

    int checked             = 0;
    int errors              = 0;
    int well_nights         = 0;
    int tired_nights        = 0;
    int nights_by_count[4]  = '{0, 0, 0, 0};
    int ignored_disturb     = 0;
    int ignored_bed         = 0;
    int resets_mid_night    = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        state      = S_AWAKE;
        count      = 0;
        limit      = 0;
        night_dist = 0;
    endfunction

    function void step_model(SleepTxn tr);
        sleep_state_e next_state;
        bit           sleeping;

        sleeping   = (state >= S_SLEEP1) && (state <= S_SLEEP5);
        next_state = state;

        case (state)
            S_AWAKE:  if (tr.bed) next_state = S_SLEEP1;
            S_SLEEP1: next_state = S_SLEEP2;
            S_SLEEP2: next_state = S_SLEEP3;
            S_SLEEP3: next_state = S_SLEEP4;
            S_SLEEP4: next_state = S_SLEEP5;
            S_SLEEP5: next_state = S_WAKING;
            S_WAKING: next_state = S_AWAKE;
            default:  next_state = S_AWAKE;
        endcase

        if (state == S_WAKING) begin
            if (limit) tired_nights++;
            else       well_nights++;
            nights_by_count[(night_dist > 3) ? 3 : night_dist]++;
        end

        if (tr.bed && (sleeping || state == S_WAKING)) ignored_bed++;

        if (state == S_AWAKE && tr.bed) begin
            if (tr.disturb) ignored_disturb++;
            count      = 0;
            limit      = 0;
            night_dist = 0;
        end
        else if (sleeping) begin
            if (tr.disturb) begin
                night_dist++;
                if (count == 2)
                    limit = 1;
                else
                    count++;
            end
        end
        else if (tr.disturb)
            ignored_disturb++;

        state = next_state;
    endfunction

    function void check(SleepTxn tr);
        bit ok = 1;
        bit exp_well;
        bit exp_tired;

        if (!tr.rst_n) begin
            if (state != S_AWAKE) resets_mid_night++;
            reset_model();
        end

        exp_well  = (state == S_WAKING) && !limit;
        exp_tired = (state == S_WAKING) && limit;

        if (tr.well !== exp_well) begin
            $error("[SB] well_rested_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.well, exp_well, state.name());
            ok = 0;
        end

        if (tr.tired !== exp_tired) begin
            $error("[SB] tired_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.tired, exp_tired, state.name());
            ok = 0;
        end

        if (tr.rst_n) step_model(tr);

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked        : %0d", checked);
        $display("errors                : %0d", errors);
        $display("well rested nights    : %0d", well_nights);
        $display("tired nights          : %0d", tired_nights);
        $display("nights with 0 disturb.: %0d", nights_by_count[0]);
        $display("nights with 1 disturb.: %0d", nights_by_count[1]);
        $display("nights with 2 disturb.: %0d", nights_by_count[2]);
        $display("nights with 3+ disturb: %0d", nights_by_count[3]);
        $display("ignored disturbances  : %0d", ignored_disturb);
        $display("ignored go-to-bed     : %0d", ignored_bed);
        $display("resets mid-night      : %0d", resets_mid_night);
        $display("--------------------------------------------");

        if (well_nights == 0 || tired_nights == 0)
            $warning("[SB] both outcomes (well rested / tired) were not reached");
        if (nights_by_count[1] == 0 || nights_by_count[2] == 0 || nights_by_count[3] == 0)
            $warning("[SB] not every disturbance count (1 / 2 / 3+) was reached");
        if (ignored_disturb == 0 || ignored_bed == 0)
            $warning("[SB] ignored disturbance or go-to-bed was never exercised");
        if (resets_mid_night == 0)
            $warning("[SB] reset was never applied in the middle of a night");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class SleepMonitor;
    virtual sleep_if vif;
    SleepScoreboard  sb;

    function new(virtual sleep_if vif, SleepScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        SleepTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.bed     = vif.mon_cb.bed;
            tr.disturb = vif.mon_cb.disturb;
            tr.well    = vif.mon_cb.well;
            tr.tired   = vif.mon_cb.tired;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class SleepDriver;
    virtual sleep_if vif;

    function new(virtual sleep_if vif);
        this.vif = vif;
    endfunction

    task drive(SleepTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.bed     <= tr.bed;
        vif.disturb <= tr.disturb;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class SleepGenerator;
    SleepDriver drv;
    int         num_random;

    function new(SleepDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit bed = 1'b0, bit disturb = 1'b0);
        SleepTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.bed     = bed;
        tr.disturb = disturb;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task sleep_night(bit [4:0] d);
        step(1'b1, 1'b1, 1'b0);
        for (int i = 0; i < 5; i++)
            step(1'b1, 1'b0, d[i]);
        step();
        calm(2);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (5) step(1'b1, 1'b0, 1'b1);
        calm(2);

        for (int p = 0; p < 32; p++)
            sleep_night(p[4:0]);

        step(1'b1, 1'b1, 1'b1);
        repeat (5) step();
        step(1'b1, 1'b0, 1'b1);
        calm(2);

        repeat (40) step(1'b1, 1'b1, 1'b0);
        calm(2);

        repeat (40) step(1'b1, 1'b1, 1'b1);
        calm(2);

        sleep_night(5'b11111);
        sleep_night(5'b00000);

        for (int k = 0; k < 6; k++) begin
            step(1'b1, 1'b1, 1'b0);
            repeat (k) step(1'b1, 1'b0, 1'b1);
            step(1'b0);
            calm(2);
            sleep_night(5'b00000);
        end
    endtask

    task random_run();
        SleepTxn tr;
        bit over;
        bit was_over = 1'b1;
        int style    = 0;

        repeat (num_random) begin
            over = (drv.vif.well === 1'b1) || (drv.vif.tired === 1'b1);

            if (over && !was_over)
                style = $urandom_range(0, 3);
            was_over = over;

            tr = new();
            tr.rst_w = 3;
            tr.bed_w = 250;
            case (style)
                0:       tr.disturb_w = 30;
                1:       tr.disturb_w = 200;
                2:       tr.disturb_w = 500;
                default: tr.disturb_w = 100;
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
class SleepEnvironment;
    SleepGenerator  gen;
    SleepDriver     drv;
    SleepMonitor    mon;
    SleepScoreboard sb;

    virtual sleep_if vif;

    function new(virtual sleep_if vif, int num_random = 20000);
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
module tb_SleepSimulator;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    sleep_if vif (clk);

    SleepSimulator dut (
        .clk           (clk),
        .rst_n         (vif.rst_n),
        .go_to_bed_i   (vif.bed),
        .disturbance_i (vif.disturb),
        .well_rested_o (vif.well),
        .tired_o       (vif.tired)
    );

    SleepEnvironment env;

    initial begin
        $dumpfile("SleepSimulator_waveform.vcd");
        $dumpvars(0, tb_SleepSimulator);
        #8us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.bed     = 1'b0;
        vif.disturb = 1'b0;

        repeat (2) @(negedge clk);

        env = new(vif);
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "[TB] timeout");
    end
endmodule // The last line must be empty so vscode doesn't give a mistake

