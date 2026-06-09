////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE CORE: Ramp Generator Logic
////////////////////////////////////////////////////////////////////////////////
module custom_ramp_gen_core (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    
    // Configuration Inputs (Driven by AXI registers)
    input  logic [13:0]   min_val_i,
    input  logic [13:0]   max_val_i,
    
    // DAC Output
    output logic [13:0]   dac_dat_o
);

logic [1:0] state;

// Ramp Logic driven by external arm_i and trigger_i
always @(posedge clk_i) begin
    if (~rstn_i) begin
        dac_dat_o <= 14'h0;
        state   <= 2'd0;
    end else begin
        if (~arm_i) begin
            state   <= 2'd0;
            dac_dat_o <= min_val_i;
        end else if (trigger_i && ~state) begin
            state   <= 2'd1;
            dac_dat_o <= min_val_i;
        end else if (state == 2'd1) begin
            if (dac_dat_o >= max_val_i) begin
                state   <= 2'd2;
                dac_dat_o <= dac_dat_o - 1;
            end else begin
                dac_dat_o <= dac_dat_o + 1;
            end
        end else if (state == 2'd2) begin
            if (dac_dat_o <= min_val_i) begin
                state   <= 2'd1;
                dac_dat_o <= dac_dat_o + 1;
            end else begin
                dac_dat_o <= dac_dat_o - 1;
            end
        end
    end
end

endmodule