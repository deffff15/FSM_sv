`timescale 1ns/1ps

typedef enum int {S_SAFE, S_TRAPPED, S_RESCUED, S_DEAD} qs_state_e;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface quicksand_if (input logic clk);
    logic rst_n;
    logic start_i;
    logic data_in;
    logic rescued;
    logic dead;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n, start_i, data_in, rescued, dead;
    endclocking
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class QuicksandTxn;
    rand bit rst_n;
    rand bit start_i;
    rand bit data_in;

    int rst_w   = 3;
    int start_w = 100;
    int data_w  = 500;

    logic rescued;
    logic dead;

    constraint c_ctrl {
        rst_n   dist {1'b0 := rst_w,   1'b1 := 1000 - rst_w};
        start_i dist {1'b1 := start_w, 1'b0 := 1000 - start_w};
        data_in dist {1'b1 := data_w,  1'b0 := 1000 - data_w};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class QuicksandScoreboard;
    int max_struggles;
    int cnt_w;
    int cnt_mask;

    qs_state_e state;
    int        cnt;
    int        timer;

    int checked         = 0;
    int errors          = 0;
    int rescues         = 0;
    int quick_rescues   = 0;
    int late_rescues    = 0;
    int limit_rescues   = 0;
    int deaths          = 0;
    int restarts        = 0;
    int ignored_starts  = 0;
    int resets_in_trap  = 0;

    function new(int max_struggles);
        this.max_struggles = max_struggles;
        cnt_w    = (max_struggles > 1) ? $clog2(max_struggles + 1) : 1;
        cnt_mask = (1 << cnt_w) - 1;
        reset_model();
    endfunction

    function void reset_model();
        state = S_SAFE;
        cnt   = 0;
        timer = 0;
    endfunction

    function void step_model(QuicksandTxn tr);
        qs_state_e next_state;
        int        next_cnt;
        int        next_timer;

        next_state = state;
        next_cnt   = cnt;
        next_timer = timer;

        case (state)
            S_SAFE, S_RESCUED, S_DEAD: begin
                if (tr.start_i) begin
                    if (state != S_SAFE) restarts++;
                    next_state = S_TRAPPED;
                    next_cnt   = 0;
                    next_timer = 0;
                end
            end

            S_TRAPPED: begin
                if (tr.start_i) ignored_starts++;

                if (tr.data_in) begin
                    if (cnt < max_struggles)
                        next_cnt = (cnt + 1) & cnt_mask;
                    next_timer = 0;
                end
                else if (timer < max_struggles + 1)
                    next_timer = (timer + 1) & cnt_mask;

                if (tr.data_in && cnt >= max_struggles - 1) begin
                    next_state = S_DEAD;
                    deaths++;
                end
                else if (!tr.data_in && timer >= cnt) begin
                    next_state = S_RESCUED;
                    rescues++;
                    if (cnt == 0) quick_rescues++;
                    else          late_rescues++;
                    if (cnt == max_struggles - 1) limit_rescues++;
                end
            end

            default: next_state = S_SAFE;
        endcase

        state = next_state;
        cnt   = next_cnt;
        timer = next_timer;
    endfunction

    function void check(QuicksandTxn tr);
        bit ok = 1;
        bit exp_rescued;
        bit exp_dead;

        if (!tr.rst_n) begin
            if (state == S_TRAPPED) resets_in_trap++;
            reset_model();
        end

        exp_rescued = (state == S_RESCUED);
        exp_dead    = (state == S_DEAD);

        if (tr.rescued !== exp_rescued) begin
            $error("[SB] rescued_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.rescued, exp_rescued, state.name());
            ok = 0;
        end

        if (tr.dead !== exp_dead) begin
            $error("[SB] dead_o mismatch @ %0t: got %0b, expected %0b (state %s)",
                   $time, tr.dead, exp_dead, state.name());
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
        $display("rescues               : %0d", rescues);
        $display("  without struggling  : %0d", quick_rescues);
        $display("  after struggling    : %0d", late_rescues);
        $display("  at the limit        : %0d", limit_rescues);
        $display("deaths                : %0d", deaths);
        $display("restarts (RESC / DEAD): %0d", restarts);
        $display("start ignored (trap)  : %0d", ignored_starts);
        $display("resets while trapped  : %0d", resets_in_trap);
        $display("--------------------------------------------");

        if (rescues == 0 || deaths == 0)
            $warning("[SB] both outcomes (rescued / dead) were not reached");
        if (late_rescues == 0 || limit_rescues == 0)
            $warning("[SB] rescue after struggling, or at the limit, never happened");
        if (restarts == 0 || ignored_starts == 0)
            $warning("[SB] restart or ignored start was never exercised");
        if (resets_in_trap == 0)
            $warning("[SB] reset was never applied while trapped");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class QuicksandMonitor;
    virtual quicksand_if vif;
    QuicksandScoreboard  sb;

    function new(virtual quicksand_if vif, QuicksandScoreboard sb);
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        QuicksandTxn tr;
        forever begin
            @(vif.mon_cb);
            tr         = new();
            tr.rst_n   = vif.mon_cb.rst_n;
            tr.start_i = vif.mon_cb.start_i;
            tr.data_in = vif.mon_cb.data_in;
            tr.rescued = vif.mon_cb.rescued;
            tr.dead    = vif.mon_cb.dead;
            sb.check(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class QuicksandDriver;
    virtual quicksand_if vif;

    function new(virtual quicksand_if vif);
        this.vif = vif;
    endfunction

    task drive(QuicksandTxn tr);
        @(negedge vif.clk);
        vif.rst_n   <= tr.rst_n;
        vif.start_i <= tr.start_i;
        vif.data_in <= tr.data_in;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class QuicksandGenerator;
    QuicksandDriver drv;
    int             num_random;
    int             max_struggles;

    function new(QuicksandDriver drv, int num_random, int max_struggles);
        this.drv           = drv;
        this.num_random    = num_random;
        this.max_struggles = max_struggles;
    endfunction

    task step(bit rst_n = 1'b1, bit start_i = 1'b0, bit data_in = 1'b0);
        QuicksandTxn tr;
        tr         = new();
        tr.rst_n   = rst_n;
        tr.start_i = start_i;
        tr.data_in = data_in;
        drv.drive(tr);
    endtask

    task calm(int n = 1);
        repeat (n) step();
    endtask

    task struggle(int n = 1);
        repeat (n) step(1'b1, 1'b0, 1'b1);
    endtask

    task begin_trap();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        step(1'b1, 1'b1);
    endtask

    task directed();
        step(1'b0);
        step(1'b0);
        step(1'b1);
        struggle(5);
        calm(2);

        begin_trap();
        calm(3);
        struggle(3);
        calm(2);

        step(1'b1, 1'b1);
        calm(3);

        for (int k = 1; k < max_struggles; k++) begin
            begin_trap();
            struggle(k);
            calm(k + 3);
        end

        begin_trap();
        struggle(max_struggles);
        struggle(3);
        calm(3);

        step(1'b1, 1'b1);
        calm(3);

        begin_trap();
        struggle(2);
        calm(1);
        struggle(1);
        calm(6);

        begin_trap();
        struggle(2);
        step(1'b1, 1'b1, 1'b1);
        step(1'b1, 1'b1, 1'b0);
        step(1'b1, 1'b1, 1'b0);
        calm(4);

        begin_trap();
        calm(2);
        repeat (6) step(1'b1, 1'b1, 1'b0);
        calm(3);

        step(1'b0);
        step(1'b1);
        step(1'b1, 1'b1, 1'b1);
        struggle(1);
        calm(5);

        begin_trap();
        struggle(max_struggles);
        step(1'b1, 1'b1, 1'b1);
        calm(4);

        begin_trap();
        struggle(max_struggles - 1);
        step(1'b0);
        calm(2);
        begin_trap();
        calm(3);

        begin_trap();
        calm(3);
        step(1'b0);
        calm(2);
        begin_trap();
        struggle(max_struggles);
        step(1'b0);
        calm(2);
    endtask

    task random_run();
        QuicksandTxn tr;
        bit over;
        bit was_over = 1'b1;
        int style    = 0;

        repeat (num_random) begin
            over = (drv.vif.rescued === 1'b1) || (drv.vif.dead === 1'b1);

            if (over && !was_over)
                style = $urandom_range(0, 3);
            was_over = over;

            tr = new();
            tr.rst_w   = over ? 20  : 3;
            tr.start_w = over ? 250 : 100;
            case (style)
                0:       tr.data_w = 500;
                1:       tr.data_w = 150;
                2:       tr.data_w = 850;
                default: tr.data_w = 300;
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
class QuicksandEnvironment;
    QuicksandGenerator  gen;
    QuicksandDriver     drv;
    QuicksandMonitor    mon;
    QuicksandScoreboard sb;

    virtual quicksand_if vif;

    function new(virtual quicksand_if vif, int max_struggles, int num_random = 20000);
        this.vif = vif;
        sb  = new(max_struggles);
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_random, max_struggles);
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
module tb_Quicksand;

    localparam int MAX_STRUGGLES = 5;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    quicksand_if vif (clk);

    Quicksand #(.MAX_STRUGGLES(MAX_STRUGGLES)) dut (
        .clk       (clk),
        .rst_n     (vif.rst_n),
        .start_i   (vif.start_i),
        .data_in   (vif.data_in),
        .rescued_o (vif.rescued),
        .dead_o    (vif.dead)
    );

    QuicksandEnvironment env;

    initial begin
        $dumpfile("Quicksand_waveform.vcd");
        $dumpvars(0, tb_Quicksand);
        #5us;
        $dumpoff;
    end

    initial begin
        vif.rst_n   = 1'b0;
        vif.start_i = 1'b0;
        vif.data_in = 1'b0;

        repeat (2) @(negedge clk);
        vif.rst_n = 1'b1;
        @(negedge clk);

        env = new(vif, MAX_STRUGGLES);
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "[TB] timeout");
    end
endmodule //The last line must be empty so vs code doesn't give a mistake

