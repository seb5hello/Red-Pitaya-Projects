////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Window-Gated 8-Peak Timestamp Detector (Preemptive Offset)
////////////////////////////////////////////////////////////////////////////////
module timestamp_logic (
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    
    // Split Triggers
    input  logic               trigger_start_i,
    input  logic               trigger_max_i,
    
    // Physical/Analog Inputs
    input  logic signed [13:0] adc_dat_i,
    
    // Configuration Inputs
    input  logic signed [13:0] threshold,
    input  logic [31:0]        offset_val,
    
    // Hardware Outputs
    output logic               done,
    output logic               preempted_o,
    output logic [3:0]         peak_count_out, 
    output logic [31:0]        ts_1, ts_2, ts_3, ts_4,
    output logic [31:0]        ts_5, ts_6, ts_7, ts_8
);

    // State Machine
    localparam [1:0] IDLE        = 2'd0;
    localparam [1:0] DETECT_UP   = 2'd1;
    localparam [1:0] DETECT_DOWN = 2'd2;
    
    logic [1:0]  state;
    logic        window_active;
    logic [31:0] counter;
    logic [31:0] offset_countdown;
    logic signed [13:0] prev_adc;
    
    // Internal "shadow" registers 
    logic [3:0]  peak_count_internal;
    logic [31:0] ts_1_int, ts_2_int, ts_3_int, ts_4_int;
    logic [31:0] ts_5_int, ts_6_int, ts_7_int, ts_8_int;

    // Trigger Edge Detection
    logic trigger_start_d, trigger_max_d;
    logic trigger_start_pe, trigger_max_pe;

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            trigger_start_d <= 1'b0;
            trigger_max_d   <= 1'b0;
        end else begin
            trigger_start_d <= trigger_start_i;
            trigger_max_d   <= trigger_max_i;
        end
    end
    
    assign trigger_start_pe = trigger_start_i && !trigger_start_d;
    assign trigger_max_pe   = trigger_max_i   && !trigger_max_d;

    // Main Control Loop
    always_ff @(posedge clk_i) begin
        if (~rstn_i || ~arm_i) begin
            state               <= IDLE;
            window_active       <= 1'b0;
            counter             <= 0;
            offset_countdown    <= 0;
            prev_adc            <= 0;
            peak_count_internal <= 0;
            
            done                <= 1'b0;
            preempted_o         <= 1'b0;
            peak_count_out      <= 0;
            
            ts_1_int <= 0; ts_2_int <= 0; ts_3_int <= 0; ts_4_int <= 0;
            ts_5_int <= 0; ts_6_int <= 0; ts_7_int <= 0; ts_8_int <= 0;
            
            ts_1 <= 0; ts_2 <= 0; ts_3 <= 0; ts_4 <= 0;
            ts_5 <= 0; ts_6 <= 0; ts_7 <= 0; ts_8 <= 0;
        end else begin
            prev_adc <= adc_dat_i;
            done     <= 1'b0; // Default: Single cycle pulse
            
            // ---------------------------------------------------------
            // Peak Detection (Independent of State)
            // ---------------------------------------------------------
            if (window_active) begin
                counter <= counter + 1;
                
                // Rising edge threshold detection
                if (adc_dat_i > threshold && prev_adc <= threshold) begin
                    if (peak_count_internal < 4'd8) begin
                        peak_count_internal <= peak_count_internal + 1;
                    end
                    
                    case (peak_count_internal)
                        4'd0: ts_1_int <= counter;
                        4'd1: ts_2_int <= counter;
                        4'd2: ts_3_int <= counter;
                        4'd3: ts_4_int <= counter;
                        4'd4: ts_5_int <= counter;
                        4'd5: ts_6_int <= counter;
                        4'd6: ts_7_int <= counter;
                        4'd7: ts_8_int <= counter;
                    endcase
                end
            end

            // ---------------------------------------------------------
            // State Machine
            // ---------------------------------------------------------
            case (state)
                IDLE: begin
                    if (trigger_start_pe) begin
                        state               <= DETECT_UP;
                        window_active       <= 1'b1;
                        counter             <= 0;
                        peak_count_internal <= 0;
                        
                        ts_1_int <= 0; ts_2_int <= 0; ts_3_int <= 0; ts_4_int <= 0;
                        ts_5_int <= 0; ts_6_int <= 0; ts_7_int <= 0; ts_8_int <= 0;
                    end
                end
                
                DETECT_UP: begin
                    if (trigger_start_pe) begin
                        // PREEMPTION: Start fired again before max!
                        // Latch current data immediately
                        done           <= 1'b1;
                        preempted_o    <= 1'b1;
                        peak_count_out <= peak_count_internal;
                        ts_1 <= ts_1_int; ts_2 <= ts_2_int; ts_3 <= ts_3_int; ts_4 <= ts_4_int;
                        ts_5 <= ts_5_int; ts_6 <= ts_6_int; ts_7 <= ts_7_int; ts_8 <= ts_8_int;
                        
                        // Restart window instantly
                        counter             <= 0;
                        peak_count_internal <= 0;
                        
                        // FIX: Explicitly clear the shadow registers so ghost peaks don't bleed!
                        ts_1_int <= 0; ts_2_int <= 0; ts_3_int <= 0; ts_4_int <= 0;
                        ts_5_int <= 0; ts_6_int <= 0; ts_7_int <= 0; ts_8_int <= 0;
                        
                    end else if (trigger_max_pe) begin
                        state            <= DETECT_DOWN;
                        offset_countdown <= offset_val;
                        
                        // FIX: Removed the code that erased ts_x_int here so we retain UP peaks!
                    end
                end
                
                DETECT_DOWN: begin
                    if (trigger_start_pe) begin
                        // PREEMPTION: Start fired while waiting for offset countdown!
                        done           <= 1'b1;
                        preempted_o    <= 1'b1;
                        peak_count_out <= peak_count_internal;
                        ts_1 <= ts_1_int; ts_2 <= ts_2_int; ts_3 <= ts_3_int; ts_4 <= ts_4_int;
                        ts_5 <= ts_5_int; ts_6 <= ts_6_int; ts_7 <= ts_7_int; ts_8 <= ts_8_int;
                        
                        // Restart window instantly
                        state               <= DETECT_UP;
                        counter             <= 0;
                        peak_count_internal <= 0;
                        
                        // FIX: Explicitly clear the shadow registers so ghost peaks don't bleed!
                        ts_1_int <= 0; ts_2_int <= 0; ts_3_int <= 0; ts_4_int <= 0;
                        ts_5_int <= 0; ts_6_int <= 0; ts_7_int <= 0; ts_8_int <= 0;
                        
                    end else begin
                        if (offset_countdown == 0) begin
                            // NORMAL FINISH
                            done           <= 1'b1;
                            preempted_o    <= 1'b0;
                            peak_count_out <= peak_count_internal;
                            ts_1 <= ts_1_int; ts_2 <= ts_2_int; ts_3 <= ts_3_int; ts_4 <= ts_4_int;
                            ts_5 <= ts_5_int; ts_6 <= ts_6_int; ts_7 <= ts_7_int; ts_8 <= ts_8_int;
                            
                            window_active  <= 1'b0;
                            state          <= IDLE;
                        end else begin
                            offset_countdown <= offset_countdown - 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule