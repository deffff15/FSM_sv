`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE      = 2'b00,
    M_PLAY      = 2'b01,
    M_EVALUATE  = 2'b10,
    M_GAME_OVER = 2'b11
} model_state_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface rps_if #(parameter int AMOUNT = 3) (input logic clk);
    logic              rst_n;
    logic              start;
    logic [AMOUNT:0]   amount_of_rounds;
    logic [1:0]        r_p_s;
    logic              winner;
    logic              loser;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class RpsTxn #(parameter int AMOUNT = 3);
    localparam int MAX_ROUNDS = 2**(AMOUNT+1) - 1;
    rand bit                rst_n;
    rand bit                start;
    rand bit [AMOUNT:0]     amount_of_rounds;
    rand bit [1:0]          r_p_s;
    constraint c_rst_n {
        rst_n dist {1 := 199, 0 := 1};
    }
    constraint c_start {
        start dist {1 := 60, 0 := 40};
    }
    constraint c_amount_of_rounds {
        amount_of_rounds dist {[0:3] :/ 80, [4:MAX_ROUNDS] :/ 20};
    }
    constraint c_r_p_s {
        r_p_s dist {2'b00 := 10, 2'b01 := 30, 2'b10 := 30, 2'b11 := 30};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class RpsScoreboard #(parameter int AMOUNT = 3);
    localparam logic [1:0] ROCK     = 2'b01;
    localparam logic [1:0] PAPER    = 2'b10;
    localparam logic [1:0] SCISSORS = 2'b11;
    model_state_t    expected_state  = M_IDLE;
    logic [AMOUNT:0] expected_player = '0;
    logic [AMOUNT:0] expected_ai     = '0;
    logic [AMOUNT:0] expected_target = '0;
    logic [7:0]      expected_random = 8'hA5;
    int checked = 0;
    int errors  = 0;
    int idle_cycles      = 0;
    int play_cycles      = 0;
    int evaluate_cycles  = 0;
    int game_over_cycles = 0;
    int player_rounds    = 0;
    int ai_rounds        = 0;
    int draw_rounds      = 0;
    int winner_cycles    = 0;
    int loser_cycles     = 0;
    int tie_cycles       = 0;

    function void check(
        input logic              rst_n,
        input logic              start,
        input logic [AMOUNT:0]   amount_of_rounds,
        input logic [1:0]        r_p_s,
        input logic              winner,
        input logic              loser
    );
        model_state_t next_state;
        logic [1:0]   ai_choice;
        logic         expected_winner;
        logic         expected_loser;
        bit           valid_input;
        bit           player_wins_round;
        bit           mismatch;

        if (!rst_n) begin
            expected_state  = M_IDLE;
            expected_player = '0;
            expected_ai     = '0;
            expected_target = '0;
            expected_random = 8'hA5;
        end
        else begin

            case (expected_random[1:0])
                2'b10:   ai_choice = PAPER;
                2'b11:   ai_choice = SCISSORS;
                default: ai_choice = ROCK;
            endcase
            valid_input = (r_p_s == ROCK) || (r_p_s == PAPER) || (r_p_s == SCISSORS);
            next_state = expected_state;
            case (expected_state)
                M_IDLE: begin
                    if (start)
                        next_state = M_PLAY;
                end
                M_PLAY: begin
                    if (start && valid_input)
                        next_state = M_EVALUATE;
                end
                M_EVALUATE: begin
                    if (expected_player >= expected_target || expected_ai >= expected_target)
                        next_state = M_GAME_OVER;
                    else
                        next_state = M_PLAY;
                end
                M_GAME_OVER: begin
                    if (start)
                        next_state = M_PLAY;
                end
                default: begin
                    next_state = M_IDLE;
                end
            endcase
            case (expected_state)
                M_IDLE, M_GAME_OVER: begin
                    if (start) begin
                        expected_target = amount_of_rounds;
                        expected_player = '0;
                        expected_ai     = '0;
                    end
                end
                M_EVALUATE: begin
                    if (r_p_s != ai_choice) begin
                        player_wins_round = (r_p_s == ROCK     && ai_choice == SCISSORS) ||
                                            (r_p_s == PAPER    && ai_choice == ROCK)     ||
                                            (r_p_s == SCISSORS && ai_choice == PAPER);
                        if (player_wins_round) begin
                            expected_player = expected_player + 1'b1;
                            player_rounds++;
                        end
                        else if (valid_input) begin
                            expected_ai = expected_ai + 1'b1;
                            ai_rounds++;
                        end
                    end
                    else begin
                        draw_rounds++;
                    end
                end
                default: ;
            endcase
            expected_random = {expected_random[6:0],
                               expected_random[7] ^ expected_random[5] ^ expected_random[4] ^ expected_random[3]};
            expected_state = next_state;
        end
        expected_winner = 1'b0;
        expected_loser  = 1'b0;
        if (expected_state == M_GAME_OVER) begin
            if (expected_player > expected_ai)
                expected_winner = 1'b1;
            else if (expected_ai > expected_player)
                expected_loser = 1'b1;
        end
        mismatch = 0;
        if (winner !== expected_winner)
            mismatch = 1;
        if (loser !== expected_loser)
            mismatch = 1;
        if (mismatch) begin
            errors++;
            if (errors <= 5)
                $display("MISMATCH t=%0t model_state=%0d player=%0d ai=%0d target=%0d winner=%b exp=%b loser=%b exp=%b",
                         $time, expected_state, expected_player, expected_ai, expected_target,
                         winner, expected_winner, loser, expected_loser);
        end
        case (expected_state)
            M_IDLE:      idle_cycles++;
            M_PLAY:      play_cycles++;
            M_EVALUATE:  evaluate_cycles++;
            M_GAME_OVER: game_over_cycles++;
            default: ;
        endcase
        if (expected_winner)
            winner_cycles++;
        if (expected_loser)
            loser_cycles++;
        if (expected_state == M_GAME_OVER && expected_player == expected_ai)
            tie_cycles++;
        checked++;
    endfunction

    function void report();
        $display("============ RPS SCOREBOARD =========");
        $display("Cycles checked      : %0d", checked);
        $display("Passed              : %0d", checked - errors);
        $display("Errors              : %0d", errors);
        $display("IDLE cycles         : %0d", idle_cycles);
        $display("PLAY cycles         : %0d", play_cycles);
        $display("EVALUATE cycles     : %0d", evaluate_cycles);
        $display("GAME_OVER cycles    : %0d", game_over_cycles);
        $display("Player round wins   : %0d", player_rounds);
        $display("AI round wins       : %0d", ai_rounds);
        $display("Draw rounds         : %0d", draw_rounds);
        $display("Winner cycles       : %0d", winner_cycles);
        $display("Loser cycles        : %0d", loser_cycles);
        $display("Tie game cycles     : %0d", tie_cycles);
        $display("=====================================");
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class RpsMonitor #(parameter int AMOUNT = 3);
    virtual rps_if #(AMOUNT) vif;
    RpsScoreboard #(AMOUNT)  sb;

    function new(
        virtual rps_if #(AMOUNT) vif,
        RpsScoreboard #(AMOUNT)  sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        forever begin
            @(posedge vif.clk);
            #1;
            sb.check(
                vif.rst_n,
                vif.start,
                vif.amount_of_rounds,
                vif.r_p_s,
                vif.winner,
                vif.loser
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class RpsDriver #(parameter int AMOUNT = 3);
    virtual rps_if #(AMOUNT) vif;

    function new(virtual rps_if #(AMOUNT) vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n            = 1'b0;
        vif.start            = 1'b0;
        vif.amount_of_rounds = '0;
        vif.r_p_s            = 2'b00;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(RpsTxn #(AMOUNT) tr);
        @(negedge vif.clk);
        vif.rst_n            = tr.rst_n;
        vif.start            = tr.start;
        vif.amount_of_rounds = tr.amount_of_rounds;
        vif.r_p_s            = tr.r_p_s;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class RpsGenerator #(parameter int AMOUNT = 3);
    RpsDriver #(AMOUNT) drv;
    int num_txn;

    function new(
        RpsDriver #(AMOUNT) drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        RpsTxn #(AMOUNT) tr;
        repeat (num_txn) begin
            tr = new();
            if (!tr.randomize())
                $fatal(1);
            drv.drive(tr);
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
class RpsEnvironment #(parameter int AMOUNT = 3);
    RpsGenerator  #(AMOUNT) gen;
    RpsDriver     #(AMOUNT) drv;
    RpsMonitor    #(AMOUNT) mon;
    RpsScoreboard #(AMOUNT) sb;
    virtual rps_if #(AMOUNT) vif;

    function new(
        virtual rps_if #(AMOUNT) vif,
        int num_txn = 30000
    );
        this.vif = vif;
        sb  = new();
        drv = new(vif);
        mon = new(vif, sb);
        gen = new(drv, num_txn);
    endfunction

    task run();
        fork
            mon.run();
        join_none
        gen.run();
        repeat (3) @(posedge vif.clk);
        #2;
        sb.report();
        if (sb.errors != 0)
            $fatal(1, "TEST FAILED: %0d errors", sb.errors);
        else
            $display("TEST PASSED");
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_Rock_Paper_Scissors;
    localparam int AMOUNT  = 3;
    localparam int NUM_TXN = 30000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    rps_if #(AMOUNT) vif(clk);

    Rock_Paper_Scissors #(
        .AMOUNT(AMOUNT)
    ) dut (
        .clk              (clk),
        .rst_n            (vif.rst_n),
        .start            (vif.start),
        .amount_of_rounds (vif.amount_of_rounds),
        .r_p_s            (vif.r_p_s),
        .winner           (vif.winner),
        .loser            (vif.loser)
    );
    RpsEnvironment #(AMOUNT) env;

    initial begin
        $dumpfile("Rock_Paper_Scissors_waveform.vcd");
        $dumpvars(0, tb_Rock_Paper_Scissors);
    end

    initial begin
        vif.rst_n            = 1'b0;
        vif.start            = 1'b0;
        vif.amount_of_rounds = '0;
        vif.r_p_s            = 2'b00;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "TIMEOUT");
    end
endmodule //The last line must be empty so vscode doesn't give a mistake

