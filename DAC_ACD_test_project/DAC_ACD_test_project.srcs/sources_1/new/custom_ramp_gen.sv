////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE: Ramp Generator (Memory mapped to SYS[2])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00: Min Value (14-bit)
// Offset 0x04: Max Value (14-bit)
module custom_ramp_gen (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    output logic [14-1:0] dac_dat_o,
    
    input  logic [19:0]   sys_addr,
    input  logic [31:0]   sys_wdata,
    input  logic          sys_wen,
    input  logic          sys_ren,
    output logic [31:0]   sys_rdata,
    output logic          sys_err,
    output logic          sys_ack
);

logic [13:0] min_val;
logic [13:0] max_val;
logic running;

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

always_comb begin
    sys_rdata = 32'h0;
    if (sys_ren) begin
        if (sys_addr[19:0] == 20'h00) sys_rdata = {18'h0, min_val};
        if (sys_addr[19:0] == 20'h04) sys_rdata = {18'h0, max_val};
    end
end
assign sys_err = 1'b0;

// Ramp Logic driven by external arm_i and trigger_i
always @(posedge clk_i) begin
    if (~rstn_i) begin
        dac_dat_o <= 14'h0;
        running   <= 1'b0;
    end else begin
        if (~arm_i) begin
            running   <= 1'b0;
            dac_dat_o <= min_val;
        end else if (trigger_i && ~running) begin
            running   <= 1'b1;
            dac_dat_o <= min_val;
        end else if (running) begin
            if (dac_dat_o >= max_val) begin
                dac_dat_o <= min_val;
            end else begin
                dac_dat_o <= dac_dat_o + 1;
            end
        end
    end
end
endmodule