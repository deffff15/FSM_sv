`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    M_IDLE,
    M_APPROACH,
    M_SEARCHING,
    M_CHECKOUT
} model_main_t;

typedef enum logic [1:0] {
    M_SCAN_SHELF,
    M_NEXT_SHELF,
    M_GRAB_BOOK
} model_search_t;

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------
interface book_if (input logic clk);
    logic rst_n;
    logic start_i;
    logic book_found_i;
    logic shelf_end_i;
    logic scan_success_i;
    logic walk_to_shelf_o;
    logic scan_eyes_o;
    logic move_next_shelf_o;
    logic take_book_o;
    logic register_checkout_o;
    logic process_done_o;
endinterface

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------
class BookTxn;
    rand bit rst_n;
    rand bit start_i;
    rand bit book_found_i;
    rand bit shelf_end_i;
    rand bit scan_success_i;
    constraint c_rst_n {
        rst_n dist {1 := 199, 0 := 1};
    }
    constraint c_start_i {
        start_i dist {1 := 40, 0 := 60};
    }
    constraint c_book_found_i {
        book_found_i dist {1 := 30, 0 := 70};
    }
    constraint c_shelf_end_i {
        shelf_end_i dist {1 := 25, 0 := 75};
    }
    constraint c_scan_success_i {
        scan_success_i dist {1 := 40, 0 := 60};
    }
endclass

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
class BookScoreboard;
    model_main_t   expected_state  = M_IDLE;
    model_search_t expected_search = M_SCAN_SHELF;
    int checked = 0;
    int errors  = 0;

    function void check(
        input logic rst_n,
        input logic start_i,
        input logic book_found_i,
        input logic shelf_end_i,
        input logic scan_success_i,
        input logic walk_to_shelf_o,
        input logic scan_eyes_o,
        input logic move_next_shelf_o,
        input logic take_book_o,
        input logic register_checkout_o,
        input logic process_done_o
    );
        model_main_t   next_state;
        model_search_t next_search;
        logic          expected_walk_to_shelf;
        logic          expected_scan_eyes;
        logic          expected_move_next_shelf;
        logic          expected_take_book;
        logic          expected_register_checkout;
        logic          expected_process_done;
        bit            mismatch;
        if (!rst_n) begin
            expected_state  = M_IDLE;
            expected_search = M_SCAN_SHELF;
        end
        expected_walk_to_shelf     = (expected_state == M_APPROACH);
        expected_register_checkout = (expected_state == M_CHECKOUT);
        expected_process_done      = (expected_state == M_CHECKOUT) && scan_success_i;
        expected_scan_eyes         = (expected_state == M_SEARCHING) && (expected_search == M_SCAN_SHELF);
        expected_move_next_shelf   = (expected_state == M_SEARCHING) && (expected_search == M_NEXT_SHELF);
        expected_take_book         = (expected_state == M_SEARCHING) && (expected_search == M_GRAB_BOOK);
        mismatch = 0;
        if (walk_to_shelf_o !== expected_walk_to_shelf)
            mismatch = 1;
        if (scan_eyes_o !== expected_scan_eyes)
            mismatch = 1;
        if (move_next_shelf_o !== expected_move_next_shelf)
            mismatch = 1;
        if (take_book_o !== expected_take_book)
            mismatch = 1;
        if (register_checkout_o !== expected_register_checkout)
            mismatch = 1;
        if (process_done_o !== expected_process_done)
            mismatch = 1;
        if (mismatch)
            errors++;
        checked++;
        if (rst_n) begin
            next_state  = expected_state;
            next_search = expected_search;
            case (expected_state)
                M_IDLE: begin
                    if (start_i)
                        next_state = M_APPROACH;
                end
                M_APPROACH: begin
                    next_state  = M_SEARCHING;
                    next_search = M_SCAN_SHELF;
                end
                M_SEARCHING: begin
                    if (expected_search == M_GRAB_BOOK && book_found_i)
                        next_state = M_CHECKOUT;
                end
                M_CHECKOUT: begin
                    if (scan_success_i)
                        next_state = M_IDLE;
                end
                default: begin
                    next_state = M_IDLE;
                end
            endcase
            if (expected_state == M_SEARCHING) begin
                case (expected_search)
                    M_SCAN_SHELF: begin
                        if (book_found_i)
                            next_search = M_GRAB_BOOK;
                        else if (shelf_end_i)
                            next_search = M_NEXT_SHELF;
                    end
                    M_NEXT_SHELF: next_search = M_SCAN_SHELF;
                    M_GRAB_BOOK:  next_search = M_SCAN_SHELF;
                    default:      next_search = M_SCAN_SHELF;
                endcase
            end
            else begin
                next_search = M_SCAN_SHELF;
            end
            expected_state  = next_state;
            expected_search = next_search;
        end
    endfunction
endclass

// ---------------------------------------------------------------------------
// Monitor
// ---------------------------------------------------------------------------
class BookMonitor;
    virtual book_if vif;
    BookScoreboard  sb;

    function new(
        virtual book_if vif,
        BookScoreboard  sb
    );
        this.vif = vif;
        this.sb  = sb;
    endfunction

    task run();
        forever begin
            @(negedge vif.clk);
            #4;
            sb.check(
                vif.rst_n,
                vif.start_i,
                vif.book_found_i,
                vif.shelf_end_i,
                vif.scan_success_i,
                vif.walk_to_shelf_o,
                vif.scan_eyes_o,
                vif.move_next_shelf_o,
                vif.take_book_o,
                vif.register_checkout_o,
                vif.process_done_o
            );
        end
    endtask
endclass

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
class BookDriver;
    virtual book_if vif;

    function new(virtual book_if vif);
        this.vif = vif;
    endfunction

    task reset();
        @(negedge vif.clk);
        vif.rst_n          = 1'b0;
        vif.start_i        = 1'b0;
        vif.book_found_i   = 1'b0;
        vif.shelf_end_i    = 1'b0;
        vif.scan_success_i = 1'b0;
        repeat (2) @(negedge vif.clk);
        vif.rst_n = 1'b1;
    endtask

    task drive(BookTxn tr);
        @(negedge vif.clk);
        vif.rst_n          = tr.rst_n;
        vif.start_i        = tr.start_i;
        vif.book_found_i   = tr.book_found_i;
        vif.shelf_end_i    = tr.shelf_end_i;
        vif.scan_success_i = tr.scan_success_i;
    endtask
endclass

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------
class BookGenerator;
    BookDriver drv;
    int num_txn;

    function new(
        BookDriver drv,
        int num_txn
    );
        this.drv     = drv;
        this.num_txn = num_txn;
    endfunction

    task run();
        BookTxn tr;
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
class BookEnvironment;
    BookGenerator  gen;
    BookDriver     drv;
    BookMonitor    mon;
    BookScoreboard sb;
    virtual book_if vif;

    function new(
        virtual book_if vif,
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
        if (sb.errors != 0)
            $fatal(1);
    endtask
endclass

// ---------------------------------------------------------------------------
// Top
// ---------------------------------------------------------------------------
module tb_BookTaking;
    localparam int NUM_TXN = 30000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    book_if vif(clk);

    BookTaking dut (
        .clk                 (clk),
        .rst_n               (vif.rst_n),
        .start_i             (vif.start_i),
        .book_found_i        (vif.book_found_i),
        .shelf_end_i         (vif.shelf_end_i),
        .scan_success_i      (vif.scan_success_i),
        .walk_to_shelf_o     (vif.walk_to_shelf_o),
        .scan_eyes_o         (vif.scan_eyes_o),
        .move_next_shelf_o   (vif.move_next_shelf_o),
        .take_book_o         (vif.take_book_o),
        .register_checkout_o (vif.register_checkout_o),
        .process_done_o      (vif.process_done_o)
    );
    BookEnvironment env;

    initial begin
        $dumpfile("BookTaking_waveform.vcd");
        $dumpvars(0, tb_BookTaking);
    end

    initial begin
        vif.rst_n          = 1'b0;
        vif.start_i        = 1'b0;
        vif.book_found_i   = 1'b0;
        vif.shelf_end_i    = 1'b0;
        vif.scan_success_i = 1'b0;
        env = new(vif, NUM_TXN);
        env.drv.reset();
        env.run();
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1);
    end
endmodule //The last line must be empty so Vs code doesn't give a mistake

