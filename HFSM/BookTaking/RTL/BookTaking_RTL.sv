`timescale 1ns/1ps
module BookTaking (
    input logic clk,
    input logic rst_n,
    input logic start_i,
    input logic book_found_i,
    input logic shelf_end_i,
    input logic scan_success_i,
    output logic walk_to_shelf_o,
    output logic scan_eyes_o,
    output logic move_next_shelf_o,
    output logic take_book_o,
    output logic register_checkout_o,
    output logic process_done_o
);
    typedef enum logic [1:0] {IDLE, APPROACH, SEARCHING, CHECKOUT} main_state_t;
    typedef enum logic [1:0] {SCAN_SHELF, NEXT_SHELF, GRAB_BOOK} search_state_t;

    main_state_t state, next_state;
    search_state_t search, next_search;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            search <= SCAN_SHELF;
        end else begin
            state <= next_state;
            search <= next_search;
        end
    end

    always_comb begin
        next_state = state;
        next_search = search;

        case (state)
            IDLE: if (start_i) next_state = APPROACH;
            APPROACH: begin
                next_state = SEARCHING;
                next_search = SCAN_SHELF;
            end
            SEARCHING: if (search == GRAB_BOOK && book_found_i)
                next_state = CHECKOUT;
            CHECKOUT: if (scan_success_i) next_state = IDLE;
            default: next_state = IDLE;
        endcase

        if (state == SEARCHING) begin
            case (search)
                SCAN_SHELF: begin
                    if (book_found_i) next_search = GRAB_BOOK;
                    else if (shelf_end_i) next_search = NEXT_SHELF;
                end
                NEXT_SHELF: next_search = SCAN_SHELF;
                GRAB_BOOK: next_search = SCAN_SHELF;
                default: next_search = SCAN_SHELF;
            endcase
        end else begin
            next_search = SCAN_SHELF;
        end
    end

    assign walk_to_shelf_o = (state == APPROACH);
    assign register_checkout_o = (state == CHECKOUT);
    assign process_done_o = (state == CHECKOUT) && scan_success_i;
    assign scan_eyes_o = (state == SEARCHING) && (search == SCAN_SHELF);
    assign move_next_shelf_o = (state == SEARCHING) && (search == NEXT_SHELF);
    assign take_book_o = (state == SEARCHING) && (search == GRAB_BOOK);
endmodule
