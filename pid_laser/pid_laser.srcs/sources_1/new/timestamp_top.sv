////////////////////////////////////////////////////////////////////////////////
// WRAPPER MODULE: 8-Peak Timestamp & Smart Filter Interface (SYS[3])
////////////////////////////////////////////////////////////////////////////////
module timestamp_top (
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    
    // Split Triggers
    input  logic               trigger_start_i,
    input  logic               trigger_max_i,
    
    input  logic signed [13:0] adc_dat_i,
    
    // Outputs to PID Controller / Hardware
    output logic               pid_trigger_o,
    output logic [3:0]         filt_peak_count_o,
    output logic [31:0]        filt_ts_1_o, filt_ts_2_o, filt_ts_3_o, filt_ts_4_o,
    output logic [31:0]        filt_ts_5_o, filt_ts_6_o, filt_ts_7_o, filt_ts_8_o,
    
    // System Bus Interface
    input  logic [19:0]        sys_addr,
    input  logic [31:0]        sys_wdata,
    input  logic               sys_wen,
    input  logic               sys_ren,
    output logic [31:0]        sys_rdata,
    output logic               sys_err,
    output logic               sys_ack
);

    // -------------------------------------------------------------------------
    // Internal Wires (Raw Logic -> Filter -> Latch)
    // -------------------------------------------------------------------------
    // Raw Output Wires
    logic        raw_done_wire;
    logic        preempted_wire;
    logic [3:0]  raw_peak_count_wire;
    logic [31:0] raw_ts_1, raw_ts_2, raw_ts_3, raw_ts_4;
    logic [31:0] raw_ts_5, raw_ts_6, raw_ts_7, raw_ts_8;
    
    // Filtered Internal Wires (for AXI Latch)
    logic        filter_done_wire;
    logic [1:0]  filter_status_wire;

    // -------------------------------------------------------------------------
    // AXI Config Registers
    // -------------------------------------------------------------------------
    logic signed [13:0] threshold_reg;
    logic [31:0]        offset_reg;
    logic [31:0]        filter_mode_reg;
    logic [31:0]        expected_peaks_reg;
    logic [31:0]        merge_threshold_reg;

    // -------------------------------------------------------------------------
    // AXI Shadow Latch (Read-Only Data)
    // -------------------------------------------------------------------------
    logic               axi_trigger_req;
    logic               axi_data_ready;
    logic               axi_preempted;
    logic [1:0]         axi_filter_status;
    logic [3:0]         axi_peak_count;
    logic [31:0]        axi_ts_1, axi_ts_2, axi_ts_3, axi_ts_4;
    logic [31:0]        axi_ts_5, axi_ts_6, axi_ts_7, axi_ts_8;

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface & Synchronization
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            threshold_reg       <= 14'h0;
            offset_reg          <= 32'h0;
            filter_mode_reg     <= 32'h0;
            expected_peaks_reg  <= 32'd2;
            merge_threshold_reg <= 32'd50;
            
            sys_ack             <= 1'b0;
            sys_rdata           <= 32'h0;
            
            axi_trigger_req     <= 1'b0;
            axi_data_ready      <= 1'b0;
            axi_preempted       <= 1'b0;
            axi_filter_status   <= 2'b00;
            axi_peak_count      <= 4'h0;
            
            axi_ts_1 <= 0; axi_ts_2 <= 0; axi_ts_3 <= 0; axi_ts_4 <= 0;
            axi_ts_5 <= 0; axi_ts_6 <= 0; axi_ts_7 <= 0; axi_ts_8 <= 0;
        end else begin
            sys_ack <= sys_wen | sys_ren;
            
            // Hardware Latch (Triggered by CPU request + Filter Done)
            if (axi_trigger_req && filter_done_wire) begin
                axi_ts_1 <= filt_ts_1_o; axi_ts_2 <= filt_ts_2_o;
                axi_ts_3 <= filt_ts_3_o; axi_ts_4 <= filt_ts_4_o;
                axi_ts_5 <= filt_ts_5_o; axi_ts_6 <= filt_ts_6_o;
                axi_ts_7 <= filt_ts_7_o; axi_ts_8 <= filt_ts_8_o;
                
                axi_peak_count    <= raw_peak_count_wire;
                axi_filter_status <= filter_status_wire;
                axi_preempted     <= preempted_wire; 
                
                axi_data_ready    <= 1'b1; 
                axi_trigger_req   <= 1'b0; // Auto-clear request
            end
            
            // AXI Write Path
            if (sys_wen) begin
                if (sys_addr[19:0] == 20'h00) threshold_reg <= sys_wdata[13:0];
                if (sys_addr[19:0] == 20'h28) begin
                    axi_trigger_req <= sys_wdata[0];
                    if (sys_wdata[0]) axi_data_ready <= 1'b0; 
                end
                if (sys_addr[19:0] == 20'h2C) offset_reg          <= sys_wdata;
                if (sys_addr[19:0] == 20'h30) filter_mode_reg     <= sys_wdata;
                if (sys_addr[19:0] == 20'h34) expected_peaks_reg  <= sys_wdata;
                if (sys_addr[19:0] == 20'h38) merge_threshold_reg <= sys_wdata;
            end
            
            // AXI Read Path 
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00: sys_rdata <= {18'h0, threshold_reg};
                    20'h04: sys_rdata <= {23'h0, axi_filter_status, axi_preempted, axi_trigger_req, axi_data_ready, axi_peak_count}; 
                    20'h28: sys_rdata <= {31'h0, axi_trigger_req};
                    20'h2C: sys_rdata <= offset_reg;
                    20'h30: sys_rdata <= filter_mode_reg;
                    20'h34: sys_rdata <= expected_peaks_reg;
                    20'h38: sys_rdata <= merge_threshold_reg;
                    
                    20'h40: sys_rdata <= axi_ts_1;
                    20'h44: sys_rdata <= axi_ts_2;
                    20'h48: sys_rdata <= axi_ts_3;
                    20'h4C: sys_rdata <= axi_ts_4;
                    20'h50: sys_rdata <= axi_ts_5;
                    20'h54: sys_rdata <= axi_ts_6;
                    20'h58: sys_rdata <= axi_ts_7;
                    20'h5C: sys_rdata <= axi_ts_8;
                    default: sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Core Module Instantiations
    // -------------------------------------------------------------------------
    
    // 1. Raw Detection Logic
    timestamp_logic i_timestamp_logic (
        .clk_i           (clk_i),
        .rstn_i          (rstn_i),
        .arm_i           (arm_i),
        .trigger_start_i (trigger_start_i),
        .trigger_max_i   (trigger_max_i),
        .adc_dat_i       (adc_dat_i),
        .threshold       (threshold_reg),
        .offset_val      (offset_reg),
        
        .done            (raw_done_wire),
        .preempted_o     (preempted_wire),
        .peak_count_out  (raw_peak_count_wire),
        .ts_1 (raw_ts_1), .ts_2 (raw_ts_2), .ts_3 (raw_ts_3), .ts_4 (raw_ts_4),
        .ts_5 (raw_ts_5), .ts_6 (raw_ts_6), .ts_7 (raw_ts_7), .ts_8 (raw_ts_8)
    );

    // 2. Smart Sweep Filter & PID Trigger
    timestamp_filter i_timestamp_filter (
        .clk_i           (clk_i),
        .rstn_i          (rstn_i),
        .arm_i           (arm_i),
        
        .filter_mode     (filter_mode_reg[1:0]),
        .expected_peaks  (expected_peaks_reg[3:0]),
        .merge_threshold (merge_threshold_reg),
        
        .raw_done        (raw_done_wire),
        .raw_peak_count  (raw_peak_count_wire),
        .raw_ts_1 (raw_ts_1), .raw_ts_2 (raw_ts_2), .raw_ts_3 (raw_ts_3), .raw_ts_4 (raw_ts_4),
        .raw_ts_5 (raw_ts_5), .raw_ts_6 (raw_ts_6), .raw_ts_7 (raw_ts_7), .raw_ts_8 (raw_ts_8),
        
        .filter_done     (filter_done_wire),
        .pid_trigger     (pid_trigger_o),
        .filter_status   (filter_status_wire),
        .filt_peak_count (filt_peak_count_o),
        
        // Mapped directly to the module's output ports
        .filt_ts_1 (filt_ts_1_o), .filt_ts_2 (filt_ts_2_o), .filt_ts_3 (filt_ts_3_o), .filt_ts_4 (filt_ts_4_o),
        .filt_ts_5 (filt_ts_5_o), .filt_ts_6 (filt_ts_6_o), .filt_ts_7 (filt_ts_7_o), .filt_ts_8 (filt_ts_8_o)
    );

endmodule