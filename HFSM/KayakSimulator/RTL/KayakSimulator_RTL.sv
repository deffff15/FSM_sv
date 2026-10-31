`timescale 1ns/1ps
module KayakSimulator(
    input  logic       rst_n,
    input  logic       clk,
    input  logic       hold,
    input  logic       go_next,
    output logic [1:0] game,
    output logic       procedure
);

    typedef enum logic [2:0] {
        PIER_STANDING = 3'b000,
        GETTING_INTO  = 3'b001,
        CASTING_OFF   = 3'b010,
        SAILING_AWAY  = 3'b011,
        KAYAKING      = 3'b100,
        SAILING_BACK  = 3'b101,
        MOORING       = 3'b110,
        GETTING_OUT   = 3'b111
    } state_p;

    typedef enum logic [1:0] {
        STABLY  = 2'b00,
        SWAY    = 2'b01,
        FALLING = 2'b10
    } state_w;

    state_p s_current, s_next;
    state_w state_c, state_n;

    logic go_next_r;
    logic go_next_edge;
    logic [6:0] counter;
    logic [6:0] program_counter;
    logic game_ended;

    assign go_next_edge = go_next && !go_next_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_current       <= PIER_STANDING;
            state_c         <= STABLY;
            go_next_r       <= 1'b0;
            counter         <= 7'd0;
            program_counter <= 7'd0;
            game_ended      <= 1'b0;
        end else begin
            s_current <= s_next;
            state_c   <= state_n;
            go_next_r <= go_next;

            if (s_current == SAILING_AWAY && s_next == KAYAKING) begin
                counter         <= 7'd100;
                program_counter <= 7'd100;
                game_ended      <= 1'b0;
            end else if (s_current == KAYAKING) begin
                if (counter > 0) begin
                    counter <= counter - 1'b1;
                    if (program_counter >= hold)
                        program_counter <= program_counter - hold;
                    else
                        program_counter <= 7'd0;
                end else begin
                    game_ended <= 1'b1;
                end
            end else begin
                game_ended <= 1'b0;
            end
        end
    end

    always_comb begin
        s_next = s_current;

        case (s_current)
            PIER_STANDING: if (go_next_edge) s_next = GETTING_INTO;
            GETTING_INTO:  if (go_next_edge) s_next = CASTING_OFF;
            CASTING_OFF:   if (go_next_edge) s_next = SAILING_AWAY;
            SAILING_AWAY:  if (go_next_edge) s_next = KAYAKING;
            KAYAKING:      if (game_ended && go_next_edge) s_next = SAILING_BACK;
            SAILING_BACK:  if (go_next_edge) s_next = MOORING;
            MOORING:       if (go_next_edge) s_next = GETTING_OUT;
            GETTING_OUT:   if (go_next_edge) s_next = PIER_STANDING;
            default:       s_next = PIER_STANDING;
        endcase
    end

    always_comb begin
        state_n = state_c;

        if (s_current == KAYAKING && game_ended) begin
            if (program_counter < 50)
                state_n = STABLY;
            else if (program_counter < 75)
                state_n = SWAY;
            else
                state_n = FALLING;
        end else if (s_current == PIER_STANDING) begin
            state_n = STABLY;
        end
    end

    always_comb begin
        case (state_c)
            STABLY:  game = 2'b10;
            SWAY:    game = 2'b01;
            FALLING: game = 2'b00;
            default: game = 2'b00;
        endcase
    end

    assign procedure = (s_current == GETTING_OUT && s_next == PIER_STANDING);

endmodule
