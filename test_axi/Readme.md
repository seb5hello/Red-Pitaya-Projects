# Explanation of the AXI Test Client Script

This document explains what each test in the Python API client checks and why it matters.

The client script is intended to test the `axi_test.sv` modules connected to:

```text
sys[1], sys[2], sys[3], sys[4], sys[5], sys[6], sys[7]
```

`sys[0]` is reserved for Red Pitaya housekeeping.

---

## 1. `check_server_connection()`

This checks that your PC can reach the Flask API server running on the Red Pitaya.

It calls:

```text
GET /api/axi_test
```

Expected result: the server returns 7 modules, corresponding to:

```text
sys[1], sys[2], sys[3], sys[4], sys[5], sys[6], sys[7]
```

This does **not** deeply prove the FPGA logic works yet. It mainly proves that this path is working:

```text
PC → network → Flask server → API route
```

If this fails, check:

```text
1. The Red Pitaya IP address
2. Whether the Flask server is running
3. Whether port 5000 is reachable
4. Whether your PC and Red Pitaya are on the same network
```

---

## 2. `test_magic_registers()`

This checks that every `axi_test` module is present at the correct address.

It reads offset:

```text
0xFC = MAGIC
```

Expected values:

```text
sys[1] -> 0xA1170001
sys[2] -> 0xA1170002
sys[3] -> 0xA1170003
sys[4] -> 0xA1170004
sys[5] -> 0xA1170005
sys[6] -> 0xA1170006
sys[7] -> 0xA1170007
```

This is one of the most important tests.

If this fails, it usually means one of these is wrong:

```text
1. Wrong or old bitstream loaded
2. Wrong base address
3. Module not instantiated
4. sys[x] still connected to a sys_bus_stub
5. sys[x] has duplicate drivers
6. Flask server base address map is wrong
```

For example, if `sys[4]` does not return:

```text
0xA1170004
```

then the software is probably not talking to the expected:

```systemverilog
axi_test #(.ID(4))
```

instance.

---

## 3. `test_basic_read_write()`

This writes normal register values into each module and reads them back.

For each `sys[x]`, it writes:

```text
CTRL   enable = 1
IN_A   unique value
IN_B   unique value
IN_C   unique value
RW_REG unique value
```

Then it reads the module back through:

```text
GET /api/axi_test/<index>
```

It checks that the values returned by the FPGA match the values that were written.

This proves that the full write/read path works:

```text
Python POST
    ↓
Flask API
    ↓
/dev/mem write
    ↓
PS AXI interface
    ↓
sys_bus_interconnect
    ↓
axi_test register write
    ↓
axi_test register read
    ↓
Python GET
```

If writes appear to work but readback is wrong, the problem is likely in:

```text
1. The FPGA read path
2. sys_rdata
3. sys_ack
4. Address decoding
5. API register mapping
```

---

## 4. `test_output_logic()`

This checks the calculated FPGA outputs:

```text
OUT_SUM = IN_A + IN_B + IN_C + RW_REG
OUT_XOR = IN_A ^ IN_B ^ IN_C ^ RW_REG
```

The script writes known values to:

```text
IN_A
IN_B
IN_C
RW_REG
```

Then it reads:

```text
0x14 = OUT_SUM
0x18 = OUT_XOR
```

This proves that the FPGA is not only storing registers, but also using them correctly in internal logic.

If `IN_A`, `IN_B`, `IN_C`, and `RW_REG` read back correctly, but `OUT_SUM` or `OUT_XOR` is wrong, then the register read/write path is probably working, but the internal RTL logic is not behaving as expected.

---

## 5. `test_enable_disable_behavior()`

This checks the `enable` bit in the control register.

The `axi_test` logic was designed so:

```text
if enable = 1:
    OUT_SUM and OUT_XOR calculate normally

if enable = 0:
    OUT_SUM = 0
    OUT_XOR = 0
```

The test does two phases.

First it enables the module:

```python
write_axi_test(index, enable=1, ...)
```

Then it expects real calculated outputs.

Then it disables the module:

```python
write_axi_test(index, enable=0)
```

Then it expects:

```text
OUT_SUM = 0
OUT_XOR = 0
```

This proves that the control register is actually affecting the FPGA logic.

It also checks that disabling the module does not destroy the stored input registers. It only gates the outputs.

---

## 6. `test_led_control()`

This checks the LED control path.

In the FPGA module, the LED is driven by:

```systemverilog
assign led = enable & rw_reg[0];
```

So the LED turns on only when:

```text
CTRL bit0 = 1
RW_REG bit0 = 1
```

The API route:

```text
POST /api/axi_test/<index>/led/1
```

does this internally:

```text
enable = 1
rw_reg[0] = 1
```

Then:

```text
POST /api/axi_test/<index>/led/0
```

clears `rw_reg[0]`.

This checks that the FPGA status register reports the LED state correctly.

It also gives you a visible hardware check on LEDs 1 through 7 if your top-level connects:

```text
sys[1] -> led_o[1]
sys[2] -> led_o[2]
sys[3] -> led_o[3]
sys[4] -> led_o[4]
sys[5] -> led_o[5]
sys[6] -> led_o[6]
sys[7] -> led_o[7]
```

Important: this test checks the **reported LED state** through the FPGA status register. You should also visually confirm the physical LEDs.

---

## 7. `test_raw_access()`

This checks the low-level raw register API.

Instead of using friendly JSON fields like:

```json
{
  "in_a": 123,
  "rw_reg": 456
}
```

it directly writes an offset:

```text
POST /api/axi_test/<index>/raw
```

with a JSON body such as:

```json
{
  "offset": "0x10",
  "value": 1426063361
}
```

Offset `0x10` is:

```text
RW_REG
```

Then it reads the same offset back:

```text
GET /api/axi_test/<index>/raw?offset=0x10
```

This proves that the generic raw API works correctly.

This is useful for debugging because it lets you test any register address directly without adding a new Flask route every time.

---

## 8. `test_free_counter()`

This checks that the FPGA clocked logic is alive.

The `FREE_COUNT` register increments every `clk_i` cycle:

```systemverilog
free_count <= free_count + 1'b1;
```

The test reads it once:

```text
count_1 = FREE_COUNT
```

waits briefly:

```python
time.sleep(0.05)
```

then reads again:

```text
count_2 = FREE_COUNT
```

Expected result:

```text
count_2 != count_1
```

This proves:

```text
1. adc_clk is running
2. adc_rstn is released
3. The axi_test module is not stuck in reset
4. The read path can observe changing FPGA state
```

If the `MAGIC` register works but `FREE_COUNT` never changes, the module may be held in reset or the clock is not reaching it.

---

## 9. `run_server_selftest_optional()`

This calls the server-side self-test endpoint:

```text
POST /api/axi_test/selftest
```

That endpoint runs a simpler version of the same test directly from the Flask server on the Red Pitaya.

This is useful because it separates two possible problems:

```text
PC client problem
```

versus:

```text
Red Pitaya local Flask/API/FPGA problem
```

If the server-side selftest passes but the client-side test fails, the FPGA is probably okay, and the problem may be network/API/client-side parsing.

If both fail, the problem is more likely in the FPGA bitstream, bus mapping, or server register map.

---

# What the Full Test Proves

The whole test checks this full chain:

```text
PC Python script
    ↓
HTTP request
    ↓
Flask API server on Red Pitaya
    ↓
/dev/mem mmap
    ↓
Zynq PS AXI interface
    ↓
Red Pitaya sys_bus_interconnect
    ↓
sys[1] ... sys[7]
    ↓
axi_test RTL module
    ↓
register write/read/status/output logic
```

The most important tests are:

```text
1. MAGIC registers
2. Basic read/write
3. FREE_COUNT
```

Those three tell you whether:

```text
1. The modules exist at the expected addresses
2. The bus can write and read them
3. The FPGA clock/reset are working
```

---

# Quick Debug Guide

## If all tests fail

Likely causes:

```text
1. Flask server is not running
2. Wrong Red Pitaya IP address
3. Wrong API server code
4. Wrong or old bitstream loaded
5. /dev/mem access failed
```

## If only `MAGIC` fails

Likely causes:

```text
1. Wrong base address map
2. axi_test modules are not instantiated
3. sys[x] still connected to stubs
4. Duplicate drivers on sys[x]
5. Wrong bitstream loaded
```

## If `MAGIC` passes but read/write fails

Likely causes:

```text
1. Register offset mismatch
2. sys_rdata timing issue
3. sys_ack timing issue
4. API server is reading/writing the wrong offsets
```

## If read/write passes but `OUT_SUM` or `OUT_XOR` fails

Likely causes:

```text
1. RTL calculation logic issue
2. enable bit is not set
3. Output registers are being gated to zero
```

## If `FREE_COUNT` does not change

Likely causes:

```text
1. Module clock is not running
2. Module reset is stuck active
3. adc_clk or adc_rstn is not connected correctly
```

## If LED status passes but physical LED does not change

Likely causes:

```text
1. led_o is not connected to axi_test_led in the top module
2. Housekeeping is still driving the same LED
3. Multiple drivers on led_o
4. You are looking at the wrong LED index
```
