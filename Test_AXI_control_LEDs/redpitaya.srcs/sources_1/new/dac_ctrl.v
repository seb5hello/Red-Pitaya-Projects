// --- dac_ctrl.v ---
`timescale 1ns / 1ps

module dac_ctrl (
    input  wire        dac_clk_1x,
    input  wire        dac_clk_2x,
    input  wire        dac_clk_2p,
    input  wire        dac_rst,
    input  wire [13:0] dac_a_i,
    input  wire [13:0] dac_b_i,
    output wire [13:0] dac_dat_o,
    output wire        dac_wrt_o,
    output wire        dac_sel_o,
    output wire        dac_clk_o,
    output wire        dac_rst_o
);

    reg [13:0] dac_dat_a, dac_dat_b;

    // Signed to unsigned (also to negative slope for native DAC)
    always @(posedge dac_clk_1x) begin 
        dac_dat_a <= {dac_a_i[13], ~dac_a_i[12:0]};
        dac_dat_b <= {dac_b_i[13], ~dac_b_i[12:0]};
    end

    // DDR Outputs
    ODDR oddr_dac_clk        (.Q(dac_clk_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2p), .CE(1'b1), .R(1'b0   ), .S(1'b0));
    ODDR oddr_dac_wrt        (.Q(dac_wrt_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
    ODDR oddr_dac_sel        (.Q(dac_sel_o), .D1(1'b1     ), .D2(1'b0     ), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
    ODDR oddr_dac_rst        (.Q(dac_rst_o), .D1(dac_rst  ), .D2(dac_rst  ), .C(dac_clk_1x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
    ODDR oddr_dac_dat [13:0] (.Q(dac_dat_o), .D1(dac_dat_b), .D2(dac_dat_a), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));

endmodule