`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// RED PITAYA CUSTOM ARCHITECTURE: Simulation Testbench (Mirrored & Filtered)
////////////////////////////////////////////////////////////////////////////////

module test_bench();

    // -------------------------------------------------------------------------
    // Clock and Reset Setup (125 MHz = 8ns period)
    // -------------------------------------------------------------------------
    logic clk;
    logic rstn;
    
    initial begin
        clk = 0;
        forever #4 clk = ~clk; // 4ns high, 4ns low
    end

    // -------------------------------------------------------------------------
    // Global Control Signals
    // -------------------------------------------------------------------------
    logic global_arm;
    logic peak_arm;
    logic master_trigger;
    
    // Split cascaded triggers
    logic cascaded_trigger_start; 
    logic cascaded_trigger_max;   

    // -------------------------------------------------------------------------
    // Module Configuration Parameters
    // -------------------------------------------------------------------------
    // Ramp Generator Config
    logic [13:0] ramp_min_val;
    logic [13:0] ramp_max_val;
    logic [31:0] ramp_period_val; 
    logic [13:0] ramp_dac_out;    
    logic        continuos;

    // Timestamp Detector Config
    logic signed [13:0] det_threshold;
    logic [31:0]        det_offset_val; 
    logic               raw_done;
    logic               det_preempted;  
    logic [3:0]         raw_peak_count; 
    logic [31:0]        raw_ts_1, raw_ts_2, raw_ts_3, raw_ts_4;
    logic [31:0]        raw_ts_5, raw_ts_6, raw_ts_7, raw_ts_8;

    // NEW: Filter Config & Outputs
    logic [1:0]         filter_mode;
    logic [3:0]         expected_peaks;
    logic [31:0]        merge_threshold;
    
    logic               filter_done;
    logic               pid_trigger;
    logic [1:0]         filter_status;
    logic [3:0]         filt_peak_count;
    logic [31:0]        filt_ts_1, filt_ts_2, filt_ts_3, filt_ts_4;
    logic [31:0]        filt_ts_5, filt_ts_6, filt_ts_7, filt_ts_8;

    // Test Peak Generator Config
    logic [31:0] test_dly_1, test_dly_2, test_dly_3, test_dly_4;
    logic [13:0] test_peak_amp, test_base_amp;
    logic [31:0] test_pulse_width;
    
    // Internal Loopback (DAC B out -> ADC A in)
    logic signed [13:0] loopback_signal;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiations
    // -------------------------------------------------------------------------
    
    // 1. Ramp Logic 
    ramp_logic dut_ramp (
        .clk_i           (clk),
        .rstn_i          (rstn),
        .arm_i           (global_arm),
        .trigger_i       (master_trigger),  
        .min_val         (ramp_min_val),
        .max_val         (ramp_max_val),
        .period_val      (ramp_period_val), 
        .continuous_en   (continuos), 
        .trigger_start_o (cascaded_trigger_start), 
        .trigger_max_o   (cascaded_trigger_max),   
        .dac_dat_o       (ramp_dac_out)
    );

    // 2. Test Peak Logic (Mirrored Pulse Generation)
    test_peak_logic dut_test_gen (
        .clk_i           (clk),
        .rstn_i          (rstn),
        .arm_i           (peak_arm),
        .trigger_start_i (cascaded_trigger_start), 
        .trigger_max_i   (cascaded_trigger_max),   
        .dly_1           (test_dly_1),
        .dly_2           (test_dly_2),
        .dly_3           (test_dly_3),
        .dly_4           (test_dly_4),
        .peak_amp        (test_peak_amp),
        .base_amp        (test_base_amp),
        .pulse_width     (test_pulse_width),
        .dac_dat_o       (loopback_signal)   
    );

    // 3. Timestamp Logic (Raw Detection)
    timestamp_logic dut_timestamp (
        .clk_i           (clk),
        .rstn_i          (rstn),
        .arm_i           (global_arm),
        .trigger_start_i (cascaded_trigger_start), 
        .trigger_max_i   (cascaded_trigger_max),   
        .adc_dat_i       (loopback_signal),  
        .threshold       (det_threshold),
        .offset_val      (det_offset_val),         
        .done            (raw_done),
        .preempted_o     (det_preempted),          
        .peak_count_out  (raw_peak_count),         
        .ts_1 (raw_ts_1), .ts_2 (raw_ts_2), .ts_3 (raw_ts_3), .ts_4 (raw_ts_4),
        .ts_5 (raw_ts_5), .ts_6 (raw_ts_6), .ts_7 (raw_ts_7), .ts_8 (raw_ts_8)
    );

    // 4. NEW: Timestamp Filter (Smart Sweep)
    timestamp_filter dut_filter (
        .clk_i           (clk),
        .rstn_i          (rstn),
        .arm_i           (global_arm),
        .filter_mode     (filter_mode),
        .expected_peaks  (expected_peaks),
        .merge_threshold (merge_threshold),
        
        .raw_done        (raw_done),
        .raw_peak_count  (raw_peak_count),
        .raw_ts_1 (raw_ts_1), .raw_ts_2 (raw_ts_2), .raw_ts_3 (raw_ts_3), .raw_ts_4 (raw_ts_4),
        .raw_ts_5 (raw_ts_5), .raw_ts_6 (raw_ts_6), .raw_ts_7 (raw_ts_7), .raw_ts_8 (raw_ts_8),
        
        .filter_done     (filter_done),
        .pid_trigger     (pid_trigger),
        .filter_status   (filter_status),
        .filt_peak_count (filt_peak_count),
        .filt_ts_1 (filt_ts_1), .filt_ts_2 (filt_ts_2), .filt_ts_3 (filt_ts_3), .filt_ts_4 (filt_ts_4),
        .filt_ts_5 (filt_ts_5), .filt_ts_6 (filt_ts_6), .filt_ts_7 (filt_ts_7), .filt_ts_8 (filt_ts_8)
    );

    // -------------------------------------------------------------------------
    // Safety Watchdog Timer
    // -------------------------------------------------------------------------
    initial begin
        #50000;
        $display("[%0t] ERROR: Watchdog Timeout! Simulation stuck.", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Main Stimulus Sequence
    // -------------------------------------------------------------------------
    initial begin
        // 1. Initialize Default States
        rstn           = 0;
        global_arm     = 0;
        master_trigger = 0;
        peak_arm = 0;

        // 2. Load Configuration 
        ramp_min_val    = 14'd205;
        ramp_max_val    = 14'd305;
        ramp_period_val = 32'd200; 
        continuos       = 1'b1; 
        
        det_threshold   = 14'd50;
        det_offset_val  = 32'd0; 
        
        // INTENTIONAL BOUNCE SIMULATION
        test_dly_1       = 32'd20;
        test_dly_2       = 32'd27;  // <--- BOUNCE! Only 2 cycles after dly_1
        test_dly_3       = 32'd70;
        test_dly_4       = 32'd160;
        test_peak_amp    = 14'd100;
        test_base_amp    = 14'd0;
        test_pulse_width = 32'd5;

        // Filter Configuration
        filter_mode     = 2'd2;     // 2 = Smart Sweep
        expected_peaks  = 4'd3;     // We expect 3 real peaks up, 3 down = 6 total
        merge_threshold = 32'd10;    // Any peak <= 5 cycles from previous is a bounce

        // 3. Release Reset
        #100;
        rstn = 1;
        #20;
        $display("[%0t] System Reset complete. Applying Arm signal...", $time);
        
        // 4. Arm the System
        @(posedge clk);
        global_arm = 1;
        peak_arm = 1;
        
        $display("[%0t] Waiting for Ramp Generator to reach min_val...", $time);
        wait(ramp_dac_out == ramp_min_val);
        #40; 
        
        $display("[%0t] System READY. Firing Master Trigger to Ramp Generator...", $time);
        // 5. Fire Master Trigger 
        @(posedge clk);
        master_trigger = 1;
        @(posedge clk);
        master_trigger = 0;
        
        // 6. Monitor Execution and Wait for Completion
        // We now wait for the FILTER to finish, not just the raw detector
        wait(filter_done == 1'b1);
        
        $display("[%0t] --------------------------------------------------", $time);
        $display("[%0t] Detection & Filtering Window Completed!", $time);
        $display("PID Trigger Fired : %b", pid_trigger);
        $display("Filter Status Flag: %b (00=OK, 01=BYPASS, 10=TOO_FEW, 11=TOO_MANY)", filter_status);
        $display("Preempted Flag    : %b", det_preempted);
        $display("--------------------------------------------------");
        $display("RAW PEAKS DETECTED : %0d (Expected Bounces caught)", raw_peak_count);
        $display("FILTERED PEAKS     : %0d", filt_peak_count);
        $display("--------------------------------------------------");
        $display("FILTERED TS_1  : %0d clock cycles", filt_ts_1);
        $display("FILTERED TS_2  : %0d clock cycles", filt_ts_2);
        $display("FILTERED TS_3  : %0d clock cycles", filt_ts_3);
        $display("FILTERED TS_4  : %0d clock cycles", filt_ts_4);
        $display("FILTERED TS_5  : %0d clock cycles", filt_ts_5);
        $display("FILTERED TS_6  : %0d clock cycles", filt_ts_6);
        $display("FILTERED TS_7  : %0d clock cycles", filt_ts_7);
        $display("FILTERED TS_8  : %0d clock cycles", filt_ts_8);
        $display("--------------------------------------------------");
        
        // 7. Test Soft Disarm Sequence
        #5000;
        $display("[%0t] Disarming system...", $time);
        peak_arm = 0;
        
//        wait(ramp_dac_out == 14'd0);
//        $display("[%0t] System safely disarmed to 0.", $time);
        
        #7000;
        $finish;
    end

    // -------------------------------------------------------------------------
    // Real-time event monitoring for Vivado TCL Console
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (cascaded_trigger_start) 
            $display("[%0t] EVENT: Cascaded Trigger START fired.", $time);
        if (cascaded_trigger_max) 
            $display("[%0t] EVENT: Cascaded Trigger MAX fired.", $time);
            
        if (raw_done)
            $display("[%0t] EVENT: Raw Detection Finished. Hitting Filter...", $time);
            
        if (pid_trigger)
            $display("[%0t] EVENT: PID Trigger Pulsed!", $time);
    end

endmodule