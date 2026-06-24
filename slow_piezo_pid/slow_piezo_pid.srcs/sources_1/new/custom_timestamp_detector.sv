////////////////////////////////////////////////////////////////////////////////
// WRAPPER MODULE: 8-Peak Timestamp & Software-Armed Bus Interface (SYS[3])
////////////////////////////////////////////////////////////////////////////////
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

    // -------------------------------------------------------------------------
    // Internal Output Wires (from Core Logic)
    // -------------------------------------------------------------------------
    logic               done_wire;
    logic [3:0]         peak_count_wire;
    logic [31:0]        ts_1_wire, ts_2_wire, ts_3_wire, ts_4_wire;
    logic [31:0]        ts_5_wire, ts_6_wire, ts_7_wire, ts_8_wire;

    // -------------------------------------------------------------------------
    // AXI Registers & Shadow Buffers
    // -------------------------------------------------------------------------
    logic signed [13:0] threshold_reg;
    
    logic               axi_trigger_req;
    logic               axi_data_ready;
    logic [3:0]         axi_peak_count;
    logic [31:0]        axi_ts_1, axi_ts_2, axi_ts_3, axi_ts_4;
    logic [31:0]        axi_ts_5, axi_ts_6, axi_ts_7, axi_ts_8;

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface & Synchronization
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            threshold_reg   <= 14'h0;
            sys_ack         <= 1'b0;
            sys_rdata       <= 32'h0;
            axi_trigger_req <= 1'b0;
            axi_data_ready  <= 1'b0;
            axi_peak_count  <= 4'h0;
            axi_ts_1 <= 0; axi_ts_2 <= 0; axi_ts_3 <= 0; axi_ts_4 <= 0;
            axi_ts_5 <= 0; axi_ts_6 <= 0; axi_ts_7 <= 0; axi_ts_8 <= 0;
            
        end else begin
            // Single-cycle bus acknowledgment
            sys_ack <= sys_wen | sys_ren;
            
            // ---------------------------------------------------------
            // Hardware Latch (Triggered by CPU request + Core Done)
            // ---------------------------------------------------------
            if (axi_trigger_req && done_wire) begin
                axi_ts_1 <= ts_1_wire;
                axi_ts_2 <= ts_2_wire;
                axi_ts_3 <= ts_3_wire;
                axi_ts_4 <= ts_4_wire;
                axi_ts_5 <= ts_5_wire;
                axi_ts_6 <= ts_6_wire;
                axi_ts_7 <= ts_7_wire;
                axi_ts_8 <= ts_8_wire;
                axi_peak_count <= peak_count_wire;
                
                axi_data_ready  <= 1'b1; // Flag data is safely latched
                axi_trigger_req <= 1'b0; // Auto-clear request
            end
            
            // ---------------------------------------------------------
            // AXI Write Path
            // ---------------------------------------------------------
            if (sys_wen) begin
                if (sys_addr[19:0] == 20'h00000) threshold_reg <= sys_wdata[13:0];
                if (sys_addr[19:0] == 20'h00028) begin
                    axi_trigger_req <= sys_wdata[0];
                    if (sys_wdata[0]) axi_data_ready <= 1'b0; // Clear ready flag on new request
                end
            end
            
            // ---------------------------------------------------------
            // AXI Read Path 
            // ---------------------------------------------------------
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00000: sys_rdata <= {18'h0, threshold_reg};
                    20'h00004: sys_rdata <= {26'h0, axi_trigger_req, axi_data_ready, axi_peak_count}; 
                    20'h00008: sys_rdata <= axi_ts_1;
                    20'h0000C: sys_rdata <= axi_ts_2;
                    20'h00010: sys_rdata <= axi_ts_3;
                    20'h00014: sys_rdata <= axi_ts_4;
                    20'h00018: sys_rdata <= axi_ts_5;
                    20'h0001C: sys_rdata <= axi_ts_6;
                    20'h00020: sys_rdata <= axi_ts_7;
                    20'h00024: sys_rdata <= axi_ts_8;
                    default:   sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    // No error handling implemented for this peripheral
    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Core Module Instantiations
    // -------------------------------------------------------------------------
    timestamp_logic i_timestamp_logic (
        .clk_i       (clk_i),
        .rstn_i      (rstn_i),
        .arm_i       (arm_i),
        .trigger_i   (trigger_i),
        .adc_dat_i   (adc_dat_i),
        .threshold   (threshold_reg),
        .done        (done_wire),
        .peak_count  (peak_count_wire),
        .ts_1        (ts_1_wire),
        .ts_2        (ts_2_wire),
        .ts_3        (ts_3_wire),
        .ts_4        (ts_4_wire),
        .ts_5        (ts_5_wire),
        .ts_6        (ts_6_wire),
        .ts_7        (ts_7_wire),
        .ts_8        (ts_8_wire)
    );

endmodule
