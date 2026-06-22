////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Pure Ramp Generator Logic
////////////////////////////////////////////////////////////////////////////////
module ramp_logic (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    
    // Configuration Inputs (Driven by Bus Interface)
    input  logic [13:0]   min_val,
    input  logic [13:0]   max_val,
    input  logic [31:0]   period_val, // NEW: Ramp period in clock cycles
    
    // Hardware Outputs
    output logic          trigger_out, 
    output logic [13:0]   dac_dat_o
);

    localparam [1:0] IDLE      = 2'd0;
    localparam [1:0] RAMP_UP   = 2'd1;
    localparam [1:0] RAMP_DOWN = 2'd2;

    logic [1:0]  state;
    logic [31:0] acc;         // NEW: Phase accumulator 
    logic [13:0] delta_v;     // NEW: Total voltage difference

    // Compute the total number of voltage steps for one slope
    assign delta_v = max_val - min_val;

    // Ramp Logic & Trigger Generation
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            dac_dat_o   <= 14'h0;
            state       <= IDLE;
            trigger_out <= 1'b0;
            acc         <= 32'h0; // Reset accumulator
        end else begin
            trigger_out <= 1'b0; 
            
            if (~arm_i) begin
                state       <= IDLE;
                dac_dat_o   <= min_val;
                acc         <= 32'h0;
                
            end else if (trigger_i && state == IDLE) begin
                state       <= RAMP_UP;
                dac_dat_o   <= min_val;
                trigger_out <= 1'b1;
                acc         <= 32'h0; // Start accumulator at 0 for a clean slope
                
            end else if (state == RAMP_UP) begin
                // Check if accumulator threshold is met
                if (acc + delta_v >= period_val) begin
                    // Retain the fractional remainder for precise long-term frequency
                    acc <= acc + delta_v - period_val; 
                    
                    if (dac_dat_o >= max_val) begin
                        state       <= RAMP_DOWN;
                        dac_dat_o   <= dac_dat_o - 1;
                        trigger_out <= 1'b1;
                    end else begin
                        dac_dat_o   <= dac_dat_o + 1;
                    end
                end else begin
                    // Keep accumulating step fractions
                    acc <= acc + delta_v; 
                end
                
            end else if (state == RAMP_DOWN) begin
                // Check if accumulator threshold is met
                if (acc + delta_v >= period_val) begin
                    acc <= acc + delta_v - period_val; 
                    
                    if (dac_dat_o <= min_val) begin
                        state       <= RAMP_UP;
                        dac_dat_o   <= dac_dat_o + 1;
                        trigger_out <= 1'b1;
                    end else begin
                        dac_dat_o   <= dac_dat_o - 1;
                    end
                end else begin
                    acc <= acc + delta_v;
                end
            end
        end
    end

endmodule
