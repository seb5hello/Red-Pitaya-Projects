`timescale 1ns / 1ps

module pid_top(
    input  logic               clk_i,
    input  logic               rstn_i,
    input  logic               arm_i,
    
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
    logic signed [31:0] target_ts_reg;
    logic signed [31:0] current_ts_reg;
    
    logic               trigger_req;
    logic               pid_ready;
    logic signed [13:0] dac_out_wire;

    // -------------------------------------------------------------------------
    // System Bus Write/Read Interface & Synchronization
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            kp_reg         <= 14'h0;
            ki_reg         <= 14'h0;
            kd_reg         <= 14'h0;
            target_ts_reg  <= 32'h0;
            current_ts_reg <= 32'h0;
            trigger_req    <= 1'b0;
            
            sys_ack        <= 1'b0;
            sys_rdata      <= 32'h0;
        end else begin
            // Single-cycle bus acknowledgment
            sys_ack <= sys_wen | sys_ren;
            
            // ---------------------------------------------------------
            // AXI Write Path
            // ---------------------------------------------------------
            if (sys_wen) begin
                case (sys_addr[19:0])
                    20'h00000: trigger_req    <= sys_wdata[0];
                    20'h00004: kp_reg         <= sys_wdata[13:0];
                    20'h00008: ki_reg         <= sys_wdata[13:0];
                    20'h0000C: kd_reg         <= sys_wdata[13:0];
                    20'h00010: target_ts_reg  <= sys_wdata;
                    20'h00014: current_ts_reg <= sys_wdata;
                    default: ;
                endcase
            end else if (trigger_req) begin
                // Auto-clear trigger flag to create a 1-cycle strobe
                trigger_req <= 1'b0;
            end
            
            // ---------------------------------------------------------
            // AXI Read Path
            // ---------------------------------------------------------
            if (sys_ren) begin
                case (sys_addr[19:0])
                    // 0x00: Bit 1 is Ready, Bit 0 is Trigger status
                    20'h00000: sys_rdata <= {30'h0, pid_ready, trigger_req};
                    20'h00004: sys_rdata <= {18'h0, kp_reg};
                    20'h00008: sys_rdata <= {18'h0, ki_reg};
                    20'h0000C: sys_rdata <= {18'h0, kd_reg};
                    20'h00010: sys_rdata <= target_ts_reg;
                    20'h00014: sys_rdata <= current_ts_reg;
                    20'h00018: sys_rdata <= {18'h0, dac_out_wire};
                    default:   sys_rdata <= 32'h0;
                endcase
            end
        end
    end

    // No error handling implemented for this peripheral
    assign sys_err = 1'b0;

    // -------------------------------------------------------------------------
    // Instantiate PID Logic
    // -------------------------------------------------------------------------
    pid_logic #(
        .MAX_INT(500000),      
        .MIN_INT(-500000),     
        .MAX_OUT(8191),        
        .MIN_OUT(-8192)        
    ) i_pid_logic (
        .clk          (clk_i),
        // --- FIX: Combine system reset and arm signal ---
        .rst_n        (rstn_i & arm_i), 
        // ------------------------------------------------
        .data_valid_i (trigger_req),
        
        .setpoint_i   (target_ts_reg), 
        .actual_i     (current_ts_reg), 

        .kp_i         (kp_reg),
        .ki_i         (ki_reg),
        .kd_i         (kd_reg),
        .dac_out_o    (dac_out_wire),
        .ready_o      (pid_ready)
    );

    
//      // Calculate Error
//     logic signed [31:0] error_calc;
//     assign error_calc = target_ts_reg - current_ts_reg;
//
//     pid_logic #(
//         .MAX_INT(500000),      // Plain 32-bit integer
//         .MIN_INT(-500000),     // Plain 32-bit integer
//         .MAX_OUT(8191),        // Safe maximum
//         .MIN_OUT(-8192)        // Safe minimum, no double-negative casting
//     ) i_pid_logic (
//         .clk          (clk_i),
//         .rst_n        (rstn_i & arm_i),
//         .data_valid_i (trigger_req),
//         .error_i      (error_calc),
//         .kp_i         (kp_reg),
//         .ki_i         (ki_reg),
//         .kd_i         (kd_reg),
//         .dac_out_o    (dac_out_wire),
//         .ready_o      (pid_ready)
//    );

endmodule