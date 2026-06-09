////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE: Test Peak Generator (Memory mapped to SYS[4])
////////////////////////////////////////////////////////////////////////////////
// Offset 0x00 to 0x0C: Delays for Peaks 1-4 (32-bit)
// Offset 0x10: Peak Amplitude (14-bit)
// Offset 0x14: Baseline Amplitude (14-bit)
// Offset 0x18: Pulse Width (32-bit clock cycles)
module custom_test_peak_gen (
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

logic [31:0] dly_1, dly_2, dly_3, dly_4;
logic [13:0] peak_amp;
logic [13:0] base_amp;
logic [31:0] pulse_width;

logic [31:0] counter;
logic running;

// System Bus Write Interface
always @(posedge clk_i) begin
    if (~rstn_i) begin
        dly_1       <= 32'd100; // Default delays
        dly_2       <= 32'd200;
        dly_3       <= 32'd300;
        dly_4       <= 32'd400;
        peak_amp    <= 14'h1FFF; // High peak
        base_amp    <= 14'h0000; // Zero baseline
        pulse_width <= 32'd10;   // Default 10 cycles (80ns) to survive analog filter
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
always_comb begin
    sys_rdata = 32'h0;
    if (sys_ren) begin
        case (sys_addr[19:0])
            20'h00: sys_rdata = dly_1;
            20'h04: sys_rdata = dly_2;
            20'h08: sys_rdata = dly_3;
            20'h0C: sys_rdata = dly_4;
            20'h10: sys_rdata = {18'h0, peak_amp};
            20'h14: sys_rdata = {18'h0, base_amp};
            20'h18: sys_rdata = pulse_width;
            default: sys_rdata = 32'h0;
        endcase
    end
end
assign sys_err = 1'b0;

// Pulse Generation Logic (Updated for Repeating Triggers)
always @(posedge clk_i) begin
    if (~rstn_i) begin
        dac_dat_o <= 14'h0;
        counter   <= 0;
        running   <= 0;
    end else begin
        if (~arm_i) begin
            counter   <= 0;
            running   <= 0;
            dac_dat_o <= base_amp;
            
        // REMOVED "~running". A new trigger always resets the timeline.
        end else if (trigger_i) begin 
            running   <= 1;
            counter   <= 0;
            dac_dat_o <= base_amp;
            
        end else if (running) begin
            counter <= counter + 1;
            
            // Output peak_amp if the counter is within the dynamic pulse width window
            if ((counter >= dly_1 && counter < dly_1 + pulse_width) || 
                (counter >= dly_2 && counter < dly_2 + pulse_width) || 
                (counter >= dly_3 && counter < dly_3 + pulse_width) || 
                (counter >= dly_4 && counter < dly_4 + pulse_width)) begin
                dac_dat_o <= peak_amp;
            end else begin
                dac_dat_o <= base_amp;
            end
        end
    end
end

endmodule