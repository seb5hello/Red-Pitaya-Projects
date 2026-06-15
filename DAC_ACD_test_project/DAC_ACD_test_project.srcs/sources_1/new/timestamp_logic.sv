////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Pure 4-Peak Timestamp Detector Logic
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

    // Timestamp & Multi-Peak Detection Logic
    always_ff @(posedge clk_i) begin
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
            end else if (trigger_i) begin
                running    <= 1;
                counter    <= 0;
                peak_count <= 0;
                done       <= 0;
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
