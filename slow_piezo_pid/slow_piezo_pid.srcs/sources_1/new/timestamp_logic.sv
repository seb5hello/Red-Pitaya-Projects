////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Window-Gated 8-Peak Timestamp Detector (2-Trigger Window)
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
    output logic [3:0]         peak_count, // Expanded to 4 bits (0-8)
    output logic [31:0]        ts_1, ts_2, ts_3, ts_4,
    output logic [31:0]        ts_5, ts_6, ts_7, ts_8
);

    logic [31:0] counter;
    logic signed [13:0] prev_adc;
    logic        window_active;
    logic        trigger_delayed;
    logic        trigger_pe;
    logic [1:0]  trigger_state; // Tracks Trigger 1, 2, and 3

    // Internal "shadow" registers for high-speed tracking
    logic [31:0] ts_1_internal, ts_2_internal, ts_3_internal, ts_4_internal;
    logic [31:0] ts_5_internal, ts_6_internal, ts_7_internal, ts_8_internal;

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
            trigger_state <= 0;
            ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0; ts_4_internal <= 0;
            ts_5_internal <= 0; ts_6_internal <= 0; ts_7_internal <= 0; ts_8_internal <= 0;
            ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
            ts_5 <= 0; ts_6 <= 0; ts_7 <= 0; ts_8 <= 0;
        end else begin
            prev_adc <= adc_dat_i;
            done     <= 1'b0; // Done is a single-cycle pulse

            if (~arm_i) begin
                counter       <= 0;
                window_active <= 0;
                peak_count    <= 0;
                trigger_state <= 0;
                ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0; ts_4_internal <= 0;
                ts_5_internal <= 0; ts_6_internal <= 0; ts_7_internal <= 0; ts_8_internal <= 0;
                ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
                ts_5 <= 0; ts_6 <= 0; ts_7 <= 0; ts_8 <= 0;
                
            end else if (trigger_pe) begin
                if (!window_active) begin
                    // First Trigger: Reset and Launch Window
                    window_active <= 1'b1;
                    trigger_state <= 2'd1;
                    counter       <= 0;
                    peak_count    <= 0;
                    ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0; ts_4_internal <= 0;
                    ts_5_internal <= 0; ts_6_internal <= 0; ts_7_internal <= 0; ts_8_internal <= 0;
                    
                end else begin
                    if (trigger_state == 2'd1) begin
                        // Second Trigger: Ignore and keep counting
                        trigger_state <= 2'd2;
                        
                    end else if (trigger_state == 2'd2) begin
                        // Third Trigger: Latch outputs, pulse done, and instantly restart cycle
                        done <= 1'b1;
                        
                        ts_1 <= ts_1_internal; ts_2 <= ts_2_internal; 
                        ts_3 <= ts_3_internal; ts_4 <= ts_4_internal;
                        ts_5 <= ts_5_internal; ts_6 <= ts_6_internal; 
                        ts_7 <= ts_7_internal; ts_8 <= ts_8_internal;
                        
                        // Start next cycle implicitly (This acts as Trigger 1 for the next round)
                        trigger_state <= 2'd1;
                        counter       <= 0;
                        peak_count    <= 0;
                        ts_1_internal <= 0; ts_2_internal <= 0; ts_3_internal <= 0; ts_4_internal <= 0;
                        ts_5_internal <= 0; ts_6_internal <= 0; ts_7_internal <= 0; ts_8_internal <= 0;
                    end
                end
                
            end else if (window_active) begin
                counter <= counter + 1;
                
                // Rising edge threshold detection
                if (adc_dat_i > threshold && prev_adc <= threshold) begin
                    case (peak_count)
                        4'd0: ts_1_internal <= counter;
                        4'd1: ts_2_internal <= counter;
                        4'd2: ts_3_internal <= counter;
                        4'd3: ts_4_internal <= counter;
                        4'd4: ts_5_internal <= counter;
                        4'd5: ts_6_internal <= counter;
                        4'd6: ts_7_internal <= counter;
                        4'd7: ts_8_internal <= counter;
                    endcase
                    
                    // Increment up to safe max boundary of 8
                    if (peak_count < 4'd8) begin
                        peak_count <= peak_count + 1;
                    end
                end
            end
        end
    end

endmodule
