`timescale 1ns/1ps
import Fighter_paczka::*;
 
// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface fighter_if (input logic clk);
    logic       rst_n;
    logic       start;
    logic       finish;
    logic [1:0] p1_ad;
    logic [1:0] p2_ad;
    logic [3:0] hp1;
    logic [3:0] hp2;
    logic [1:0] winner;
 
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, start, finish, p1_ad, p2_ad, hp1, hp2, winner;
    endclocking
endinterface
 
// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class FighterTxn;
    rand bit       rst_n;
    rand bit       start;
    rand bit       finish;
    rand bit [1:0] p1_ad;
    rand bit [1:0] p2_ad;
 
    int rst_w    = 1;
    int finish_w = 2;
    int p1_w[4]  = '{40, 20, 30, 10};
    int p2_w[4]  = '{40, 20, 30, 10};
 
    logic [3:0] hp1;
    logic [3:0] hp2;
    logic [1:0] winner;
 
    constraint c_ctrl {
        rst_n  dist {1'b0 := rst_w,    1'b1 := 1000 - rst_w};
        finish dist {1'b1 := finish_w, 1'b0 := 1000 - finish_w};
        start  dist {1'b1 := 30, 1'b0 := 70};
        p1_ad  dist {2'b00 := p1_w[0], 2'b01 := p1_w[1], 2'b10 := p1_w[2], 2'b11 := p1_w[3]};
        p2_ad  dist {2'b00 := p2_w[0], 2'b01 := p2_w[1], 2'b10 := p2_w[2], 2'b11 := p2_w[3]};
    }
endclass
 
// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class FighterScoreboard;
    logic [3:0] max_hp;
    logic [3:0] damage;
 
    stany       state;
    akcje       act1, act2;
    logic [3:0] hp1, hp2;
    logic [1:0] prev1, prev2;
    bit         in_finish = 0;
 
    int checked         = 0;
    int errors          = 0;
    int hits            = 0;
    int blocked         = 0;
    int p1_wins         = 0;
    int p2_wins         = 0;
    int draws           = 0;
    int resets_in_fight = 0;
 
    function new(logic [3:0] max_hp, logic [3:0] damage);
        this.max_hp = max_hp;
        this.damage = damage;
        reset_model();
    endfunction
 
    function void reset_model();
        state = START;
        act1  = IDLE;
        act2  = IDLE;
        hp1   = max_hp;
        hp2   = max_hp;
        prev1 = 2'b00;
        prev2 = 2'b00;
    endfunction
 
    function logic [1:0] winner_of();
        if (state != FINISH) return 2'b00;
        if (hp1 > hp2)       return 2'b01;
        if (hp2 > hp1)       return 2'b10;
        return 2'b11;
    endfunction
 
    function void step_model(FighterTxn tr);
        logic       p1_atk_rise, p1_def_rise;
        logic       p2_atk_rise, p2_def_rise;
        bit         p1_hit_try, p2_hit_try;
        bit         p1_blocking, p2_blocking;
        stany       next_state;
        akcje       next_act1, next_act2;
        logic [3:0] next_hp1, next_hp2;
 
        p1_atk_rise = tr.p1_ad[1] & ~prev1[1];
        p1_def_rise = tr.p1_ad[0] & ~prev1[0];
        p2_atk_rise = tr.p2_ad[1] & ~prev2[1];
        p2_def_rise = tr.p2_ad[0] & ~prev2[0];
 
        p1_hit_try = (state == FIGHT) && (act1 == IDLE) && p1_atk_rise;
        p2_hit_try = (state == FIGHT) && (act2 == IDLE) && p2_atk_rise;
 
        p1_blocking = (act1 == DEFENSE) || ((act1 == IDLE) && p1_def_rise && !p1_atk_rise);
        p2_blocking = (act2 == DEFENSE) || ((act2 == IDLE) && p2_def_rise && !p2_atk_rise);
 
        next_state = state;
        case (state)
            START:  if (tr.start) next_state = FIGHT;
            FIGHT:  if (tr.finish || hp1 == 0 || hp2 == 0) next_state = FINISH;
            FINISH: next_state = FINISH;
            default: next_state = START;
        endcase
 
        next_hp1 = hp1;
        next_hp2 = hp2;
        if (state == START) begin
            next_hp1 = max_hp;
            next_hp2 = max_hp;
        end
        else if (state == FIGHT) begin
            if (p1_hit_try) begin
                if (p2_blocking)
                    blocked++;
                else begin
                    hits++;
                    next_hp2 = (hp2 <= damage) ? 4'd0 : hp2 - damage;
                end
            end
            if (p2_hit_try) begin
                if (p1_blocking)
                    blocked++;
                else begin
                    hits++;
                    next_hp1 = (hp1 <= damage) ? 4'd0 : hp1 - damage;
                end
            end
        end
 
        next_act1 = act1;
        next_act2 = act2;
        if (state != FIGHT) begin
            next_act1 = IDLE;
            next_act2 = IDLE;
        end
        else begin
            if (tr.p1_ad == 2'b00)
                next_act1 = IDLE;
            else if (act1 == IDLE) begin
                if (p1_atk_rise)
                    next_act1 = ATTACK;
                else if (p1_def_rise)
                    next_act1 = DEFENSE;
            end
 
            if (tr.p2_ad == 2'b00)
                next_act2 = IDLE;
            else if (act2 == IDLE) begin
                if (p2_atk_rise)
                    next_act2 = ATTACK;
                else if (p2_def_rise)
                    next_act2 = DEFENSE;
            end
        end
 
        state = next_state;
        hp1   = next_hp1;
        hp2   = next_hp2;
        act1  = next_act1;
        act2  = next_act2;
        prev1 = tr.p1_ad;
        prev2 = tr.p2_ad;
    endfunction
 
    function void check(FighterTxn tr);
        bit ok = 1;
 
        if (!tr.rst_n) begin
            if (state == FIGHT) resets_in_fight++;
            reset_model();
        end
 
        if (tr.hp1 !== hp1) begin
            $error("[SB] player1_hp mismatch @ %0t: got %0d, expected %0d (state %s)",
                   $time, tr.hp1, hp1, state.name());
            ok = 0;
        end
 
        if (tr.hp2 !== hp2) begin
            $error("[SB] player2_hp mismatch @ %0t: got %0d, expected %0d (state %s)",
                   $time, tr.hp2, hp2, state.name());
            ok = 0;
        end
 
        if (tr.winner !== winner_of()) begin
            $error("[SB] Wy_winner mismatch @ %0t: got %02b, expected %02b (state %s)",
                   $time, tr.winner, winner_of(), state.name());
            ok = 0;
        end
 
        if (state == FINISH) begin
            if (!in_finish) begin
                case (winner_of())
                    2'b01:   p1_wins++;
                    2'b10:   p2_wins++;
                    2'b11:   draws++;
                    default: ;
                endcase
            end
            in_finish = 1;
        end
        else
            in_finish = 0;
 
        if (tr.rst_n) step_model(tr);
 
        checked++;
        if (!ok) errors++;
    endfunction
 
    function void report();
        $display("---------------- scoreboard ----------------");
        $display("cycles checked    : %0d", checked);
        $display("errors            : %0d", errors);
        $display("hits              : %0d", hits);
        $display("blocked attacks   : %0d", blocked);
        $display("player 1 wins     : %0d", p1_wins);
        $display("player 2 wins     : %0d", p2_wins);
        $display("draws             : %0d", draws);
        $display("resets mid-fight  : %0d", resets_in_fight);
        $display("--------------------------------------------");
 
        if (hits == 0 || blocked == 0)
            $warning("[SB] hits or blocks were never exercised");
        if (p1_wins == 0 || p2_wins == 0 || draws == 0)
            $warning("[SB] not every outcome (P1 / P2 / draw) was reached");
        if (resets_in_fight == 0)
            $warning("[SB] reset was never applied during a fight");
    endfunction
endclass
 
// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class FighterMonitor;
    virtual fighter_if vif;
    FighterScoreboard  sb;
 
    function new(virtual fighter_if vif, FighterScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction
 
    task run();
        FighterTxn tr;
        forever begin
            @(vif.mon_cb);
            tr        = new();
            tr.rst_n  = vif.mon_cb.rst_n;
            tr.start  = vif.mon_cb.start;
            tr.finish = vif.mon_cb.finish;
            tr.p1_ad  = vif.mon_cb.p1_ad;
            tr.p2_ad  = vif.mon_cb.p2_ad;
            tr.hp1    = vif.mon_cb.hp1;
            tr.hp2    = vif.mon_cb.hp2;
            tr.winner = vif.mon_cb.winner;
            sb.check(tr);
        end
    endtask
endclass
 
// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class FighterDriver;
    virtual fighter_if vif;
 
    function new(virtual fighter_if vif);
        this.vif = vif;
    endfunction
 
    task drive(FighterTxn tr);
        @(negedge vif.clk);
        vif.rst_n  <= tr.rst_n;
        vif.start  <= tr.start;
        vif.finish <= tr.finish;
        vif.p1_ad  <= tr.p1_ad;
        vif.p2_ad  <= tr.p2_ad;
    endtask
endclass
 
// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class FighterGenerator;
    localparam logic [1:0] BTN_NONE = 2'b00;
    localparam logic [1:0] BTN_DEF  = 2'b01;
    localparam logic [1:0] BTN_ATK  = 2'b10;
    localparam logic [1:0] BTN_BOTH = 2'b11;
 
    FighterDriver drv;
    int           num_random;
    int           max_hp;
 
    function new(FighterDriver drv, int num_random, int max_hp);
        this.drv        = drv;
        this.num_random = num_random;
        this.max_hp     = max_hp;
    endfunction
 
    task step(bit rst_n = 1'b1, bit start = 1'b0, bit finish = 1'b0,
              bit [1:0] p1 = 2'b00, bit [1:0] p2 = 2'b00);
        FighterTxn tr;
        tr        = new();
        tr.rst_n  = rst_n;
        tr.start  = start;
        tr.finish = finish;
        tr.p1_ad  = p1;
        tr.p2_ad  = p2;
        drv.drive(tr);
    endtask
 
    task idle(int n = 1);
        repeat (n) step();
    endtask
 
    task hold(bit [1:0] p1, bit [1:0] p2, int n = 1);
        repeat (n) step(1'b1, 1'b0, 1'b0, p1, p2);
    endtask
 
    task begin_fight();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        step(1'b1, 1'b1);
        idle();
    endtask
 
    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        hold(BTN_ATK, BTN_ATK, 3);
        hold(BTN_DEF, BTN_DEF, 2);
        idle(2);

        begin_fight();
        hold(BTN_ATK, BTN_NONE, 4);
        idle(2);

        begin_fight();
        hold(BTN_NONE, BTN_DEF, 2);
        hold(BTN_ATK, BTN_DEF, 3);
        idle(2);
 
        begin_fight();
        hold(BTN_ATK, BTN_DEF, 2);
        idle(2);
        hold(BTN_DEF, BTN_ATK, 2);
        idle(2);

        step(1'b0);
        step(1'b1);
        hold(BTN_ATK, BTN_NONE, 3);
        step(1'b1, 1'b1, 1'b0, BTN_ATK, BTN_NONE);
        hold(BTN_ATK, BTN_NONE, 3);
        idle(2);
        hold(BTN_ATK, BTN_NONE, 2);
        idle(2);

        begin_fight();
        hold(BTN_DEF, BTN_NONE, 2);
        hold(BTN_BOTH, BTN_NONE, 2);
        hold(BTN_DEF, BTN_NONE, 2);
        idle(2);

        begin_fight();
        hold(BTN_BOTH, BTN_NONE, 3);
        idle(2);

        begin_fight();
        hold(BTN_ATK, BTN_ATK, 2);
        idle(2);
 
        begin_fight();
        repeat (max_hp) begin
            hold(BTN_ATK, BTN_NONE);
            idle();
        end
        hold(BTN_ATK, BTN_ATK, 2);
        idle(3);

        begin_fight();
        repeat (max_hp) begin
            hold(BTN_NONE, BTN_ATK);
            idle();
        end
        idle(3);

        begin_fight();
        repeat (max_hp) begin
            hold(BTN_ATK, BTN_ATK);
            idle();
        end
        idle(3);
 
        begin_fight();
        hold(BTN_ATK, BTN_NONE);
        idle();
        step(1'b1, 1'b0, 1'b1);
        idle(3);

        begin_fight();
        hold(BTN_NONE, BTN_ATK);
        idle();
        step(1'b1, 1'b0, 1'b1);
        idle(3);

        begin_fight();
        step(1'b1, 1'b0, 1'b1);
        idle(3);

        begin_fight();
        hold(BTN_ATK, BTN_NONE);
        idle();
        step(1'b0);
        idle(2);
        hold(BTN_ATK, BTN_ATK, 2);
        idle(2);
    endtask
 
    function void set_style(FighterTxn tr, int player, int style);
        int w[4];
        case (style)
            0:       w = '{40, 20, 30, 10};
            1:       w = '{30,  5, 55, 10};
            2:       w = '{35, 50, 10,  5};
            default: w = '{10, 10, 40, 40};
        endcase
        if (player == 1)
            tr.p1_w = w;
        else
            tr.p2_w = w;
    endfunction
 
    task random_run();
        FighterTxn tr;
        bit fight_over;
        bit was_over = 1'b1;
        int style1   = 0;
        int style2   = 0;
 
        repeat (num_random) begin
            fight_over = (drv.vif.winner !== 2'b00);
 
            if (was_over && !fight_over) begin
                style1 = $urandom_range(0, 3);
                style2 = $urandom_range(0, 3);
            end
            was_over = fight_over;
 
            tr = new();
            tr.rst_w = fight_over ? 300 : 1;
            set_style(tr, 1, style1);
            set_style(tr, 2, style2);
 
            if (!tr.randomize())
                $fatal(1, "[GEN] randomization failed");
            drv.drive(tr);
        end
    endtask
endclass
 
// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class FighterEnvironment;
    FighterGenerator  gen;
    FighterDriver     drv;
    FighterMonitor    mon;
    FighterScoreboard sb;
 
    virtual fighter_if vif;
 
    function new(virtual fighter_if vif, logic [3:0] max_hp, logic [3:0] damage,
                 int num_random = 20000);
        this.vif = vif;
        sb  = new(max_hp, damage);
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_random, int'(max_hp));
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
module tb_Fighter;
 
    localparam logic [3:0] MAX_HP = 4'd10;
    localparam logic [3:0] DAMAGE = 4'd1;
 
    logic clk = 1'b0;
    always #5 clk = ~clk;
 
    fighter_if vif (clk);
 
    Fighter #(.MAX_HP(MAX_HP), .DAMAGE(DAMAGE)) dut (
        .clk                    (clk),
        .rst_n                  (vif.rst_n),
        .start                  (vif.start),
        .finish                 (vif.finish),
        .player1_attack_defense (vif.p1_ad),
        .player2_attack_defense (vif.p2_ad),
        .player1_hp             (vif.hp1),
        .player2_hp             (vif.hp2),
        .Wy_winner              (vif.winner)
    );
 
    FighterEnvironment env;
 
    initial begin
        $dumpfile("Fighter_waveform.vcd");
        $dumpvars(0, tb_Fighter);
        #5us;
        $dumpoff;
    end
 
    initial begin
        vif.rst_n  = 1'b0;
        vif.start  = 1'b0;
        vif.finish = 1'b0;
        vif.p1_ad  = 2'b00;
        vif.p2_ad  = 2'b00;
 
        repeat (2) @(negedge clk);
        vif.rst_n = 1'b1;
        @(negedge clk);
 
        env = new(vif, MAX_HP, DAMAGE);
        env.run();
        $finish;
    end
 
    initial begin
        #10ms;
        $fatal(1, "[TB] timeout");
    end
endmodule //The last line must be empty so VS code won't give a mistake

