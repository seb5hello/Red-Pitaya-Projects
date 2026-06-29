////////////////////////////////////////////////////////////////////////////////
// WRAPPER MODULE: Test Peak Generator Bus Interface (SYS[4])
////////////////////////////////////////////////////////////////////////////////
module custom_test_peak_gen (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    
    // Split Triggers
    input  logic          trigger_start_i,
    input  logic          trigger_max_i,
    
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
    logic [31:0] dly_1_reg, dly_2_reg, dly_3_reg, dly_4_reg;
    logic [13:0] peak_amp_reg;
    logic [13:0] base_amp_reg;
    logic [31:0] pulse_width_reg;

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            dly_1_reg       <= 32'd100;
            dly_2_reg       <= 32'd200;
            dly_3_reg       <= 32'd300;
            dly_4_reg       <= 32'd400;
            peak_amp_reg    <= 14'h3FFF; 
            base_amp_reg    <= 14'h0000;
            pulse_width_reg <= 32'd50;
            sys_ack         <= 1'b0;
            sys_rdata       <= 32'h0;
        end else begin
            sys_ack <= sys_wen | sys_ren;
            
            // Write Path
            if (sys_wen) begin
                case (sys_addr[19:0])
                    20'h00: dly_1_reg       <= sys_wdata;
                    20'h04: dly_2_reg       <= sys_wdata;
                    20'h08: dly_3_reg       <= sys_wdata;
                    20'h0C: dly_4_reg       <= sys_wdata;
                    20'h10: peak_amp_reg    <= sys_wdata[13:0];
                    20'h14: base_amp_reg    <= sys_wdata[13:0];
                    20'h18: pulse_width_reg <= sys_wdata;
                    default: ; // Ignore unmapped writes
                endcase
            end
            
            // Read Path (Registered)
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00:  sys_rdata <= dly_1_reg;
                    20'h04:  sys_rdata <= dly_2_reg;
                    20'h08:  sys_rdata <= dly_3_reg;
                    20'h0C:  sys_rdata <= dly_4_reg;
                    20'h10:  sys_rdata <= {18'h0, peak_amp_reg};
                    20'h14:  sys_rdata <= {18'h0, base_amp_reg};
                    20'h18:  sys_rdata <= pulse_width_reg;
                    default: sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Core Logic Instantiation
    // -------------------------------------------------------------------------
    test_peak_logic i_test_peak_logic (
        .clk_i           (clk_i),
        .rstn_i          (rstn_i),
        .arm_i           (arm_i),
        
        .trigger_start_i (trigger_start_i),
        .trigger_max_i   (trigger_max_i),
        
        .dly_1           (dly_1_reg),
        .dly_2           (dly_2_reg),
        .dly_3           (dly_3_reg),
        .dly_4           (dly_4_reg),
        .peak_amp        (peak_amp_reg),
        .base_amp        (base_amp_reg),
        .pulse_width     (pulse_width_reg),
        .dac_dat_o       (dac_dat_o)
    );

endmodule