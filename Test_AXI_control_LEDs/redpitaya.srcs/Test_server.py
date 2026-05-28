import os
import mmap
import struct
from flask import Flask, request, jsonify

# ============================================================================
# FPGA Hardware Constants
# ============================================================================
# REPLACE THIS with your actual Master Base Address from Vivado's Address Editor
FPGA_BASE_ADDRESS = 0x43C00000 
PAGE_SIZE = 4096

# Register Offsets (Each register is 32-bit, so offsets increment by 4 bytes)
# WRITE Registers (ARM -> FPGA)
REG_KP      = 0x00 # slv_reg0
REG_KI      = 0x04 # slv_reg1
REG_KD      = 0x08 # slv_reg2
REG_STATE   = 0x0C # slv_reg3
REG_LED     = 0x10 # slv_reg4

# READ Registers (FPGA -> ARM)
REG_STATUS  = 0x20 # slv_reg8
REG_CONTROL = 0x24 # slv_reg9

# ============================================================================
# Memory Mapping Helper Class
# ============================================================================
class FPGAMemory:
    def __init__(self, base_address):
        self.base_address = base_address
        # Open /dev/mem with Read/Write and Sync flags
        self.f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        # Map a single page of memory (4096 bytes is plenty for our 16 registers)
        self.mem = mmap.mmap(self.f, PAGE_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base_address)

    def write_reg(self, offset, value):
        """Write a 32-bit unsigned integer to the FPGA register."""
        # Pack the integer into 4 bytes (little-endian)
        self.mem[offset:offset+4] = struct.pack('<I', int(value) & 0xFFFFFFFF)

    def read_reg(self, offset):
        """Read a 32-bit unsigned integer from the FPGA register."""
        # Unpack 4 bytes into an integer
        return struct.unpack('<I', self.mem[offset:offset+4])[0]

    def close(self):
        self.mem.close()
        os.close(self.f)

# ============================================================================
# Flask REST API Server
# ============================================================================
app = Flask(__name__)
fpga = None

@app.route('/api/config', methods=['POST'])
def set_config():
    """Endpoint to update FPGA parameters."""
    data = request.json
    
    try:
        # Write values to the FPGA if they exist in the JSON payload
        if 'kp' in data:
            fpga.write_reg(REG_KP, data['kp'])
        if 'ki' in data:
            fpga.write_reg(REG_KI, data['ki'])
        if 'kd' in data:
            fpga.write_reg(REG_KD, data['kd'])
        if 'state' in data:
            fpga.write_reg(REG_STATE, data['state'])
        if 'leds' in data:
            fpga.write_reg(REG_LED, data['leds'])
            
        return jsonify({"status": "success", "message": "FPGA registers updated."}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/status', methods=['GET'])
def get_status():
    """Endpoint to read results from the FPGA."""
    try:
        # Read the hardware registers
        status_val = fpga.read_reg(REG_STATUS)
        control_val = fpga.read_reg(REG_CONTROL)
        
        # Also read back the LEDs to show what they are currently set to
        current_leds = fpga.read_reg(REG_LED)
        
        return jsonify({
            "hardware_status": status_val,
            "hardware_control_out": control_val,
            "current_leds": current_leds
        }), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    print(f"Initializing FPGA memory map at {hex(FPGA_BASE_ADDRESS)}...")
    fpga = FPGAMemory(FPGA_BASE_ADDRESS)
    
    try:
        # Run the server on all available network interfaces at port 5000
        print("Starting FPGA Control Server on port 5000...")
        app.run(host='0.0.0.0', port=5000)
    finally:
        fpga.close()
        print("FPGA memory map closed safely.")