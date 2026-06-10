////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE: 4-Peak Timestamp Detector (Memory mapped to SYS[3])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00: Threshold (14-bit signed)
// Offset 0x04: Status (Bit 0: Done, Bits 3:1: Current Peak Count)
// Offset 0x08: Timestamp 1
// Offset 0x0C: Timestamp 2
// Offset 0x10: Timestamp 3
// Offset 0x14: Timestamp 4
module custom_timestamp_detector (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    input  logic signed [13:0] adc_dat_i,
    
    input  logic [19:0]   sys_addr,
    input  logic [31:0]   sys_wdata,
    input  logic          sys_wen,
    input  logic          sys_ren,
    output logic [31:0]   sys_rdata,
    output logic          sys_err,
    output logic          sys_ack
);

logic signed [13:0] threshold;
logic [31:0] counter;
logic signed [13:0] prev_adc;
logic running;
logic done;
logic [2:0] peak_count;
logic [31:0] ts_1, ts_2, ts_3, ts_4;

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

always_comb begin
    sys_rdata = 32'h0;
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
assign sys_err = 1'b0;

// Timestamp & Multi-Peak Detection Logic driven by external arm_i and trigger_i
always @(posedge clk_i) begin
    if (~rstn_i) begin
        counter    <= 0;
        prev_adc   <= 0;
        running    <= 0;
        done       <= 0;
        peak_count <= 0;
        ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
    end else begin
        prev_adc <= adc_dat_i;
        
        if (~arm_i) begin
            counter    <= 0;
            running    <= 0;
            done       <= 0;
            peak_count <= 0;
            ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
            
        // REMOVED "~running && ~done". A new trigger always resets the timeline.
        end else if (trigger_i) begin
            running    <= 1;
            counter    <= 0;
            peak_count <= 0;
            done       <= 0;
            // Note: Timestamps are naturally overwritten as new peaks are found, 
            // so we don't strictly need to zero them out here.
            
        end else if (running) begin
            counter <= counter + 1;
            
            // Rising edge threshold detection
            if (adc_dat_i > threshold && prev_adc <= threshold) begin
                case (peak_count)
                    3'd0: ts_1 <= counter;
                    3'd1: ts_2 <= counter;
                    3'd2: ts_3 <= counter;
                    3'd3: ts_4 <= counter;
                endcase
                
                peak_count <= peak_count + 1;
                
                if (peak_count == 3'd3) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                end
            end
        end
    end
end

endmodule