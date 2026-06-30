`timescale 1ns / 1ps

module tb_pid_soft_out();

    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    logic arm_i;
    
    initial begin
        clk = 0;
        forever #4 clk = ~clk; // 125 MHz (8ns period)
    end

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic               trigger;
    logic signed [31:0] error_i;
    logic signed [13:0] kp_i, ki_i, kd_i;
    logic signed [13:0] offset_i;
    logic signed [13:0] max_out_i, min_out_i;
    logic [31:0]        step_cycles_i;
    
    // Internal interconnect
    logic signed [13:0] pid_target_wire;
    logic               pid_ready_wire;
    
    // Final output
    logic signed [13:0] dac_out_o;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiations
    // -------------------------------------------------------------------------
    pid_logic #(
        .MAX_INT(500000),
        .MIN_INT(-500000),
        .SHIFT_VAL(10)
    ) dut_pid (
        .clk          (clk),
        .rst_n        (rst_n & arm_i), // PID math clears instantly on disarm
        .data_valid_i (trigger),
        .error_i      (error_i),
        .kp_i         (kp_i),
        .ki_i         (ki_i),
        .kd_i         (kd_i),
        .offset_i     (offset_i),
        .max_out_i    (max_out_i),
        .min_out_i    (min_out_i),
        .dac_out_o    (pid_target_wire),
        .ready_o      (pid_ready_wire)
    );

    piezo_soft_output #(
        .OUT_WIDTH(14)
    ) dut_soft_out (
        .clk           (clk),
        .rst_n         (rst_n),  // Soft output stays alive
        .arm_i         (arm_i),  // Soft output monitors arm status
        .target_val_i  (pid_target_wire),
        .pid_ready_i   (pid_ready_wire),
        .step_cycles_i (step_cycles_i),
        .max_out_i     (max_out_i),
        .min_out_i     (min_out_i),
        .dac_out_o     (dac_out_o)
    );

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    task pulse_trigger();
        begin
            @(posedge clk);
            trigger = 1'b1;
            @(posedge clk);
            trigger = 1'b0;
        end
    endtask

    task wait_for_settle();
        logic signed [13:0] last_val;
        integer stable_count;
        begin
            stable_count = 0;
            while (stable_count < (step_cycles_i + 5)) begin
                last_val = dac_out_o;
                @(posedge clk);
                if (dac_out_o == last_val) 
                    stable_count++;
                else 
                    stable_count = 0;
            end
            $display("[%0t] DAC Output Settled at: %0d", $time, dac_out_o);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        rst_n   = 0;
        arm_i   = 0;
        trigger = 0;
        error_i = 0;
        
        kp_i = 14'sd1024;  // P-Gain = 1.0
        ki_i = 14'sd512;   // I-Gain = 0.5
        kd_i = 14'sd0;     
        
        offset_i  = 14'sd2000;
        max_out_i = 14'sd8191;
        min_out_i = -14'sd8191;
        step_cycles_i = 32'd4; 

        $display("===============================================================");
        $display("[%0t] STARTING PID + SOFT OUTPUT TESTBENCH", $time);
        $display("===============================================================");

        // ---------------------------------------------------------------------
        // TEST 1: Arm System
        // ---------------------------------------------------------------------
        #100;
        $display("\n--- TEST 1: Arming PID (No Trigger) ---");
        rst_n = 1; 
        arm_i = 1; // Assert arm_i to start normal operations
        wait_for_settle();
        if (dac_out_o == 2000) $display(" -> PASS: Piezo safely slewed up to baseline offset.");
        else $display(" -> FAIL: Did not settle at offset.");

        // ---------------------------------------------------------------------
        // TEST 2: Error changes, no trigger
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 2: Error changes, no trigger sent ---");
        error_i = 32'sd100; 
        #1000; 
        if (dac_out_o == 2000) $display(" -> PASS: Ignored error without trigger.");
        else $display(" -> FAIL: PID acted without a trigger pulse.");

        // ---------------------------------------------------------------------
        // TEST 3: Trigger sent
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 3: Error is 100, trigger sent ---");
        pulse_trigger();
        wait_for_settle();
        if (dac_out_o == 2150) $display(" -> PASS: Correctly calculated and slewed to first PID iteration.");
        else $display(" -> FAIL: Expected 2150.");

        // ---------------------------------------------------------------------
        // TEST 4: Trigger sent again
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 4: Error stays 100, trigger sent again ---");
        pulse_trigger();
        wait_for_settle();
        if (dac_out_o == 2200) $display(" -> PASS: Integrator accumulated correctly. Slewed to new target.");
        else $display(" -> FAIL: Expected 2200.");

        // ---------------------------------------------------------------------
        // TEST 5: Graceful Soft Disarm
        // Expected: Pulling arm_i low forces target to 0, DAC slowly walks down.
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 5: Graceful Soft Disarm (arm_i goes low) ---");
        arm_i = 0; // Drop the arm flag
        wait_for_settle();
        if (dac_out_o == 0) $display(" -> PASS: DAC successfully and safely slewed down to 0.");
        else $display(" -> FAIL: Did not slew to 0.");

        #1000;
        $display("\n===============================================================");
        $display("[%0t] TESTBENCH COMPLETE.", $time);
        $display("===============================================================");
        $finish;
    end

endmodule