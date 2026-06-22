////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Window-Gated 4-Peak Timestamp Detector
////////////////////////////////////////////////////////////////////////////////
module timestamp_logic (
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    input  logic               trigger_i,
    
    // Physical/Analog Inputs
    input  logic signed [13:0] adc_dat_i,
    
    // Configuration Inputs
    input  logic signed [13:0] threshold,
    
    // Hardware Outputs
    output logic               done,
    output logic [2:0]         peak_count,
    output logic [31:0]        ts_1,
    output logic [31:0]        ts_2,
    output logic [31:0]        ts_3,
    output logic [31:0]        ts_4
);

    logic [31:0] counter;
    logic signed [13:0] prev_adc;
    logic        window_active;
    logic        trigger_delayed;
    logic        trigger_pe;

    // Internal "shadow" registers for high-speed tracking
    logic [31:0] ts_1_internal;
    logic [31:0] ts_2_internal;
    logic [31:0] ts_3_internal;
    logic [31:0] ts_4_internal;

    // Trigger Edge Detection
    always_ff @(posedge clk_i) begin
        if (~rstn_i) trigger_delayed <= 1'b0;
        else         trigger_delayed <= trigger_i;
    end
    assign trigger_pe = trigger_i && !trigger_delayed;

    // Main Gated Control Loop
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            counter       <= 0;
            prev_adc      <= 0;
            window_active <= 0;
            done          <= 0;
            peak_count    <= 0;
            
            ts_1_internal <= 0; ts_2_internal <= 0; 
            ts_3_internal <= 0; ts_4_internal <= 0;
            ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
        end else begin
            prev_adc <= adc_dat_i;
            
            if (~arm_i) begin
                counter       <= 0;
                window_active <= 0;
                done          <= 0;
                peak_count    <= 0;
                ts_1_internal <= 0; ts_2_internal <= 0; 
                ts_3_internal <= 0; ts_4_internal <= 0;
            end 
            else if (trigger_pe) begin
                if (!window_active) begin
                    // First Pulse: Reset and Launch Windows
                    window_active <= 1'b1;
                    counter       <= 0;
                    peak_count    <= 0;
                    done          <= 0;
                    ts_1_internal <= 0; ts_2_internal <= 0; 
                    ts_3_internal <= 0; ts_4_internal <= 0;
                end else begin
                    // Second Pulse: Forced Termination & Immediate Latch
                    window_active <= 1'b0;
                    done          <= 1'b1;
                    
                    ts_1          <= ts_1_internal;
                    ts_2          <= ts_2_internal;
                    ts_3          <= ts_3_internal;
                    ts_4          <= ts_4_internal;
                end
            end 
            else if (window_active) begin
                counter <= counter + 1;
                
                // Rising edge threshold detection
                if (adc_dat_i > threshold && prev_adc <= threshold) begin
                    case (peak_count)
                        3'd0: ts_1_internal <= counter;
                        3'd1: ts_2_internal <= counter;
                        3'd2: ts_3_internal <= counter;
                        3'd3: ts_4_internal <= counter;
                    endcase
                    
                    // Increment up to safe max boundary
                    if (peak_count < 3'd7) begin
                        peak_count <= peak_count + 1;
                    end
                end
            end
        end
    end

endmodule