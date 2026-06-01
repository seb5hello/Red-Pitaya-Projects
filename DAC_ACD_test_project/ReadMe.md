# Red Pitaya Custom FPGA Architecture Documentation

## 1. Overview
This custom FPGA implementation for the Red Pitaya STEMlab 125-14 LN strips out the stock applications (Scope, ASG, PID, Daisy) to make room for a synchronized, custom data acquisition and generation pipeline. 

The system relies on a **System Controller** acting as a central orchestrator. It dispatches global `arm` and `trigger` signals to three sub-modules: a **Ramp Generator** (DAC A), a **Timestamp Peak Detector** (ADC A), and a **Test Peak Generator** (DAC B) for internal loopback verification. All modules operate synchronously on the 125 MHz `adc_clk` (8 ns period).

---

## 2. Global Memory Map
The system utilizes the Red Pitaya `sys_bus_interconnect`, which divides the AXI memory space into regions with 20-bit address widths ($2^{20}$ bytes = 1 MB per region). The base address for the FPGA custom logic is `0x40000000`.

| Bus Region | Absolute Base Address | Module Name | Connected Hardware |
| :--- | :--- | :--- | :--- |
| `sys[0]` | `0x40000000` | Housekeeping (`red_pitaya_hk`) | LEDs, Expansion IO |
| `sys[1]` | `0x40100000` | System Controller | Global Orchestration |
| `sys[2]` | `0x40200000` | Custom Ramp Generator | DAC Channel A |
| `sys[3]` | `0x40300000` | Timestamp Peak Detector | ADC Channel A |
| `sys[4]` | `0x40400000` | Test Peak Generator | DAC Channel B |
| `sys[5-7]` | `0x40500000` - `0x40700000` | *(Unused/Stubbed)* | N/A |

---

## 3. Module Specifications & Register Maps

### 3.1 System Controller (`sys[1]`)
**Description:** The master orchestrator. It guarantees that all DAC generation and ADC acquisition sub-modules begin executing on the exact same clock cycle. 
* **Global Arm:** Resets all sub-module state machines and counters to zero.
* **Global Trigger:** Starts the execution of the active state across all armed sub-modules.

**Register Map (Base: `0x40100000`)**
| Offset | Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `CTRL_REG` | R/W | Master Control. <br>• **Bit 0:** `global_arm` <br>• **Bit 1:** `global_trigger` |

---

### 3.2 Custom Ramp Generator (`sys[2]`)
**Description:** Generates a continuous sawtooth waveform on DAC Channel A. When triggered, it outputs the `min_val`, increments by 1 bit per clock cycle (125 MHz), and wraps back to `min_val` upon reaching `max_val`.

**Register Map (Base: `0x40200000`)**
| Offset | Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `MIN_VAL` | R/W | Minimum Ramp Value (14-bit unsigned). |
| `0x04` | `MAX_VAL` | R/W | Maximum Ramp Value (14-bit unsigned). |

**Key Internal Signals:**
* `running`: Boolean flag indicating the ramp is currently incrementing.
* `dac_dat_o`: 14-bit output bus directly feeding the DAC A formatting logic.

---

### 3.3 Timestamp Peak Detector (`sys[3]`)
**Description:** Monitors ADC Channel A for rising edges that cross a specified signed threshold. It features a 32-bit counter acting as a stopwatch. It captures the exact clock cycle of the first four threshold-crossing events after the trigger is engaged. Once 4 peaks are found, it halts and sets a `done` flag.

**Register Map (Base: `0x40300000`)**
| Offset | Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `THRESHOLD` | R/W | 14-bit signed voltage threshold. |
| `0x04` | `STATUS` | RO | Status Register.<br>• **Bit 0:** `done` (1 = 4 peaks found)<br>• **Bits 3:1:** `peak_count` (0 to 4) |
| `0x08` | `TS_1` | RO | Timestamp of Peak 1 (32-bit clock cycles). |
| `0x0C` | `TS_2` | RO | Timestamp of Peak 2 (32-bit clock cycles). |
| `0x10` | `TS_3` | RO | Timestamp of Peak 3 (32-bit clock cycles). |
| `0x14` | `TS_4` | RO | Timestamp of Peak 4 (32-bit clock cycles). |

**Key Internal Signals:**
* `prev_adc`: 14-bit signed register holding the $T-1$ ADC value for rising-edge calculation (`adc_dat_i > threshold && prev_adc <= threshold`).
* `counter`: 32-bit timer, increments every 8 ns.
* `peak_count`: 3-bit state tracker mapping the current trigger to the correct timestamp register.

---

### 3.4 Test Peak Generator (`sys[4]`)
**Description:** A verification module connected to DAC Channel B. Designed to simulate the output of a comparator circuit. It outputs a `base_amp` signal, and spikes to `peak_amp` for exactly one clock cycle when its internal timer perfectly matches one of the four configured delays. 

**Register Map (Base: `0x40400000`)**
| Offset | Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `DLY_1` | R/W | Clock cycles to wait before firing Peak 1 (32-bit). |
| `0x04` | `DLY_2` | R/W | Clock cycles to wait before firing Peak 2 (32-bit). |
| `0x08` | `DLY_3` | R/W | Clock cycles to wait before firing Peak 3 (32-bit). |
| `0x0C` | `DLY_4` | R/W | Clock cycles to wait before firing Peak 4 (32-bit). |
| `0x10` | `PEAK_AMP` | R/W | 14-bit amplitude of the artificial pulse. |
| `0x14` | `BASE_AMP` | R/W | 14-bit amplitude of the idle baseline. |

**Key Internal Signals:**
* `counter`: 32-bit timer, identical and perfectly synchronous to the Peak Detector's counter.

---

## 4. Hardware I/O Constraints & Modifications
To ensure Vivado successfully compiles the bitstream without Critical Warnings or Implementation failures, the following modifications were made to the stock `red_pitaya_top.v` and standard `.xdc` constraint files:

1. **XADC Cell Removal:** The `set_property LOC XADC_X0Y0 [get_cells i_ams/XADC_inst]` constraint was removed as the `red_pitaya_ams` module was deleted.
2. **False Path Cleanup:** Constraints targeting the stock `i_asg` (Arbitrary Signal Generator) were removed.
3. **Daisy Chain Tie-offs:** The differential SATA output pins (`daisy_p_o`, `daisy_n_o`) were driven to logical `0` using `OBUFDS` primitives to prevent Vivado from optimizing the ports away and failing the implementation stage.
4. **PWM DAC IOB Constraint:** The `set_property IOB TRUE` constraint for the audio `dac_pwm_o` ports was removed, as the driving PDM module was stripped from the design and replaced with a static ground tie-off.