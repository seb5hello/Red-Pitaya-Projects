import os
import mmap
import ctypes
import threading
from flask import Flask, request, jsonify

app = Flask(__name__)

# ==============================================================================
# AXI BASE ADDRESSES (From ReadMe.md)
# ==============================================================================
MODULE_BASES = {
    "sys_ctrl": 0x40100000, # sys[1]
    "ramp_gen": 0x40200000, # sys[2]
    "peak_det": 0x40300000, # sys[3]
    "test_gen": 0x40400000  # sys[4]
}

MAP_SIZE = 4096
lock = threading.Lock()

# ==============================================================================
# HARDWARE MEMORY INITIALIZATION
# ==============================================================================
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)

mmaps = {
    name: mmap.mmap(
        fd, 
        MAP_SIZE, 
        mmap.MAP_SHARED, 
        mmap.PROT_READ | mmap.PROT_WRITE, 
        offset=base_addr
    )
    for name, base_addr in MODULE_BASES.items()
}

# ==============================================================================
# LOW-LEVEL HARDWARE DRIVERS (Thread-Safe)
# ==============================================================================
def u32(value):
    """Enforces strict 32-bit unsigned casting."""
    return int(value) & 0xFFFFFFFF

def write_reg(module_name, offset, value):
    """Safely writes a 32-bit value to the hardware."""
    if offset % 4 != 0:
        raise ValueError("AXI requires 4-byte alignment.")
        
    with lock:
        reg = ctypes.c_uint32.from_buffer(mmaps[module_name], offset)
        reg.value = u32(value)
        del reg  # Destroy pointer instantly

def read_reg(module_name, offset):
    """Safely reads a 32-bit value from the hardware."""
    if offset % 4 != 0:
        raise ValueError("AXI requires 4-byte alignment.")
        
    with lock:
        reg = ctypes.c_uint32.from_buffer(mmaps[module_name], offset)
        value = reg.value
        del reg  # Destroy pointer instantly
    return value

# ==============================================================================
# API ROUTES
# ==============================================================================

# --- 1. System Controller (sys[1]) ---
@app.route('/api/sys_ctrl', methods=['POST', 'GET'])
def sys_ctrl():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        arm = int(data.get('arm', 0)) & 0x1
        trigger = int(data.get('trigger', 0)) & 0x1
        
        # Pack Bit 0: Arm, Bit 1: Trigger
        reg_val = (trigger << 1) | arm
        write_reg("sys_ctrl", 0x00, reg_val)
        return jsonify({"status": "success", "reg_val": reg_val})
    else:
        # GET method implemented to support your test_api.py validation
        reg_val = read_reg("sys_ctrl", 0x00)
        return jsonify({
            "arm": reg_val & 0x1,
            "trigger": (reg_val >> 1) & 0x1,
            "raw": reg_val
        })
    
# --- 2. Custom Ramp Generator (sys[2]) ---
@app.route('/api/ramp_gen', methods=['POST', 'GET'])
def ramp_gen():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        
        # Read current state to validate bounds if only partial update is sent
        curr_min = read_reg("ramp_gen", 0x00) & 0x3FFF
        curr_max = read_reg("ramp_gen", 0x04) & 0x3FFF
        curr_n_cycles = read_reg("ramp_gen", 0x08)
        curr_mode = read_reg("ramp_gen", 0x0C)
        
        # Determine intended new values
        new_min = (data['min_val'] & 0x3FFF) if 'min_val' in data else curr_min
        new_max = (data['max_val'] & 0x3FFF) if 'max_val' in data else curr_max
        new_n_cycles = int(data['n_cycles']) if 'n_cycles' in data else curr_n_cycles
        new_continuous = (int(data['continuous']) & 0x1) if 'continuous' in data else curr_mode
        
        # Constraint 1: min_val must be larger than 204
        if new_min < 204:
            return jsonify({
                "status": "error", 
                "message": "min_val must be strictly greater than 205."
            }), 400
        
        # Constraint 2: max_val must be larger than 8191
        if new_max >= 8191:
            return jsonify({
                "status": "error", 
                "message": "max_val must be strictly smaller than 8191."
            }), 400
            
        # Constraint 3: n_cycles must be larger than the max-min amplitude
        amplitude = new_max - new_min
        if new_n_cycles <= amplitude:
            return jsonify({
                "status": "error", 
                "message": f"n_cycles ({new_n_cycles}) must be larger than the amplitude difference ({amplitude})."
            }), 400

        # All checks passed, commit to hardware
        if 'min_val' in data:
            write_reg("ramp_gen", 0x00, new_min)
        if 'max_val' in data:
            write_reg("ramp_gen", 0x04, new_max)
        if 'n_cycles' in data:
            write_reg("ramp_gen", 0x08, new_n_cycles)
        if 'continuous' in data:
            write_reg("ramp_gen", 0x0C, new_continuous)
            
        return jsonify({"status": "success"})
        
    else:
        return jsonify({
            "min_val": read_reg("ramp_gen", 0x00) & 0x3FFF,
            "max_val": read_reg("ramp_gen", 0x04) & 0x3FFF,
            "n_cycles": read_reg("ramp_gen", 0x08),
            "continuous": read_reg("ramp_gen", 0x0C) & 0x1
        })

# --- 3. Timestamp Peak Detector (sys[3]) ---
@app.route('/api/peak_detector', methods=['POST', 'GET'])
def peak_detector():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        if 'threshold' in data:
            write_reg("peak_det", 0x00, data['threshold'] & 0x3FFF)
        return jsonify({"status": "success"})
    else:
        status_reg = read_reg("peak_det", 0x04)
        return jsonify({
            "threshold": read_reg("peak_det", 0x00) & 0x3FFF,
            "done": bool(status_reg & 0x01),
            "peak_count": (status_reg >> 1) & 0x07,
            "ts_1": read_reg("peak_det", 0x08),
            "ts_2": read_reg("peak_det", 0x0C),
            "ts_3": read_reg("peak_det", 0x10),
            "ts_4": read_reg("peak_det", 0x14)
        })

# --- 4. Test Peak Generator (sys[4]) ---
@app.route('/api/test_gen', methods=['POST', 'GET'])
def test_gen():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        if 'dly_1' in data: write_reg("test_gen", 0x00, data['dly_1'])
        if 'dly_2' in data: write_reg("test_gen", 0x04, data['dly_2'])
        if 'dly_3' in data: write_reg("test_gen", 0x08, data['dly_3'])
        if 'dly_4' in data: write_reg("test_gen", 0x0C, data['dly_4'])
        if 'peak_amp' in data: write_reg("test_gen", 0x10, data['peak_amp'] & 0x3FFF)
        if 'base_amp' in data: write_reg("test_gen", 0x14, data['base_amp'] & 0x3FFF)
        if 'pulse_width' in data: write_reg("test_gen", 0x18, data['pulse_width'])
        return jsonify({"status": "success"})
    else:
        return jsonify({
            "dly_1": read_reg("test_gen", 0x00),
            "dly_2": read_reg("test_gen", 0x04),
            "dly_3": read_reg("test_gen", 0x08),
            "dly_4": read_reg("test_gen", 0x0C),
            "peak_amp": read_reg("test_gen", 0x10) & 0x3FFF,
            "base_amp": read_reg("test_gen", 0x14) & 0x3FFF,
            "pulse_width": read_reg("test_gen", 0x18)
        })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
    