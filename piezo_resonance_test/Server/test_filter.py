import requests
import time
import sys

# ==============================================================================
# NETWORK CONFIGURATION
# ==============================================================================
# RP_IP = "100.83.1.106" 
RP_IP = "192.168.2.29" 
BASE_URL = f"http://{RP_IP}:5000/api"

# ==============================================================================
# GLOBAL HARDWARE CONFIGURATION PARAMETERS
# ==============================================================================
RAMP_FREQ_HZ = 6000       # Target frequency in Hz
MIN_VOLT = 0.025          # Target minimum voltage (V)
MAX_VOLT = 0.061          # Target maximum voltage (V)
THRESHOLD_VOLT = 0.5      # Peak detector threshold (V)

# New Peak Detector Settings
DET_OFFSET_CYCLES = 100   # Preemptive window offset
FILTER_MODE = 1           # 0: Bypass, 1: Strict, 2: Smart Sweep
EXPECTED_PEAKS = 2        # We expect 3 peaks up + 3 down = 6 total
MERGE_THRESHOLD = 10       # Peaks within 5 cycles of each other are considered bounces

# Test Generator Settings (Intentional Bounce Simulated!)
TEST_DLY_1 = 50
TEST_DLY_2 = 55           # <-- BOUNCE! Only 3 cycles after DLY_1
TEST_DLY_3 = 3500
TEST_DLY_4 = 3505
TEST_PEAK_AMP = 4000
TEST_BASE_AMP = 0
TEST_PULSE_WIDTH = 3

# ==============================================================================
# MODULE ABSTRACTION: READ/WRITE FUNCTIONS
# ==============================================================================

def write_sys_ctrl(mode, trigger):
    return requests.post(f"{BASE_URL}/sys_ctrl", json={"mode": mode, "trigger": trigger}).json()

def read_sys_ctrl():
    resp = requests.get(f"{BASE_URL}/sys_ctrl")
    return resp.json() if resp.ok else {"error": "GET not implemented"}

def write_ramp_gen(**kwargs):
    return requests.post(f"{BASE_URL}/ramp_gen", json=kwargs).json()

def read_ramp_gen():
    return requests.get(f"{BASE_URL}/ramp_gen").json()

def write_peak_detector(**kwargs):
    return requests.post(f"{BASE_URL}/peak_detector", json=kwargs).json()

def read_peak_detector():
    return requests.get(f"{BASE_URL}/peak_detector").json()

def write_test_gen(**kwargs):
    return requests.post(f"{BASE_URL}/test_gen", json=kwargs).json()

def read_test_gen():
    return requests.get(f"{BASE_URL}/test_gen").json()

# ==============================================================================
# HELPER CONVERSION FUNCTIONS
# ==============================================================================

def volt_to_dac(voltage):
    dac_val = int(voltage * 8191)
    return max(0, min(8191, dac_val))

def freq_to_cycles(freq_hz):
    if freq_hz <= 0:
        return 0
    return int(125_000_000 / freq_hz)

# ==============================================================================
# MAIN TEST ROUTINES
# ==============================================================================

def configure_system():
    print("1. Disarming system to ensure safe configuration (Mode=0)...")
    write_sys_ctrl(mode=0, trigger=0)
    
    print("2. Configuring Systems via AXI...")

    calc_n_cycles = freq_to_cycles(RAMP_FREQ_HZ)
    calc_min_val = volt_to_dac(MIN_VOLT)
    calc_max_val = volt_to_dac(MAX_VOLT)
    calc_threshold = volt_to_dac(THRESHOLD_VOLT)

    print(f"ramp_freq_hz    -> Converted {RAMP_FREQ_HZ} Hz to {calc_n_cycles} cycles.")
    print(f"min_volt        -> Converted {MIN_VOLT} V min to DAC val {calc_min_val}.")
    print(f"max_volt        -> Converted {MAX_VOLT} V max to DAC val {calc_max_val}.")
    print(f"threshold       -> Converted {THRESHOLD_VOLT} V to DAC val {calc_threshold}.")

    ramp_cfg = {
        "min_val": calc_min_val,    
        "max_val": calc_max_val, 
        "n_cycles": calc_n_cycles, 
        "continuous": 1    
    }
    
    # Updated Configuration Dictionary
    det_cfg  = {
        "threshold": calc_threshold,
        "offset": DET_OFFSET_CYCLES,
        "filter_mode": FILTER_MODE,
        "expected_peaks": EXPECTED_PEAKS,
        "merge_threshold": MERGE_THRESHOLD
    }

    test_cfg = {
        "dly_1": TEST_DLY_1,
        "dly_2": TEST_DLY_2,
        "dly_3": TEST_DLY_3,
        "dly_4": TEST_DLY_4,
        "peak_amp": TEST_PEAK_AMP,
        "base_amp": TEST_BASE_AMP,
        "pulse_width": TEST_PULSE_WIDTH
    }

    ramp_res = write_ramp_gen(**ramp_cfg)
    if ramp_res.get("status") == "error":
        print(f"\nAPI Error (Ramp Gen): {ramp_res.get('message')}")
        sys.exit(1)
        
    write_peak_detector(**det_cfg)
    write_test_gen(**test_cfg)

    print("3. Verifying Configuration...")
    
    ramp_resp = read_ramp_gen()
    det_resp  = read_peak_detector()
    test_resp = read_test_gen()

    errors = 0
    for key, val in ramp_cfg.items():
        if ramp_resp.get(key) != val:
            print(f" ERROR: Ramp Gen '{key}' expected {val}, got {ramp_resp.get(key)}")
            errors += 1
            
    # Verify new Detector parameters dynamically
    for key, val in det_cfg.items():
        if det_resp.get(key) != val:
            print(f" ERROR: Peak Detector '{key}' expected {val}, got {det_resp.get(key)}")
            errors += 1
        
    for key, val in test_cfg.items():
        if test_resp.get(key) != val:
            print(f" ERROR: Test Gen '{key}' expected {val}, got {test_resp.get(key)}")
            errors += 1

    if errors > 0:
        print("\nConfiguration Verification FAILED. Aborting test.")
        sys.exit(1)
    else:
        print(" -> All variables successfully verified over AXI!")

def run_test():
    print("\n4. Arming the system (Mode=-1, Trigger=0)...")
    write_sys_ctrl(mode=-1, trigger=0)
    time.sleep(0.1) 
    
    print("5. Firing Hardware Trigger! (Mode=-1, Trigger=1)...")
    write_sys_ctrl(mode=-1, trigger=1)
    write_sys_ctrl(mode=-1, trigger=0)

def fetch_results():
    print("6. Waiting for hardware to capture initial peaks...")
    time.sleep(0.5) 

    print("7. Requesting Timestamp Data via AXI Software Trigger...")
    write_peak_detector(trigger=1)
    
    timeout = 5.0 
    start_time = time.time()
    resp = {}
    
    print("   -> Polling for data_ready flag...")
    while time.time() - start_time < timeout:
        resp = read_peak_detector()
        if resp.get("data_ready"):
            print("   -> Success: Data successfully latched by hardware!")
            break
        time.sleep(0.01) 
    else:
        print("   -> TIMEOUT ERROR: Hardware never set data_ready flag. Did the peaks cross the threshold?")

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected    : {resp.get('peak_count', 0)}")
    print(f"Filter Status     : {resp.get('filter_status_str')} (Raw Code: {resp.get('filter_status_raw')})")
    print(f"Preempted / Trunc : {resp.get('preempted', False)}")
    print("---------------------------------------")
    
    for i in range(1, 9):
        print(f"Filtered TS {i}   : {resp.get(f'ts_{i}', 0):<6} clock cycles")

if __name__ == "__main__":
    try:
        # Ensure we start in a safe state
        write_sys_ctrl(mode=0, trigger=0)
        configure_system()
        run_test()
        fetch_results() 

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")