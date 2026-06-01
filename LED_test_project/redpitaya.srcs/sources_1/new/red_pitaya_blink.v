`timescale 1ns / 1ps

module red_pitaya_blink (
    input  wire       clk_i,   // Clock input
    output wire [7:0] led_o    // 8-bit LED output
);

    reg [27:0] counter = 28'd0;
    
    // Initialize with only the first LED turned on
    reg [7:0] led_reg = 8'b00000001; 

    always @(posedge clk_i) begin
        counter <= counter + 1'b1;
        
        // 12.5 million clock cycles at 125 MHz = 100ms per shift (10 Hz)
        if (counter == 28'd12500000 - 1) begin
            counter <= 28'd0; // Reset the counter
            
            // Circular shift to the left:
            // e.g., 00000001 -> 00000010 -> ... -> 10000000 -> 00000001
            led_reg <= {led_reg[6:0], led_reg[7]}; 
        end
    end

    assign led_o = led_reg;

endmodule