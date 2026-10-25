`timescale 1ns/1ps

typedef enum int {N_IDLE, N_MOW1, N_MOW2, N_MOW3, N_SHOUT, N_POLICE, N_FIGHT, N_SUCCESS} neighbor_state_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface neighbor_if (input logic clk);
    logic rst_n;
    logic start;
    logic noticed;
    logic shouting;
    logic police;
    logic fight;
    logic mowed;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, start, noticed, shouting, police, fight, mowed;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class NeighborTxn;
    rand bit rst_n;
    rand bit start;
    rand bit noticed;

    int rst_w     = 3;
    int start_w   = 150;
    int noticed_w = 300;

    logic shouting;
    logic police;
    logic fight;
    logic mowed;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,     1'b1 := 1000 - rst_w};
        start   dist {1'b1 := start_w,   1'b0 := 1000 - start_w};
        noticed dist {1'b1 := noticed_w, 1'b0 := 1000 - noticed_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class NeighborScoreboard;
    neighbor_state_e state;

    int checked          = 0;
    int errors           = 0;
    int successes        = 0;
    int shouts           = 0;
    int polices          = 0;
    int fights           = 0;
    int ignored_starts   = 0;
    int ignored_notices  = 0;
    int resets_mid_game  = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        state = N_IDLE;
    endfunction

    function void step_model(NeighborTxn tr);
        neighbor_state_e next_state;

        next_state = state;

        case (state)
            N_IDLE: begin
                if (tr.start) next_state = N_MOW1;
                if (tr.noticed) ignored_notices++;
            end

            N_MOW1: begin
                if (tr.start) ignored_starts++;
                if (tr.noticed) begin
                    next_state = N_SHOUT;
                    shouts++;
                end
                else
                    next_state = N_MOW2;
            end

            N_MOW2: begin
                if (tr.start) ignored_starts++;
                if (tr.noticed) begin
                    next_state = N_POLICE;
                    polices++;
                end
                else
                    next_state = N_MOW3;
            end

            N_MOW3: begin
                if (tr.start) ignored_starts++;
                if (tr.noticed) begin
                    next_state = N_FIGHT;
                    fights++;
                end
                else begin
                    next_state = N_SUCCESS;
                    successes++;
                end
            end

            N_SHOUT, N_POLICE, N_FIGHT, N_SUCCESS: begin
                if (tr.start)   ignored_starts++;
                if (tr.noticed) ignored_notices++;
                next_state = N_IDLE;
            end

            default: next_state = N_IDLE;
        endcase

        state = next_state;
    endfunction

    function void check(NeighborTxn tr);
        bit ok = 1;
        bit exp_shouting;
        bit exp_police;
        bit exp_fight;
        bit exp_mowed;

        if (!tr.rst_n) begin
            if (state != N_IDLE) resets_mid_game++;
            reset_model();
        end

        exp_shouting = (state == N_SHOUT);
        exp_police   = (state == N_POLICE);
        exp_fight    = (state == N_FIGHT);
        exp_mowed    = (state == N_SUCCESS);

        if (tr.shouting !== exp_shouting) begin
            $error("[SB] shouting_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.shouting, exp_shouting, state.name());
            ok = 0;
        end

        if (tr.police !== exp_police) begin
            $error("[SB] police_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.police, exp_police, state.name());
            ok = 0;
        end

        if (tr.fight !== exp_fight) begin
            $error("[SB] fight_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.fight, exp_fight, state.name());
            ok = 0;
        end

        if (tr.mowed !== exp_mowed) begin
            $error("[SB] grass_mowed_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.mowed, exp_mowed, state.name());
            ok = 0;
        end

        if (tr.rst_n) step_model(tr);

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked    : %0d", checked);
        $display("errors            : %0d", errors);
        $display("grass mowed       : %0d", successes);
        $display("shouting          : %0d", shouts);
        $display("police            : %0d", polices);
        $display("fight             : %0d", fights);
        $display("ignored starts    : %0d", ignored_starts);
        $display("ignored notices   : %0d", ignored_notices);
        $display("resets mid-game   : %0d", resets_mid_game);
        $display("--------------------------------------------");

        if (successes == 0 || shouts == 0 || polices == 0 || fights == 0)
            $warning("[SB] not every outcome (mowed / shouting / police / fight) was reached");
        if (ignored_starts == 0 || ignored_notices == 0)
            $warning("[SB] ignored start or notice was never exercised");
        if (resets_mid_game == 0)
            $warning("[SB] reset was never applied in the middle of a game");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class NeighborMonitor;
    virtual neighbor_if vif;
    NeighborScoreboard  sb;

    function new(virtual neighbor_if vif, NeighborScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        NeighborTxn tr;
        forever begin
            @(vif.mon_cb);
            tr          = new();
            tr.rst_n    = vif.mon_cb.rst_n;
            tr.start    = vif.mon_cb.start;
            tr.noticed  = vif.mon_cb.noticed;
            tr.shouting = vif.mon_cb.shouting;
            tr.police   = vif.mon_cb.police;
            tr.fight    = vif.mon_cb.fight;
            tr.mowed    = vif.mon_cb.mowed;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class NeighborDriver;
    virtual neighbor_if vif;

    function new(virtual neighbor_if vif);
        this.vif = vif;
    endfunction

    task drive(NeighborTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.start   <= tr.start;
        vif.noticed <= tr.noticed;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class NeighborGenerator;
    NeighborDriver drv;
    int            num_random;

    function new(NeighborDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit start = 1'b0, bit noticed = 1'b0);
        NeighborTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.start   = start;
        tr.noticed = noticed;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task play(bit n1, bit n2, bit n3);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, n1);
        step(1'b1, 1'b0, n2);
        step(1'b1, 1'b0, n3);
        calm(2);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        repeat (4) step(1'b1, 1'b0, 1'b1);
        calm(2);

        for (int c = 0; c < 8; c++)
            play(c[0], c[1], c[2]);

        step(1'b1, 1'b1, 1'b1);
        repeat (5) step(1'b1, 1'b0, 1'b1);
        calm(2);

        repeat (30) step(1'b1, 1'b1, 1'b0);
        calm(3);

        repeat (30) step(1'b1, 1'b1, 1'b1);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        calm(1);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        calm(2);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b0, 1'b1);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        calm(1);
        step(1'b1, 1'b0, 1'b1);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        calm(2);
        step(1'b1, 1'b0, 1'b1);
        step(1'b0);
        calm(3);

        step(1'b1, 1'b1, 1'b0);
        calm(3);
        step(1'b0);
        calm(3);
    endtask

    task random_run();
        NeighborTxn tr;
        bit over;
        bit was_over = 1'b1;
        int style    = 0;

        repeat (num_random) begin
            over = (drv.vif.shouting === 1'b1) || (drv.vif.police === 1'b1) || (drv.vif.fight === 1'b1)    || (drv.vif.mowed === 1'b1);

            if (over && !was_over)
                style = $urandom_range(0, 3);
            was_over = over;

            tr = new();
            tr.rst_w   = 3;
            tr.start_w = over ? 300 : 150;
            case (style)
                0:       tr.noticed_w = 50;
                1:       tr.noticed_w = 300;
                2:       tr.noticed_w = 700;
                default: tr.noticed_w = 500;
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
class NeighborEnvironment;
    NeighborGenerator  gen;
    NeighborDriver     drv;
    NeighborMonitor    mon;
    NeighborScoreboard sb;

    virtual neighbor_if vif;

    function new(virtual neighbor_if vif, int num_random = 20000);
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
module tb_NeighborSimulator;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    neighbor_if vif (clk);

    NeighborSimulator dut (
        .clk                 (clk),
        .rst_n               (vif.rst_n),
        .start_mowing_i      (vif.start),
        .neighbor_noticed_i  (vif.noticed),
        .shouting_o          (vif.shouting),
        .police_o            (vif.police),
        .fight_o             (vif.fight),
        .grass_mowed_o       (vif.mowed)
    );

    NeighborEnvironment env;

    initial begin
        $dumpfile("NeighborSimulator_waveform.vcd");
        $dumpvars(0, tb_NeighborSimulator);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.start   = 1'b0;
        vif.noticed = 1'b0;

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

