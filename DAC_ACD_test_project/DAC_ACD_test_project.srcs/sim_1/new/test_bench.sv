`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// RED PITAYA CUSTOM ARCHITECTURE: Simulation Testbench
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
    logic master_trigger;
    logic cascaded_trigger; // Trigger from Ramp Gen to other modules

    // -------------------------------------------------------------------------
    // Module Configuration Parameters
    // -------------------------------------------------------------------------
    // Ramp Generator Config
    logic [13:0] ramp_min_val;
    logic [13:0] ramp_max_val;
    logic [13:0] ramp_dac_out; // Unused in loopback, but driven by logic

    // Timestamp Detector Config
    logic signed [13:0] det_threshold;
    logic               det_done;
    logic [2:0]         det_peak_count;
    logic [31:0]        ts_1, ts_2, ts_3, ts_4;

    // Test Peak Generator Config
    logic [31:0] test_dly_1, test_dly_2, test_dly_3, test_dly_4;
    logic [13:0] test_peak_amp, test_base_amp;
    logic [31:0] test_pulse_width;
    
    // Internal Loopback (DAC B out -> ADC A in)
    logic signed [13:0] loopback_signal; 

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiations
    // -------------------------------------------------------------------------
    
    // 1. Ramp Logic (Master Trigger Receiver)
    ramp_logic dut_ramp (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .arm_i       (global_arm),
        .trigger_i   (master_trigger),   // Triggered by testbench sequence
        .min_val     (ramp_min_val),
        .max_val     (ramp_max_val),
        .trigger_out (cascaded_trigger), // Fires when ramp starts
        .dac_dat_o   (ramp_dac_out)
    );

    // 2. Test Peak Logic (Cascaded Trigger Receiver)
    test_peak_logic dut_test_gen (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .arm_i       (global_arm),
        .trigger_i   (cascaded_trigger), // Triggered by Ramp Gen
        .dly_1       (test_dly_1),
        .dly_2       (test_dly_2),
        .dly_3       (test_dly_3),
        .dly_4       (test_dly_4),
        .peak_amp    (test_peak_amp),
        .base_amp    (test_base_amp),
        .pulse_width (test_pulse_width),
        .dac_dat_o   (loopback_signal)   // Drives the internal loopback
    );

    // 3. Timestamp Logic (Cascaded Trigger Receiver)
    timestamp_logic dut_timestamp (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .arm_i       (global_arm),
        .trigger_i   (cascaded_trigger), // Triggered by Ramp Gen
        .adc_dat_i   (loopback_signal),  // Reads the internal loopback
        .threshold   (det_threshold),
        .done        (det_done),
        .peak_count  (det_peak_count),
        .ts_1        (ts_1),
        .ts_2        (ts_2),
        .ts_3        (ts_3),
        .ts_4        (ts_4)
    );

    // -------------------------------------------------------------------------
    // Main Stimulus Sequence
    // -------------------------------------------------------------------------
    initial begin
        // 1. Initialize Default States
        rstn           = 0;
        global_arm     = 0;
        master_trigger = 0;
        
        // 2. Load Configuration (Matching your Python API payload)
        ramp_min_val   = 14'd0;
        ramp_max_val   = 14'd100;
        
        det_threshold  = 14'd80;
        
        test_dly_1       = 32'd20;
        test_dly_2       = 32'd90;
        test_dly_3       = 32'd140;
        test_dly_4       = 32'd180;
        test_peak_amp    = 14'd100;
        test_base_amp    = 14'd0;
        test_pulse_width = 32'd10;

        // 3. Release Reset
        #100;
        rstn = 1;
        #20;
        
        $display("[%0t] System Reset complete. Applying Arm signal...", $time);
        
        // 4. Arm the System
        @(posedge clk);
        global_arm = 1;
        #40; // Wait a few clock cycles before triggering
        
        $display("[%0t] Firing Master Trigger to Ramp Generator...", $time);
        
        // 5. Fire Master Trigger (1 clock cycle pulse)
        @(posedge clk);
        master_trigger = 1;
        @(posedge clk);
        master_trigger = 0;
        
        // 6. Monitor Execution and Wait for Completion
        // We wait for the Timestamp Detector to assert the 'done' flag
        wait(det_done == 1'b1);
        
        $display("[%0t] All 4 Peaks Detected! Simulation Complete.", $time);
        $display("--------------------------------------------------");
        $display("Expected Delays: %0d, %0d, %0d, %0d", test_dly_1, test_dly_2, test_dly_3, test_dly_4);
        $display("Recorded TS_1  : %0d clock cycles", ts_1);
        $display("Recorded TS_2  : %0d clock cycles", ts_2);
        $display("Recorded TS_3  : %0d clock cycles", ts_3);
        $display("Recorded TS_4  : %0d clock cycles", ts_4);
        $display("--------------------------------------------------");
        
        // Let the simulation run for a few more cycles to observe the final state
        #5000;
        $finish;
    end

    // -------------------------------------------------------------------------
    // Optional: Real-time event monitoring for Vivado TCL Console
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (cascaded_trigger) 
            $display("[%0t] EVENT: Cascaded Trigger fired by Ramp Gen.", $time);
            
        if (dut_timestamp.adc_dat_i > det_threshold && dut_timestamp.prev_adc <= det_threshold && global_arm)
            $display("[%0t] EVENT: Threshold Crossed! Peak %0d detected.", $time, det_peak_count + 1);
    end

endmodule
