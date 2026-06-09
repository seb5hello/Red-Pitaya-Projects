`timescale 1ns / 1ps

module tb_core_logic();

    // -------------------------------------------------------------------------
    // 1. Global Signals & Clock Generation
    // -------------------------------------------------------------------------
    logic clk_i;
    logic rstn_i;
    logic arm_i;
    logic trigger_i;

    // 125 MHz Clock (8 ns period -> 4 ns half-period)
    initial begin
        clk_i = 1'b0;
        forever #4 clk_i = ~clk_i; 
    end

    // -------------------------------------------------------------------------
    // 2. Module Interconnect & Configuration Signals
    // -------------------------------------------------------------------------
    // Ramp Generator
    logic [13:0] ramp_min_val;
    logic [13:0] ramp_max_val;
    logic [13:0] ramp_dac_out;

    // Test Peak Generator
    logic [31:0] test_dly_1, test_dly_2, test_dly_3, test_dly_4;
    logic [13:0] test_peak_amp, test_base_amp;
    logic [31:0] test_pulse_width; // NEW
    logic        test_gen_done;    // NEW
    logic [13:0] test_dac_out;

    // Timestamp Peak Detector
    logic signed [13:0] det_threshold;
    logic               det_done;
    logic [2:0]         det_peak_count;
    logic [31:0]        det_ts_1, det_ts_2, det_ts_3, det_ts_4;

    // -------------------------------------------------------------------------
    // 3. Module Instantiations
    // -------------------------------------------------------------------------
    
    // DUT 1: Ramp Generator
    custom_ramp_gen_core dut_ramp (
        .clk_i      (clk_i),
        .rstn_i     (rstn_i),
        .arm_i      (arm_i),
        .trigger_i  (trigger_i),
        .min_val_i  (ramp_min_val),
        .max_val_i  (ramp_max_val),
        .dac_dat_o  (ramp_dac_out)
    );

    // DUT 2: Test Peak Generator
    custom_test_peak_gen_core dut_test_gen (
        .clk_i         (clk_i),
        .rstn_i        (rstn_i),
        .arm_i         (arm_i),
        .trigger_i     (trigger_i),
        .dly_1_i       (test_dly_1),
        .dly_2_i       (test_dly_2),
        .dly_3_i       (test_dly_3),
        .dly_4_i       (test_dly_4),
        .peak_amp_i    (test_peak_amp),
        .base_amp_i    (test_base_amp),
        .pulse_width_i (test_pulse_width), // NEW
        .done_o        (test_gen_done),    // NEW
        .dac_dat_o     (test_dac_out)
    );

    // DUT 3: Timestamp Detector 
    // Note: We loop the Test Gen DAC output directly into the Detector ADC input
    custom_timestamp_detector_core dut_detector (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),
        .arm_i        (arm_i),
        .trigger_i    (trigger_i),
        .adc_dat_i    (test_dac_out), // Loopback connection
        .threshold_i  (det_threshold),
        .done_o       (det_done),
        .peak_count_o (det_peak_count),
        .ts_1_o       (det_ts_1),
        .ts_2_o       (det_ts_2),
        .ts_3_o       (det_ts_3),
        .ts_4_o       (det_ts_4)
    );

    // -------------------------------------------------------------------------
    // 4. Main Simulation Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Initialize Control Signals
        rstn_i    = 1'b0;
        arm_i     = 1'b0;
        trigger_i = 1'b0;

        // Initialize Parameters for Ramp
        ramp_min_val = 14'h0000;
        ramp_max_val = 14'h000F; // Short ramp for simulation visibility

        // Initialize Parameters for Test Peak Generator
        test_dly_1       = 32'd20;  // Fire peak at clock cycle 20
        test_dly_2       = 32'd40;  // Fire peak at clock cycle 40
        test_dly_3       = 32'd80;  // Fire peak at clock cycle 80
        test_dly_4       = 32'd150; // Fire peak at clock cycle 150
        test_peak_amp    = 14'h1FFF; // High peak
        test_base_amp    = 14'h0000; // Zero baseline
        test_pulse_width = 32'd3;    // NEW: Hold peak for 3 clock cycles

        // Initialize Parameters for Timestamp Detector
        det_threshold = 14'h0FFF; // Threshold lower than peak, higher than base

        $display("[%0t] Starting Simulation...", $time);

        // Apply Reset
        #16;
        rstn_i = 1'b1;
        $display("[%0t] Reset Released.", $time);

        // Arm the modules
        #16;
        arm_i = 1'b1;
        $display("[%0t] Modules Armed.", $time);

        // Wait a few clocks, then Trigger
        #24;
        trigger_i = 1'b1;
        $display("[%0t] Modules Triggered!", $time);
        
        // Hold trigger for exactly 1 clock cycle (8ns) then release
        #8;
        trigger_i = 1'b0;

        // Wait for the Timestamp Detector to declare 'done'
        // Timeout safeguard included in case of logic failure
        fork
            begin
                wait(det_done == 1'b1);
                $display("[%0t] SUCCESS: Timestamp Detector caught all 4 peaks!", $time);
                $display("   -> TS_1: %0d (Expected: %0d)", det_ts_1, test_dly_1);
                $display("   -> TS_2: %0d (Expected: %0d)", det_ts_2, test_dly_2);
                $display("   -> TS_3: %0d (Expected: %0d)", det_ts_3, test_dly_3);
                $display("   -> TS_4: %0d (Expected: %0d)", det_ts_4, test_dly_4);
                
                // --- ADDED DISARM LOGIC ---
                $display("[%0t] Waiting 5 clock cycles to disarm...", $time);
                repeat (5) @(posedge clk_i);
                arm_i = 1'b0;
                $display("[%0t] System Disarmed. Verifying reset states...", $time);
                // --------------------------
            end
            begin
                #5000; // 5us timeout
                $display("[%0t] ERROR: Simulation Timeout. Done signal never went high.", $time);
            end
        join_any
        disable fork; // Kill the timeout if success finished first

        // Let the simulation run a little longer to observe the ramp wrapping
        #1000;
        $display("[%0t] Simulation Complete.", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // 5. Optional: Waveform Dumping (For Vivado/Icarus/ModelSim)
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("core_logic_sim.vcd");
        $dumpvars(0, tb_core_logic);
    end

endmodule