# Bare-Metal Red Pitaya FPGA Architecture

## Overview

This project is a streamlined, bare-metal FPGA implementation for the Red Pitaya (Zynq-7000 SoC). It strips away the legacy factory bloatware (Scope, ASG, PID, Daisy chain) to provide a clean slate for custom Digital Signal Processing (DSP) and hardware control.

The architecture bridges the ARM Processing System (PS) and the Programmable Logic (PL) using a custom AXI4-Lite IP, allowing software (C/Python) to control hardware parameters and read back status flags via memory-mapped registers.

## System Architecture

The top-level wrapper (`top_test.sv`) instantiates three primary active domains, plus commented-out placeholders for future analog I/O:

1. **Clocking & Reset Domain (`red_pitaya_pll`)**
* Driven by the external physical ADC differential clock (`adc_clk_i`).
* Generates a stable `adc_clk` (typically 125 MHz) for the main FPGA logic.
* Generates multiple DAC-specific clocks (`1x`, `2x`, `2p`) to handle strict Output Double Data Rate (ODDR) timing.
* Manages a locked reset sequence (`adc_rstn`, `dac_rst`) ensuring logic does not start until PLLs are stable.


2. **Zynq Processing System Wrapper (`custom_ps`)**
* Wraps the Vivado Block Design (`ps_system`).
* Handles all DDR and FIXED_IO physical pins for the ARM processor.
* Exposes a 16-register AXI4-Lite interface to the FPGA:
* **8 "Read" Registers (`read_reg0` - `read_reg7`):** Written by the ARM processor, read by the FPGA (Configuration inputs).
* **8 "Write" Registers (`write_reg8` - `write_reg15`):** Written by the FPGA, read by the ARM processor (Status/Data outputs).




3. **Custom User Logic (`logic_test`)**
* The core application logic running at the `adc_clk` speed.
* Currently implements a dummy calculation (`kp + ki + kd`) to verify the AXI read/write data paths between the ARM and the FPGA.



## Hardware Register Map

To interact with the FPGA from the ARM processor (e.g., via `/dev/mem` in Linux), use the base address assigned to the AXI IP in Vivado, mapped to these internal wires:

### ARM -> FPGA (Configuration)

| Internal Wire | Connected To | Description |
| --- | --- | --- |
| `read_reg0` | `logic_test.kp_in` | User algorithm parameter (e.g., Proportional gain). |
| `read_reg1` | `logic_test.ki_in` | User algorithm parameter (e.g., Integral gain). |
| `read_reg2` | `logic_test.kd_in` | User algorithm parameter (e.g., Derivative gain). |
| `read_reg3` | `logic_test.state_in` | User algorithm parameter (e.g., System state). |
| `read_reg4` | `led_o` [7:0] | Drives the 8 physical LEDs on the Red Pitaya board. |
| `read_reg5` - `7` | *Unconnected* | Available for future expansion. |

### FPGA -> ARM (Status & Output)

| Internal Wire | Connected To | Description |
| --- | --- | --- |
| `write_reg8` | `logic_test.status_out` | Output of the user math calculation + `state_in`. |
| `write_reg9` | `logic_test.control_out` | Raw output of the user math calculation. |
| `write_reg10` - `15` | Hardcoded to `0` | Tied to zero to prevent floating buses. |

## Current Code State & Disabled Features

In this specific iteration of the code, the physical **Analog-to-Digital (ADC)** and **Digital-to-Analog (DAC)** data paths have been temporarily **commented out**.

* **ADC Data In (`adc_dat_i`):** Port is commented out. The physical clock is still routed to the PLL, but raw sample data is ignored.
* **ADC/DAC Controllers (`adc_ctrl`, `dac_ctrl`):** Module instantiations are commented out.
* **DAC Data Out (`dac_dat_o`, etc.):** Output ports are commented out, except for the DAC clock (`dac_clk_o`).

**To Reactivate Analog I/O:**

1. Uncomment the ADC/DAC ports in the module header.
2. Uncomment the `adc_ctrl` and `dac_ctrl` module instantiations.
3. Wire the 14-bit `adc_dat_a` / `adc_dat_b` wires into the `logic_test` module.
4. Route the `control_out` from `logic_test` into the `dac_a_i` / `dac_b_i` inputs of the `dac_ctrl` module.