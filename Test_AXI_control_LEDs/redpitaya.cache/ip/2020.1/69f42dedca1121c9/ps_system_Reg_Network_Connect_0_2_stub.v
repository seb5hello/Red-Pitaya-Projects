// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
// Date        : Sun May 10 18:15:04 2026
// Host        : DESKTOP-VSBV2NH running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ ps_system_Reg_Network_Connect_0_2_stub.v
// Design      : ps_system_Reg_Network_Connect_0_2
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z010clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "Reg_Network_Connect_v1_0,Vivado 2020.1" *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix(s00_axi_aclk, s00_axi_aresetn, 
  s00_axi_awaddr, s00_axi_awprot, s00_axi_awvalid, s00_axi_awready, s00_axi_wdata, 
  s00_axi_wstrb, s00_axi_wvalid, s00_axi_wready, s00_axi_bresp, s00_axi_bvalid, 
  s00_axi_bready, s00_axi_araddr, s00_axi_arprot, s00_axi_arvalid, s00_axi_arready, 
  s00_axi_rdata, s00_axi_rresp, s00_axi_rvalid, s00_axi_rready, read_reg0, read_reg1, 
  read_reg2, read_reg3, read_reg4, read_reg5, read_reg6, read_reg7, write_reg8, write_reg9, 
  write_reg10, write_reg11, write_reg12, write_reg13, write_reg14, write_reg15)
/* synthesis syn_black_box black_box_pad_pin="s00_axi_aclk,s00_axi_aresetn,s00_axi_awaddr[5:0],s00_axi_awprot[2:0],s00_axi_awvalid,s00_axi_awready,s00_axi_wdata[31:0],s00_axi_wstrb[3:0],s00_axi_wvalid,s00_axi_wready,s00_axi_bresp[1:0],s00_axi_bvalid,s00_axi_bready,s00_axi_araddr[5:0],s00_axi_arprot[2:0],s00_axi_arvalid,s00_axi_arready,s00_axi_rdata[31:0],s00_axi_rresp[1:0],s00_axi_rvalid,s00_axi_rready,read_reg0[31:0],read_reg1[31:0],read_reg2[31:0],read_reg3[31:0],read_reg4[31:0],read_reg5[31:0],read_reg6[31:0],read_reg7[31:0],write_reg8[31:0],write_reg9[31:0],write_reg10[31:0],write_reg11[31:0],write_reg12[31:0],write_reg13[31:0],write_reg14[31:0],write_reg15[31:0]" */;
  input s00_axi_aclk;
  input s00_axi_aresetn;
  input [5:0]s00_axi_awaddr;
  input [2:0]s00_axi_awprot;
  input s00_axi_awvalid;
  output s00_axi_awready;
  input [31:0]s00_axi_wdata;
  input [3:0]s00_axi_wstrb;
  input s00_axi_wvalid;
  output s00_axi_wready;
  output [1:0]s00_axi_bresp;
  output s00_axi_bvalid;
  input s00_axi_bready;
  input [5:0]s00_axi_araddr;
  input [2:0]s00_axi_arprot;
  input s00_axi_arvalid;
  output s00_axi_arready;
  output [31:0]s00_axi_rdata;
  output [1:0]s00_axi_rresp;
  output s00_axi_rvalid;
  input s00_axi_rready;
  output [31:0]read_reg0;
  output [31:0]read_reg1;
  output [31:0]read_reg2;
  output [31:0]read_reg3;
  output [31:0]read_reg4;
  output [31:0]read_reg5;
  output [31:0]read_reg6;
  output [31:0]read_reg7;
  input [31:0]write_reg8;
  input [31:0]write_reg9;
  input [31:0]write_reg10;
  input [31:0]write_reg11;
  input [31:0]write_reg12;
  input [31:0]write_reg13;
  input [31:0]write_reg14;
  input [31:0]write_reg15;
endmodule
