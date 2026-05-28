////////////////////////////////////////////////////////////////////////////////
// @brief Red Pitaya Processing System (PS) wrapper. Including simple AXI slave.
// @Author Matej Oblak
// (c) Red Pitaya  http://www.redpitaya.com
////////////////////////////////////////////////////////////////////////////////

/**
 * GENERAL DESCRIPTION:
 *
 * Wrapper of block design.  
 *
 *                   /-------\
 *   PS CLK -------> |       | <---------------------> SPI master & slave
 *   PS RST -------> |  PS   |
 *                   |       | ------------+---------> FCLK & reset 
 *                   |       |             |
 *   PS DDR <------> |  ARM  |   AXI   /-------\
 *   PS MIO <------> |       | <-----> |  AXI  | <---> system bus
 *                   \-------/         | SLAVE |
 *                                     \-------/
 *
 * Module wrappes PS module (BD design from Vivado or EDK from PlanAhead).
 * There is also included simple AXI slave which serves as master for custom
 * system bus. With this simpler bus it is more easy for newbies to develop 
 * their own module communication with ARM.
 */

module custom_ps (
  // PS peripherals
  inout  logic [ 54-1:0] FIXED_IO_mio       ,
  inout  logic           FIXED_IO_ps_clk    ,
  inout  logic           FIXED_IO_ps_porb   ,
  inout  logic           FIXED_IO_ps_srstb  ,
  inout  logic           FIXED_IO_ddr_vrn   ,
  inout  logic           FIXED_IO_ddr_vrp   ,
  // DDR
  inout  logic [ 15-1:0] DDR_addr           ,
  inout  logic [  3-1:0] DDR_ba             ,
  inout  logic           DDR_cas_n          ,
  inout  logic           DDR_ck_n           ,
  inout  logic           DDR_ck_p           ,
  inout  logic           DDR_cke            ,
  inout  logic           DDR_cs_n           ,
  inout  logic [  4-1:0] DDR_dm             ,
  inout  logic [ 32-1:0] DDR_dq             ,
  inout  logic [  4-1:0] DDR_dqs_n          ,
  inout  logic [  4-1:0] DDR_dqs_p          ,
  inout  logic           DDR_odt            ,
  inout  logic           DDR_ras_n          ,
  inout  logic           DDR_reset_n        ,
  inout  logic           DDR_we_n           ,
  // system signals
  output logic           fclk_clk_o         ,
  output logic           fclk_rstn_o        ,
  
  output logic [32-1:0]  read_reg0,
  output logic [32-1:0]  read_reg1,
  output logic [32-1:0]  read_reg2,
  output logic [32-1:0]  read_reg3,
  output logic [32-1:0]  read_reg4,
  output logic [32-1:0]  read_reg5,
  output logic [32-1:0]  read_reg6,
  output logic [32-1:0]  read_reg7,
  
  input  logic [32-1:0]  write_reg8,
  input  logic [32-1:0]  write_reg9,
  input  logic [32-1:0]  write_reg10,
  input  logic [32-1:0]  write_reg11,
  input  logic [32-1:0]  write_reg12,
  input  logic [32-1:0]  write_reg13,
  input  logic [32-1:0]  write_reg14,
  input  logic [32-1:0]  write_reg15
);

////////////////////////////////////////////////////////////////////////////////
// PS STUB
////////////////////////////////////////////////////////////////////////////////

logic fclk_clk ;
logic fclk_rstn;

BUFG fclk_buf (.O(fclk_clk_o), .I(fclk_clk));
assign fclk_rstn_o = fclk_rstn;

//wire [32-1:0] read_reg0, read_reg1, read_reg2, read_reg3, read_reg4, read_reg5, read_reg6, read_reg7;
//wire [32-1:0] write_reg8, read_reg9, read_reg10, read_reg11, read_reg12, read_reg13, read_reg14, read_reg15;

`ifdef SIMULATION
system_model system_i
`else
ps_system ps_system_i 
`endif //SIMULATION
(
  // MIO
  .FIXED_IO_mio      (FIXED_IO_mio     ),
  .FIXED_IO_ps_clk   (FIXED_IO_ps_clk  ),
  .FIXED_IO_ps_porb  (FIXED_IO_ps_porb ),
  .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
  .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn ),
  .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp ),
  // DDR
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
  // FCLKs
  .FCLK_CLK0         (fclk_clk      ),
  .FCLK_RESET0_N     (fclk_rstn     ),
  // Read Registers
  .read_reg0(read_reg0),
  .read_reg1(read_reg1),
  .read_reg2(read_reg2),
  .read_reg3(read_reg3),
  .read_reg4(read_reg4),
  .read_reg5(read_reg5),
  .read_reg6(read_reg6),
  .read_reg7(read_reg7),
  // Write Registers
  .write_reg8(write_reg8),
  .write_reg9(write_reg9),
  .write_reg10(write_reg10),
  .write_reg11(write_reg11),
  .write_reg12(write_reg12),
  .write_reg13(write_reg13),
  .write_reg14(write_reg14),
  .write_reg15(write_reg15)
);

endmodule
