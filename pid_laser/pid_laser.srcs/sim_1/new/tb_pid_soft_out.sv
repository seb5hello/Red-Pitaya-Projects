`timescale 1ns / 1ps

module tb_pid_soft_out();

    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    logic global_arm;
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
        .rst_n        (rst_n & global_arm), // PID math clears instantly on disarm
        .data_valid_i (trigger & arm_i),
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
        .arm_i         (global_arm),  // Soft output monitors arm status
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
        global_arm = 0;
        
        kp_i = 14'sd1024;  // P-Gain = 1.0
        ki_i = 14'sd512;   // I-Gain = 0.5
        kd_i = 14'sd0;     
        
        offset_i  = 14'sd200;
        max_out_i = 14'sd8191;
        min_out_i = -14'sd8191;
        step_cycles_i = 32'd4; 

        $display("===============================================================");
        $display("[%0t] STARTING PID + SOFT OUTPUT TESTBENCH", $time);
        $display("===============================================================");

        // ---------------------------------------------------------------------
        // TEST 1: Arm System
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 1: Global Arming PID (No Trigger) ---");
        rst_n = 1; 
        global_arm = 1'b1;
        arm_i = 1'b0;
        error_i = 32'sd0; 
        wait_for_settle();

        // ---------------------------------------------------------------------
        // TEST 2: Error changes, no trigger
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 2: Error changes, no trigger sent ---");
        error_i = 32'sd100; 
        wait_for_settle();

        // ---------------------------------------------------------------------
        // TEST 2: Error changes, no trigger
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 3: Error changes, trigger sent, arm off ---");
        error_i = 32'sd100; 
        pulse_trigger();
        wait_for_settle();

        // ---------------------------------------------------------------------
        // TEST 2: Error changes, no trigger
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 4: Error changes, trigger sent, arm on ---");
        arm_i = 1'b1;
        pulse_trigger();
        wait_for_settle();

        // ---------------------------------------------------------------------
        // TEST 3: Trigger sent
        // ---------------------------------------------------------------------
        #5000;
        $display("\n--- TEST 5: Error is 100, trigger sent ---");
        error_i = -32'sd50; 
        pulse_trigger();
        wait_for_settle();

        // ---------------------------------------------------------------------
        // TEST 4: Trigger sent again
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 6: Error stays 100, trigger sent again ---");
        arm_i = 1'b0;
        wait_for_settle();

        // ---------------------------------------------------------------------
        // TEST 5: Graceful Soft Disarm
        // Expected: Pulling arm_i low forces target to 0, DAC slowly walks down.
        // ---------------------------------------------------------------------
        #500;
        $display("\n--- TEST 7: Graceful Soft Disarm (arm_i goes low) ---");
        global_arm = 1'b0; // Drop the arm flag
        wait_for_settle();

        #1000;
        $display("\n===============================================================");
        $display("[%0t] TESTBENCH COMPLETE.", $time);
        $display("===============================================================");
        $finish;
    end

endmodule