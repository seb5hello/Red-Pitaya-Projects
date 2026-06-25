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
    "pid_ctrl": 0x40200000, # sys[2]
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
    
# --- 5. PID Controller (sys[5]) ---
@app.route('/api/pid_ctrl', methods=['POST', 'GET'])
def pid_ctrl():
    if request.method == 'POST':
        data = request.get_json(force=True) or {}
        
        # 1. Update the parameters and timestamps first
        if 'kp' in data: 
            write_reg("pid_ctrl", 0x04, data['kp'])
        if 'ki' in data: 
            write_reg("pid_ctrl", 0x08, data['ki'])
        if 'kd' in data: 
            write_reg("pid_ctrl", 0x0C, data['kd'])
            
        if 'target_timestamp' in data: 
            write_reg("pid_ctrl", 0x10, data['target_timestamp'])
        if 'current_timestamp' in data: 
            write_reg("pid_ctrl", 0x14, data['current_timestamp'])
            
        # 2. Issue the trigger to calculate the PID step 
        if data.get('trigger', 0):
            write_reg("pid_ctrl", 0x00, 1) # Automatically clears to 0 on the FPGA
            
        return jsonify({"status": "success"})
        
    else:
        # GET method to read PID configuration and outputs
        status_reg = read_reg("pid_ctrl", 0x00)
        
        # Bit 1 of register 0x00 is our `ready_o` signal 
        is_ready = (status_reg >> 1) & 0x1
        
        # Read parameters
        kp_val  = read_reg("pid_ctrl", 0x04)
        ki_val  = read_reg("pid_ctrl", 0x08)
        kd_val  = read_reg("pid_ctrl", 0x0C)
        targ_ts = read_reg("pid_ctrl", 0x10)
        curr_ts = read_reg("pid_ctrl", 0x14)
        
        # Handle the signed 14-bit output (sign extension for Python)
        dac_raw = read_reg("pid_ctrl", 0x18)
        dac_val = dac_raw if (dac_raw < 8192) else dac_raw - 16384
        
        return jsonify({
            "ready": is_ready,
            "kp": kp_val,
            "ki": ki_val,
            "kd": kd_val,
            "target_timestamp": targ_ts,
            "current_timestamp": curr_ts,
            "dac_out": dac_val,
            "dac_raw": dac_raw
        })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
    