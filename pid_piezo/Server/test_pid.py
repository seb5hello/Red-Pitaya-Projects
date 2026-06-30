import requests
import time
import sys

# ==============================================================================
# NETWORK CONFIGURATION
# ==============================================================================
RP_IP = "100.83.1.119" 
BASE_URL = f"http://{RP_IP}:5000/api"

# ==============================================================================
# GLOBAL HARDWARE CONFIGURATION PARAMETERS
# ==============================================================================
RAMP_FREQ_HZ = 6000       
MIN_VOLT = 0.025          
MAX_VOLT = 0.061          
THRESHOLD_VOLT = 0.5      

# Peak Detector Settings
DET_OFFSET_CYCLES = 100   
FILTER_MODE = 1           
EXPECTED_PEAKS = 2        
MERGE_THRESHOLD = 10       

# Test Generator Settings
TEST_DLY_1 = 50
TEST_DLY_2 = 55           
TEST_DLY_3 = 3500
TEST_DLY_4 = 3505
TEST_PEAK_AMP = 4000
TEST_BASE_AMP = 0
TEST_PULSE_WIDTH = 3

# PID Controller Settings
PID_KP = 150              
PID_KI = 25               
PID_KD = -10              
TARGET_TS = 12500         
TS_SELECT = 0             

PID_OFFSET = 4000         
PID_MAX_OUT = 8191        
PID_MIN_OUT = -8191       

# Piezo Soft Output Limiter (Cycles to wait before +/- 1)
PID_STEP_CYCLES = 2       

# ==============================================================================
# MODULE ABSTRACTION: READ/WRITE FUNCTIONS
# ==============================================================================

def write_sys_ctrl(mode, trigger):
    return requests.post(f"{BASE_URL}/sys_ctrl", json={"mode": mode, "trigger": trigger}).json()

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

def write_pid_ctrl(**kwargs):
    return requests.post(f"{BASE_URL}/pid_ctrl", json=kwargs).json()

def read_pid_ctrl():
    return requests.get(f"{BASE_URL}/pid_ctrl").json()

# ==============================================================================
# HELPER CONVERSION FUNCTIONS
# ==============================================================================

def volt_to_dac(voltage):
    dac_val = int(voltage * 8191)
    return max(0, min(8191, dac_val))

def freq_to_cycles(freq_hz):
    if freq_hz <= 0: return 0
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

    ramp_cfg = {
        "min_val": calc_min_val,    
        "max_val": calc_max_val, 
        "n_cycles": calc_n_cycles, 
        "continuous": 1    
    }
    
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

    pid_cfg = {
        "kp": PID_KP,
        "ki": PID_KI,
        "kd": PID_KD,
        "target_ts": TARGET_TS,
        "ts_select": TS_SELECT,
        "offset": PID_OFFSET,
        "max_out": PID_MAX_OUT,
        "min_out": PID_MIN_OUT,
        "step_cycles": PID_STEP_CYCLES
    }

    write_ramp_gen(**ramp_cfg)
    write_peak_detector(**det_cfg)
    write_test_gen(**test_cfg)
    write_pid_ctrl(**pid_cfg)

    print("3. Verifying Configuration...")
    
    ramp_resp = read_ramp_gen()
    det_resp  = read_peak_detector()
    test_resp = read_test_gen()
    pid_resp  = read_pid_ctrl()

    errors = 0
    for key, val in ramp_cfg.items():
        if ramp_resp.get(key) != val:
            print(f" ERROR: Ramp Gen '{key}' expected {val}, got {ramp_resp.get(key)}")
            errors += 1
            
    for key, val in det_cfg.items():
        if det_resp.get(key) != val:
            print(f" ERROR: Peak Detector '{key}' expected {val}, got {det_resp.get(key)}")
            errors += 1
        
    for key, val in test_cfg.items():
        if test_resp.get(key) != val:
            print(f" ERROR: Test Gen '{key}' expected {val}, got {test_resp.get(key)}")
            errors += 1

    for key, val in pid_cfg.items():
        if pid_resp.get(key) != val:
            print(f" ERROR: PID Ctrl '{key}' expected {val}, got {pid_resp.get(key)}")
            errors += 1

    if errors > 0:
        print("\nConfiguration Verification FAILED. Aborting test.")
        sys.exit(1)
    else:
        print(" -> All variables successfully verified over AXI!")

def run_test():
    print("\n4. Arming the system (Mode=2, Trigger=0)...")
    write_sys_ctrl(mode=1, trigger=0)
    time.sleep(0.1) 
    
    print("5. Firing Hardware Trigger! (Mode=2, Trigger=1)...")
    write_sys_ctrl(mode=1, trigger=1)
    write_sys_ctrl(mode=1, trigger=0)

def run_pid():
    print("\n4. Arming the system (Mode=2, Trigger=0)...")
    write_sys_ctrl(mode=2, trigger=0)

def fetch_results():
    print("6. Waiting for hardware to capture initial peaks...")
    time.sleep(0.5) 

    print("7. Requesting Timestamp Data via AXI Software Trigger...")
    write_peak_detector(trigger=1)
    
    timeout = 5.0 
    start_time = time.time()
    resp = {}
    
    while time.time() - start_time < timeout:
        resp = read_peak_detector()
        if resp.get("data_ready"):
            print("   -> Success: Data successfully latched by hardware!")
            break
        time.sleep(0.01) 
    else:
        print("   -> TIMEOUT ERROR: Hardware never set data_ready flag.")

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected    : {resp.get('peak_count', 0)}")
    print(f"Filter Status     : {resp.get('filter_status_str')} (Raw Code: {resp.get('filter_status_raw')})")
    print(f"Preempted / Trunc : {resp.get('preempted', False)}")
    print("---------------------------------------")
    
    for i in range(1, 9):
        print(f"Filtered TS {i}   : {resp.get(f'ts_{i}', 0):<6} clock cycles")

def soft_disarm():
    print("\n8. Initiating Graceful Soft Disarm (Mode=0)...")
    # Setting mode=0 will drive arm_i low on the hardware
    write_sys_ctrl(mode=0, trigger=0)
    print("   -> System disarmed. Piezo Soft Output engine is walking the DAC down to 0.")
    
    # Wait for the slew to complete. (If offset is 4000, and step_cycles is 2, 
    # it takes 8000 clock cycles @ 125MHz = ~64 microseconds. We wait 1 sec to be safe).
    time.sleep(1.0)
    print("   -> Disarm complete. Safe to power down or restart.")

if __name__ == "__main__":
    try:
        configure_system()
        run_test()
        fetch_results() 
        # run_pid()
        # soft_disarm()

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")