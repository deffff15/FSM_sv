`timescale 1ns/1ps
module TractorDriver (
    input  logic clk,
    input  logic rst_n,
    input  logic start_engine,
    input  logic row_end,
    input  logic field_done,
    input  logic shutdown,
    output logic glow_plugs,
    output logic plow_down,
    output logic turning,
    output logic beacon
);

    typedef enum logic [1:0] {
        GARAGE = 2'b00,
        STARTING = 2'b01,
        FIELDWORK = 2'b10,
        SHUTDOWN = 2'b11
    } top_state_t;

    typedef enum logic [1:0] {
        PLOWING = 2'b00,
        TURNING = 2'b01,
        UNLOADING = 2'b10
    } sub_state_t;

    top_state_t top_state, top_next;
    sub_state_t sub_state, sub_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_state <= GARAGE;
            sub_state <= PLOWING;
        end else begin
            top_state <= top_next;
            sub_state <= sub_next;
        end
    end

    always_comb begin
        top_next = top_state;
        sub_next = sub_state;

        case (top_state)
            GARAGE:
                if (start_engine)
                    top_next = STARTING;

            STARTING: begin
                top_next = FIELDWORK;
                sub_next = PLOWING;
            end

            FIELDWORK:
                case (sub_state)
                    PLOWING: begin
                        if (field_done)
                            top_next = SHUTDOWN;
                        else if (row_end)
                            sub_next = TURNING;
                    end

                    TURNING:
                        if (!row_end)
                            sub_next = PLOWING;

                    UNLOADING:
                        sub_next = PLOWING;

                    default: sub_next = PLOWING;
                endcase

            SHUTDOWN:
                if (shutdown)
                    top_next = GARAGE;

            default: begin
                top_next = GARAGE;
                sub_next = PLOWING;
            end
        endcase
    end

    always_comb begin
        glow_plugs = 1'b0;
        plow_down  = 1'b0;
        turning    = 1'b0;
        beacon     = 1'b0;

        case (top_state)
            STARTING:
                glow_plugs = 1'b1;

            FIELDWORK: begin
                beacon = 1'b1;
                plow_down = (sub_state == PLOWING);
                turning = (sub_state == TURNING);
            end

            SHUTDOWN:
                beacon = 1'b1;

            default: ;
        endcase
    end

endmodule

