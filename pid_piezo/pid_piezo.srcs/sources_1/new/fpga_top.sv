`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Red Pitaya TOP module - CUSTOM RAMP & TIMESTAMP Detection + Test EDITION
////////////////////////////////////////////////////////////////////////////////

/**
 * GENERAL DESCRIPTION:
 *
 * Top module connects PS part with rest of Red Pitaya applications.  
 *
 *                   /-------\      
 *   PS DDR <------> |  PS   |      AXI <-> custom bus
 *   PS MIO <------> |   /   | <-----------------------+
 *   PS CLK -------> |  ARM  |                         |
 *                   \-------/                         |
 *                                                     |
 *                            /---------------\        |
 *                         -> | Peak Detector | <------+
 *                         |  \---------------/        |
 *                         |                           |
 *            /--------\   |   /-----\                 |
 *   ADC ---> |        | --+-> | Free | <--------------+
 *            |        |       \-----/                 |
 *            | ANALOG |                               |
 *            |        |       /----------------\      |
 *   DAC <--- |        | <---- | Ramp Generator |<-----+
 *            \--------/   ^   \----------------/      |
 *                         |                           |
 *                         |  /----------------\       |
 *                         -- |  Peak Detector | <-----+ 
 *                            |     Tester     |
 *                            \----------------/     
 *                                          
 *
 * Inside analog module, ADC data is translated from unsigned neg-slope into
 * two's complement. Similar is done on DAC data.
 */

module fpga_top #(
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
  output logic           [ 2-1:0] adc_clk_o,  // optional ADC clock source (unused) [0] = p; [1] = n
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
  output logic [  2-1:0] daisy_p_o  ,
  output logic [  2-1:0] daisy_n_o  ,
  input  logic [  2-1:0] daisy_p_i  ,
  input  logic [  2-1:0] daisy_n_i  ,
  // LED
  output logic [  8-1:0] led_o
);

////////////////////////////////////////////////////////////////////////////////
// local signals
////////////////////////////////////////////////////////////////////////////////
localparam int unsigned GDW = DWE;
localparam RST_MAX = 64;
logic [4-1:0] fclk ;
logic [4-1:0] frstn;

logic adc_clk_in, pll_adc_clk, pll_dac_clk_1x, pll_dac_clk_2x, pll_dac_clk_2p, pll_ser_clk, pll_pwm_clk;
logic pll_locked, pll_locked_r, fpll_locked_r, fpll_locked_r2, fpll_locked_r3;
logic [16-1:0] rst_cnt = 'h0;
logic rst_after_locked, rstn_pll;
logic ser_clk, pwm_clk, pwm_rstn, adc_clk, adc_rstn;
logic dac_clk_1x, dac_clk_2x, dac_clk_2p, dac_axi_clk, dac_rst, dac_axi_rstn;

localparam type SBA_T = logic signed [ADW-1:0]; 
SBA_T [MNA-1:0] adc_dat;
logic [14-1:0] dac_dat_a, dac_dat_b, dac_a, dac_b;

// system bus
sys_bus_if   ps_sys      (.clk (fclk[0]), .rstn (frstn[0]));
sys_bus_if   sys [8-1:0] (.clk (adc_clk), .rstn (adc_rstn));
gpio_if #(.DW (3*GDW)) gpio ();
axi_sys_if axi0_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi1_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi2_sys (.clk(dac_axi_clk), .rstn(dac_axi_rstn));
axi_sys_if axi3_sys (.clk(dac_axi_clk), .rstn(dac_axi_rstn));

////////////////////////////////////////////////////////////////////////////////
// PLL & PS Instantiation
////////////////////////////////////////////////////////////////////////////////
IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));
assign rstn_pll = frstn[0] & ~(!fpll_locked_r2 && fpll_locked_r3);

red_pitaya_pll pll (
  .clk         (adc_clk_in),
  .rstn        (rstn_pll  ),
  .clk_adc     (pll_adc_clk   ),
  .clk_dac_1x  (pll_dac_clk_1x),
  .clk_dac_2x  (pll_dac_clk_2x),
  .clk_dac_2p  (pll_dac_clk_2p),
  .clk_ser     (pll_ser_clk   ),
  .clk_pdm     (pll_pwm_clk   ),
  .pll_locked  (pll_locked    )
);

BUFG bufg_adc_clk     (.O (adc_clk    ), .I (pll_adc_clk   ));
BUFG bufg_dac_clk_1x  (.O (dac_clk_1x ), .I (pll_dac_clk_1x));
BUFG bufg_dac_clk_2x  (.O (dac_clk_2x ), .I (pll_dac_clk_2x));
BUFG bufg_dac_axi_clk (.O (dac_axi_clk), .I (pll_dac_clk_2x));
BUFG bufg_dac_clk_2p  (.O (dac_clk_2p ), .I (pll_dac_clk_2p));
BUFG bufg_ser_clk     (.O (ser_clk    ), .I (pll_ser_clk   ));
BUFG bufg_pwm_clk     (.O (pwm_clk    ), .I (pll_pwm_clk   ));

always @(posedge fclk[0]) begin
  fpll_locked_r   <= pll_locked;
  fpll_locked_r2  <= fpll_locked_r;
  fpll_locked_r3  <= fpll_locked_r2;
end

always @(posedge adc_clk) begin
  pll_locked_r <= pll_locked;
  if ((pll_locked && !pll_locked_r) || rst_cnt > 0) begin 
    if (rst_cnt < RST_MAX) rst_cnt <= rst_cnt + 1;
    else rst_cnt <= 'h0;
  end else begin
    if (~pll_locked) rst_cnt <= 'h0;
  end
end

assign rst_after_locked = |rst_cnt;
always @(posedge adc_clk)     adc_rstn     <=  frstn[0] & ~rst_after_locked;
always @(posedge dac_clk_1x)  dac_rst      <= ~frstn[0] |  rst_after_locked;
always @(posedge dac_axi_clk) dac_axi_rstn <=  frstn[0] & ~rst_after_locked;
always @(posedge pwm_clk)     pwm_rstn     <=  frstn[0] & ~rst_after_locked;

red_pitaya_ps ps (
  .FIXED_IO_mio       (FIXED_IO_mio     ),
  .FIXED_IO_ps_clk    (FIXED_IO_ps_clk  ),
  .FIXED_IO_ps_porb   (FIXED_IO_ps_porb ),
  .FIXED_IO_ps_srstb  (FIXED_IO_ps_srstb),
  .FIXED_IO_ddr_vrn   (FIXED_IO_ddr_vrn ),
  .FIXED_IO_ddr_vrp   (FIXED_IO_ddr_vrp ),
  .DDR_addr      (DDR_addr   ), .DDR_ba       (DDR_ba     ),
  .DDR_cas_n     (DDR_cas_n  ), .DDR_ck_n     (DDR_ck_n   ),
  .DDR_ck_p      (DDR_ck_p   ), .DDR_cke      (DDR_cke    ),
  .DDR_cs_n      (DDR_cs_n   ), .DDR_dm       (DDR_dm     ),
  .DDR_dq        (DDR_dq     ), .DDR_dqs_n    (DDR_dqs_n  ),
  .DDR_dqs_p     (DDR_dqs_p  ), .DDR_odt      (DDR_odt    ),
  .DDR_ras_n     (DDR_ras_n  ), .DDR_reset_n  (DDR_reset_n),
  .DDR_we_n      (DDR_we_n   ),
  .fclk_clk_o    (fclk       ), .fclk_rstn_o  (frstn      ),
  .vinp_i        (vinp_i     ), .vinn_i       (vinn_i     ),
  .CAN0_rx(1'b1), .CAN0_tx(), .CAN1_rx(1'b1), .CAN1_tx(), // Tied off CAN
  .gpio          (gpio),
  .bus           (ps_sys     ),
  .axi0_sys      (axi0_sys   ), .axi1_sys     (axi1_sys   ),
  .axi2_sys      (axi2_sys   ), .axi3_sys     (axi3_sys   )
);

sys_bus_interconnect #(.SN (8), .SW (20)) sys_bus_interconnect (
  .pll_locked_i(pll_locked), .bus_m (ps_sys), .bus_s (sys)
);

////////////////////////////////////////////////////////////////////////////////
// ADC Format Logic
////////////////////////////////////////////////////////////////////////////////
assign adc_cdcs_o = 1'b1;
logic [2-1:0] [ADW-1:0] adc_dat_raw;
assign adc_dat_raw[0] = adc_dat_i[0][16-1 -: ADW];
assign adc_dat_raw[1] = adc_dat_i[1][16-1 -: ADW];

always @(posedge adc_clk) begin
  // 2s complement mapping
  adc_dat[0] <= {adc_dat_raw[0][ADW-1], ~adc_dat_raw[0][ADW-2:0]};
  adc_dat[1] <= {adc_dat_raw[1][ADW-1], ~adc_dat_raw[1][ADW-2:0]};
end

////////////////////////////////////////////////////////////////////////////////
// DAC Format Logic
////////////////////////////////////////////////////////////////////////////////
// Output registers + signed to unsigned (negative slope format for Red Pitaya DAC)
always @(posedge dac_clk_1x) begin 
  dac_dat_a <= {dac_a[14-1], ~dac_a[14-2:0]};
  dac_dat_b <= {dac_b[14-1], ~dac_b[14-2:0]};
end

ODDR oddr_dac_clk          (.Q(dac_clk_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2p), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_wrt          (.Q(dac_wrt_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_sel          (.Q(dac_sel_o), .D1(1'b1     ), .D2(1'b0     ), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
ODDR oddr_dac_rst          (.Q(dac_rst_o), .D1(dac_rst  ), .D2(dac_rst  ), .C(dac_clk_1x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_dat [14-1:0] (.Q(dac_dat_o), .D1(dac_dat_b), .D2(dac_dat_a), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));

// Unused Outputs Tied Off
ODDR i_adc_clk_p ( .Q(adc_clk_o[0]), .D1(1'b1), .D2(1'b0), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));
ODDR i_adc_clk_n ( .Q(adc_clk_o[1]), .D1(1'b0), .D2(1'b1), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));
assign dac_pwm_o = 4'b0;

////////////////////////////////////////////////////////////////////////////////
// SYS [0]: Housekeeping (Kept for LEDs and basic board config)
////////////////////////////////////////////////////////////////////////////////
logic [DWE-1: 0] exp_p_in, exp_p_out, exp_p_dir;
logic [DWE-1: 0] exp_n_in, exp_n_out, exp_n_dir;
logic [2-1:0] digital_loop;

red_pitaya_hk #(.DWE(DWE)) i_hk (
  .clk_i(adc_clk), .rstn_i(adc_rstn), .fclk_i(fclk[0]), .frstn_i(frstn[0]),
  .led_o(led_o), .digital_loop(digital_loop), .daisy_mode_o(),
  .exp_p_dat_i(exp_p_in), .exp_p_dat_o(exp_p_out), .exp_p_dir_o(exp_p_dir),
  .exp_n_dat_i(exp_n_in), .exp_n_dat_o(exp_n_out), .exp_n_dir_o(exp_n_dir),
  .sys_addr(sys[0].addr), .sys_wdata(sys[0].wdata), .sys_wen(sys[0].wen),
  .sys_ren(sys[0].ren), .sys_rdata(sys[0].rdata), .sys_err(sys[0].err), .sys_ack(sys[0].ack)
);

////////////////////////////////////////////////////////////////////////////////
// Global Orchestration Signals
////////////////////////////////////////////////////////////////////////////////
logic signed [2:0] mode;
logic global_trigger;

// Split Ramp Triggers
logic ramp_trigger_start;
logic ramp_trigger_max;

logic ramp_arm;
logic detector_arm;
logic generator_arm;
logic pid_arm;

// Mode to Arm Signal Decoder
always_comb begin
    // Default state: all off
    ramp_arm      = 1'b0;
    detector_arm  = 1'b0;
    generator_arm = 1'b0;
    pid_arm       = 1'b0;

    case (mode)
        -3'sd2: begin
            // Mode -2: Arm ramp, detector, and generator
            ramp_arm      = 1'b1;
            detector_arm  = 1'b1;
            generator_arm = 1'b1;
            pid_arm       = 1'b1;
        end
        -3'sd1: begin
            // Mode -1: Arm ramp, detector, and generator
            ramp_arm      = 1'b1;
            detector_arm  = 1'b1;
            generator_arm = 1'b1;
            pid_arm       = 1'b0;
        end
        3'sd0: begin
            // Mode 0: All arm signals off
            ramp_arm      = 1'b0;
            detector_arm  = 1'b0;
            generator_arm = 1'b0;
            pid_arm       = 1'b0;
        end
        3'sd1: begin
            // Mode 1: Arm ramp, detector
            ramp_arm      = 1'b1;
            detector_arm  = 1'b1;
            generator_arm = 1'b0;
            pid_arm       = 1'b0;
        end
        3'sd2: begin
            // Mode 2: Arm ramp, detector, and pid
            ramp_arm      = 1'b1;
            detector_arm  = 1'b1;
            generator_arm = 1'b0;
            pid_arm       = 1'b1;
        end
        default: begin
            // Other modes to be implemented later fall back to default (0)
        end
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// SYS [1]: Master System Controller
////////////////////////////////////////////////////////////////////////////////
system_controller i_sys_ctrl (
    .clk_i            (adc_clk),
    .rstn_i           (adc_rstn),
    .mode_o           (mode),
    .global_trigger_o (global_trigger),
    .sys_addr         (sys[1].addr ),
    .sys_wdata        (sys[1].wdata),
    .sys_wen          (sys[1].wen  ),
    .sys_ren          (sys[1].ren  ),
    .sys_rdata        (sys[1].rdata),
    .sys_err          (sys[1].err  ),
    .sys_ack          (sys[1].ack  )
);

////////////////////////////////////////////////////////////////////////////////
// SYS [2]: Custom Ramp Generator (DAC Channel A)
////////////////////////////////////////////////////////////////////////////////
custom_ramp_gen generator_ramp (
    .clk_i            (adc_clk),
    .rstn_i           (adc_rstn),
    .arm_i            (ramp_arm),       
    .trigger_i        (global_trigger), 
    
    // Dual Trigger Outputs
    .trigger_start_o  (ramp_trigger_start), 
    .trigger_max_o    (ramp_trigger_max), 
    
    .dac_dat_o        (dac_a),
    .sys_addr         (sys[2].addr ),
    .sys_wdata        (sys[2].wdata),
    .sys_wen          (sys[2].wen  ),
    .sys_ren          (sys[2].ren  ),
    .sys_rdata        (sys[2].rdata),
    .sys_err          (sys[2].err  ),
    .sys_ack          (sys[2].ack  )
);

////////////////////////////////////////////////////////////////////////////////
// SYS [3]: Custom Peak & Timestamp Detector (ADC Channel A)
////////////////////////////////////////////////////////////////////////////////
custom_timestamp_detector detector_timestamp (
    .clk_i              (adc_clk),
    .rstn_i             (adc_rstn),
    .arm_i              (detector_arm),   
    
    // Map the split triggers from the ramp generator
    .trigger_start_i    (ramp_trigger_start), 
    .trigger_max_i      (ramp_trigger_max),   
    
    .adc_dat_i          (adc_dat[0]),
    
//    // Hardware Outputs to route to PID module
//    .pid_trigger_o      (hw_pid_trigger),
//    .filt_peak_count_o  (hw_filt_peak_count),
//    .filt_ts_1_o        (hw_ts_1), .filt_ts_2_o (hw_ts_2),
//    .filt_ts_3_o        (hw_ts_3), .filt_ts_4_o (hw_ts_4),
//    .filt_ts_5_o        (hw_ts_5), .filt_ts_6_o (hw_ts_6),
//    .filt_ts_7_o        (hw_ts_7), .filt_ts_8_o (hw_ts_8),
    
    // AXI Bus
    .sys_addr           (sys[3].addr ),
    .sys_wdata          (sys[3].wdata),
    .sys_wen            (sys[3].wen  ),
    .sys_ren            (sys[3].ren  ),
    .sys_rdata          (sys[3].rdata),
    .sys_err            (sys[3].err  ),
    .sys_ack            (sys[3].ack  )
);

////////////////////////////////////////////////////////////////////////////////
// SYS [4]: Custom Test Peak Generator (DAC Channel B)
////////////////////////////////////////////////////////////////////////////////
custom_test_peak_gen generator_test_peak (
    .clk_i            (adc_clk),
    .rstn_i           (adc_rstn),
    .arm_i            (generator_arm),  
    
    // Map the split triggers from the ramp generator
    .trigger_start_i  (ramp_trigger_start), 
    .trigger_max_i    (ramp_trigger_max), 
      
    .dac_dat_o        (dac_b),          
    .sys_addr         (sys[4].addr ),
    .sys_wdata        (sys[4].wdata),
    .sys_wen          (sys[4].wen  ),
    .sys_ren          (sys[4].ren  ),
    .sys_rdata        (sys[4].rdata),
    .sys_err          (sys[4].err  ),
    .sys_ack          (sys[4].ack  )
);

////////////////////////////////////////////////////////////////////////////////
// SYS [5]: TEST PID CONTROLLER (DAC Channel B)
////////////////////////////////////////////////////////////////////////////////
pid_top pid_test_instance (
    .clk_i      (adc_clk),
    .rstn_i     (adc_rstn),
    .arm_i      (pid_arm),
    .sys_addr   (sys[5].addr ),
    .sys_wdata  (sys[5].wdata),
    .sys_wen    (sys[5].wen  ),
    .sys_ren    (sys[5].ren  ),
    .sys_rdata  (sys[5].rdata),
    .sys_err    (sys[5].err  ),
    .sys_ack    (sys[5].ack  )
);

////////////////////////////////////////////////////////////////////////////////
// SYS [5-7]: Unused Bus Stubs (Updated to start from 5)
////////////////////////////////////////////////////////////////////////////////
generate
for (genvar i=6; i<8; i++) begin: for_sys
  sys_bus_stub sys_bus_stub_i (sys[i]);
end
endgenerate

////////////////////////////////////////////////////////////////////////////////
// Unused Daisy Chain Outputs Tied Off
////////////////////////////////////////////////////////////////////////////////
OBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18"), .SLEW ("FAST")) i_OBUF_daisy_clk (
  .O  ( daisy_p_o[1]  ),
  .OB ( daisy_n_o[1]  ),
  .I  ( 1'b0          )
);

OBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18"), .SLEW ("FAST")) i_OBUF_daisy_dat (
  .O  ( daisy_p_o[0]  ),
  .OB ( daisy_n_o[0]  ),
  .I  ( 1'b0          )
);

endmodule

