`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// AXI/SYS bus register test module
//
// This is not a full AXI slave. On Red Pitaya, the PS AXI GP interface is already
// converted into the lightweight sys_bus interface before it reaches this module.
//
// Register map:
//   0x00 CTRL        R/W  bit0 = enable, bit1 = clear counters
//   0x04 IN_A        R/W
//   0x08 IN_B        R/W
//   0x0C IN_C        R/W
//   0x10 RW_REG      R/W
//   0x14 OUT_SUM     R
//   0x18 OUT_XOR     R
//   0x1C STATUS      R
//   0x20 WRITE_COUNT R
//   0x24 READ_COUNT  R
//   0x28 FREE_COUNT  R
//   0xFC MAGIC       R
////////////////////////////////////////////////////////////////////////////////

module axi_test #(
    parameter int unsigned ID = 0
)(
    input  logic          clk_i,
    input  logic          rstn_i,

    output logic          led,

    input  logic [19:0]   sys_addr,
    input  logic [31:0]   sys_wdata,
    input  logic          sys_wen,
    input  logic          sys_ren,
    output logic [31:0]   sys_rdata,
    output logic          sys_err,
    output logic          sys_ack
);

    logic        enable;
    logic [31:0] in_a;
    logic [31:0] in_b;
    logic [31:0] in_c;
    logic [31:0] rw_reg;

    logic [31:0] write_count;
    logic [31:0] read_count;
    logic [31:0] free_count;

    logic [31:0] out_sum;
    logic [31:0] out_xor;

    assign out_sum = enable ? (in_a + in_b + in_c + rw_reg) : 32'h0000_0000;
    assign out_xor = enable ? (in_a ^ in_b ^ in_c ^ rw_reg) : 32'h0000_0000;

    // Deterministic LED test:
    // write CTRL bit0 = 1 and RW_REG bit0 = 1 to turn this LED on.
    assign led = enable & rw_reg[0];

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            enable      <= 1'b0;

            in_a        <= 32'h0000_0000;
            in_b        <= 32'h0000_0000;
            in_c        <= 32'h0000_0000;
            rw_reg      <= 32'h0000_0000;

            write_count <= 32'h0000_0000;
            read_count  <= 32'h0000_0000;
            free_count  <= 32'h0000_0000;

            sys_rdata   <= 32'h0000_0000;
            sys_ack     <= 1'b0;
            sys_err     <= 1'b0;
        end else begin
            // One-cycle acknowledge for each accepted read or write.
            sys_ack    <= sys_wen | sys_ren;
            sys_err    <= 1'b0;
            free_count <= free_count + 1'b1;

            ////////////////////////////////////////////////////////////////////////////
            // Write path
            ////////////////////////////////////////////////////////////////////////////
            if (sys_wen) begin
                write_count <= write_count + 1'b1;

                unique case (sys_addr[7:0])
                    8'h00: begin
                        enable <= sys_wdata[0];

                        // CTRL bit1 clears counters. It does not stay set.
                        if (sys_wdata[1]) begin
                            write_count <= 32'h0000_0000;
                            read_count  <= 32'h0000_0000;
                        end
                    end

                    8'h04: in_a   <= sys_wdata;
                    8'h08: in_b   <= sys_wdata;
                    8'h0C: in_c   <= sys_wdata;
                    8'h10: rw_reg <= sys_wdata;

                    default: begin
                        // Unknown writes are acknowledged but ignored.
                    end
                endcase
            end

            ////////////////////////////////////////////////////////////////////////////
            // Read path
            //
            // sys_rdata is registered, not purely combinational. This is the safer
            // pattern because rdata remains stable when sys_ack is returned.
            ////////////////////////////////////////////////////////////////////////////
            if (sys_ren) begin
                read_count <= read_count + 1'b1;

                unique case (sys_addr[7:0])
                    8'h00: sys_rdata <= {30'h0, 1'b0, enable};
                    8'h04: sys_rdata <= in_a;
                    8'h08: sys_rdata <= in_b;
                    8'h0C: sys_rdata <= in_c;
                    8'h10: sys_rdata <= rw_reg;

                    8'h14: sys_rdata <= out_sum;
                    8'h18: sys_rdata <= out_xor;

                    // STATUS:
                    // [31:24] = 0xA5
                    // [23:16] = module ID
                    // [1]     = LED state
                    // [0]     = enable
                    8'h1C: sys_rdata <= {8'hA5, ID[7:0], 14'h0, led, enable};

                    8'h20: sys_rdata <= write_count;
                    8'h24: sys_rdata <= read_count;
                    8'h28: sys_rdata <= free_count;

                    8'hFC: sys_rdata <= (32'hA117_0000 | ID[15:0]);

                    default: sys_rdata <= 32'h0000_0000;
                endcase
            end
        end
    end

endmodule
