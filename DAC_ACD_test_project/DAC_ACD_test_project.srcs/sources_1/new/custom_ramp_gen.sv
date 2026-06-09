////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE WRAPPER: Ramp Generator (Memory mapped to SYS[2])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00: Min Value (14-bit)
// Offset 0x04: Max Value (14-bit)
module custom_ramp_gen (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    output logic [13:0]   dac_dat_o,
    
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
logic [13:0] min_val;
logic [13:0] max_val;

// System Bus Write Interface
always @(posedge clk_i) begin
    if (~rstn_i) begin
        min_val <= 14'h0;
        max_val <= 14'h3FFF;
        sys_ack <= 1'b0;
    end else begin
        sys_ack <= sys_wen | sys_ren;
        if (sys_wen) begin
            if (sys_addr[19:0] == 20'h00) min_val <= sys_wdata[13:0];
            if (sys_addr[19:0] == 20'h04) max_val <= sys_wdata[13:0];
        end
    end
end

// System Bus Read Interface
always @(posedge clk_i) begin
    if (~rstn_i) begin
        sys_rdata <= 32'h0;
    end else begin
        // Default to 0 unless reading
        sys_rdata <= 32'h0; 
        
        if (sys_ren) begin
            case (sys_addr[19:0])
                20'h00: sys_rdata = {18'h0, min_val};
                20'h04: sys_rdata = {18'h0, max_val};
            endcase
        end
    end
end

assign sys_err = 1'b0;

// Core Logic Instantiation
custom_ramp_gen_core ramp_gen_logic (
    .clk_i      (clk_i),
    .rstn_i     (rstn_i),
    .arm_i      (arm_i),
    .trigger_i  (trigger_i),
    .min_val_i  (min_val),
    .max_val_i  (max_val),
    .dac_dat_o  (dac_dat_o)
);

endmodule