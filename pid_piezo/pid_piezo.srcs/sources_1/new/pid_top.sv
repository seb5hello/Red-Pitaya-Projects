`timescale 1ns / 1ps

module pid_top(
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               global_arm,
    input  logic               arm_i,
    
    input  logic               trigger_i,
    input  logic  [31:0]       current_ts_reg,
    
    output logic  [3:0]        ts_select,
    output logic  [14-1:0]     dac_dat_o,
    
    // System Bus Interface
    input  logic [19:0]        sys_addr,
    input  logic [31:0]        sys_wdata,
    input  logic               sys_wen,
    input  logic               sys_ren,
    output logic [31:0]        sys_rdata,
    output logic               sys_err,
    output logic               sys_ack
);
    // -------------------------------------------------------------------------
    // AXI Registers & Wires
    // -------------------------------------------------------------------------
    logic signed [13:0] kp_reg;
    logic signed [13:0] ki_reg;
    logic signed [13:0] kd_reg;
    logic [31:0]        target_ts_reg;
    logic signed [13:0] offset_reg;
    logic signed [13:0] max_out_reg;
    logic signed [13:0] min_out_reg;

    // Soft Output Limiter Register
    logic [31:0]        step_cycles_reg;

    // Sampling Registers (New)
    logic               trigger_req;
    logic signed [31:0] sampled_error_reg;
    logic signed [13:0] sampled_dac_reg;

    // Internal Wires
    logic               pid_ready_wire;
    logic signed [13:0] pid_target_wire; 

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface & Synchronization
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            kp_reg            <= 14'h0;
            ki_reg            <= 14'h0;
            kd_reg            <= 14'h0;
            target_ts_reg     <= 32'h0;
            ts_select         <= 4'h0;
            offset_reg        <= 14'sd0;
            max_out_reg       <= 14'sd8191;
            min_out_reg       <= -14'sd8191;
            step_cycles_reg   <= 32'd1;

            // Initialize Sampling Registers
            trigger_req       <= 1'b0;
            sampled_error_reg <= 32'sd0;
            sampled_dac_reg   <= 14'sd0;
            
            sys_ack           <= 1'b0;
            sys_rdata         <= 32'h0;
        end else begin
            sys_ack <= sys_wen | sys_ren;

            // ---------------------------------------------------------
            // AXI Write Path
            // ---------------------------------------------------------
            if (sys_wen) begin
                case (sys_addr[19:0])
                    20'h00000: trigger_req     <= sys_wdata[0];
                    20'h00004: kp_reg          <= sys_wdata[13:0];
                    20'h00008: ki_reg          <= sys_wdata[13:0];
                    20'h0000C: kd_reg          <= sys_wdata[13:0];
                    20'h00010: target_ts_reg   <= sys_wdata;
                    20'h00014: ts_select       <= sys_wdata[3:0];
                    20'h00018: offset_reg      <= sys_wdata[13:0];
                    20'h0001C: max_out_reg     <= sys_wdata[13:0];
                    20'h00020: min_out_reg     <= sys_wdata[13:0];
                    20'h00024: step_cycles_reg <= sys_wdata;
                    default: ;
                endcase
            end else if (trigger_req && pid_ready_wire) begin // <-- UPDATED: Waits for PID ready
                // Auto-clear trigger flag & latch values
                sampled_error_reg <= error_calc;
                sampled_dac_reg   <= pid_target_wire;         // <-- UPDATED: Samples PID target
                trigger_req       <= 1'b0;
            end
            
            // ---------------------------------------------------------
            // AXI Read Path
            // ---------------------------------------------------------
            if (sys_ren) begin
                case (sys_addr[19:0])
                    20'h00000: sys_rdata <= {30'h0, pid_ready_wire, trigger_req};
                    20'h00004: sys_rdata <= {{18{kp_reg[13]}}, kp_reg};
                    20'h00008: sys_rdata <= {{18{ki_reg[13]}}, ki_reg};
                    20'h0000C: sys_rdata <= {{18{kd_reg[13]}}, kd_reg};
                    20'h00010: sys_rdata <= target_ts_reg;
                    20'h00014: sys_rdata <= {28'h0, ts_select};
                    20'h00018: sys_rdata <= {{18{offset_reg[13]}}, offset_reg};
                    20'h0001C: sys_rdata <= {{18{max_out_reg[13]}}, max_out_reg};
                    20'h00020: sys_rdata <= {{18{min_out_reg[13]}}, min_out_reg};
                    20'h00024: sys_rdata <= step_cycles_reg;
                    
                    // Added Sampled Data Reads
                    20'h00028: sys_rdata <= sampled_error_reg;
                    20'h0002C: sys_rdata <= {{18{sampled_dac_reg[13]}}, sampled_dac_reg};
                    
                    default:   sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Instantiate PID Logic (Calculates Target)
    // -------------------------------------------------------------------------
    logic signed [31:0] error_calc;
    logic               filtered_trigger;
    logic               filtered_trigger_reg; // 1-cycle pipeline delay

    assign filtered_trigger = trigger_i & arm_i & (current_ts_reg != 32'd0);

    // PIPELINE FIX: Register the error calculation to break the critical path
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            error_calc           <= 32'sd0;
            filtered_trigger_reg <= 1'b0;
        end else begin
            // Latches the MUX output and Subtraction 1
            error_calc           <= target_ts_reg - current_ts_reg;
            filtered_trigger_reg <= filtered_trigger;
        end
    end

    pid_logic #(
        .MAX_INT(500000),      
        .MIN_INT(-500000)      
    ) i_pid_logic (
        .clk          (clk_i),
        .rst_n        (rstn_i & global_arm),
        
        // Pass the new filtered trigger here instead of (trigger_i & arm_i)
        .data_valid_i (filtered_trigger_reg), 
        
        .error_i      (error_calc),
        .kp_i         (kp_reg),
        .ki_i         (ki_reg),
        .kd_i         (kd_reg),
        .offset_i     (offset_reg),
        .max_out_i    (max_out_reg),
        .min_out_i    (min_out_reg),
        
        .dac_out_o    (pid_target_wire),
        .ready_o      (pid_ready_wire)
    );

    // -------------------------------------------------------------------------
    // Instantiate Soft Output Engine (+/- 1 smoothing)
    // -------------------------------------------------------------------------
    piezo_soft_output #(
        .OUT_WIDTH(14)
    ) i_piezo_soft_output (
        .clk           (clk_i),
        .rst_n         (rstn_i), // <-- Changed: Now uses true reset only
        .arm_i         (global_arm),  // <-- Added: Passes arm status directly
        
        .target_val_i  (pid_target_wire),
        .pid_ready_i   (pid_ready_wire),
        
        .step_cycles_i (step_cycles_reg),
        .max_out_i     (max_out_reg),
        .min_out_i     (min_out_reg),
        
        .dac_out_o     (dac_dat_o) 
    );

endmodule