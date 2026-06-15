////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Pure 4-Peak Timestamp Detector Logic (AXI-Stable)
////////////////////////////////////////////////////////////////////////////////
module timestamp_logic (
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    input  logic               trigger_i,
    
    // Physical/Analog Inputs
    input  logic signed [13:0] adc_dat_i,
    
    // Configuration Inputs (Driven by Bus Interface)
    input  logic signed [13:0] threshold,
    
    // Hardware Outputs (Read by Bus Interface)
    output logic               done,
    output logic [2:0]         peak_count,
    output logic [31:0]        ts_1,
    output logic [31:0]        ts_2,
    output logic [31:0]        ts_3,
    output logic [31:0]        ts_4
);

    logic [31:0] counter;
    logic signed [13:0] prev_adc;
    logic running;

    // Internal "shadow" registers for high-speed tracking
    logic [31:0] ts_1_internal;
    logic [31:0] ts_2_internal;
    logic [31:0] ts_3_internal;

    // Timestamp & Multi-Peak Detection Logic
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            counter       <= 0;
            prev_adc      <= 0;
            running       <= 0;
            done          <= 0;
            peak_count    <= 0;
            
            // Clear both internal and output registers on reset
            ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0;
            ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
        end else begin
            prev_adc <= adc_dat_i;
            
            if (~arm_i) begin
                counter       <= 0;
                running       <= 0;
                done          <= 0;
                peak_count    <= 0;
                ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0;
                
                // Note: We DO NOT clear ts_1...ts_4 here. 
                // This keeps the outputs stable for the AXI bus between captures.
                
            end else if (trigger_i) begin
                running       <= 1;
                counter       <= 0;
                peak_count    <= 0;
                done          <= 0;
                ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0;
            end else if (running) begin
                counter <= counter + 1;
                
                // Rising edge threshold detection
                if (adc_dat_i > threshold && prev_adc <= threshold) begin
                    case (peak_count)
                        3'd0: ts_1_internal <= counter;
                        3'd1: ts_2_internal <= counter;
                        3'd2: ts_3_internal <= counter;
                    endcase
                    
                    peak_count <= peak_count + 1;
                    
                    if (peak_count == 3'd3) begin
                        running <= 1'b0;
                        done    <= 1'b1;
                        
                        // Transfer valid internal tracking registers to AXI outputs
                        ts_1 <= ts_1_internal;
                        ts_2 <= ts_2_internal;
                        ts_3 <= ts_3_internal;
                        
                        // For the 4th peak, assign directly from the counter.
                        // Because of non-blocking (<=) assignments, an internal register 
                        // wouldn't be ready until the next clock cycle.
                        ts_4 <= counter; 
                    end
                end
            end
        end
    end

endmodule