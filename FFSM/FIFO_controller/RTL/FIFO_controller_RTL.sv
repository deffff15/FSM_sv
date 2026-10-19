`timescale 1ns/1ps
module FifoController (
    input  logic clk,
    input  logic rst_n,
    input  logic wr_req,
    input  logic rd_req,
    input  logic fifo_full,
    input  logic fifo_empty,
    output logic wr_en,
    output logic rd_en,
    output logic alarm
);

    localparam int unsigned NUM_STATES = 4;
    localparam logic [NUM_STATES-1:0] IDLE  = 4'b0001;
    localparam logic [NUM_STATES-1:0] WRITE = 4'b0010;
    localparam logic [NUM_STATES-1:0] READ  = 4'b0100;
    localparam logic [NUM_STATES-1:0] ERROR = 4'b1000;
    logic [NUM_STATES-1:0] current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        wr_en      = 1'b0;
        rd_en      = 1'b0;
        alarm      = 1'b0;

        if (current_state[0]) begin
            if (wr_req && !fifo_full)
                next_state = WRITE;
            else if (rd_req && !fifo_empty)
                next_state = READ;
            else if ((wr_req && fifo_full) ||
                     (rd_req && fifo_empty))
                next_state = ERROR;
        end else if (current_state[1]) begin
            wr_en = 1'b1;

            if (rd_req && !fifo_empty)
                next_state = READ;
            else if (wr_req && !fifo_full)
                next_state = WRITE;
            else
                next_state = IDLE;
        end else if (current_state[2]) begin
            rd_en = 1'b1;

            if (wr_req && !fifo_full)
                next_state = WRITE;
            else if (rd_req && !fifo_empty)
                next_state = READ;
            else
                next_state = IDLE;
        end else if (current_state[3]) begin
            alarm = 1'b1;

            if (!wr_req && !rd_req)
                next_state = IDLE;
        end else begin
            next_state = IDLE;
        end
    end

endmodule
