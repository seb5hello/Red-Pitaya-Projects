////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE WRAPPER: 4-Peak Timestamp Detector (Memory mapped to SYS[3])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00: Threshold (14-bit signed)
// Offset 0x04: Status (Bit 0: Done, Bits 3:1: Current Peak Count)
// Offset 0x08: Timestamp 1
// Offset 0x0C: Timestamp 2
// Offset 0x10: Timestamp 3
// Offset 0x14: Timestamp 4
module custom_timestamp_detector (
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    input  logic               trigger_i,
    input  logic signed [13:0] adc_dat_i,
    
    // System Bus Interface
    input  logic [19:0]        sys_addr,
    input  logic [31:0]        sys_wdata,
    input  logic               sys_wen,
    input  logic               sys_ren,
    output logic [31:0]        sys_rdata,
    output logic               sys_err,
    output logic               sys_ack
);

// Internal Configurations (Writeable)
logic signed [13:0] threshold;

// Core Logic Outputs (Read-only)
logic        done;
logic [2:0]  peak_count;
logic [31:0] ts_1, ts_2, ts_3, ts_4;

// System Bus Write Interface
always @(posedge clk_i) begin
    if (~rstn_i) begin
        threshold <= 14'h0;
        sys_ack   <= 1'b0;
    end else begin
        sys_ack <= sys_wen | sys_ren;
        if (sys_wen) begin
            if (sys_addr[19:0] == 20'h00) threshold <= sys_wdata[13:0];
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
                20'h00: sys_rdata = {18'h0, threshold};
                20'h04: sys_rdata = {28'h0, peak_count, done}; 
                20'h08: sys_rdata = ts_1;
                20'h0C: sys_rdata = ts_2;
                20'h10: sys_rdata = ts_3;
                20'h14: sys_rdata = ts_4;
                default: sys_rdata = 32'h0;
            endcase
        end
    end
end

assign sys_err = 1'b0;

// Core Logic Instantiation
custom_timestamp_detector_core timestamp_detector_logic (
    .clk_i        (clk_i),
    .rstn_i       (rstn_i),
    .arm_i        (arm_i),
    .trigger_i    (trigger_i),
    .adc_dat_i    (adc_dat_i),
    .threshold_i  (threshold),
    .done_o       (done),
    .peak_count_o (peak_count),
    .ts_1_o       (ts_1),
    .ts_2_o       (ts_2),
    .ts_3_o       (ts_3),
    .ts_4_o       (ts_4)
);

endmodule