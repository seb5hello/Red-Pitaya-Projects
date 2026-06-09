import os
import mmap
import ctypes
from flask import Flask, request, jsonify

app = Flask(__name__)

# Base addresses for the custom AXI regions
SYS_CTRL_BASE = 0x40100000
RAMP_GEN_BASE = 0x40200000
PEAK_DET_BASE = 0x40300000
TEST_GEN_BASE = 0x40400000
MAP_SIZE = 4096

# ==============================================================================
# HARDWARE MEMORY INITIALIZATION
# Open /dev/mem ONCE globally and keep it open. This prevents Python BufferErrors 
# and massively speeds up the AXI bus communication.
# ==============================================================================
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)

# Dictionary holding persistent memory maps for each hardware module
mmaps = {
    SYS_CTRL_BASE: mmap.mmap(fd, MAP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=SYS_CTRL_BASE),
    RAMP_GEN_BASE: mmap.mmap(fd, MAP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=RAMP_GEN_BASE),
    PEAK_DET_BASE: mmap.mmap(fd, MAP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=PEAK_DET_BASE),
    TEST_GEN_BASE: mmap.mmap(fd, MAP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=TEST_GEN_BASE)
}

def write_mem(base_addr, offset, value):
    """Writes a 32-bit integer atomically using an inline ctypes cast."""
    # from_buffer evaluates the exact byte offset, writes the 32-bit value, 
    # and immediately releases the object. No dangling pointers!
    ctypes.c_uint32.from_buffer(mmaps[base_addr], offset).value = value

def read_mem(base_addr, offset):
    """Reads a 32-bit integer atomically using an inline ctypes cast."""
    return ctypes.c_uint32.from_buffer(mmaps[base_addr], offset).value

# ==============================================================================
# API ROUTES
# ==============================================================================

# --- System Controller ---
@app.route('/api/sys_ctrl', methods=['POST'])
def sys_ctrl():
    data = request.json
    arm = data.get('arm', 0)
    trigger = data.get('trigger', 0)
    
    # Pack Bit 0: Arm, Bit 1: Trigger
    reg_val = (trigger << 1) | arm
    write_mem(SYS_CTRL_BASE, 0x00, reg_val)
    return jsonify({"status": "success", "reg_val": reg_val})

# --- Custom Ramp Generator ---
@app.route('/api/ramp_gen', methods=['POST', 'GET'])
def ramp_gen():
    if request.method == 'POST':
        data = request.json
        if 'min_val' in data:
            write_mem(RAMP_GEN_BASE, 0x00, data['min_val'] & 0x3FFF)
        if 'max_val' in data:
            write_mem(RAMP_GEN_BASE, 0x04, data['max_val'] & 0x3FFF)
        return jsonify({"status": "success"})
    else:
        return jsonify({
            "min_val": read_mem(RAMP_GEN_BASE, 0x00) & 0x3FFF,
            "max_val": read_mem(RAMP_GEN_BASE, 0x04) & 0x3FFF
        })

# --- Timestamp Detector ---
@app.route('/api/peak_detector', methods=['POST', 'GET'])
def peak_detector():
    if request.method == 'POST':
        data = request.json
        if 'threshold' in data:
            write_mem(PEAK_DET_BASE, 0x00, data['threshold'] & 0x3FFF)
        return jsonify({"status": "success"})
    else:
        status_reg = read_mem(PEAK_DET_BASE, 0x04)
        return jsonify({
            "threshold": read_mem(PEAK_DET_BASE, 0x00) & 0x3FFF,
            "done": bool(status_reg & 0x01),
            "peak_count": (status_reg >> 1) & 0x07,
            "ts_1": read_mem(PEAK_DET_BASE, 0x08),
            "ts_2": read_mem(PEAK_DET_BASE, 0x0C),
            "ts_3": read_mem(PEAK_DET_BASE, 0x10),
            "ts_4": read_mem(PEAK_DET_BASE, 0x14)
        })

# --- Test Peak Generator ---
@app.route('/api/test_gen', methods=['POST', 'GET'])
def test_gen():
    if request.method == 'POST':
        data = request.json
        if 'dly_1' in data: write_mem(TEST_GEN_BASE, 0x00, data['dly_1'])
        if 'dly_2' in data: write_mem(TEST_GEN_BASE, 0x04, data['dly_2'])
        if 'dly_3' in data: write_mem(TEST_GEN_BASE, 0x08, data['dly_3'])
        if 'dly_4' in data: write_mem(TEST_GEN_BASE, 0x0C, data['dly_4'])
        if 'peak_amp' in data: write_mem(TEST_GEN_BASE, 0x10, data['peak_amp'] & 0x3FFF)
        if 'base_amp' in data: write_mem(TEST_GEN_BASE, 0x14, data['base_amp'] & 0x3FFF)
        if 'pulse_width' in data: write_mem(TEST_GEN_BASE, 0x18, data['pulse_width'])
        return jsonify({"status": "success"})
    else:
        return jsonify({
            "dly_1": read_mem(TEST_GEN_BASE, 0x00),
            "dly_2": read_mem(TEST_GEN_BASE, 0x04),
            "dly_3": read_mem(TEST_GEN_BASE, 0x08),
            "dly_4": read_mem(TEST_GEN_BASE, 0x0C),
            "peak_amp": read_mem(TEST_GEN_BASE, 0x10) & 0x3FFF,
            "base_amp": read_mem(TEST_GEN_BASE, 0x14) & 0x3FFF,
            "pulse_width": read_mem(TEST_GEN_BASE, 0x18)
        })

if __name__ == '__main__':
    # Listen on all interfaces on port 5000
    app.run(host='0.0.0.0', port=5000, debug=False)