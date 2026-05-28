// --- adc_ctrl.v ---
`timescale 1ns / 1ps

module adc_ctrl #(
    parameter ADW = 14, 
    parameter MNA = 2
)(
    input  wire                   adc_clk,
    input  wire [MNA-1:0][15:0]   adc_dat_i,
    output reg  signed [13:0]     adc_dat_a_o,
    output reg  signed [13:0]     adc_dat_b_o,
    output wire [1:0]             adc_clk_o,
    output wire                   adc_cdcs_o
);

    // Forward ADC clock to physical pins
    ODDR i_adc_clk_p (.Q(adc_clk_o[0]), .D1(1'b1), .D2(1'b0), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));
    ODDR i_adc_clk_n (.Q(adc_clk_o[1]), .D1(1'b0), .D2(1'b1), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));

    assign adc_cdcs_o = 1'b1;

    // Extract raw data
    wire [ADW-1:0] adc_dat_raw_0 = adc_dat_i[0][15 -: ADW];
    wire [ADW-1:0] adc_dat_raw_1 = adc_dat_i[1][15 -: ADW];

    // Transform into 2's complement (negative slope)
    always @(posedge adc_clk) begin
        adc_dat_a_o <= {adc_dat_raw_0[ADW-1], ~adc_dat_raw_0[ADW-2:0]};
        adc_dat_b_o <= {adc_dat_raw_1[ADW-1], ~adc_dat_raw_1[ADW-2:0]};
    end

endmodule