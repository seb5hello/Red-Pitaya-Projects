////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Timestamp Bounce Filter & PID Trigger Generator
////////////////////////////////////////////////////////////////////////////////
module timestamp_filter (
    input  logic        clk_i,
    input  logic        rstn_i,
    input  logic        arm_i,
    
    // Config Inputs (From AXI)
    input  logic [1:0]  filter_mode,      // 0: Bypass, 1: Strict, 2: Smart Sweep
    input  logic [3:0]  expected_peaks,
    input  logic [31:0] merge_threshold,
    
    // Inputs from Raw Timestamp Logic
    input  logic        raw_done,
    input  logic [3:0]  raw_peak_count,
    input  logic [31:0] raw_ts_1, raw_ts_2, raw_ts_3, raw_ts_4,
    input  logic [31:0] raw_ts_5, raw_ts_6, raw_ts_7, raw_ts_8,
    
    // Outputs to AXI Wrapper & PID
    output logic        filter_done,
    output logic        pid_trigger,
    output logic [1:0]  filter_status,    // 00: OK, 01: BYPASS, 10: TOO_FEW, 11: TOO_MANY
    output logic [3:0]  filt_peak_count,
    output logic [31:0] filt_ts_1, filt_ts_2, filt_ts_3, filt_ts_4,
    output logic [31:0] filt_ts_5, filt_ts_6, filt_ts_7, filt_ts_8
);

    // Expanded Pipelined State Machine
    localparam [2:0] IDLE         = 3'd0;
    localparam [2:0] EVALUATE     = 3'd1;
    localparam [2:0] SWEEP_READ   = 3'd2;
    localparam [2:0] SWEEP_EVAL   = 3'd3;
    localparam [2:0] SWEEP_SHIFT  = 3'd4;
    
    logic [2:0] state;
    
    // Internal Working Registers
    logic [31:0] work_ts [0:7];
    logic [3:0]  work_count;
    logic [3:0]  idx;
    
    // NEW: Pipeline Registers to break the timing path
    logic [31:0] val_cur;
    logic [31:0] val_prev;

    // Helper task to map raw ports to array
    task load_raw();
        work_ts[0] <= raw_ts_1; work_ts[1] <= raw_ts_2;
        work_ts[2] <= raw_ts_3; work_ts[3] <= raw_ts_4;
        work_ts[4] <= raw_ts_5; work_ts[5] <= raw_ts_6;
        work_ts[6] <= raw_ts_7; work_ts[7] <= raw_ts_8;
        work_count <= raw_peak_count;
    endtask
    
    // Helper task to map array to output ports
    task output_results();
        filt_ts_1 <= work_ts[0]; filt_ts_2 <= work_ts[1];
        filt_ts_3 <= work_ts[2]; filt_ts_4 <= work_ts[3];
        filt_ts_5 <= work_ts[4]; filt_ts_6 <= work_ts[5];
        filt_ts_7 <= work_ts[6]; filt_ts_8 <= work_ts[7];
        filt_peak_count <= work_count;
    endtask

    always_ff @(posedge clk_i) begin
        if (~rstn_i || ~arm_i) begin
            state           <= IDLE;
            filter_done     <= 1'b0;
            pid_trigger     <= 1'b0;
            filter_status   <= 2'b00;
            filt_peak_count <= 4'h0;
            idx             <= 4'h1;
            val_cur         <= 32'h0;
            val_prev        <= 32'h0;
            
            for (int i=0; i<8; i++) work_ts[i] <= 32'h0;
            output_results();
        end else begin
            // Default 1-cycle pulses
            filter_done <= 1'b0;
            pid_trigger <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (raw_done) begin
                        load_raw();
                        
                        if (filter_mode == 2'd0) begin
                            // MODE 0: BYPASS
                            filter_status <= 2'b01;
                            filter_done   <= 1'b1;
                            pid_trigger   <= 1'b1;
                            output_results();
                            
                        end else if (filter_mode == 2'd1) begin
                            // MODE 1: STRICT VALIDATION
                            state <= EVALUATE;
                            
                        end else begin
                            // MODE 2: SMART SWEEP
                            if (raw_peak_count > expected_peaks) begin
                                state <= SWEEP_READ;
                                idx   <= 4'h1; // Start checking at index 1
                            end else begin
                                state <= EVALUATE;
                            end
                        end
                    end
                end
                
                // CYCLE 1: Read array values (Isolates MUX timing)
                SWEEP_READ: begin
                    if (idx < work_count) begin
                        val_cur  <= work_ts[idx];
                        val_prev <= work_ts[idx-1];
                        state    <= SWEEP_EVAL;
                    end else begin
                        state    <= EVALUATE;
                    end
                end
                
                // CYCLE 2: Subtract & Compare (Isolates Math timing)
                SWEEP_EVAL: begin
                    if ((val_cur - val_prev) <= merge_threshold) begin
                        state <= SWEEP_SHIFT;
                    end else begin
                        idx   <= idx + 1;
                        state <= SWEEP_READ;
                    end
                end
                
                // CYCLE 3: Shift Data (Isolates Flip-Flop CE timing)
                SWEEP_SHIFT: begin
                    // BOUNCE DETECTED: Shift everything left
                    for (int i = 0; i < 7; i++) begin
                        if (i >= idx) work_ts[i] <= work_ts[i+1];
                    end
                    work_ts[7] <= 32'h0;
                    work_count <= work_count - 1;
                    
                    // Do NOT increment idx, check the newly shifted value next
                    state <= SWEEP_READ;
                end
                
                EVALUATE: begin
                    // Final Check for Mode 1 & 2
                    if (work_count == expected_peaks) begin
                        filter_status <= 2'b00; // OK
                        pid_trigger   <= 1'b1;  // Fire PID
                    end else if (work_count < expected_peaks) begin
                        filter_status <= 2'b10; // TOO_FEW
                        pid_trigger   <= 1'b0;  // Block PID
                    end else begin
                        filter_status <= 2'b11; // TOO_MANY
                        pid_trigger   <= 1'b0;  // Block PID
                    end
                    
                    filter_done <= 1'b1;
                    output_results();
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule