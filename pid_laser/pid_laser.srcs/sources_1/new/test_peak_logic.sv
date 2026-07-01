////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Pure Test Peak Generator Logic (Mirrored Down-Ramp)
////////////////////////////////////////////////////////////////////////////////
module test_peak_logic (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    
    // Split Triggers
    input  logic          trigger_start_i,
    input  logic          trigger_max_i,
    
    // Configuration Inputs (Driven by Bus Interface)
    input  logic [31:0]   dly_1,
    input  logic [31:0]   dly_2,
    input  logic [31:0]   dly_3,
    input  logic [31:0]   dly_4,
    input  logic [13:0]   peak_amp,
    input  logic [13:0]   base_amp,
    input  logic [31:0]   pulse_width,
    
    // Hardware Outputs
    output logic [13:0]   dac_dat_o
);

    typedef enum logic [1:0] {IDLE = 2'd0, UP = 2'd1, DOWN = 2'd2} state_t;
    state_t state;
    logic [31:0] counter;

    // Edge detectors to ensure clean 1-cycle transitions
    logic t_start_d, t_max_d;
    logic t_start_pe, t_max_pe;

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            t_start_d <= 1'b0;
            t_max_d   <= 1'b0;
        end else begin
            t_start_d <= trigger_start_i;
            t_max_d   <= trigger_max_i;
        end
    end
    
    assign t_start_pe = trigger_start_i & ~t_start_d;
    assign t_max_pe   = trigger_max_i   & ~t_max_d;

    // Main Generation Logic
    always_ff @(posedge clk_i) begin
        if (~rstn_i || ~arm_i) begin
            dac_dat_o <= base_amp;
            counter   <= 0;
            state     <= IDLE;
        end else begin
            // ---------------------------------------------------------
            // 1. Counter & State Machine
            // ---------------------------------------------------------
            if (t_start_pe) begin
                state   <= UP;
                counter <= 0;
            end else if (t_max_pe && state == UP) begin
                state   <= DOWN;
                // Counter intentionally holds its value to start counting backward
            end else if (state == UP) begin
                counter <= counter + 1;
            end else if (state == DOWN) begin
                if (counter > 0) counter <= counter - 1;
            end

            // ---------------------------------------------------------
            // 2. Pulse Generation (Identical logic works for both UP and DOWN)
            // ---------------------------------------------------------
            if (state != IDLE) begin
                // Check if counter is within window AND delay is not zero (disabled)
                if ((dly_1 != 0 && counter >= dly_1 && counter < dly_1 + pulse_width) || 
                    (dly_2 != 0 && counter >= dly_2 && counter < dly_2 + pulse_width) || 
                    (dly_3 != 0 && counter >= dly_3 && counter < dly_3 + pulse_width) || 
                    (dly_4 != 0 && counter >= dly_4 && counter < dly_4 + pulse_width)) begin
                    dac_dat_o <= peak_amp;
                end else begin
                    dac_dat_o <= base_amp;
                end
            end else begin
                dac_dat_o <= base_amp;
            end
        end
    end

endmodule