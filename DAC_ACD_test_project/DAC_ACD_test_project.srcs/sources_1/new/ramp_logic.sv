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
    
    // Hardware Outputs
    output logic          trigger_out, 
    output logic [13:0]   dac_dat_o
);

    localparam [1:0] IDLE      = 2'd0;
    localparam [1:0] RAMP_UP   = 2'd1;
    localparam [1:0] RAMP_DOWN = 2'd2;

    logic [1:0] state;

    // Ramp Logic & Trigger Generation
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            dac_dat_o   <= 14'h0;
            state       <= IDLE;
            trigger_out <= 1'b0;
        end else begin
            trigger_out <= 1'b0; 
            
            if (~arm_i) begin
                state       <= IDLE;
                dac_dat_o   <= min_val;
            end else if (trigger_i && state == IDLE) begin
                state       <= RAMP_UP;
                dac_dat_o   <= min_val;
                trigger_out <= 1'b1;
            end else if (state == RAMP_UP) begin
                if (dac_dat_o >= max_val) begin
                    state       <= RAMP_DOWN;
                    dac_dat_o   <= dac_dat_o - 1;
                    trigger_out <= 1'b1;
                end else begin
                    dac_dat_o   <= dac_dat_o + 1;
                end
            end else if (state == RAMP_DOWN) begin
                if (dac_dat_o <= min_val) begin
                    state       <= RAMP_UP;
                    dac_dat_o   <= dac_dat_o + 1;
                    trigger_out <= 1'b1;
                end else begin
                    dac_dat_o   <= dac_dat_o - 1;
                end
            end
        end
    end

endmodule
