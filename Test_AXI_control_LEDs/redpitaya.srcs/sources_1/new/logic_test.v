`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/09/2026 02:21:28 PM
// Design Name: 
// Module Name: logic_test
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module logic_test(
    input wire clk,
    input wire reset_n,

    // Inputs from ARM (via AXI Registers)
    input wire [31:0] kp_in,
    input wire [31:0] ki_in,
    input wire [31:0] kd_in,
    input wire [31:0] state_in,

    // Outputs back to ARM (Read via AXI)
    output reg [31:0] status_out,
    output wire [31:0] control_out
    );
    
    // Internal signals
    reg [31:0] internal_calc;

    // 2. Logic to process the AXI Registers
    // Here we just add the gains together as a test.
    // In a real system, this would be your PID math.
    always @(posedge clk) begin
        if (!reset_n) begin
            internal_calc <= 32'h0;
            status_out    <= 32'h0;
        end else begin
            // Perform a dummy calculation to verify ARM data
            internal_calc <= kp_in + ki_in + kd_in;
            
            // Send the result + the state back to the ARM for verification
            // This proves the "Read" path is working
            status_out <= internal_calc + state_in;
        end
    end

    // Direct assignment for control_out
    assign control_out = internal_calc;
    
endmodule
