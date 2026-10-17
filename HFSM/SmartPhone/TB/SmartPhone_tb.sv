`timescale 1ns / 1ps
import PhonePackage::*;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface phone_if (input logic clk);

    logic rst_n;
    logic battery_critical;
    logic power_button;
    logic unlock_success;
    logic launch_game;
    logic exit_to_menu;
    logic screen_on;
    logic gpu_high_power;
    logic phone_off;

endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class PhoneTxn;

    rand bit rst_n;
    rand bit battery_critical;
    rand bit power_button;
    rand bit unlock_success;
    rand bit launch_game;
    rand bit exit_to_menu;

    constraint c_rst_n {
        rst_n dist {1 := 99, 0 := 1};
    }

    constraint c_battery_critical {
        battery_critical dist {1 := 3, 0 := 97};
    }

    constraint c_power_button {
        power_button dist {1 := 15, 0 := 85};
    }

    constraint c_unlock_success {
        unlock_success dist {1 := 15, 0 := 85};
    }

    constraint c_launch_game {
        launch_game dist {1 := 25, 0 := 75};
    }

    constraint c_exit_to_menu {
        exit_to_menu dist {1 := 15, 0 := 85};
    }

endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class PhoneScoreboard;

    super_state_t    expected_super    = LOCKED;
    locked_state_t   expected_locked   = DEEP_SLEEP;
    unlocked_state_t expected_unlocked = HOME;

    int checked = 0;
    int errors  = 0;

    int powered_off_cycles = 0;
    int locked_cycles      = 0;
    int unlocked_cycles    = 0;
    int deep_sleep_cycles  = 0;
    int aod_cycles         = 0;
    int home_cycles        = 0;
    int game_cycles        = 0;
    int screen_on_cycles   = 0;
    int gpu_cycles         = 0;

    function void check(
        input logic rst_n,
        input logic battery_critical,
        input logic power_button,
        input logic unlock_success,
        input logic launch_game,
        input logic exit_to_menu,
        input logic screen_on,
        input logic gpu_high_power,
        input logic phone_off
    );
        super_state_t    next_super;
        locked_state_t   next_locked;
        unlocked_state_t next_unlocked;

        logic expected_screen_on;
        logic expected_gpu;
        logic expected_phone_off;
        bit   mismatch;

        if (!rst_n) begin
            expected_super    = LOCKED;
            expected_locked   = DEEP_SLEEP;
            expected_unlocked = HOME;
        end
        else begin

            next_super    = expected_super;
            next_locked   = expected_locked;
            next_unlocked = expected_unlocked;

            if (battery_critical) begin
                next_super = POWERED_OFF;
            end
            else begin

                case (expected_super)

                    POWERED_OFF: begin
                        if (power_button) begin
                            next_super  = LOCKED;
                            next_locked = AOD;
                        end
                    end

                    LOCKED: begin
                        if (unlock_success) begin
                            next_super    = UNLOCKED;
                            next_unlocked = HOME;
                        end
                        else if (power_button) begin
                            next_locked = (expected_locked == AOD) ? DEEP_SLEEP : AOD;
                        end
                    end

                    UNLOCKED: begin
                        if (power_button) begin
                            next_super  = LOCKED;
                            next_locked = AOD;
                        end
                        else begin
                            case (expected_unlocked)

                                HOME: begin
                                    if (launch_game)
                                        next_unlocked = GAME;
                                end

                                GAME: begin
                                    if (exit_to_menu)
                                        next_unlocked = HOME;
                                end

                                default: next_unlocked = HOME;

                            endcase
                        end
                    end

                    default: begin
                        next_super = POWERED_OFF;
                    end

                endcase
            end

            expected_super    = next_super;
            expected_locked   = next_locked;
            expected_unlocked = next_unlocked;

        end

        expected_screen_on = 1'b0;
        expected_gpu       = 1'b0;
        expected_phone_off = 1'b0;

        if (battery_critical) begin
            expected_phone_off = 1'b1;
        end
        else begin

            case (expected_super)

                POWERED_OFF: begin
                    expected_phone_off = 1'b1;
                end

                LOCKED: begin
                    expected_screen_on = (expected_locked == AOD);
                end

                UNLOCKED: begin
                    expected_screen_on = 1'b1;
                    if (expected_unlocked == GAME)
                        expected_gpu = 1'b1;
                end

                default: begin
                    expected_phone_off = 1'b1;
                end

            endcase

        end
        mismatch = 0;

        if (screen_on !== expected_screen_on)
            mismatch = 1;

        if (gpu_high_power !== expected_gpu)
            mismatch = 1;

        if (phone_off !== expected_phone_off)
            mismatch = 1;

        if (mismatch)
            errors++;

        case (expected_super)

            POWERED_OFF: powered_off_cycles++;

            LOCKED: begin
                locked_cycles++;
                if (expected_locked == AOD)
                    aod_cycles++;
                else
                    deep_sleep_cycles++;
            end

            UNLOCKED: begin
                unlocked_cycles++;
                if (expected_unlocked == GAME)
                    game_cycles++;
                else
                    home_cycles++;
            end

            default: ;
        endcase

        if (expected_screen_on)
            screen_on_cycles++;

        if (expected_gpu)
            gpu_cycles++;

        checked++;

    endfunction


    function void report();

        $display("");
        $display("========== PHONE SCOREBOARD =========");
        $display("Cycles checked      : %0d", checked);
        $display("Passed              : %0d", checked - errors);
        $display("Errors              : %0d", errors);
        $display("POWERED_OFF cycles  : %0d", powered_off_cycles);
        $display("LOCKED cycles       : %0d", locked_cycles);
        $display("  DEEP_SLEEP cycles : %0d", deep_sleep_cycles);
        $display("  AOD cycles        : %0d", aod_cycles);
        $display("UNLOCKED cycles     : %0d", unlocked_cycles);
        $display("  HOME cycles       : %0d", home_cycles);
        $display("  GAME cycles       : %0d", game_cycles);
        $display("Screen on cycles    : %0d", screen_on_cycles);
        $display("GPU high cycles     : %0d", gpu_cycles);
        $display("=====================================");

    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class PhoneMonitor;

    virtual phone_if vif;
    PhoneScoreboard  sb;

    function new(
        virtual phone_if vif,
        PhoneScoreboard  sb
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
                vif.battery_critical,
                vif.power_button,
                vif.unlock_success,
                vif.launch_game,
                vif.exit_to_menu,
                vif.screen_on,
                vif.gpu_high_power,
                vif.phone_off
            );

        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class PhoneDriver;

    virtual phone_if vif;

    function new(virtual phone_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);

        vif.rst_n            = 1'b0;
        vif.battery_critical = 1'b0;
        vif.power_button     = 1'b0;
        vif.unlock_success   = 1'b0;
        vif.launch_game      = 1'b0;
        vif.exit_to_menu     = 1'b0;

        repeat (2) @(negedge vif.clk);

        vif.rst_n = 1'b1;
    endtask

    task drive(PhoneTxn tr);

        @(negedge vif.clk);

        vif.rst_n            = tr.rst_n;
        vif.battery_critical = tr.battery_critical;
        vif.power_button     = tr.power_button;
        vif.unlock_success   = tr.unlock_success;
        vif.launch_game      = tr.launch_game;
        vif.exit_to_menu     = tr.exit_to_menu;
    endtask

endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class PhoneGenerator;

    PhoneDriver drv;
    int num_txn;

    function new(
        PhoneDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();

        PhoneTxn tr;

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
class PhoneEnvironment;

    PhoneGenerator  gen;
    PhoneDriver     drv;
    PhoneMonitor    mon;
    PhoneScoreboard sb;

    virtual phone_if vif;

    function new(
        virtual phone_if vif,
        int num_txn = 3000
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
module tb_SmartPhone;

    localparam int NUM_TXN = 3000;

    logic clk = 1'b0;

    always #5 clk = ~clk;

    phone_if vif(clk);

    SmartPhoneFSM dut (
        .clk              (clk),
        .rst_n            (vif.rst_n),
        .battery_critical (vif.battery_critical),
        .power_button     (vif.power_button),
        .unlock_success   (vif.unlock_success),
        .launch_game      (vif.launch_game),
        .exit_to_menu     (vif.exit_to_menu),
        .screen_on        (vif.screen_on),
        .gpu_high_power   (vif.gpu_high_power),
        .phone_off        (vif.phone_off)
    );

    PhoneEnvironment env;

    initial begin
        $dumpfile("SmartPhone_waveform.vcd");
        $dumpvars(0, tb_SmartPhone);
    end

    initial begin

        vif.rst_n            = 1'b0;
        vif.battery_critical = 1'b0;
        vif.power_button     = 1'b0;
        vif.unlock_success   = 1'b0;
        vif.launch_game      = 1'b0;
        vif.exit_to_menu     = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();

        $finish;

    end

    initial begin
        #1ms;
        $fatal(1, "TIMEOUT");
    end
endmodule //The last line must be empty so Vs Code doesn't give a endmodule

