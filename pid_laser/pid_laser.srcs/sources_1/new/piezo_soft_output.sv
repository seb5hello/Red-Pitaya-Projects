`timescale 1ns / 1ps

module piezo_soft_output #(
    parameter OUT_WIDTH = 14
)(
    input  wire clk,
    input  wire rst_n,       // True hardware reset only
    input  wire arm_i,       // Software arm/disarm state
    
    // Target and synchronization from the PID
    input  wire signed [OUT_WIDTH-1:0] target_val_i,
    input  wire                        pid_ready_i,
    
    // Slew and boundary configurations
    input  wire [31:0]                 step_cycles_i,
    input  wire signed [OUT_WIDTH-1:0] max_out_i,
    input  wire signed [OUT_WIDTH-1:0] min_out_i,
    
    // Smooth output to the physical DAC
    output reg  signed [OUT_WIDTH-1:0] dac_out_o
);

    reg pid_ready_q;
    reg signed [OUT_WIDTH-1:0] safe_target;
    reg [31:0] delay_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dac_out_o   <= 0;
            pid_ready_q <= 1'b1;
            safe_target <= 0;
            delay_cnt   <= 0;
        end else begin
            pid_ready_q <= pid_ready_i;
            
            // ---------------------------------------------------------
            // 1. Target Latching & Boundary Clamping
            // ---------------------------------------------------------
            if (!arm_i) begin
                // Soft Disarm: Safely force the target back to absolute zero
                safe_target <= 0;
            end 
            else if (pid_ready_i && !pid_ready_q) begin
                // Normal Operation: Latch new target from PID
                if (target_val_i > max_out_i)
                    safe_target <= max_out_i;
                else if (target_val_i < min_out_i)
                    safe_target <= min_out_i;
                else
                    safe_target <= target_val_i;
            end
            else begin
                // Boundary protection if AXI limits shrink while idle
                if (safe_target > max_out_i)      safe_target <= max_out_i;
                else if (safe_target < min_out_i) safe_target <= min_out_i;
            end
            
            // ---------------------------------------------------------
            // 2. Soft Output Engine (+/- 1 per step)
            // ---------------------------------------------------------
            // This runs continuously as long as rst_n is high!
            if (dac_out_o != safe_target) begin
                if (step_cycles_i <= 1 || delay_cnt >= (step_cycles_i - 1)) begin
                    delay_cnt <= 0;
                    
                    if (safe_target > dac_out_o)
                        dac_out_o <= dac_out_o + 1;
                    else
                        dac_out_o <= dac_out_o - 1;
                end else begin
                    delay_cnt <= delay_cnt + 1;
                end
            end else begin
                delay_cnt <= 0;
            end
        end
    end

endmodule