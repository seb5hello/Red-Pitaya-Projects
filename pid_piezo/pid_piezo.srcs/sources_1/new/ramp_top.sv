////////////////////////////////////////////////////////////////////////////////
// WRAPPER MODULE: Ramp Generator Bus Interface (SYS[2])
////////////////////////////////////////////////////////////////////////////////
module ramp_top (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    
    // Updated Triggers
    output logic          trigger_start_o, 
    output logic          trigger_max_o, 
    
    output logic [14-1:0] dac_dat_o,
    
    // System Bus Interface
    input  logic [19:0]   sys_addr,
    input  logic [31:0]   sys_wdata,
    input  logic          sys_wen,
    input  logic          sys_ren,
    output logic [31:0]   sys_rdata,
    output logic          sys_err,
    output logic          sys_ack
);

    // Internal Configuration Registers
    logic [13:0] min_val_reg;
    logic [13:0] max_val_reg;
    logic [31:0] period_reg;     
    logic [31:0] mode_reg;

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface (UNCHANGED)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            min_val_reg <= 14'h205;
            max_val_reg <= 14'h3FFF;  
            period_reg  <= 32'd10000; 
            mode_reg    <= 32'h0;
            sys_ack     <= 1'b0;
            sys_rdata   <= 32'h0;
        end else begin
            sys_ack <= sys_wen | sys_ren;
            
            // Write Path
            if (sys_wen) begin
                if (sys_addr[19:0] == 20'h00) min_val_reg <= sys_wdata[13:0];
                if (sys_addr[19:0] == 20'h04) max_val_reg <= sys_wdata[13:0];
                if (sys_addr[19:0] == 20'h08) period_reg  <= sys_wdata;
                if (sys_addr[19:0] == 20'h0C) mode_reg    <= sys_wdata;
            end
            
            // Read Path (Registered)
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00:  sys_rdata <= {18'h0, min_val_reg};
                    20'h04:  sys_rdata <= {18'h0, max_val_reg};
                    20'h08:  sys_rdata <= period_reg;
                    20'h0C:  sys_rdata <= mode_reg;
                    default: sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Core Logic Instantiation
    // -------------------------------------------------------------------------
    ramp_logic i_ramp_logic (
        .clk_i           (clk_i),
        .rstn_i          (rstn_i),
        .arm_i           (arm_i),
        .trigger_i       (trigger_i),
        .min_val         (min_val_reg),
        .max_val         (max_val_reg),
        .period_val      (period_reg),
        .continuous_en   (mode_reg[0]), 
        
        // Updated Triggers
        .trigger_start_o (trigger_start_o),
        .trigger_max_o   (trigger_max_o),
        
        .dac_dat_o       (dac_dat_o)
    );

endmodule