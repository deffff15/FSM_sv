`timescale 1ns/1ps

typedef enum int {S_IDLE, S_L1, S_L2, S_L3, S_WIN, S_LOSE} casino_state_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface casino_if (input logic clk);
    logic       rst_n;
    logic       spin_i;
    logic       jackpot;
    logic       lost;
    logic [1:0] level;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, spin_i, jackpot, lost, level;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class CasinoTxn;
    rand bit rst_n;
    rand bit spin_i;

    int rst_w  = 2;
    int spin_w = 500;

    logic       jackpot;
    logic       lost;
    logic [1:0] level;

    constraint c_ctrl {
        rst_n  dist {1'b0 := rst_w,   1'b1 := 1000 - rst_w};
        spin_i dist {1'b1 := spin_w,  1'b0 := 1000 - spin_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class CasinoScoreboard;
    casino_state_e state;
    logic [7:0]    lfsr;

    int checked         = 0;
    int errors          = 0;
    int wins            = 0;
    int lose_l1         = 0;
    int lose_l2         = 0;
    int lose_l3         = 0;
    int waits           = 0;
    int ignored_spins   = 0;
    int resets_mid_game = 0;

    function new();
        reset_model();
    endfunction

    function void reset_model();
        state = S_IDLE;
        lfsr  = 8'hFE;
    endfunction

    function bit next_lsb();
        return lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    endfunction

    function logic [1:0] level_of();
        case (state)
            S_L1:    return 2'b01;
            S_L2:    return 2'b10;
            S_L3:    return 2'b11;
            default: return 2'b00;
        endcase
    endfunction

    function void step_model(CasinoTxn tr);
        casino_state_e next_state;
        bit            lsb;

        next_state = state;
        lsb        = lfsr[0];

        case (state)
            S_IDLE: begin
                if (tr.spin_i) next_state = S_L1;
            end

            S_L1: begin
                if (tr.spin_i) ignored_spins++;
                if (lsb) next_state = S_L2;
                else begin
                    next_state = S_LOSE;
                    lose_l1++;
                end
            end

            S_L2: begin
                if (tr.spin_i) begin
                    if (lsb) next_state = S_L3;
                    else begin
                        next_state = S_LOSE;
                        lose_l2++;
                    end
                end
                else waits++;
            end

            S_L3: begin
                if (tr.spin_i) begin
                    if (lsb) begin
                        next_state = S_WIN;
                        wins++;
                    end
                    else begin
                        next_state = S_LOSE;
                        lose_l3++;
                    end
                end
                else waits++;
            end

            S_WIN, S_LOSE: begin
                if (tr.spin_i) ignored_spins++;
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase

        state = next_state;
        lfsr  = {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
    endfunction

    function void check(CasinoTxn tr);
        bit ok = 1;
        bit exp_jackpot;
        bit exp_lost;

        if (!tr.rst_n) begin
            if (state != S_IDLE) resets_mid_game++;
            reset_model();
        end

        exp_jackpot = (state == S_WIN);
        exp_lost    = (state == S_LOSE);

        if (tr.jackpot !== exp_jackpot) begin
            $error("[SB] jackpot_won_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.jackpot, exp_jackpot, state.name());
            ok = 0;
        end

        if (tr.lost !== exp_lost) begin
            $error("[SB] game_lost_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.lost, exp_lost, state.name());
            ok = 0;
        end

        if (tr.level !== level_of()) begin
            $error("[SB] current_level_o mismatch @ %0t: got %02b, expected %02b (state %s)",
                   $time, tr.level, level_of(), state.name());
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
        $display("jackpots          : %0d", wins);
        $display("lost at level 1   : %0d", lose_l1);
        $display("lost at level 2   : %0d", lose_l2);
        $display("lost at level 3   : %0d", lose_l3);
        $display("waiting for spin  : %0d", waits);
        $display("ignored spins     : %0d", ignored_spins);
        $display("resets mid-game   : %0d", resets_mid_game);
        $display("--------------------------------------------");

        if (wins == 0 || lose_l1 == 0 || lose_l2 == 0 || lose_l3 == 0)
            $warning("[SB] not every outcome (jackpot / loss at each level) was reached");
        if (waits == 0 || ignored_spins == 0)
            $warning("[SB] waiting or ignored spins were never exercised");
        if (resets_mid_game == 0)
            $warning("[SB] reset was never applied in the middle of a game");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class CasinoMonitor;
    virtual casino_if vif;
    CasinoScoreboard  sb;

    function new(virtual casino_if vif, CasinoScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        CasinoTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.spin_i  = vif.mon_cb.spin_i;
            tr.jackpot = vif.mon_cb.jackpot;
            tr.lost    = vif.mon_cb.lost;
            tr.level   = vif.mon_cb.level;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class CasinoDriver;
    virtual casino_if vif;

    function new(virtual casino_if vif);
        this.vif = vif;
    endfunction

    task apply(CasinoTxn tr);
        vif.rst_n  <= tr.rst_n;
        vif.spin_i <= tr.spin_i;
    endtask

    task drive(CasinoTxn tr);
        @(negedge vif.clk);
        apply(tr);
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class CasinoGenerator;
    CasinoDriver     drv;
    CasinoScoreboard sb;
    int              num_random;

    function new(CasinoDriver drv, CasinoScoreboard sb, int num_random);
        this.drv        = drv;
        this.sb         = sb;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit spin_i = 1'b0);
        CasinoTxn tr;
        tr        = new();
        tr.rst_n  = rst_n;
        tr.spin_i = spin_i;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task hold_spin(int n);
        repeat (n) step(1'b1, 1'b1);
    endtask

    task spin_when(bit want, bit first_level);
        CasinoTxn tr;
        bit       ready;

        for (int i = 0; i < 60; i++) begin
            @(negedge drv.vif.clk);

            if (first_level)
                ready = (sb.state == S_IDLE) && (sb.next_lsb() == want);
            else
                ready = ((sb.state == S_L2) || (sb.state == S_L3)) && (sb.lfsr[0] == want);

            tr        = new();
            tr.rst_n  = 1'b1;
            tr.spin_i = ready;
            drv.apply(tr);

            if (ready) break;
        end
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        calm(5);

        spin_when(1'b1, 1'b1);
        spin_when(1'b1, 1'b0);
        spin_when(1'b1, 1'b0);
        calm(4);

        spin_when(1'b0, 1'b1);
        calm(4);

        spin_when(1'b1, 1'b1);
        spin_when(1'b0, 1'b0);
        calm(4);

        spin_when(1'b1, 1'b1);
        spin_when(1'b1, 1'b0);
        spin_when(1'b0, 1'b0);
        calm(4);

        spin_when(1'b1, 1'b1);
        calm(8);
        spin_when(1'b1, 1'b0);
        calm(8);
        spin_when(1'b1, 1'b0);
        calm(4);

        hold_spin(40);
        calm(3);

        spin_when(1'b1, 1'b1);
        step(1'b0);
        calm(3);

        spin_when(1'b1, 1'b1);
        calm(2);
        step(1'b0);
        calm(3);

        spin_when(1'b1, 1'b1);
        spin_when(1'b1, 1'b0);
        step(1'b0);
        calm(3);

        spin_when(1'b1, 1'b1);
        spin_when(1'b1, 1'b0);
        spin_when(1'b1, 1'b0);
        step(1'b0);
        calm(3);

        spin_when(1'b0, 1'b1);
        step(1'b0);
        calm(3);

        spin_when(1'b1, 1'b1);
        spin_when(1'b1, 1'b0);
        spin_when(1'b1, 1'b0);
        calm(4);
    endtask

    task random_run();
        CasinoTxn tr;
        bit over;
        bit was_over = 1'b1;
        int style    = 0;

        repeat (num_random) begin
            over = (drv.vif.jackpot === 1'b1) || (drv.vif.lost === 1'b1);

            if (over && !was_over)
                style = $urandom_range(0, 3);
            was_over = over;

            tr = new();
            tr.rst_w = 2;
            case (style)
                0:       tr.spin_w = 500;
                1:       tr.spin_w = 150;
                2:       tr.spin_w = 900;
                default: tr.spin_w = 300;
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
class CasinoEnvironment;
    CasinoGenerator  gen;
    CasinoDriver     drv;
    CasinoMonitor    mon;
    CasinoScoreboard sb;

    virtual casino_if vif;

    function new(virtual casino_if vif, int num_random = 20000);
        this.vif = vif;
        sb  = new();
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, sb, num_random);
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
module tb_CasinoSpin;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    casino_if vif (clk);

    CasinoSpin dut (
        .clk             (clk),
        .rst_n           (vif.rst_n),
        .spin_i          (vif.spin_i),
        .jackpot_won_o   (vif.jackpot),
        .game_lost_o     (vif.lost),
        .current_level_o (vif.level)
    );

    CasinoEnvironment env;

    initial begin
        $dumpfile("CasinoSpin_waveform.vcd");
        $dumpvars(0, tb_CasinoSpin);
        #6us;
        $dumpoff;
    end

    initial begin
        vif.rst_n  = 1'b0;
        vif.spin_i = 1'b0;

        repeat (2) @(negedge clk);

        env = new(vif);
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "[TB] timeout");
    end
endmodule //The last line must be empty so vs code doesn't give a mistake 

