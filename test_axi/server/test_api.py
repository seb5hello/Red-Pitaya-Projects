import requests
import time
import sys

# Replace with your Red Pitaya's local IP address
# RP_IP = "100.83.1.106" 
RP_IP = "192.168.2.29" 
BASE_URL = f"http://{RP_IP}:5000/api"

TIMEOUT = 3.0

# ==============================================================================
# AXI TEST REGISTER EXPECTATIONS
# ==============================================================================

AXI_INDICES = range(1, 8)  # sys[1] through sys[7], sys[0] is housekeeping

REG_CTRL        = 0x00
REG_IN_A        = 0x04
REG_IN_B        = 0x08
REG_IN_C        = 0x0C
REG_RW_REG      = 0x10
REG_OUT_SUM     = 0x14
REG_OUT_XOR     = 0x18
REG_STATUS      = 0x1C
REG_WRITE_COUNT = 0x20
REG_READ_COUNT  = 0x24
REG_FREE_COUNT  = 0x28
REG_MAGIC       = 0xFC


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

def u32(value):
    """Force value into unsigned 32-bit range, same as FPGA 32-bit wraparound."""
    return int(value) & 0xFFFFFFFF


def request_json(method, endpoint, **kwargs):
    """
    Sends a request and returns parsed JSON.
    Raises an exception if the server is unreachable or returns an error.
    """
    url = f"{BASE_URL}{endpoint}"

    if method.upper() == "GET":
        resp = requests.get(url, timeout=TIMEOUT, **kwargs)
    elif method.upper() == "POST":
        resp = requests.post(url, timeout=TIMEOUT, **kwargs)
    else:
        raise ValueError(f"Unsupported HTTP method: {method}")

    try:
        data = resp.json()
    except Exception:
        raise RuntimeError(f"Non-JSON response from {url}: HTTP {resp.status_code}, text={resp.text!r}")

    if not resp.ok:
        raise RuntimeError(f"HTTP error from {url}: HTTP {resp.status_code}, response={data}")

    if data.get("status") == "error":
        raise RuntimeError(f"API error from {url}: {data}")

    return data


def check_equal(label, expected, actual):
    """
    Prints PASS/FAIL for one check.
    Returns 0 if passed, 1 if failed.
    """
    if expected == actual:
        print(f"    PASS: {label}: {actual}")
        return 0

    print(f"    ERROR: {label}: expected {expected}, got {actual}")
    return 1


def check_equal_hex(label, expected, actual):
    """
    Prints PASS/FAIL for one 32-bit hex check.
    Returns 0 if passed, 1 if failed.
    """
    expected = u32(expected)
    actual = u32(actual)

    if expected == actual:
        print(f"    PASS: {label}: 0x{actual:08X}")
        return 0

    print(f"    ERROR: {label}: expected 0x{expected:08X}, got 0x{actual:08X}")
    return 1


# ==============================================================================
# MODULE ABSTRACTION: API READ/WRITE FUNCTIONS
# ==============================================================================

def read_all_axi_tests():
    """Reads all axi_test modules."""
    return request_json("GET", "/axi_test")


def read_axi_test(index):
    """Reads one axi_test module."""
    resp = request_json("GET", f"/axi_test/{index}")
    return resp["module"]


def write_axi_test(index, **kwargs):
    """
    Writes fields to one axi_test module.

    Valid kwargs:
        enable
        clear_counters
        ctrl
        in_a
        in_b
        in_c
        rw_reg
    """
    resp = request_json("POST", f"/axi_test/{index}", json=kwargs)
    return resp["module"]


def clear_axi_counters(index):
    """Clears read/write counters for one axi_test module."""
    resp = request_json("POST", f"/axi_test/{index}/clear")
    return resp["module"]


def set_axi_led(index, value):
    """
    Sets LED for one axi_test module.

    In the FPGA:
        led = enable & rw_reg[0]
    """
    resp = request_json("POST", f"/axi_test/{index}/led/{1 if value else 0}")
    return resp["module"]


def raw_read(index, offset):
    """Reads one raw register offset from one axi_test module."""
    resp = request_json("GET", f"/axi_test/{index}/raw", params={"offset": hex(offset)})
    return int(resp["value"])


def raw_write(index, offset, value):
    """Writes one raw register offset and returns the server's readback."""
    resp = request_json(
        "POST",
        f"/axi_test/{index}/raw",
        json={
            "offset": hex(offset),
            "value": u32(value),
        },
    )
    return int(resp["readback"])


def server_selftest():
    """Runs the server-side selftest, if that endpoint exists."""
    return request_json("POST", "/axi_test/selftest")


# ==============================================================================
# MAIN TEST ROUTINES
# ==============================================================================

def check_server_connection():
    print("0. Checking connection to Red Pitaya API server...")

    resp = read_all_axi_tests()

    modules = resp.get("modules", [])
    print(f"   Connected. Server returned {len(modules)} axi_test modules.")

    if len(modules) != 7:
        print(f"   WARNING: Expected 7 modules, got {len(modules)}")

    print("   Connection OK.\n")


def test_magic_registers():
    print("1. Checking MAGIC registers...")

    errors = 0

    for index in AXI_INDICES:
        expected_magic = 0xA1170000 | index
        actual_magic = raw_read(index, REG_MAGIC)

        print(f"  AXI/sys[{index}]")
        errors += check_equal_hex("MAGIC", expected_magic, actual_magic)

    if errors == 0:
        print("   -> All MAGIC registers are correct.\n")
    else:
        print(f"   -> MAGIC register test FAILED with {errors} error(s).\n")

    return errors


def test_basic_read_write():
    print("2. Testing basic write/readback on IN_A, IN_B, IN_C, and RW_REG...")

    errors = 0

    for index in AXI_INDICES:
        print(f"  AXI/sys[{index}]")

        # Unique values per bus.
        test_cfg = {
            "enable": 1,
            "in_a": 1000 * index + 11,
            "in_b": 1000 * index + 22,
            "in_c": 1000 * index + 33,
            "rw_reg": (0xAB00 + index) | 0x1,  # bit0 = 1, so LED should turn on
        }

        print("Next write\n")

        write_axi_test(index, **test_cfg)
        time.sleep(0.01)

        print("data was writen\n")

        resp = read_axi_test(index)

        
        print("data was read\n")

        errors += check_equal("enable", True, bool(resp.get("enable")))
        errors += check_equal("in_a", test_cfg["in_a"], resp.get("in_a"))
        errors += check_equal("in_b", test_cfg["in_b"], resp.get("in_b"))
        errors += check_equal("in_c", test_cfg["in_c"], resp.get("in_c"))
        errors += check_equal("rw_reg", test_cfg["rw_reg"], resp.get("rw_reg"))

    if errors == 0:
        print("   -> Basic write/readback test PASSED.\n")
    else:
        print(f"   -> Basic write/readback test FAILED with {errors} error(s).\n")

    return errors


def test_output_logic():
    print("3. Testing OUT_SUM and OUT_XOR logic...")

    errors = 0

    for index in AXI_INDICES:
        print(f"  AXI/sys[{index}]")

        in_a = 0x00000100 + index
        in_b = 0x00001000 + (index << 4)
        in_c = 0x00010000 + (index << 8)
        rw_reg = 0x01000000 + index

        write_axi_test(
            index,
            enable=1,
            in_a=in_a,
            in_b=in_b,
            in_c=in_c,
            rw_reg=rw_reg,
        )
        time.sleep(0.01)

        resp = read_axi_test(index)

        expected_sum = u32(in_a + in_b + in_c + rw_reg)
        expected_xor = u32(in_a ^ in_b ^ in_c ^ rw_reg)

        errors += check_equal_hex("OUT_SUM", expected_sum, resp.get("out_sum"))
        errors += check_equal_hex("OUT_XOR", expected_xor, resp.get("out_xor"))

    if errors == 0:
        print("   -> Output logic test PASSED.\n")
    else:
        print(f"   -> Output logic test FAILED with {errors} error(s).\n")

    return errors


def test_enable_disable_behavior():
    print("4. Testing enable/disable behavior...")

    errors = 0

    for index in AXI_INDICES:
        print(f"  AXI/sys[{index}]")

        in_a = 10
        in_b = 20
        in_c = 30
        rw_reg = 40

        # Enabled: outputs should calculate.
        write_axi_test(index, enable=1, in_a=in_a, in_b=in_b, in_c=in_c, rw_reg=rw_reg)
        time.sleep(0.01)
        enabled_resp = read_axi_test(index)

        errors += check_equal("enable when enabled", True, bool(enabled_resp.get("enable")))
        errors += check_equal_hex("OUT_SUM enabled", in_a + in_b + in_c + rw_reg, enabled_resp.get("out_sum"))
        errors += check_equal_hex("OUT_XOR enabled", in_a ^ in_b ^ in_c ^ rw_reg, enabled_resp.get("out_xor"))

        # Disabled: outputs should become 0, while stored input registers remain readable.
        write_axi_test(index, enable=0)
        time.sleep(0.01)
        disabled_resp = read_axi_test(index)

        errors += check_equal("enable when disabled", False, bool(disabled_resp.get("enable")))
        errors += check_equal_hex("OUT_SUM disabled", 0, disabled_resp.get("out_sum"))
        errors += check_equal_hex("OUT_XOR disabled", 0, disabled_resp.get("out_xor"))

        # Re-enable for later tests.
        write_axi_test(index, enable=1)

    if errors == 0:
        print("   -> Enable/disable behavior test PASSED.\n")
    else:
        print(f"   -> Enable/disable behavior test FAILED with {errors} error(s).\n")

    return errors


def test_led_control():
    print("5. Testing LED control through API...")

    errors = 0

    for index in AXI_INDICES:
        print(f"  AXI/sys[{index}]")

        # Turn LED on.
        resp_on = set_axi_led(index, 1)
        status_on = resp_on.get("status", {})
        led_on = bool(status_on.get("led"))
        enable_on = bool(status_on.get("enable"))

        errors += check_equal("LED on status", True, led_on)
        errors += check_equal("Enable while LED on", True, enable_on)

        # Turn LED off.
        resp_off = set_axi_led(index, 0)
        status_off = resp_off.get("status", {})
        led_off = bool(status_off.get("led"))

        errors += check_equal("LED off status", False, led_off)

    if errors == 0:
        print("   -> LED control test PASSED.\n")
    else:
        print(f"   -> LED control test FAILED with {errors} error(s).\n")

    return errors


def test_raw_access():
    print("6. Testing raw register access...")

    errors = 0

    for index in AXI_INDICES:
        print(f"  AXI/sys[{index}]")

        test_value = 0x55000000 | index

        readback = raw_write(index, REG_RW_REG, test_value)
        errors += check_equal_hex("raw write/readback RW_REG", test_value, readback)

        direct_read = raw_read(index, REG_RW_REG)
        errors += check_equal_hex("raw read RW_REG", test_value, direct_read)

    if errors == 0:
        print("   -> Raw access test PASSED.\n")
    else:
        print(f"   -> Raw access test FAILED with {errors} error(s).\n")

    return errors


def test_free_counter():
    print("7. Testing FREE_COUNT increments...")

    errors = 0

    for index in AXI_INDICES:
        print(f"  AXI/sys[{index}]")

        count_1 = raw_read(index, REG_FREE_COUNT)
        time.sleep(0.05)
        count_2 = raw_read(index, REG_FREE_COUNT)

        if count_2 != count_1:
            print(f"    PASS: FREE_COUNT changed: 0x{count_1:08X} -> 0x{count_2:08X}")
        else:
            print(f"    ERROR: FREE_COUNT did not change: 0x{count_1:08X} -> 0x{count_2:08X}")
            errors += 1

    if errors == 0:
        print("   -> FREE_COUNT test PASSED.\n")
    else:
        print(f"   -> FREE_COUNT test FAILED with {errors} error(s).\n")

    return errors


def run_server_selftest_optional():
    print("8. Running server-side selftest endpoint...")

    try:
        resp = server_selftest()
    except Exception as e:
        print(f"   WARNING: Server-side selftest failed or endpoint missing: {e}")
        print("   Continuing because the client-side tests above are the main checks.\n")
        return 0

    all_passed = bool(resp.get("all_passed"))

    if all_passed:
        print("   -> Server-side selftest PASSED.\n")
        return 0

    print("   -> Server-side selftest FAILED.")
    for result in resp.get("results", []):
        index = result.get("index")
        passed = result.get("passed")
        magic = result.get("magic")
        expected_magic = result.get("expected_magic")
        print(f"      sys[{index}]: passed={passed}, magic={magic}, expected={expected_magic}")

    print()
    return 1


def run_full_axi_test():
    total_errors = 0

    check_server_connection()

    total_errors += test_magic_registers()
    total_errors += test_basic_read_write()
    total_errors += test_output_logic()
    total_errors += test_enable_disable_behavior()
    total_errors += test_led_control()
    total_errors += test_raw_access()
    total_errors += test_free_counter()
    total_errors += run_server_selftest_optional()

    print("--- AXI TEST COMPLETE ---")

    if total_errors == 0:
        print("SUCCESS: All AXI/sys test modules appear to be working correctly.")
        return 0

    print(f"FAILED: Found {total_errors} error(s).")
    print()
    print("Most likely causes:")
    print("  1. Wrong or old bitstream is loaded.")
    print("  2. One or more sys[x] lines are still connected to sys_bus_stub.")
    print("  3. A sys[x] line has two drivers.")
    print("  4. The Flask server does not match the axi_test register map.")
    print("  5. The top file instantiated fewer than seven axi_test modules.")
    return 1


if __name__ == "__main__":
    try:
        exit_code = run_full_axi_test()
        sys.exit(exit_code)

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya.")
        print("Check that:")
        print(f"  - RP_IP is correct: {RP_IP}")
        print("  - The Flask server is running on port 5000")
        print("  - Your computer can reach the Red Pitaya over the network")
        sys.exit(1)

    except requests.exceptions.Timeout:
        print("Error: API request timed out.")
        print("This can happen if the Flask server is stuck waiting on a bad AXI read.")
        print("Check the FPGA bus wiring, sys_ack behavior, and whether the bitstream is correct.")
        sys.exit(1)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)