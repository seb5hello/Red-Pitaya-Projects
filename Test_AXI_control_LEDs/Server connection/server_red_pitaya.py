import mmap
import os
from flask import Flask

app = Flask(__name__)
FPGA_BASE_ADDR = 0x40000000 # Standard for Red Pitaya custom logic

@app.route('/control/<value>')
def control_fpga(value):
    f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    # Map 1 page (4096 bytes) of FPGA memory
    mem = mmap.mmap(f, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=FPGA_BASE_ADDR)

    # Write to the first register (offset 0)
    mem[0:4] = int(value).to_bytes(4, byteorder='little')

    mem.close()
    os.close(f)
    return f"Wrote {value} to FPGA"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080) # Use 8080 to avoid SCPI conflict