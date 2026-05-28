`timescale 1ns / 1ps

module top_test #(
  parameter MNA = 2,  // number of acquisition modules
  parameter MNG = 2,  // number of generator   modules
  parameter ADW = 14, // ADC bit width
  parameter DWE = 8   // Expansion connector width
)(
  // PS connections
  inout  logic [54-1:0] FIXED_IO_mio     ,
  inout  logic          FIXED_IO_ps_clk  ,
  inout  logic          FIXED_IO_ps_porb ,
  inout  logic          FIXED_IO_ps_srstb,
  inout  logic          FIXED_IO_ddr_vrn ,
  inout  logic          FIXED_IO_ddr_vrp ,
  // DDR
  inout  logic [15-1:0] DDR_addr   ,
  inout  logic [ 3-1:0] DDR_ba     ,
  inout  logic          DDR_cas_n  ,
  inout  logic          DDR_ck_n   ,
  inout  logic          DDR_ck_p   ,
  inout  logic          DDR_cke    ,
  inout  logic          DDR_cs_n   ,
  inout  logic [ 4-1:0] DDR_dm     ,
  inout  logic [32-1:0] DDR_dq     ,
  inout  logic [ 4-1:0] DDR_dqs_n  ,
  inout  logic [ 4-1:0] DDR_dqs_p  ,
  inout  logic          DDR_odt    ,
  inout  logic          DDR_ras_n  ,
  inout  logic          DDR_reset_n,
  inout  logic          DDR_we_n   ,

  // // ADC
  // input  logic [MNA-1:0] [16-1:0] adc_dat_i,  // ADC data
   input  logic           [ 2-1:0] adc_clk_i,  // ADC clock {p,n}
   output logic           [ 2-1:0] adc_clk_o,  // optional ADC clock source
  // output logic                    adc_cdcs_o, // ADC clock duty cycle stabilizer
  
  // // DAC
  // output logic [ 14-1:0] dac_dat_o  ,  // DAC combined data
  // output logic           dac_wrt_o  ,  // DAC write
  // output logic           dac_sel_o  ,  // DAC channel select
   output logic           dac_clk_o  ,  // DAC clock
  // output logic           dac_rst_o  ,  // DAC reset

  // LED
  output logic [  8-1:0] led_o
);

  // -------------------------------------------------------------------------
  // Clocks and Resets
  // -------------------------------------------------------------------------
  logic [3:0] fclk;
  logic [3:0] frstn;

  logic adc_clk_in, pll_adc_clk, pll_dac_clk_1x, pll_dac_clk_2x, pll_dac_clk_2p;
  logic pll_locked, pll_locked_r, fpll_locked_r2, fpll_locked_r3;
  logic rstn_pll, rst_after_locked;
  logic [15:0] rst_cnt = 'h0;

  logic adc_clk, adc_rstn;
  logic dac_clk_1x, dac_clk_2x, dac_clk_2p, dac_rst;

  IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));
  
  assign rstn_pll = frstn[0] & ~(!fpll_locked_r2 && fpll_locked_r3);
  
  red_pitaya_pll pll (
    .clk         (adc_clk_in),
    .rstn        (rstn_pll  ),
    .clk_adc     (pll_adc_clk   ),
    .clk_dac_1x  (pll_dac_clk_1x),
    .clk_dac_2x  (pll_dac_clk_2x),
    .clk_dac_2p  (pll_dac_clk_2p),
    .pll_locked  (pll_locked    )
  );

  BUFG bufg_adc_clk    (.O (adc_clk   ), .I (pll_adc_clk   ));
  BUFG bufg_dac_clk_1x (.O (dac_clk_1x), .I (pll_dac_clk_1x));
  BUFG bufg_dac_clk_2x (.O (dac_clk_2x), .I (pll_dac_clk_2x));
  BUFG bufg_dac_clk_2p (.O (dac_clk_2p), .I (pll_dac_clk_2p));

  always @(posedge fclk[0]) begin
    fpll_locked_r2  <= pll_locked;
    fpll_locked_r3  <= fpll_locked_r2;
  end

  always @(posedge adc_clk) begin
    pll_locked_r <= pll_locked;
    if ((pll_locked && !pll_locked_r) || rst_cnt > 0) begin
      if (rst_cnt < 64) rst_cnt <= rst_cnt + 1;
      else rst_cnt <= 'h0;
    end else begin
      if (~pll_locked) rst_cnt <= 'h0;
    end
  end

  assign rst_after_locked = |rst_cnt;
  always @(posedge adc_clk)    adc_rstn <=  frstn[0] & ~rst_after_locked;
  always @(posedge dac_clk_1x) dac_rst  <= ~frstn[0] |  rst_after_locked;

  // -------------------------------------------------------------------------
  // AXI Register Wires
  // -------------------------------------------------------------------------
  wire [31:0] read_reg0, read_reg1, read_reg2, read_reg3;
  wire [31:0] read_reg4, read_reg5, read_reg6, read_reg7;
  
  wire [31:0] write_reg8, write_reg9;
  
  // Set unused inputs back to PS to 0 to prevent floating wires
  wire [31:0] write_reg10 = 32'h0;
  wire [31:0] write_reg11 = 32'h0;
  wire [31:0] write_reg12 = 32'h0;
  wire [31:0] write_reg13 = 32'h0;
  wire [31:0] write_reg14 = 32'h0;
  wire [31:0] write_reg15 = 32'h0;

  // -------------------------------------------------------------------------
  // Sub-Module Instantiations
  // -------------------------------------------------------------------------

  // 1. Processing System Wrapper
  custom_ps ps_inst (
    .FIXED_IO_mio      (FIXED_IO_mio     ),
    .FIXED_IO_ps_clk   (FIXED_IO_ps_clk  ),
    .FIXED_IO_ps_porb  (FIXED_IO_ps_porb ),
    .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
    .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn ),
    .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp ),
    .DDR_addr          (DDR_addr         ),
    .DDR_ba            (DDR_ba           ),
    .DDR_cas_n         (DDR_cas_n        ),
    .DDR_ck_n          (DDR_ck_n         ),
    .DDR_ck_p          (DDR_ck_p         ),
    .DDR_cke           (DDR_cke          ),
    .DDR_cs_n          (DDR_cs_n         ),
    .DDR_dm            (DDR_dm           ),
    .DDR_dq            (DDR_dq           ),
    .DDR_dqs_n         (DDR_dqs_n        ),
    .DDR_dqs_p         (DDR_dqs_p        ),
    .DDR_odt           (DDR_odt          ),
    .DDR_ras_n         (DDR_ras_n        ),
    .DDR_reset_n       (DDR_reset_n      ),
    .DDR_we_n          (DDR_we_n         ),
    .fclk_clk_o        (fclk             ),
    .fclk_rstn_o       (frstn            ),
    // AXI Registers
    .read_reg0(read_reg0), .read_reg1(read_reg1), .read_reg2(read_reg2), .read_reg3(read_reg3),
    .read_reg4(read_reg4), .read_reg5(read_reg5), .read_reg6(read_reg6), .read_reg7(read_reg7),
    .write_reg8(write_reg8), .write_reg9(write_reg9), .write_reg10(write_reg10), .write_reg11(write_reg11),
    .write_reg12(write_reg12), .write_reg13(write_reg13), .write_reg14(write_reg14), .write_reg15(write_reg15)
  );

  // 3. Custom User Logic

  logic_test logic_inst (
    .clk         (fclk),        // Run logic at 125MHz ADC speed
    .reset_n     (frstn),
    .kp_in       (read_reg0),   // Read from ARM
    .ki_in       (read_reg1),
    .kd_in       (read_reg2),
    .state_in    (read_reg3),
    .status_out  (write_reg8),  // Write back to ARM
    .control_out (write_reg9)  // To DAC
  );

  // // Connect upper 14 bits of reg9 to DAC channel B as a test
  // wire [13:0] dac_b_override = read_reg4[13:0];
  // wire [13:0] custom_dac_out; // To drive the DAC

  // // 4. DAC Control Module
  // dac_ctrl dac_inst (
  //   .dac_clk_1x  (dac_clk_1x),
  //   .dac_clk_2x  (dac_clk_2x),
  //   .dac_clk_2p  (dac_clk_2p),
  //   .dac_rst     (dac_rst),
  //   .dac_a_i     (custom_dac_out), // Channel 1 driven by custom logic
  //   .dac_b_i     (dac_b_override), // Channel 2 driven directly by ARM reg4
  //   .dac_dat_o   (dac_dat_o),
  //   .dac_wrt_o   (dac_wrt_o),
  //   .dac_sel_o   (dac_sel_o),
  //   .dac_clk_o   (dac_clk_o),
  //   .dac_rst_o   (dac_rst_o)
  // );

  // // 2. ADC Control Module
  // wire signed [13:0] adc_dat_a;
  // wire signed [13:0] adc_dat_b;
  
  // adc_ctrl #(.ADW(ADW), .MNA(MNA)) adc_inst (
  //   .adc_clk     (adc_clk),
  //   .adc_dat_i   (adc_dat_i),
  //   .adc_dat_a_o (adc_dat_a),
  //   .adc_dat_b_o (adc_dat_b),
  //   .adc_clk_o   (adc_clk_o),
  //   .adc_cdcs_o  (adc_cdcs_o)
  // );

  // Hardcode LEDs off or bind them to a register
  assign led_o = read_reg4[7:0]; 

endmodule
