////////////////////////////////////////////////////////////////////////////////
// CORE MODULE: Pure Test Peak Generator Logic
////////////////////////////////////////////////////////////////////////////////
module test_peak_logic (
    input  logic          clk_i,
    input  logic          rstn_i,
    input  logic          arm_i,
    input  logic          trigger_i,
    
    // Configuration Inputs (Driven by Bus Interface)
    input  logic [31:0]   dly_1,
    input  logic [31:0]   dly_2,
    input  logic [31:0]   dly_3,
    input  logic [31:0]   dly_4,
    input  logic [13:0]   peak_amp,
    input  logic [13:0]   base_amp,
    input  logic [31:0]   pulse_width,
    
    // Hardware Outputs
    output logic [13:0]   dac_dat_o
);

    logic [31:0] counter;
    logic        running;

    // Pulse Generation Logic
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            dac_dat_o <= 14'h0;
            counter   <= 0;
            running   <= 0;
        end else begin
            if (~arm_i) begin
                counter   <= 0;
                running   <= 0;
                dac_dat_o <= base_amp;
            end else if (trigger_i) begin 
                running   <= 1;
                counter   <= 0;
                dac_dat_o <= base_amp;
            end else if (running) begin
                counter <= counter + 1;
                
                // Output peak_amp if the counter is within the dynamic pulse width window
                if ((counter >= dly_1 && counter < dly_1 + pulse_width) || 
                    (counter >= dly_2 && counter < dly_2 + pulse_width) || 
                    (counter >= dly_3 && counter < dly_3 + pulse_width) || 
                    (counter >= dly_4 && counter < dly_4 + pulse_width)) begin
                    dac_dat_o <= peak_amp;
                end else begin
                    dac_dat_o <= base_amp;
                end
            end
        end
    end

endmodule
