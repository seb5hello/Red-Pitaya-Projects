////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE: Master System Controller (Memory mapped to SYS[1])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00 (R/W): Master Control 
//   Bits [2:0] : Mode (Signed 3-bit integer)
//   Bit  [3]   : Global Trigger
module system_controller (
    input  logic              clk_i,
    input  logic              rstn_i,
    output logic signed [2:0] mode_o,
    output logic              global_trigger_o,
    
    input  logic [19:0]       sys_addr,
    input  logic [31:0]       sys_wdata,
    input  logic              sys_wen,
    input  logic              sys_ren,
    output logic [31:0]       sys_rdata,
    output logic              sys_err,
    output logic              sys_ack
);

// --- WRITE LOGIC ---
always @(posedge clk_i) begin
    if (~rstn_i) begin
        mode_o           <= 3'sd0;
        global_trigger_o <= 1'b0;
        sys_ack          <= 1'b0;
    end else begin
        // Acknowledge any read or write request
        sys_ack <= sys_wen | sys_ren;
        
        if (sys_wen) begin
            if (sys_addr[19:0] == 20'h00) begin
                mode_o           <= sys_wdata[2:0];
                global_trigger_o <= sys_wdata[3];
            end
        end
    end
end

// --- READ LOGIC ---
always_comb begin
    sys_rdata = 32'h0; // Default to 0 to prevent latching
    
    if (sys_ren) begin
        if (sys_addr[19:0] == 20'h00) begin
            // Concatenate: 28 padding zeros + 1-bit trigger + 3-bit mode = 32 bits
            sys_rdata = {28'h0, global_trigger_o, mode_o};
        end
    end
end

assign sys_err = 1'b0; // No bus errors generated
endmodule