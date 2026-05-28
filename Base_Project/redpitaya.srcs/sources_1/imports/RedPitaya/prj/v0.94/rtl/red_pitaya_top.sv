////////////////////////////////////////////////////////////////////////////////
// Red Pitaya TOP module. It connects external pins and PS part with
// other application modules.
// Authors: Matej Oblak, Iztok Jeras
// (c) Red Pitaya  http://www.redpitaya.com
////////////////////////////////////////////////////////////////////////////////

module red_pitaya_top #(
  // identification
  bit [0:5*32-1] GITH = '0,
  // module numbers
  parameter MNA = 2,  // number of acquisition modules
  parameter MNG = 2,  // number of generator   modules
  parameter ADW_125 = 14,
  parameter ADW_122 = 16,
  parameter DWE_Z20 = 11,
  parameter DWE_Z10 = 8,
  parameter DDW     = 14,
`ifdef Z20_122
  parameter ADW=ADW_122,
  parameter ADC_DW=ADW_122,
`else
  parameter ADW=ADW_125,
  parameter ADC_DW=ADW_125,
`endif
`ifdef Z20_xx
  parameter DWE=DWE_Z20
`else
  parameter DWE=DWE_Z10
`endif
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

  // Red Pitaya periphery

  // ADC
  input  logic [MNA-1:0] [16-1:0] adc_dat_i,  // ADC data
  input  logic           [ 2-1:0] adc_clk_i,  // ADC clock {p,n}
  output logic           [ 2-1:0] adc_clk_o,  // optional ADC clock source
  output logic                    adc_cdcs_o, // ADC clock duty cycle stabilizer
  // DAC
  output logic [ 14-1:0] dac_dat_o  ,  // DAC combined data
  output logic           dac_wrt_o  ,  // DAC write
  output logic           dac_sel_o  ,  // DAC channel select
  output logic           dac_clk_o  ,  // DAC clock
  output logic           dac_rst_o  ,  // DAC reset
  // PWM DAC
  output logic [  4-1:0] dac_pwm_o  ,  // 1-bit PWM DAC
  // XADC
  input  logic [  5-1:0] vinp_i     ,  // voltages p
  input  logic [  5-1:0] vinn_i     ,  // voltages n
  // Expansion connector
  inout  logic [DWE-1:0] exp_p_io  ,
  inout  logic [DWE-1:0] exp_n_io  ,
  // SATA connector
  output logic [  2-1:0] daisy_p_o  ,  // line 1 is clock capable
  output logic [  2-1:0] daisy_n_o  ,
  input  logic [  2-1:0] daisy_p_i  ,  // line 1 is clock capable
  input  logic [  2-1:0] daisy_n_i  ,

  `ifdef Z20_G2
  // Additional E3 connector
  output logic [  4-1:0] exp_e3p_o  ,  // line 3 is clock capable (SRCC)
  output logic [  4-1:0] exp_e3n_o  ,
  input  logic [  4-1:0] exp_e3p_i  ,  // line 3 is clock capable (MRCC)
  input  logic [  4-1:0] exp_e3n_i  ,
  input  logic           s1_orient_i ,
  input  logic           s1_link_i   ,
  `endif
  // LED
  output  logic [  8-1:0] led_o
);

////////////////////////////////////////////////////////////////////////////////
// local signals
////////////////////////////////////////////////////////////////////////////////

// Tie off unused outputs
assign adc_clk_o  = 2'b00;
assign adc_cdcs_o = 1'b1;
assign dac_dat_o  = 14'b0;
assign dac_wrt_o  = 1'b0;
assign dac_sel_o  = 1'b0;
assign dac_clk_o  = 1'b0;
assign dac_rst_o  = 1'b0;
assign dac_pwm_o  = 4'b0;

// Properly tie off unused differential daisy outputs using OBUFDS
OBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18"), .SLEW ("FAST")) i_OBUF_daisy_0 (
  .O  ( daisy_p_o[0] ),
  .OB ( daisy_n_o[0] ),
  .I  ( 1'b0 )
);

OBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18"), .SLEW ("FAST")) i_OBUF_daisy_1 (
  .O  ( daisy_p_o[1] ),
  .OB ( daisy_n_o[1] ),
  .I  ( 1'b0 )
);

`ifdef Z20_G2
assign exp_e3p_o  = 4'b0;
assign exp_e3n_o  = 4'b0;
`endif

// GPIO input data width
localparam int unsigned GDW = DWE;
localparam RST_MAX = 64;
logic [4-1:0] fclk ; //[0]-125MHz, [1]-250MHz, [2]-50MHz, [3]-200MHz
logic [4-1:0] frstn;

logic [ 3-1:0] daisy_mode;
logic          trig_output_sel = 1'b0; // Scope removed

// PLL signals
logic                 adc_clk_in;
logic                 pll_adc_clk;
logic                 pll_locked;
logic                 pll_locked_r;
logic                 fpll_locked_r,fpll_locked_r2,fpll_locked_r3;

logic   [16-1:0]      rst_cnt = 'h0;
logic                 rst_after_locked;
logic                 rstn_pll;

// ADC clock/reset (Used for HK and SYS bus)
logic                 adc_clk;
logic                 adc_rstn;

//CAN
logic                 CAN0_rx, CAN0_tx;
logic                 CAN1_rx, CAN1_tx;
logic                 can_on;

// configuration
logic [2-1:0]         digital_loop;

// system bus
sys_bus_if   ps_sys      (.clk (fclk[0]), .rstn (frstn[0]));
sys_bus_if   sys [8-1:0] (.clk (adc_clk), .rstn (adc_rstn));

// GPIO interface
gpio_if #(.DW (3*GDW)) gpio ();

// AXI masters (Kept interface declarations to satisfy the PS module instantiation)
axi_sys_if axi0_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi1_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi2_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi3_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));

////////////////////////////////////////////////////////////////////////////////
// PLL (clock and reset)
////////////////////////////////////////////////////////////////////////////////

// diferential clock input
IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));  // differential clock input

assign rstn_pll = frstn[0] & ~(!fpll_locked_r2 && fpll_locked_r3);
red_pitaya_pll pll (
  // inputs
  .clk         (adc_clk_in),  // clock
  .rstn        (rstn_pll  ),  // reset - active low
  // output clocks
  .clk_adc     (pll_adc_clk   ),  // ADC clock
  .clk_dac_1x  (),  
  .clk_dac_2x  (),  
  .clk_dac_2p  (),  
  .clk_ser     (),  
  .clk_pdm     (),  
  // status outputs
  .pll_locked  (pll_locked    )
);

BUFG bufg_adc_clk     (.O (adc_clk    ), .I (pll_adc_clk   ));

always @(posedge fclk[0]) begin
  fpll_locked_r   <= pll_locked;
  fpll_locked_r2  <= fpll_locked_r;
  fpll_locked_r3  <= fpll_locked_r2;
end

always @(posedge adc_clk) begin
  pll_locked_r      <= pll_locked;
  if ((pll_locked && !pll_locked_r) || rst_cnt > 0) begin // some clk cycles after rising edge of pll_locked
    if (rst_cnt < RST_MAX)
      rst_cnt <= rst_cnt + 1;
    else 
      rst_cnt <= 'h0;
  end else begin
    if (~pll_locked) begin
      rst_cnt <= 'h0;
    end
  end
end

assign rst_after_locked = |rst_cnt;
// ADC reset (active low)
always @(posedge adc_clk)
adc_rstn     <=  frstn[0] & ~rst_after_locked;

////////////////////////////////////////////////////////////////////////////////
//  Connections to PS
////////////////////////////////////////////////////////////////////////////////

red_pitaya_ps ps (
  .FIXED_IO_mio       (  FIXED_IO_mio                ),
  .FIXED_IO_ps_clk    (  FIXED_IO_ps_clk             ),
  .FIXED_IO_ps_porb   (  FIXED_IO_ps_porb            ),
  .FIXED_IO_ps_srstb  (  FIXED_IO_ps_srstb           ),
  .FIXED_IO_ddr_vrn   (  FIXED_IO_ddr_vrn            ),
  .FIXED_IO_ddr_vrp   (  FIXED_IO_ddr_vrp            ),
  // DDR
  .DDR_addr      (DDR_addr    ),
  .DDR_ba        (DDR_ba      ),
  .DDR_cas_n     (DDR_cas_n   ),
  .DDR_ck_n      (DDR_ck_n    ),
  .DDR_ck_p      (DDR_ck_p    ),
  .DDR_cke       (DDR_cke     ),
  .DDR_cs_n      (DDR_cs_n    ),
  .DDR_dm        (DDR_dm      ),
  .DDR_dq        (DDR_dq      ),
  .DDR_dqs_n     (DDR_dqs_n   ),
  .DDR_dqs_p     (DDR_dqs_p   ),
  .DDR_odt       (DDR_odt     ),
  .DDR_ras_n     (DDR_ras_n   ),
  .DDR_reset_n   (DDR_reset_n ),
  .DDR_we_n      (DDR_we_n    ),
  // system signals
  .fclk_clk_o    (fclk        ),
  .fclk_rstn_o   (frstn       ),
  // ADC analog inputs
  .vinp_i        (vinp_i      ),
  .vinn_i        (vinn_i      ),
  // CAN0
  .CAN0_rx       (CAN0_rx     ),
  .CAN0_tx       (CAN0_tx     ),
  // CAN1
  .CAN1_rx       (CAN1_rx     ),
  .CAN1_tx       (CAN1_tx     ),
  // GPIO
  .gpio          (gpio),
  // system read/write channel
  .bus           (ps_sys      ),
  // AXI masters
  .axi0_sys      (axi0_sys    ),
  .axi1_sys      (axi1_sys    ),
  .axi2_sys      (axi2_sys    ),
  .axi3_sys      (axi3_sys    )
);

////////////////////////////////////////////////////////////////////////////////
// system bus decoder & multiplexer (it breaks memory addresses into 8 regions)
////////////////////////////////////////////////////////////////////////////////

sys_bus_interconnect #(
  .SN (8),
  .SW (20)
) sys_bus_interconnect (
  .pll_locked_i(pll_locked),
  .bus_m (ps_sys),
  .bus_s (sys)
);

////////////////////////////////////////////////////////////////////////////////
//  House Keeping
////////////////////////////////////////////////////////////////////////////////

logic [DWE-1: 0] exp_p_in ,  exp_n_in ;
logic [DWE-1: 0] exp_p_out,  exp_n_out;
logic [DWE-1: 0] exp_p_dir,  exp_n_dir;
logic [DWE-1: 0] exp_p_otr,  exp_n_otr;
logic [DWE-1: 0] exp_p_dtr,  exp_n_dtr;
logic [DWE-1: 0] exp_p_alt,  exp_n_alt;
logic [DWE-1: 0] exp_p_altr, exp_n_altr;
logic [DWE-1: 0] exp_p_altd, exp_n_altd;

red_pitaya_hk #(.DWE(DWE)) i_hk (
  // system signals
  .clk_i           (adc_clk    ),  // clock
  .rstn_i          (adc_rstn   ),  // reset - active low
  .fclk_i          (fclk[0]    ),  // clock
  .frstn_i         (frstn[0]   ),  // reset - active low

  // LED
//  .led_o           (  led_o    ),  // LED output
  // global configuration
  .digital_loop    (digital_loop),
  .daisy_mode_o    (daisy_mode),
  // Expansion connector
  .exp_p_dat_i     (exp_p_in ),  // input data
  .exp_p_dat_o     (exp_p_out),  // output data
  .exp_p_dir_o     (exp_p_dir),  // 1-output enable
  .exp_n_dat_i     (exp_n_in ),
  .exp_n_dat_o     (exp_n_out),
  .exp_n_dir_o     (exp_n_dir),
  .can_on_o        (can_on   ),
   // System bus
  .sys_addr        (sys[0].addr ),
  .sys_wdata       (sys[0].wdata),
  .sys_wen         (sys[0].wen  ),
  .sys_ren         (sys[0].ren  ),
  .sys_rdata       (sys[0].rdata),
  .sys_err         (sys[0].err  ),
  .sys_ack         (sys[0].ack  )
);

////////////////////////////////////////////////////////////////////////////////
// GPIO
////////////////////////////////////////////////////////////////////////////////

assign exp_p_alt  = {DWE{1'b0}};
assign exp_n_alt  = {{DWE-8{1'b0}},  can_on,  can_on, 5'h0, daisy_mode[1]  };

assign exp_p_altr = {DWE{1'b0}};
assign exp_n_altr = {{DWE-8{1'b0}}, CAN0_tx, CAN1_tx, 5'h0, trig_output_sel};

assign exp_p_altd = {DWE{1'b0}};
assign exp_n_altd = {{DWE-8{1'b0}},   1'b1,   1'b1, 5'h0, 1'b1};

genvar GM;
generate
for(GM = 0 ; GM < DWE ; GM = GM + 1) begin : gpios
  assign exp_p_otr[GM] = exp_p_alt[GM] ? exp_p_altr[GM] : exp_p_out[GM];
  assign exp_n_otr[GM] = exp_n_alt[GM] ? exp_n_altr[GM] : exp_n_out[GM];

  assign exp_p_dtr[GM] = exp_p_alt[GM] ? exp_p_altd[GM] : exp_p_dir[GM];
  assign exp_n_dtr[GM] = exp_n_alt[GM] ? exp_n_altd[GM] : exp_n_dir[GM];
end
endgenerate

IOBUF i_iobufp [DWE-1:0] (.O(exp_p_in), .IO(exp_p_io), .I(exp_p_otr), .T(~exp_p_dtr) );
IOBUF i_iobufn [DWE-1:0] (.O(exp_n_in), .IO(exp_n_io), .I(exp_n_otr), .T(~exp_n_dtr) );

assign gpio.i[2*GDW-1:  GDW] = exp_p_in[GDW-1:0];
assign gpio.i[3*GDW-1:2*GDW] = exp_n_in[GDW-1:0];

assign CAN0_rx = can_on & exp_p_in[7];
assign CAN1_rx = can_on & exp_p_in[6];

//// Stub out unused system bus regions
//generate
//for (genvar i=1; i<8; i++) begin: for_sys_stubs
//  sys_bus_stub sys_bus_stub_block (sys[i]);
//end: for_sys_stubs
//endgenerate

//////////////////////////////////////////////////////////////////////////////////
//// Custom Blink Logic
//////////////////////////////////////////////////////////////////////////////////

//wire blink_state;

//// Instantiate the custom blink module
//red_pitaya_blink i_blink (
//    .clk_i (adc_clk),      // Feed it the core ADC clock
//    .led_o (led_o)   // Wire the output to our local signal
//);

////////////////////////////////////////////////////////////////////////////////
// Custom AXI LED Control
////////////////////////////////////////////////////////////////////////////////

red_pitaya_led_axi i_led_ctrl (
  .clk_i    (adc_clk),
  .rstn_i   (adc_rstn),
  // Connect to System Bus Region 6
  .sys_addr  (sys[6].addr),
  .sys_wdata (sys[6].wdata),
  .sys_wen   (sys[6].wen),
  .sys_ren   (sys[6].ren),
  .sys_rdata (sys[6].rdata),
  .sys_err   (sys[6].err),
  .sys_ack   (sys[6].ack),
  // Output to physical LEDs
  .led_o     (led_o)
);

endmodule: red_pitaya_top