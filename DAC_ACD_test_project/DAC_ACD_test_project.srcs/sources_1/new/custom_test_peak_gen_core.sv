////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE CORE: Test Peak Generator Logic (Timing Fixed)
////////////////////////////////////////////////////////////////////////////////
module custom_test_peak_gen_core (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    
    // Configuration Inputs (Driven by AXI registers)
    input  logic [31:0]   dly_1_i,
    input  logic [31:0]   dly_2_i,
    input  logic [31:0]   dly_3_i,
    input  logic [31:0]   dly_4_i,
    input  logic [13:0]   peak_amp_i,
    input  logic [13:0]   base_amp_i,
    input  logic [31:0]   pulse_width_i,
    
    // Status & Output
    output logic          done_o,
    output logic [13:0]   dac_dat_o
);

logic [31:0] counter;
logic running;

// -------------------------------------------------------------------------
// 1. Registered Math Boundaries (Pipelining to fix 22 Logic Levels)
// -------------------------------------------------------------------------
logic [31:0] dly_1_max, dly_2_max, dly_3_max, dly_4_max;
logic [31:0] max_dly_12, max_dly_34, final_dly, finish_time;

always @(posedge clk_i) begin
    if (~rstn_i) begin
        dly_1_max <= 0; dly_2_max <= 0; dly_3_max <= 0; dly_4_max <= 0;
        max_dly_12 <= 0; max_dly_34 <= 0; final_dly <= 0; finish_time <= 0;
    end else begin
        // Stage 1: Calculate individual pulse upper limits and intermediate maxes
        dly_1_max  <= dly_1_i + pulse_width_i;
        dly_2_max  <= dly_2_i + pulse_width_i;
        dly_3_max  <= dly_3_i + pulse_width_i;
        dly_4_max  <= dly_4_i + pulse_width_i;
        max_dly_12 <= (dly_1_i > dly_2_i) ? dly_1_i : dly_2_i;
        max_dly_34 <= (dly_3_i > dly_4_i) ? dly_3_i : dly_4_i;
        
        // Stage 2: Calculate final maximum delay and total finish time
        final_dly   <= (max_dly_12 > max_dly_34) ? max_dly_12 : max_dly_34;
        finish_time <= final_dly + pulse_width_i;
    end
end

// -------------------------------------------------------------------------
// 2. Pulse Window Evaluation (Simplified combinational check)
// -------------------------------------------------------------------------
logic is_pulse;
always_comb begin
    is_pulse = ((counter >= dly_1_i) && (counter < dly_1_max)) ||
               ((counter >= dly_2_i) && (counter < dly_2_max)) ||
               ((counter >= dly_3_i) && (counter < dly_3_max)) ||
               ((counter >= dly_4_i) && (counter < dly_4_max));
end

// -------------------------------------------------------------------------
// 3. Main State Machine
// -------------------------------------------------------------------------
always @(posedge clk_i) begin
    if (~rstn_i) begin
        dac_dat_o <= 14'h0;
        counter   <= 0;
        running   <= 0;
        done_o    <= 0;
    end else begin
        if (~arm_i) begin
            counter   <= 0;
            running   <= 0;
            done_o    <= 0;
            dac_dat_o <= base_amp_i;
            
        end else if (trigger_i) begin 
            running   <= 1;
            done_o    <= 0;
            counter   <= 0;
            dac_dat_o <= base_amp_i;
            
        end else if (running) begin
            
            if (counter >= finish_time) begin
                running   <= 0;
                done_o    <= 1;
                dac_dat_o <= base_amp_i;
            end else begin
                counter <= counter + 1;
                
                if (is_pulse) begin
                    dac_dat_o <= peak_amp_i;
                end else begin
                    dac_dat_o <= base_amp_i;
                end
            end
        end
    end
end
endmodule