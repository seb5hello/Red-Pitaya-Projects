import os
import mmap
import ctypes
import sys
import threading
from flask import Flask, request, jsonify

app = Flask(__name__)

# ==============================================================================
# AXI/SYS TEST BASE ADDRESSES
# ==============================================================================
# sys[0] = 0x40000000 is housekeeping, so do not use it here.
AXI_TEST_BASES = {
    1: 0x40100000,
    2: 0x40200000,
    3: 0x40300000,
    4: 0x40400000,
    5: 0x40500000,
    6: 0x40600000,
    7: 0x40700000,
}

MAP_SIZE = 4096

# Register offsets for axi_test.sv
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

REGISTER_NAMES = {
    REG_CTRL:        "ctrl",
    REG_IN_A:        "in_a",
    REG_IN_B:        "in_b",
    REG_IN_C:        "in_c",
    REG_RW_REG:      "rw_reg",
    REG_OUT_SUM:     "out_sum",
    REG_OUT_XOR:     "out_xor",
    REG_STATUS:      "status",
    REG_WRITE_COUNT: "write_count",
    REG_READ_COUNT:  "read_count",
    REG_FREE_COUNT:  "free_count",
    REG_MAGIC:       "magic",
}

WRITABLE_FIELDS = {
    "ctrl":   REG_CTRL,
    "in_a":   REG_IN_A,
    "in_b":   REG_IN_B,
    "in_c":   REG_IN_C,
    "rw_reg": REG_RW_REG,
}

lock = threading.Lock()

# ==============================================================================
# HARDWARE MEMORY INITIALIZATION
# ==============================================================================

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)

mmaps = {
    index: mmap.mmap(
        fd,
        MAP_SIZE,
        mmap.MAP_SHARED,
        mmap.PROT_READ | mmap.PROT_WRITE,
        offset=base_addr,
    )
    for index, base_addr in AXI_TEST_BASES.items()
}


# ==============================================================================
# LOW-LEVEL READ/WRITE HELPERS
# ==============================================================================

def validate_index(index):
    if index not in AXI_TEST_BASES:
        raise ValueError("Invalid AXI test index. Use 1 through 7.")
    return index


def validate_offset(offset):
    if offset < 0 or offset >= MAP_SIZE:
        raise ValueError("Offset outside mmap range.")
    if offset % 4 != 0:
        raise ValueError("Offset must be 4-byte aligned.")
    return offset


def u32(value):
    return int(value) & 0xFFFFFFFF


def write_reg(index, offset, value):
    index = validate_index(index)
    offset = validate_offset(offset)

    base_addr = AXI_TEST_BASES[index]
    physical_addr = base_addr + offset

    print(
        f"WRITE sys[{index}] addr=0x{physical_addr:08X} "
        f"offset=0x{offset:02X} value=0x{u32(value):08X}",
        flush=True
    )

    with lock:
        reg = ctypes.c_uint32.from_buffer(mmaps[index], offset)
        reg.value = u32(value)
        del reg

    print("WRITE OK", flush=True)


def read_reg(index, offset):
    index = validate_index(index)
    offset = validate_offset(offset)

    base_addr = AXI_TEST_BASES[index]
    physical_addr = base_addr + offset

    print(
        f"READ  sys[{index}] addr=0x{physical_addr:08X} "
        f"offset=0x{offset:02X}",
        flush=True
    )

    with lock:
        reg = ctypes.c_uint32.from_buffer(mmaps[index], offset)
        value = reg.value
        del reg

    print(f"READ OK value=0x{value:08X}", flush=True)
    return value


def decode_status(status):
    return {
        "raw": status,
        "raw_hex": f"0x{status:08X}",
        "header": (status >> 24) & 0xFF,
        "module_id": (status >> 16) & 0xFF,
        "led": bool((status >> 1) & 0x1),
        "enable": bool(status & 0x1),
    }


def read_axi_test(index):
    ctrl = read_reg(index, REG_CTRL)
    status = read_reg(index, REG_STATUS)

    return {
        "index": index,
        "base_addr": f"0x{AXI_TEST_BASES[index]:08X}",

        "ctrl": ctrl,
        "enable": bool(ctrl & 0x1),

        "in_a": read_reg(index, REG_IN_A),
        "in_b": read_reg(index, REG_IN_B),
        "in_c": read_reg(index, REG_IN_C),
        "rw_reg": read_reg(index, REG_RW_REG),

        "out_sum": read_reg(index, REG_OUT_SUM),
        "out_xor": read_reg(index, REG_OUT_XOR),

        "status": decode_status(status),

        "write_count": read_reg(index, REG_WRITE_COUNT),
        "read_count": read_reg(index, REG_READ_COUNT),
        "free_count": read_reg(index, REG_FREE_COUNT),

        "magic": f"0x{read_reg(index, REG_MAGIC):08X}",
    }


# ==============================================================================
# API ROUTES
# ==============================================================================

@app.route("/api/axi_test", methods=["GET"])
def list_axi_tests():
    """
    Read all axi_test modules.
    """
    try:
        return jsonify({
            "status": "success",
            "modules": [read_axi_test(i) for i in range(1, 8)]
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/api/axi_test/<int:index>", methods=["GET"])
def get_axi_test(index):
    """
    Read one axi_test module.

    Example:
        GET /api/axi_test/4
    """
    try:
        validate_index(index)
        return jsonify({
            "status": "success",
            "module": read_axi_test(index)
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route("/api/axi_test/<int:index>", methods=["POST"])
def set_axi_test(index):
    """
    Write fields to one axi_test module.

    Example JSON:
    {
        "enable": 1,
        "in_a": 10,
        "in_b": 20,
        "in_c": 30,
        "rw_reg": 1
    }

    Optional:
    {
        "clear_counters": 1
    }
    """
    try:
        validate_index(index)
        data = request.get_json(force=True) or {}

        # Build CTRL from user-friendly fields if present.
        if "enable" in data or "clear_counters" in data:
            enable = int(data.get("enable", read_reg(index, REG_CTRL) & 0x1)) & 0x1
            clear = int(data.get("clear_counters", 0)) & 0x1
            ctrl_value = enable | (clear << 1)
            write_reg(index, REG_CTRL, ctrl_value)

        # Also allow direct ctrl write.
        if "ctrl" in data:
            write_reg(index, REG_CTRL, data["ctrl"])

        # Write normal writable registers.
        for field, offset in WRITABLE_FIELDS.items():
            if field in data:
                write_reg(index, offset, data[field])

        return jsonify({
            "status": "success",
            "module": read_axi_test(index)
        })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route("/api/axi_test/<int:index>/clear", methods=["POST"])
def clear_axi_test_counters(index):
    """
    Clear read/write counters for one module.
    Preserves the current enable bit.
    """
    try:
        validate_index(index)

        current_ctrl = read_reg(index, REG_CTRL)
        enable = current_ctrl & 0x1

        # bit1 = clear counters
        write_reg(index, REG_CTRL, enable | 0x2)

        # write again with clear bit removed
        write_reg(index, REG_CTRL, enable)

        return jsonify({
            "status": "success",
            "module": read_axi_test(index)
        })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route("/api/axi_test/<int:index>/led/<int:value>", methods=["POST"])
def set_axi_test_led(index, value):
    """
    Turn LED off/on for this axi_test module.

    LED behavior in FPGA:
        led = enable & rw_reg[0]

    So this route writes:
        CTRL bit0 = 1
        RW_REG bit0 = value
    """
    try:
        validate_index(index)

        value = 1 if value else 0

        # Enable module.
        write_reg(index, REG_CTRL, 0x1)

        # Preserve upper bits of rw_reg, modify only bit0.
        old_rw = read_reg(index, REG_RW_REG)
        new_rw = (old_rw & 0xFFFFFFFE) | value
        write_reg(index, REG_RW_REG, new_rw)

        return jsonify({
            "status": "success",
            "led": bool(value),
            "module": read_axi_test(index)
        })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route("/api/axi_test/<int:index>/raw", methods=["GET", "POST"])
def raw_axi_test_access(index):
    """
    Raw register access.

    GET example:
        /api/axi_test/4/raw?offset=0xFC

    POST example:
    {
        "offset": "0x10",
        "value": 123
    }
    """
    try:
        validate_index(index)

        if request.method == "GET":
            offset_text = request.args.get("offset", None)
            if offset_text is None:
                return jsonify({
                    "status": "error",
                    "message": "Missing offset query parameter."
                }), 400

            offset = int(offset_text, 0)
            value = read_reg(index, offset)

            return jsonify({
                "status": "success",
                "index": index,
                "offset": f"0x{offset:02X}",
                "value": value,
                "value_hex": f"0x{value:08X}",
                "name": REGISTER_NAMES.get(offset, "unknown"),
            })

        data = request.get_json(force=True) or {}
        offset = int(data["offset"], 0) if isinstance(data["offset"], str) else int(data["offset"])
        value = int(data["value"], 0) if isinstance(data["value"], str) else int(data["value"])

        write_reg(index, offset, value)
        readback = read_reg(index, offset)

        return jsonify({
            "status": "success",
            "index": index,
            "offset": f"0x{offset:02X}",
            "written": u32(value),
            "readback": readback,
            "readback_hex": f"0x{readback:08X}",
            "name": REGISTER_NAMES.get(offset, "unknown"),
        })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route("/api/axi_test/selftest", methods=["POST"])
def selftest_all_axi_tests():
    """
    Runs a basic write/read test on sys[1] through sys[7].
    """
    try:
        results = []

        for index in range(1, 8):
            base_value = index * 100

            write_reg(index, REG_CTRL, 0x1)
            write_reg(index, REG_IN_A, base_value + 1)
            write_reg(index, REG_IN_B, base_value + 2)
            write_reg(index, REG_IN_C, base_value + 3)
            write_reg(index, REG_RW_REG, 0x1)

            in_a = read_reg(index, REG_IN_A)
            in_b = read_reg(index, REG_IN_B)
            in_c = read_reg(index, REG_IN_C)
            rw   = read_reg(index, REG_RW_REG)

            out_sum = read_reg(index, REG_OUT_SUM)
            out_xor = read_reg(index, REG_OUT_XOR)
            magic   = read_reg(index, REG_MAGIC)

            expected_sum = u32(in_a + in_b + in_c + rw)
            expected_xor = u32(in_a ^ in_b ^ in_c ^ rw)
            expected_magic = 0xA1170000 | index

            passed = (
                in_a == base_value + 1 and
                in_b == base_value + 2 and
                in_c == base_value + 3 and
                rw == 0x1 and
                out_sum == expected_sum and
                out_xor == expected_xor and
                magic == expected_magic
            )

            results.append({
                "index": index,
                "base_addr": f"0x{AXI_TEST_BASES[index]:08X}",
                "passed": passed,
                "in_a": in_a,
                "in_b": in_b,
                "in_c": in_c,
                "rw_reg": rw,
                "out_sum": out_sum,
                "expected_sum": expected_sum,
                "out_xor": out_xor,
                "expected_xor": expected_xor,
                "magic": f"0x{magic:08X}",
                "expected_magic": f"0x{expected_magic:08X}",
            })

        return jsonify({
            "status": "success",
            "all_passed": all(r["passed"] for r in results),
            "results": results,
        })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)