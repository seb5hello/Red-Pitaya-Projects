`timescale 1ns / 1ps

module red_pitaya_led_axi (
    // System signals
    input  wire        clk_i,
    input  wire        rstn_i,

    // System bus interface
    input  wire [31:0] sys_addr,
    input  wire [31:0] sys_wdata,
    input  wire        sys_wen,
    input  wire        sys_ren,
    output reg  [31:0] sys_rdata,
    output wire        sys_err,
    output wire        sys_ack,

    // LED Output
    output reg  [7:0]  led_o
);

    // Address logic: We only have one register, so we don't need to check sys_addr 
    // unless you want to add more features later.

    always @(posedge clk_i) begin
        if (rstn_i == 1'b0) begin
            led_o     <= 8'h00;
            sys_rdata <= 32'h0;
        end else begin
            // Write logic: if write enable is high, update LED register
            if (sys_wen) begin
                led_o <= sys_wdata[7:0];
            end
            
            // Read logic: allow the CPU to read back the current LED state
            if (sys_ren) begin
                sys_rdata <= {24'h0, led_o};
            end else begin
                sys_rdata <= 32'h0;
            end
        end
    end

    // Standard bus response: no error, acknowledge immediately
    assign sys_err = 1'b0;
    assign sys_ack = sys_wen | sys_ren;

endmodule