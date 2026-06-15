////////////////////////////////////////////////////////////////////////////////
// WRAPPER MODULE: 4-Peak Timestamp Detector Bus Interface (SYS[3])
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

    // Internal Configuration Registers
    logic signed [13:0] threshold_reg;
    
    // Internal Output Wires (from Core Logic)
    logic               done_wire;
    logic [2:0]         peak_count_wire;
    logic [31:0]        ts_1_wire;
    logic [31:0]        ts_2_wire;
    logic [31:0]        ts_3_wire;
    logic [31:0]        ts_4_wire;

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            threshold_reg <= 14'h0;
            sys_ack       <= 1'b0;
            sys_rdata     <= 32'h0;
        end else begin
            sys_ack <= sys_wen | sys_ren;
            
            // Write Path
            if (sys_wen) begin
                if (sys_addr[19:0] == 20'h00) threshold_reg <= sys_wdata[13:0];
            end
            
            // Read Path (Registered)
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00:  sys_rdata <= {18'h0, threshold_reg};
                    20'h04:  sys_rdata <= {28'h0, peak_count_wire, done_wire}; 
                    20'h08:  sys_rdata <= ts_1_wire;
                    20'h0C:  sys_rdata <= ts_2_wire;
                    20'h10:  sys_rdata <= ts_3_wire;
                    20'h14:  sys_rdata <= ts_4_wire;
                    default: sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Core Logic Instantiation
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
        .ts_4        (ts_4_wire)
    );

endmodule
