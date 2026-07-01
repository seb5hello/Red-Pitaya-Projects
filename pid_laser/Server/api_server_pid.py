import os
import mmap
import ctypes
import threading
from flask import Flask, request, jsonify

app = Flask(__name__)

# ==============================================================================
# AXI BASE ADDRESSES
# ==============================================================================
MODULE_BASES = {
    "sys_ctrl": 0x40100000, # sys[1]
    "ramp_gen": 0x40200000, # sys[2]
    "peak_det": 0x40300000, # sys[3]
    "pid_ctrl": 0x40400000, # sys[4]
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
        del reg

def read_reg(module_name, offset):
    """Safely reads a 32-bit value from the hardware."""
    if offset % 4 != 0:
        raise ValueError("AXI requires 4-byte alignment.")
        
    with lock:
        reg = ctypes.c_uint32.from_buffer(mmaps[module_name], offset)
        value = reg.value
        del reg
    return value

# ==============================================================================
# API ROUTES
# ==============================================================================

# --- 1. System Controller (sys[1]) ---
@app.route('/api/sys_ctrl', methods=['POST', 'GET'])
def sys_ctrl():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        
        curr_reg_val = read_reg("sys_ctrl", 0x00)
        curr_mode = curr_reg_val & 0x7
        curr_trigger = (curr_reg_val >> 3) & 0x1
        
        new_mode = (int(data['mode']) & 0x7) if 'mode' in data else curr_mode
        new_trigger = (int(data['trigger']) & 0x1) if 'trigger' in data else curr_trigger
        
        reg_val = (new_trigger << 3) | new_mode
        write_reg("sys_ctrl", 0x00, reg_val)
        
        return jsonify({"status": "success", "written_val": reg_val})
        
    else:
        reg_val = read_reg("sys_ctrl", 0x00)
        mode_3bit = reg_val & 0x7
        trigger = (reg_val >> 3) & 0x1
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
        
        curr_min = read_reg("ramp_gen", 0x00) & 0x3FFF
        curr_max = read_reg("ramp_gen", 0x04) & 0x3FFF
        curr_n_cycles = read_reg("ramp_gen", 0x08)
        curr_mode = read_reg("ramp_gen", 0x0C)
        
        new_min = (data['min_val'] & 0x3FFF) if 'min_val' in data else curr_min
        new_max = (data['max_val'] & 0x3FFF) if 'max_val' in data else curr_max
        new_n_cycles = int(data['n_cycles']) if 'n_cycles' in data else curr_n_cycles
        new_continuous = (int(data['continuous']) & 0x1) if 'continuous' in data else curr_mode
        
        if new_min < 204:
            return jsonify({"status": "error", "message": "min_val must be > 205."}), 400
        if new_max >= 8191:
            return jsonify({"status": "error", "message": "max_val must be < 8191."}), 400
            
        amplitude = new_max - new_min
        if new_n_cycles <= amplitude:
            return jsonify({"status": "error", "message": "n_cycles must be > amplitude."}), 400
        if new_n_cycles < 6250:
            return jsonify({"status": "error", "message": "n_cycles is too low."}), 400

        if 'min_val' in data: write_reg("ramp_gen", 0x00, new_min)
        if 'max_val' in data: write_reg("ramp_gen", 0x04, new_max)
        if 'n_cycles' in data: write_reg("ramp_gen", 0x08, new_n_cycles)
        if 'continuous' in data: write_reg("ramp_gen", 0x0C, new_continuous)
            
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
        
        if 'threshold' in data: write_reg("peak_det", 0x00, data['threshold'] & 0x3FFF)
        if 'offset' in data: write_reg("peak_det", 0x2C, u32(data['offset']))
        if 'filter_mode' in data: write_reg("peak_det", 0x30, int(data['filter_mode']) & 0x03)
        if 'expected_peaks' in data: write_reg("peak_det", 0x34, int(data['expected_peaks']) & 0x0F)
        if 'merge_threshold' in data: write_reg("peak_det", 0x38, u32(data['merge_threshold']))
        if 'trigger' in data: write_reg("peak_det", 0x28, data['trigger'] & 0x1)
            
        return jsonify({"status": "success"})
    else:
        status_reg = read_reg("peak_det", 0x04)
        filter_status_raw = (status_reg >> 7) & 0x03
        filter_status_map = {0: "OK", 1: "BYPASS", 2: "TOO_FEW", 3: "TOO_MANY"}
        
        return jsonify({
            "threshold": read_reg("peak_det", 0x00) & 0x3FFF,
            "offset": read_reg("peak_det", 0x2C),
            "filter_mode": read_reg("peak_det", 0x30),
            "expected_peaks": read_reg("peak_det", 0x34),
            "merge_threshold": read_reg("peak_det", 0x38),
            
            "peak_count": status_reg & 0x0F,
            "data_ready": bool((status_reg >> 4) & 0x01),
            "trigger_req": bool((status_reg >> 5) & 0x01),
            "preempted": bool((status_reg >> 6) & 0x01),
            "filter_status_raw": filter_status_raw,
            "filter_status_str": filter_status_map.get(filter_status_raw, "UNKNOWN"),
            
            "ts_1": read_reg("peak_det", 0x40),
            "ts_2": read_reg("peak_det", 0x44),
            "ts_3": read_reg("peak_det", 0x48),
            "ts_4": read_reg("peak_det", 0x4C),
            "ts_5": read_reg("peak_det", 0x50),
            "ts_6": read_reg("peak_det", 0x54),
            "ts_7": read_reg("peak_det", 0x58),
            "ts_8": read_reg("peak_det", 0x5C)
        })

# --- 5. PID Controller (sys[5]) ---
@app.route('/api/pid_ctrl', methods=['POST', 'GET'])
def pid_ctrl():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        
        # Software trigger to sample the current error and output
        if 'trigger_req' in data: write_reg("pid_ctrl", 0x00, data['trigger_req'] & 0x1)

        if 'kp' in data: write_reg("pid_ctrl", 0x04, data['kp'] & 0x3FFF)
        if 'ki' in data: write_reg("pid_ctrl", 0x08, data['ki'] & 0x3FFF)
        if 'kd' in data: write_reg("pid_ctrl", 0x0C, data['kd'] & 0x3FFF)
        if 'target_ts' in data: write_reg("pid_ctrl", 0x10, u32(data['target_ts']))
        if 'ts_select' in data: write_reg("pid_ctrl", 0x14, data['ts_select'] & 0x0F)
        
        # Offset and Output Limits
        if 'offset' in data: write_reg("pid_ctrl", 0x18, data['offset'] & 0x3FFF)
        if 'max_out' in data: write_reg("pid_ctrl", 0x1C, data['max_out'] & 0x3FFF)
        if 'min_out' in data: write_reg("pid_ctrl", 0x20, data['min_out'] & 0x3FFF)
        
        # Soft Output Limiter Config
        if 'step_cycles' in data: write_reg("pid_ctrl", 0x24, u32(data['step_cycles']))
        
        return jsonify({"status": "success"})
    else:
        def to_signed(val, bits=32):
            return val if val < (1 << (bits - 1)) else val - (1 << bits)
            
        status_reg = read_reg("pid_ctrl", 0x00)

        return jsonify({
            # Status and Sampling registers
            "trigger_req": status_reg & 0x01,
            "pid_ready": (status_reg >> 1) & 0x01,
            "trigger_seen": (status_reg >> 2) & 0x01,  # <--- NEW: Unpacks bit 2
            
            # PID Configuration
            "kp": to_signed(read_reg("pid_ctrl", 0x04)),
            "ki": to_signed(read_reg("pid_ctrl", 0x08)),
            "kd": to_signed(read_reg("pid_ctrl", 0x0C)),
            "target_ts": read_reg("pid_ctrl", 0x10),
            "ts_select": read_reg("pid_ctrl", 0x14) & 0x0F,
            
            "offset": to_signed(read_reg("pid_ctrl", 0x18)),
            "max_out": to_signed(read_reg("pid_ctrl", 0x1C)),
            "min_out": to_signed(read_reg("pid_ctrl", 0x20)),
            
            "step_cycles": read_reg("pid_ctrl", 0x24),
            
            # Data outputs (latched when trigger_req is sent)
            "sampled_error": to_signed(read_reg("pid_ctrl", 0x28)),
            "sampled_dac_out": to_signed(read_reg("pid_ctrl", 0x2C))
        })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)