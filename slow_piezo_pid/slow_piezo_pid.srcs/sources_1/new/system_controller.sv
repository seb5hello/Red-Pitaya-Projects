////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE: Master System Controller (Memory mapped to SYS[1])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00: Master Control (Bit 0: Global Arm, Bit 1: Global Trigger)
module system_controller (
    input  logic          clk_i,
    input  logic          rstn_i,
    output logic          global_arm_o,
    output logic          global_trigger_o,
    
    input  logic [19:0]   sys_addr,
    input  logic [31:0]   sys_wdata,
    input  logic          sys_wen,
    input  logic          sys_ren,
    output logic [31:0]   sys_rdata,
    output logic          sys_err,
    output logic          sys_ack
);

always @(posedge clk_i) begin
    if (~rstn_i) begin
        global_arm_o     <= 1'b0;
        global_trigger_o <= 1'b0;
        sys_ack          <= 1'b0;
    end else begin
        sys_ack <= sys_wen | sys_ren;
        if (sys_wen) begin
            if (sys_addr[19:0] == 20'h00) {global_trigger_o, global_arm_o} <= sys_wdata[1:0];
        end
    end
end

always_comb begin
    sys_rdata = 32'h0;
    if (sys_ren) begin
        if (sys_addr[19:0] == 20'h00) sys_rdata = {30'h0, global_trigger_o, global_arm_o};
    end
end
assign sys_err = 1'b0;
endmodule
