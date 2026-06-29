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
        
        # 1. READ current hardware state
        curr_reg_val = read_reg("sys_ctrl", 0x00)
        curr_mode = curr_reg_val & 0x7
        curr_trigger = (curr_reg_val >> 3) & 0x1
        
        # 2. MODIFY state based on provided data
        if 'mode' in data:
            new_mode = int(data['mode']) & 0x7
        else:
            new_mode = curr_mode
            
        if 'trigger' in data:
            new_trigger = int(data['trigger']) & 0x1
        else:
            new_trigger = curr_trigger
        
        # Pack Trigger (Bit 3) and Mode (Bits 2:0)
        reg_val = (new_trigger << 3) | new_mode
        
        # 3. WRITE back to hardware
        write_reg("sys_ctrl", 0x00, reg_val)
        
        return jsonify({"status": "success", "written_val": reg_val})
        
    else:
        # --- VERIFICATION (GET) ---
        # Read directly from the AXI bus to verify what the hardware is holding
        reg_val = read_reg("sys_ctrl", 0x00)
        
        # Extract bits
        mode_3bit = reg_val & 0x7
        trigger = (reg_val >> 3) & 0x1
        
        # Convert 3-bit two's complement back to a standard Python signed integer
        mode = mode_3bit if mode_3bit < 4 else mode_3bit - 8
        
        return jsonify({
            "mode": mode,
            "trigger": trigger,
            "raw_hex": hex(reg_val)
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
        
        # Constraint 2: max_val must be smaller than 8191
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
            
        # Constraint 4: n_cycles must be larger than 6250
        if new_n_cycles < 6250: # Fixed the comparison operator here
            return jsonify({
                "status": "error", 
                "message": f"n_cycles is too low, it must be a minimum of 6250 cycles or 20kHz for half of the triangle. You where trying to set at {new_n_cycles} cycles."
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

# --- 3. Timestamp Peak Detector & Smart Filter (sys[3]) ---
@app.route('/api/peak_detector', methods=['POST', 'GET'])
def peak_detector():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        
        # Write Configuration
        if 'threshold' in data:
            write_reg("peak_det", 0x00, data['threshold'] & 0x3FFF)
            
        if 'offset' in data:
            write_reg("peak_det", 0x2C, u32(data['offset']))
            
        if 'filter_mode' in data:
            write_reg("peak_det", 0x30, int(data['filter_mode']) & 0x03)
            
        if 'expected_peaks' in data:
            write_reg("peak_det", 0x34, int(data['expected_peaks']) & 0x0F)
            
        if 'merge_threshold' in data:
            write_reg("peak_det", 0x38, u32(data['merge_threshold']))
            
        # Write Software Trigger (Self-clears in hardware)
        if 'trigger' in data:
            write_reg("peak_det", 0x28, data['trigger'] & 0x1)
            
        return jsonify({"status": "success"})
    else:
        # Read the Master Status Register
        status_reg = read_reg("peak_det", 0x04)
        
        # Decode the 2-bit filter status (Bits [8:7])
        filter_status_raw = (status_reg >> 7) & 0x03
        filter_status_map = {
            0: "OK", 
            1: "BYPASS", 
            2: "TOO_FEW", 
            3: "TOO_MANY"
        }
        
        return jsonify({
            # Configurations
            "threshold": read_reg("peak_det", 0x00) & 0x3FFF,
            "offset": read_reg("peak_det", 0x2C),
            "filter_mode": read_reg("peak_det", 0x30),
            "expected_peaks": read_reg("peak_det", 0x34),
            "merge_threshold": read_reg("peak_det", 0x38),
            
            # Unpacked Status Register Bits
            "peak_count": status_reg & 0x0F,               # Bits [3:0]
            "data_ready": bool((status_reg >> 4) & 0x01),  # Bit 4
            "trigger_req": bool((status_reg >> 5) & 0x01), # Bit 5
            "preempted": bool((status_reg >> 6) & 0x01),   # Bit 6 (Truncation flag)
            "filter_status_raw": filter_status_raw,        # Bits [8:7]
            "filter_status_str": filter_status_map.get(filter_status_raw, "UNKNOWN"),
            
            # Filtered Timestamps (Shifted to 0x40 - 0x5C)
            "ts_1": read_reg("peak_det", 0x40),
            "ts_2": read_reg("peak_det", 0x44),
            "ts_3": read_reg("peak_det", 0x48),
            "ts_4": read_reg("peak_det", 0x4C),
            "ts_5": read_reg("peak_det", 0x50),
            "ts_6": read_reg("peak_det", 0x54),
            "ts_7": read_reg("peak_det", 0x58),
            "ts_8": read_reg("peak_det", 0x5C)
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
    