////////////////////////////////////////////////////////////////////////////////
// CUSTOM MODULE CORE: 4-Peak Timestamp Detector Logic
////////////////////////////////////////////////////////////////////////////////
module custom_timestamp_detector_core (
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    input  logic               trigger_i,
    input  logic signed [13:0] adc_dat_i,
    
    // Configuration Inputs
    input  logic signed [13:0] threshold_i,
    
    // Status & Data Outputs (Read by AXI registers)
    output logic               done_o,
    output logic [2:0]         peak_count_o,
    output logic [31:0]        ts_1_o,
    output logic [31:0]        ts_2_o,
    output logic [31:0]        ts_3_o,
    output logic [31:0]        ts_4_o
);

logic [31:0] counter;
logic signed [13:0] prev_adc;
logic running;

// Timestamp & Multi-Peak Detection Logic driven by external arm_i and trigger_i
always @(posedge clk_i) begin
    if (~rstn_i) begin
        counter      <= 0;
        prev_adc     <= 0;
        running      <= 0;
        done_o       <= 0;
        peak_count_o <= 0;
        ts_1_o <= 0; ts_2_o <= 0; ts_3_o <= 0; ts_4_o <= 0;
    end else begin
        prev_adc <= adc_dat_i;
        
        if (~arm_i) begin
            counter      <= 0;
            running      <= 0;
            done_o       <= 0;
            peak_count_o <= 0;
            ts_1_o <= 0; ts_2_o <= 0; ts_3_o <= 0; ts_4_o <= 0;
            
        end else if (trigger_i && ~running && ~done_o) begin
            running      <= 1;
            counter      <= 0;
            peak_count_o <= 0;
            done_o       <= 0;
            
        end else if (running) begin
            counter <= counter + 1;
            
            // Rising edge trigger calculation
            if (adc_dat_i > threshold_i && prev_adc <= threshold_i) begin
                case (peak_count_o)
                    3'd0: ts_1_o <= counter;
                    3'd1: ts_2_o <= counter;
                    3'd2: ts_3_o <= counter;
                    3'd3: ts_4_o <= counter;
                endcase
                
                peak_count_o <= peak_count_o + 1;
                
                if (peak_count_o == 3'd3) begin
                    running <= 1'b0;
                    done_o  <= 1'b1;
                end
            end
        end
    end
end
endmodule