////////////////////////////////////////////////////////////////////////////////
// WRAPPER MODULE: Ramp Generator Bus Interface (SYS[2])
////////////////////////////////////////////////////////////////////////////////
module custom_ramp_gen (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    output logic          trigger_out, 
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
    logic [31:0] period_reg;     // NEW: 32-bit register for ramp period (cycles per slope)

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            min_val_reg <= 14'h205;   // Minimum voltage
            max_val_reg <= 14'h3FFF;  // Maximum voltage
            period_reg  <= 32'd10000; // NEW: Default period in clock cycles
            sys_ack     <= 1'b0;
            sys_rdata   <= 32'h0;
        end else begin
            sys_ack <= sys_wen | sys_ren;
            
            // Write Path
            if (sys_wen) begin
                if (sys_addr[19:0] == 20'h00) min_val_reg <= sys_wdata[13:0];
                if (sys_addr[19:0] == 20'h04) max_val_reg <= sys_wdata[13:0];
                if (sys_addr[19:0] == 20'h08) period_reg  <= sys_wdata; // NEW: Write period
            end
            
            // Read Path (Registered)
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00:  sys_rdata <= {18'h0, min_val_reg};
                    20'h04:  sys_rdata <= {18'h0, max_val_reg};
                    20'h08:  sys_rdata <= period_reg;                   // NEW: Read period
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
        .clk_i       (clk_i),
        .rstn_i      (rstn_i),
        .arm_i       (arm_i),
        .trigger_i   (trigger_i),
        .min_val     (min_val_reg),
        .max_val     (max_val_reg),
        .period_val  (period_reg), // NEW: Passed to core logic
        .trigger_out (trigger_out),
        .dac_dat_o   (dac_dat_o)
    );

endmodule
