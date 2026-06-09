////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE WRAPPER: Test Peak Generator (Memory mapped to SYS[4])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00: Delay for Peak 1 (32-bit)
// Offset 0x04: Delay for Peak 2 (32-bit)
// Offset 0x08: Delay for Peak 3 (32-bit)
// Offset 0x0C: Delay for Peak 4 (32-bit)
// Offset 0x10: Peak Amplitude (14-bit)
// Offset 0x14: Baseline Amplitude (14-bit)
// Offset 0x18: Pulse Width (32-bit, in clock cycles)
// Offset 0x1C: Status Register (Bit 0: Done)
module custom_test_peak_gen (
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

// Internal Registers
logic [31:0] dly_1, dly_2, dly_3, dly_4;
logic [13:0] peak_amp;
logic [13:0] base_amp;
logic [31:0] pulse_width;

// Core Status Signals
logic done;

// System Bus Write Interface
always @(posedge clk_i) begin
    if (~rstn_i) begin
        dly_1       <= 32'd100;
        dly_2       <= 32'd200;
        dly_3       <= 32'd300;
        dly_4       <= 32'd400;
        peak_amp    <= 14'h1FFF;
        base_amp    <= 14'h0000;
        pulse_width <= 32'd1;    // Default to 1 clock cycle
        sys_ack     <= 1'b0;
    end else begin
        sys_ack <= sys_wen | sys_ren;
        if (sys_wen) begin
            case (sys_addr[19:0])
                20'h00: dly_1       <= sys_wdata;
                20'h04: dly_2       <= sys_wdata;
                20'h08: dly_3       <= sys_wdata;
                20'h0C: dly_4       <= sys_wdata;
                20'h10: peak_amp    <= sys_wdata[13:0];
                20'h14: base_amp    <= sys_wdata[13:0];
                20'h18: pulse_width <= sys_wdata;
            endcase
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
                20'h00: sys_rdata <= dly_1;
                20'h04: sys_rdata <= dly_2;
                20'h08: sys_rdata <= dly_3;
                20'h0C: sys_rdata <= dly_4;
                20'h10: sys_rdata <= {18'h0, peak_amp};
                20'h14: sys_rdata <= {18'h0, base_amp};
                20'h18: sys_rdata <= pulse_width;
                20'h1C: sys_rdata <= {31'h0, done}; // Read-only status
                default: sys_rdata <= 32'h0;
            endcase
        end
    end
end

assign sys_err = 1'b0;

// Core Logic Instantiation
custom_test_peak_gen_core peak_gen_logic (
    .clk_i         (clk_i),
    .rstn_i        (rstn_i),
    .arm_i         (arm_i),
    .trigger_i     (trigger_i),
    .dly_1_i       (dly_1),
    .dly_2_i       (dly_2),
    .dly_3_i       (dly_3),
    .dly_4_i       (dly_4),
    .peak_amp_i    (peak_amp),
    .base_amp_i    (base_amp),
    .pulse_width_i (pulse_width),
    .done_o        (done),
    .dac_dat_o     (dac_dat_o)
);

endmodule