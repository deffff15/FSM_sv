`timescale 1ns/1ps

typedef enum int {K_PIER, K_GETTING_INTO, K_CASTING_OFF, K_SAILING_AWAY,
                  K_KAYAKING, K_SAILING_BACK, K_MOORING, K_GETTING_OUT} kay_e;
typedef enum int {W_STABLY, W_SWAY, W_FALLING} kw_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface kay_if (input logic clk);
    logic       rst_n;
    logic       hold;
    logic       go;
    logic [1:0] game;
    logic       proc;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, hold, go, game, proc;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class KayakTxn;
    rand bit rst_n;
    rand bit hold;
    rand bit go;

    int rst_w  = 3;
    int hold_w = 500;
    int go_w   = 300;

    logic [1:0] game;
    logic       proc;

    constraint c_ctrl {
        rst_n dist {1'b0 := rst_w,  1'b1 := 1000 - rst_w};
        hold  dist {1'b1 := hold_w, 1'b0 := 1000 - hold_w};
        go    dist {1'b1 := go_w,   1'b0 := 1000 - go_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class KayakScoreboard;
    kay_e st;
    kw_e  w;
    int   counter;
    int   pc;
    bit   ended;
    bit   go_r;

    int checked        = 0;
    int errors         = 0;
    int adv [8];
    int resets_in [8];
    int early_go       = 0;
    int go_held        = 0;
    int ended_waits    = 0;
    int hold_cycles    = 0;
    int hold_ignored   = 0;
    int cat_stable     = 0;
    int cat_sway       = 0;
    int cat_fall       = 0;
    int pc49           = 0;
    int pc50           = 0;
    int pc74           = 0;
    int pc75           = 0;
    int pier_stale_w   = 0;

    function new();
        for (int i = 0; i < 8; i++) begin
            adv[i]       = 0;
            resets_in[i] = 0;
        end
        reset_model();
    endfunction

    function void reset_model();
        st      = K_PIER;
        w       = W_STABLY;
        counter = 0;
        pc      = 0;
        ended   = 1'b0;
        go_r    = 1'b0;
    endfunction

    function kay_e next_of(kay_e s, bit go_edge, bit game_ended);
        case (s)
            K_PIER:          return go_edge ? K_GETTING_INTO : K_PIER;
            K_GETTING_INTO:  return go_edge ? K_CASTING_OFF  : K_GETTING_INTO;
            K_CASTING_OFF:   return go_edge ? K_SAILING_AWAY : K_CASTING_OFF;
            K_SAILING_AWAY:  return go_edge ? K_KAYAKING     : K_SAILING_AWAY;
            K_KAYAKING:      return (game_ended && go_edge) ? K_SAILING_BACK : K_KAYAKING;
            K_SAILING_BACK:  return go_edge ? K_MOORING      : K_SAILING_BACK;
            K_MOORING:       return go_edge ? K_GETTING_OUT  : K_MOORING;
            K_GETTING_OUT:   return go_edge ? K_PIER         : K_GETTING_OUT;
            default:         return K_PIER;
        endcase
    endfunction

    function void step_model(KayakTxn tr, bit go_edge, kay_e nxt);
        int next_counter;
        int next_pc;
        bit next_ended;
        kw_e next_w;
        int h;

        next_counter = counter;
        next_pc      = pc;
        next_ended   = ended;
        next_w       = w;
        h            = tr.hold;

        if (nxt != st)
            adv[st]++;
        if (st == K_KAYAKING && !ended && go_edge)
            early_go++;
        if (tr.go && go_r)
            go_held++;
        if (st == K_KAYAKING && ended && !go_edge)
            ended_waits++;
        if (tr.hold && st == K_KAYAKING && counter > 0)
            hold_cycles++;
        if (tr.hold && !(st == K_KAYAKING && counter > 0))
            hold_ignored++;
        if (st == K_PIER && w != W_STABLY)
            pier_stale_w++;

        if (st == K_KAYAKING && ended) begin
            if (pc < 50)      cat_stable++;
            else if (pc < 75) cat_sway++;
            else              cat_fall++;
            if (pc == 49) pc49++;
            if (pc == 50) pc50++;
            if (pc == 74) pc74++;
            if (pc == 75) pc75++;
        end

        if (st == K_SAILING_AWAY && nxt == K_KAYAKING) begin
            next_counter = 100;
            next_pc      = 100;
            next_ended   = 1'b0;
        end
        else if (st == K_KAYAKING) begin
            if (counter > 0) begin
                next_counter = counter - 1;
                if (pc >= h) next_pc = pc - h;
                else         next_pc = 0;
            end
            else
                next_ended = 1'b1;
        end
        else
            next_ended = 1'b0;

        if (st == K_KAYAKING && ended) begin
            if (pc < 50)      next_w = W_STABLY;
            else if (pc < 75) next_w = W_SWAY;
            else              next_w = W_FALLING;
        end
        else if (st == K_PIER)
            next_w = W_STABLY;

        st      = nxt;
        w       = next_w;
        counter = next_counter;
        pc      = next_pc;
        ended   = next_ended;
        go_r    = tr.go;
    endfunction

    function void check(KayakTxn tr);
        bit       ok = 1;
        bit       go_edge;
        kay_e     nxt;
        bit [1:0] exp_game;
        bit       exp_proc;

        if (!tr.rst_n) begin
            if (st != K_PIER)
                resets_in[st]++;
            reset_model();
        end

        go_edge = tr.go && !go_r;
        nxt     = next_of(st, go_edge, ended);

        case (w)
            W_STABLY: exp_game = 2'b10;
            W_SWAY:   exp_game = 2'b01;
            default:  exp_game = 2'b00;
        endcase
        exp_proc = (st == K_GETTING_OUT) && (nxt == K_PIER);

        if (tr.game !== exp_game) begin
            $error("[SB] game mismatch @ %0t: got %b, expected %b (state %s, weather %s, pc %0d)",
                   $time, tr.game, exp_game, st.name(), w.name(), pc);
            ok = 0;
        end

        if (tr.proc !== exp_proc) begin
            $error("[SB] procedure mismatch @ %0t: got %0b, expected %0b (state %s, go_edge %0b)",
                   $time, tr.proc, exp_proc, st.name(), go_edge);
            ok = 0;
        end

        if (tr.rst_n) step_model(tr, go_edge, nxt);

        checked++;
        if (!ok) errors++;
    endfunction

    function void report();
        kay_e s;

        $display("---------------- scoreboard ----------------");
        $display("cycles checked          : %0d", checked);
        $display("errors                  : %0d", errors);
        for (int i = 0; i < 8; i++) begin
            s = kay_e'(i);
            $display("advanced from %-14s: %0d", s.name(), adv[i]);
        end
        $display("go_next in kayaking too early : %0d", early_go);
        $display("go_next held (no edge)  : %0d", go_held);
        $display("waiting, game ended     : %0d", ended_waits);
        $display("hold cycles counted     : %0d", hold_cycles);
        $display("hold ignored            : %0d", hold_ignored);
        $display("result stably           : %0d", cat_stable);
        $display("result sway             : %0d", cat_sway);
        $display("result falling          : %0d", cat_fall);
        $display("program_counter == 49   : %0d", pc49);
        $display("program_counter == 50   : %0d", pc50);
        $display("program_counter == 74   : %0d", pc74);
        $display("program_counter == 75   : %0d", pc75);
        $display("old result on pier      : %0d", pier_stale_w);
        for (int i = 1; i < 8; i++) begin
            s = kay_e'(i);
            $display("resets in %-14s: %0d", s.name(), resets_in[i]);
        end
        $display("--------------------------------------------");

        for (int i = 0; i < 8; i++) begin
            s = kay_e'(i);
            if (adv[i] == 0)
                $warning("[SB] state %s was never left by go_next", s.name());
        end
        if (early_go == 0)
            $warning("[SB] go_next edge before the game ended was never applied in kayaking");
        if (go_held == 0)
            $warning("[SB] go_next held high without a new edge was never applied");
        if (ended_waits == 0)
            $warning("[SB] waiting for go_next after the game ended was never exercised");
        if (hold_cycles == 0 || hold_ignored == 0)
            $warning("[SB] hold was not seen both counted and ignored");
        if (cat_stable == 0 || cat_sway == 0 || cat_fall == 0)
            $warning("[SB] not every result (stably / sway / falling) was reached");
        if (pc49 == 0 || pc50 == 0 || pc74 == 0 || pc75 == 0)
            $warning("[SB] result thresholds (program_counter 49 / 50 / 74 / 75) were not reached");
        if (pier_stale_w == 0)
            $warning("[SB] the old result on the first pier cycle was never observed");
        for (int i = 1; i < 8; i++) begin
            s = kay_e'(i);
            if (resets_in[i] == 0)
                $warning("[SB] reset was never applied in %s", s.name());
        end
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class KayakMonitor;
    virtual kay_if vif;
    KayakScoreboard sb;

    function new(virtual kay_if vif, KayakScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        KayakTxn tr;
        forever begin
            @(vif.mon_cb);
            tr       = new();
            tr.rst_n = vif.mon_cb.rst_n;
            tr.hold  = vif.mon_cb.hold;
            tr.go    = vif.mon_cb.go;
            tr.game  = vif.mon_cb.game;
            tr.proc  = vif.mon_cb.proc;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class KayakDriver;
    virtual kay_if vif;

    function new(virtual kay_if vif);
        this.vif = vif;
    endfunction

    task drive(KayakTxn tr);
        @(negedge vif.clk);
        vif.rst_n <= tr.rst_n;
        vif.hold  <= tr.hold;
        vif.go    <= tr.go;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class KayakGenerator;
    KayakDriver drv;
    int         num_random;

    function new(KayakDriver drv, int num_random);
        this.drv        = drv;
        this.num_random = num_random;
    endfunction

    task step(bit rst_n = 1'b1, bit hold = 1'b0, bit go = 1'b0);
        KayakTxn tr;
        tr       = new();
        tr.rst_n = rst_n;
        tr.hold  = hold;
        tr.go    = go;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task pulse();
        step(1'b1, 1'b0, 1'b1);
        step();
    endtask

    task trip(int h, bit spread, int early, int wait_end, int stop, bit rst);
        bit hold_now;
        bit go_now;

        if (rst) step(1'b0);

        pulse();
        if (stop == 1) return;
        pulse();
        if (stop == 2) return;
        pulse();
        if (stop == 3) return;

        step(1'b1, 1'b0, 1'b1);

        for (int i = 0; i < 100; i++) begin
            if (spread) hold_now = (((i + 1) * h) / 100) != ((i * h) / 100);
            else        hold_now = (i < h);
            go_now = (early == 1) && (i == 49);
            step(1'b1, hold_now, go_now);
            if (stop == 4 && i == 29) return;
        end

        if (early == 2) begin
            step(1'b1, 1'b0, 1'b1);
            step(1'b1, 1'b0, 1'b1);
            step();
        end
        else begin
            step();
            calm(wait_end);
        end

        step(1'b1, 1'b0, 1'b1);
        step();
        if (stop == 5) return;
        pulse();
        if (stop == 6) return;
        pulse();
        if (stop == 7) return;

        step(1'b1, 1'b0, 1'b1);
        step();
        calm(3);
    endtask

    task directed();
        step(1'b0);
        step(1'b0, 1'b1, 1'b1);

        trip(0,   1'b0, 0, 0,  8, 1'b1);
        trip(100, 1'b0, 0, 3,  8, 1'b0);
        trip(50,  1'b0, 0, 1,  8, 1'b0);
        trip(51,  1'b1, 0, 1,  8, 1'b0);
        trip(26,  1'b0, 0, 2,  8, 1'b0);
        trip(25,  1'b1, 0, 0,  8, 1'b0);
        trip(60,  1'b0, 1, 2,  8, 1'b0);
        trip(40,  1'b1, 2, 0,  8, 1'b0);
        trip(10,  1'b0, 0, 10, 8, 1'b1);

        step(1'b0);
        repeat (3) step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b1, 1'b1);
        repeat (3) step(1'b1, 1'b1, 1'b0);
        step(1'b0);
        calm(2);

        step(1'b0);
        repeat (5) step(1'b1, 1'b0, 1'b1);
        calm(2);
        pulse();
        step(1'b0);
        calm(2);

        for (int s = 1; s <= 7; s++) begin
            trip(60, 1'b0, 0, 0, s, 1'b1);
            step(1'b0, 1'b1, 1'b1);
            calm(2);
            trip(30, 1'b1, 0, 1, 8, 1'b0);
        end

        step(1'b0);
        repeat (40) step(1'b1, 1'b1, 1'b1);
        step(1'b0);
        calm(2);

        step(1'b0, 1'b1, 1'b1);
        calm(2);
        trip(75, 1'b1, 0, 1, 8, 1'b0);
    endtask

    task random_run();
        KayakTxn tr;
        int style = 0;
        int left  = 0;

        repeat (num_random) begin
            if (left == 0) begin
                style = $urandom_range(0, 3);
                left  = 200;
            end
            left--;

            tr = new();
            case (style)
                0: begin
                    tr.rst_w = 3; tr.hold_w = 500; tr.go_w = 300;
                end
                1: begin
                    tr.rst_w = 2; tr.hold_w = 200; tr.go_w = 200;
                end
                2: begin
                    tr.rst_w = 2; tr.hold_w = 800; tr.go_w = 400;
                end
                default: begin
                    tr.rst_w = 5; tr.hold_w = 500; tr.go_w = 100;
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
class KayakEnvironment;
    KayakGenerator  gen;
    KayakDriver     drv;
    KayakMonitor    mon;
    KayakScoreboard sb;

    virtual kay_if vif;

    function new(virtual kay_if vif, int num_random = 20000);
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
module tb_KayakSimulator;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    kay_if vif (clk);

    KayakSimulator dut (
        .rst_n     (vif.rst_n),
        .clk       (clk),
        .hold      (vif.hold),
        .go_next   (vif.go),
        .game      (vif.game),
        .procedure (vif.proc)
    );

    KayakEnvironment env;

    initial begin
        $dumpfile("KayakSimulator_waveform.vcd");
        $dumpvars(0, tb_KayakSimulator);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n = 1'b0;
        vif.hold  = 1'b0;
        vif.go    = 1'b0;

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

