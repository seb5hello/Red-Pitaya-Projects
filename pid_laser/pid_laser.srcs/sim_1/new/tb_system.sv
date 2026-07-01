`timescale 1ns / 1ps

module tb_system;

    // -------------------------------------------------------------------------
    // Clock and Reset (125 MHz / 8ns period)
    // -------------------------------------------------------------------------
    logic adc_clk;
    logic adc_rstn;

    initial begin
        adc_clk = 0;
        forever #4 adc_clk = ~adc_clk;
    end

    // -------------------------------------------------------------------------
    // Global Orchestration Signals
    // -------------------------------------------------------------------------
    logic [2:0] mode;
    logic global_trigger;

    logic ramp_trigger_start;
    logic ramp_trigger_max;

    logic ramp_arm, detector_arm, generator_arm, pid_arm, pid_on;

    always_comb begin
        ramp_arm = 0; detector_arm = 0; generator_arm = 0; pid_arm = 0; pid_on = 0;
        case (mode)
            3'sd1: begin ramp_arm = 1; detector_arm = 1; end
            3'sd2: begin ramp_arm = 1; detector_arm = 1; pid_arm = 1; end
            3'sd3: begin ramp_arm = 1; detector_arm = 1; pid_arm = 1; pid_on = 1; end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // Hardware Routing & External IO
    // -------------------------------------------------------------------------
    logic [13:0] dac_a, dac_b, cavity_peak_sim_out;
    logic        hw_pid_trigger;
    logic [3:0]  hw_filt_peak_count;
    logic [31:0] hw_ts_1, hw_ts_2, hw_ts_3, hw_ts_4, hw_ts_5, hw_ts_6, hw_ts_7, hw_ts_8;
    logic [7:0]  exp_n_io;
    
    // Drive the Click Shield TRIG OUT (DIO0_N) high when either ramp trigger is high
    assign exp_n_io[0] = ramp_trigger_start | ramp_trigger_max;

    logic        pid_switch;
    logic [3:0]  timestamp_select = 4'd0; 
    logic [31:0] timestamp_pid;

    always_comb begin
        // Default assignments to prevent latch inference
        pid_switch    = 0;
        timestamp_pid = 32'd0; 

        case(timestamp_select)
            4'd0: begin pid_switch = 1; timestamp_pid = hw_ts_1; end
            4'd1: begin pid_switch = 1; timestamp_pid = hw_ts_2; end
            4'd2: begin pid_switch = 1; timestamp_pid = hw_ts_3; end
            4'd3: begin pid_switch = 1; timestamp_pid = hw_ts_4; end
            4'd4: begin pid_switch = 1; timestamp_pid = hw_ts_5; end
            4'd5: begin pid_switch = 1; timestamp_pid = hw_ts_6; end
            4'd6: begin pid_switch = 1; timestamp_pid = hw_ts_7; end
            4'd7: begin pid_switch = 1; timestamp_pid = hw_ts_8; end
            default: begin pid_switch = 0; timestamp_pid = 32'd0; end
        endcase
    end

    // -------------------------------------------------------------------------
    // Test Peak Simulator Configuration (Shadow Latching)
    // -------------------------------------------------------------------------
    logic [31:0] next_dly_1 = 0, next_dly_2 = 0, next_dly_3 = 0, next_dly_4 = 0;
    logic [13:0] next_peak_amp = 14'd5000; // Above the 4095 threshold
    logic [13:0] next_base_amp = 14'd0;
    logic [31:0] next_pulse_width = 32'd30;

    logic [31:0] active_dly_1, active_dly_2, active_dly_3, active_dly_4;
    logic [13:0] active_peak_amp, active_base_amp;
    logic [31:0] active_pulse_width;

    always_ff @(posedge adc_clk) begin
        if (~adc_rstn) begin
            active_dly_1 <= 0; active_dly_2 <= 0; active_dly_3 <= 0; active_dly_4 <= 0;
            active_peak_amp <= 0; active_base_amp <= 0; active_pulse_width <= 0;
        end else if (ramp_trigger_start) begin
            active_dly_1 <= next_dly_1; active_dly_2 <= next_dly_2;
            active_dly_3 <= next_dly_3; active_dly_4 <= next_dly_4;
            active_peak_amp <= next_peak_amp; active_base_amp <= next_base_amp;
            active_pulse_width <= next_pulse_width;
        end
    end

    // -------------------------------------------------------------------------
    // BFM (Bus Functional Model) Setup
    // -------------------------------------------------------------------------
    logic [19:0] sys1_addr=0, sys2_addr=0, sys3_addr=0, sys4_addr=0;
    logic [31:0] sys1_wdata=0, sys2_wdata=0, sys3_wdata=0, sys4_wdata=0;
    logic        sys1_wen=0, sys2_wen=0, sys3_wen=0, sys4_wen=0;
    logic        sys1_ren=0, sys2_ren=0, sys3_ren=0, sys4_ren=0;
    logic [31:0] sys1_rdata, sys2_rdata, sys3_rdata, sys4_rdata;
    logic        sys1_ack, sys2_ack, sys3_ack, sys4_ack;
    logic        sys1_err, sys2_err, sys3_err, sys4_err;

    // --- Instantiations (sys_ctrl, ramp_top, test_peak_logic, timestamp_top, pid_top) ---
    system_controller system_controller_inst (
        .clk_i(adc_clk), .rstn_i(adc_rstn), .mode_o(mode), .global_trigger_o(global_trigger),
        .sys_addr(sys1_addr), .sys_wdata(sys1_wdata), .sys_wen(sys1_wen), .sys_ren(sys1_ren), .sys_rdata(sys1_rdata), .sys_err(sys1_err), .sys_ack(sys1_ack)
    );

    ramp_top ramp_top_inst (
        .clk_i(adc_clk), .rstn_i(adc_rstn), .arm_i(ramp_arm), .trigger_i(global_trigger),
        .trigger_start_o(ramp_trigger_start), .trigger_max_o(ramp_trigger_max), .dac_dat_o(dac_a),
        .sys_addr(sys2_addr), .sys_wdata(sys2_wdata), .sys_wen(sys2_wen), .sys_ren(sys2_ren), .sys_rdata(sys2_rdata), .sys_err(sys2_err), .sys_ack(sys2_ack)
    );

    test_peak_logic test_peak_inst (
        .clk_i(adc_clk), .rstn_i(adc_rstn), .arm_i(ramp_arm), .trigger_start_i(ramp_trigger_start), .trigger_max_i(ramp_trigger_max),
        .dly_1(active_dly_1), .dly_2(active_dly_2), .dly_3(active_dly_3), .dly_4(active_dly_4),
        .peak_amp(active_peak_amp), .base_amp(active_base_amp), .pulse_width(active_pulse_width), .dac_dat_o(cavity_peak_sim_out)
    );

    timestamp_top timestamp_top_inst (
        .clk_i(adc_clk), .rstn_i(adc_rstn), .arm_i(detector_arm), .trigger_start_i(ramp_trigger_start), .trigger_max_i(ramp_trigger_max), .adc_dat_i(cavity_peak_sim_out),
        .pid_trigger_o(hw_pid_trigger), .filt_peak_count_o(hw_filt_peak_count),
        .filt_ts_1_o(hw_ts_1), .filt_ts_2_o(hw_ts_2), .filt_ts_3_o(hw_ts_3), .filt_ts_4_o(hw_ts_4),
        .filt_ts_5_o(hw_ts_5), .filt_ts_6_o(hw_ts_6), .filt_ts_7_o(hw_ts_7), .filt_ts_8_o(hw_ts_8),
        .sys_addr(sys3_addr), .sys_wdata(sys3_wdata), .sys_wen(sys3_wen), .sys_ren(sys3_ren), .sys_rdata(sys3_rdata), .sys_err(sys3_err), .sys_ack(sys3_ack)
    );

    pid_top pid_top_inst (
        .clk_i(adc_clk), .rstn_i(adc_rstn & pid_switch), .global_arm(pid_arm), .arm_i(pid_on), .trigger_i(hw_pid_trigger), .current_ts_reg(timestamp_pid), .ts_select(timestamp_select), .dac_dat_o(dac_b),
        .ramp_peak (ramp_trigger_max), .ramp_start (ramp_trigger_start), .sys_addr(sys4_addr), .sys_wdata(sys4_wdata), .sys_wen(sys4_wen), .sys_ren(sys4_ren), .sys_rdata(sys4_rdata), .sys_err(sys4_err), .sys_ack(sys4_ack)
    );
    
    
    

    // -------------------------------------------------------------------------
    // BFM Helper Tasks
    // -------------------------------------------------------------------------
    task write_bus(input int bus_idx, input [19:0] addr, input [31:0] data);
        @(posedge adc_clk);
        case(bus_idx)
            1: begin sys1_addr <= addr; sys1_wdata <= data; sys1_wen <= 1; end
            2: begin sys2_addr <= addr; sys2_wdata <= data; sys2_wen <= 1; end
            3: begin sys3_addr <= addr; sys3_wdata <= data; sys3_wen <= 1; end
            4: begin sys4_addr <= addr; sys4_wdata <= data; sys4_wen <= 1; end
        endcase
        @(posedge adc_clk);
        case(bus_idx)
            1: while(!sys1_ack) @(posedge adc_clk);
            2: while(!sys2_ack) @(posedge adc_clk);
            3: while(!sys3_ack) @(posedge adc_clk);
            4: while(!sys4_ack) @(posedge adc_clk);
        endcase
        sys1_wen <= 0; sys2_wen <= 0; sys3_wen <= 0; sys4_wen <= 0;
    endtask

    task read_bus(input int bus_idx, input [19:0] addr, output [31:0] data);
        @(posedge adc_clk);
        case(bus_idx)
            1: begin sys1_addr <= addr; sys1_ren <= 1; end
            2: begin sys2_addr <= addr; sys2_ren <= 1; end
            3: begin sys3_addr <= addr; sys3_ren <= 1; end
            4: begin sys4_addr <= addr; sys4_ren <= 1; end
        endcase
        @(posedge adc_clk);
        case(bus_idx)
            1: begin while(!sys1_ack) @(posedge adc_clk); data = sys1_rdata; end
            2: begin while(!sys2_ack) @(posedge adc_clk); data = sys2_rdata; end
            3: begin while(!sys3_ack) @(posedge adc_clk); data = sys3_rdata; end
            4: begin while(!sys4_ack) @(posedge adc_clk); data = sys4_rdata; end
        endcase
        sys1_ren <= 0; sys2_ren <= 0; sys3_ren <= 0; sys4_ren <= 0;
    endtask

    // -------------------------------------------------------------------------
    // Python API Emulation Tasks
    // -------------------------------------------------------------------------
    task configure_system();
        $display("[%0t] 1. Disarming system to ensure safe configuration...", $time);
        write_bus(1, 20'h00, 32'd0); // Mode=0, Trigger=0
        #1000;

        $display("[%0t] 2. Configuring Systems via AXI...", $time);
        
        // RAMP (6000Hz -> 20833 cycles, 0.11V -> 901 dac, 0.16V -> 1310 dac)
        write_bus(2, 20'h00, 32'd901);     // min_val
        write_bus(2, 20'h04, 32'd1310);    // max_val
        write_bus(2, 20'h08, 32'd20833);   // n_cycles
        write_bus(2, 20'h0C, 32'd1);       // continuous
        
        // DETECTOR (0.5V -> 4095 dac)
        write_bus(3, 20'h00, 32'd4095);    // threshold
        write_bus(3, 20'h2C, 32'd0);       // offset
        write_bus(3, 20'h30, 32'd0);       // filter_mode
        write_bus(3, 20'h34, 32'd1);       // expected_peaks
        write_bus(3, 20'h38, 32'd300);     // merge_threshold
        
        // PID
        write_bus(4, 20'h00004, 32'd150);  // kp = 150
        write_bus(4, 20'h00008, 32'd25);   // ki = 25
        write_bus(4, 20'h0000C, -32'sd10); // kd = -10 (Two's complement)
        write_bus(4, 20'h00010, 32'd15000);// target_ts = 15000
        write_bus(4, 20'h00014, 32'd0);    // ts_select = 0
        write_bus(4, 20'h00018, 32'd205);  // offset = 205
        write_bus(4, 20'h0001C, 32'd8191); // max_out
        write_bus(4, 20'h00020, 32'd205);  // min_out
        write_bus(4, 20'h00024, 32'd4);    // step_cycles
    endtask

    task arm_ramp();
        $display("[%0t] 4. Arming the system (Mode=1, Trigger=0)...", $time);
        write_bus(1, 20'h00, 32'd1); // mode=1, trig=0 -> 0x01
        
        // Wait for Ramp to initialize to Min Val
        #50000;
        $display("[%0t] 5. Firing Hardware Trigger! (Mode=1, Trigger=1)...", $time);
        write_bus(1, 20'h00, 32'h00000009); // mode=1, trig=1 -> (1<<3)|1 = 9
        write_bus(1, 20'h00, 32'h00000001); // Remove trigger
    endtask

    task arm_pid();
        $display("[%0t] 7. Enabling PID Control (Mode=2)...", $time);
        write_bus(1, 20'h00, 32'd2); // mode=2, trig=0 -> 0x02
    endtask

    task engage_pid();
        $display("[%0t] 7. Enabling PID Control (Mode=2)...", $time);
        write_bus(1, 20'h00, 32'd3); // mode=2, trig=0 -> 0x02
    endtask

    task disengage_pid();
        $display("[%0t] 7. Disabling PID Control (Mode=1)...", $time);
        write_bus(1, 20'h00, 32'd2); // mode=1, trig=0 -> 0x01
    endtask

    task disarm_pid();
        $display("[%0t] 7. Disabling PID Control (Mode=1)...", $time);
        write_bus(1, 20'h00, 32'd1); // mode=1, trig=0 -> 0x01
    endtask

    task disarm_ramp();
        $display("[%0t] 8. Initiating Graceful Soft Disarm (Mode=0)...", $time);
        write_bus(1, 20'h00, 32'd0); // Mode=0, Trigger=0
        
        // Wait long enough to observe piezos walking back down to 0
        #100000;
        $display("[%0t]    -> Disarm complete. Safe to shut down.", $time);
    endtask
    
    // --- NEW TASK: Fetch PID Results over AXI ---
    task fetch_pid_results();
        logic [31:0] pid_status;
        logic signed [31:0] sampled_err;
        logic signed [31:0] sampled_dac;
        logic trigger_done = 0;

        $display("[%0t]    -> Requesting PID Sample via AXI...", $time);
        write_bus(4, 20'h00000, 32'd1); // Set trigger_req bit (bit 0)

        // Poll until hardware auto-clears the trigger_req bit indicating the data is latched
        while (!trigger_done) begin
            read_bus(4, 20'h00000, pid_status);
            trigger_done = (pid_status[0] == 1'b0);
            #100; // Small delay between polls
        end

        // Read latched values from the new AXI offsets
        read_bus(4, 20'h00028, sampled_err);
        read_bus(4, 20'h0002C, sampled_dac);

        $display("[%0t]    -> Success! PID Sampled Error = %0d, Latched DAC Target = %0d", $time, sampled_err, sampled_dac);
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Reset System
        adc_rstn = 0;
        #100; @(posedge adc_clk);
        adc_rstn = 1;
        #100;

        // Position the simulated peak slightly off-target (Target is 15000, Peak is 9000)
        // so we can watch the PID error respond when it gets activated.
        next_pulse_width = 50;
        next_dly_1 = 32'd9000; 
        next_dly_2 = 32'd9200; 

        // Execute API Sequence
        configure_system();
        arm_ramp();
        
        // Wait long enough for the peak generator to fire inside the 20,833 cycle window
        #500000;
        arm_pid();
        
        // Wait long enough for the peak generator to fire inside the 20,833 cycle window
        #500000;
        engage_pid();
        
        // Let PID run for a few ramp cycles to see dac_b change
        #250000;
        
        // Let PID run for a few ramp cycles to see dac_b change
        #250000;
        
        // Let PID run for a few ramp cycles to see dac_b change
        #250000;
        
        // Poll the PID over AXI while it is running
        fetch_pid_results();
        
        #250000;
        
        #250000;
        disengage_pid();
        
        #250000;
        disarm_pid();
        
        // Let PID run for a few ramp cycles to verify it stops updating dac_b
        #500000;
        disarm_ramp();
        
        $stop;
    end

endmodule