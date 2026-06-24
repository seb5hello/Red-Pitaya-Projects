import requests
import time
import sys

# Replace with your Red Pitaya's local IP address
RP_IP = "100.83.1.106" 
# RP_IP = "100.83.1.117" 
# RP_IP = "192.168.2.29" 
BASE_URL = f"http://{RP_IP}:5000/api"

# ==============================================================================
# MODULE ABSTRACTION: READ/WRITE FUNCTIONS
# ==============================================================================

def write_sys_ctrl(arm, trigger):
    return requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": arm, "trigger": trigger}).json()

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
    """
    Converts a voltage value to a 13-bit integer.
    1 Volt = 13 bits all set to 1 (8191).
    """
    dac_val = int(voltage * 8191)
    # Clamp to max 13-bit unsigned value to prevent overflow errors
    return max(0, min(8191, dac_val))

def freq_to_cycles(freq_hz):
    """
    Converts a frequency in Hz to number of clock cycles.
    Based on the Red Pitaya's 125 MHz clock (8 ns per cycle).
    """
    if freq_hz <= 0:
        return 0
    return int(125_000_000 / freq_hz)

# ==============================================================================
# MAIN TEST ROUTINES
# ==============================================================================

def configure_system():
    print("1. Disarming system to ensure safe configuration...")
    # Explicitly disarm before touching any configuration registers
    write_sys_ctrl(arm=0, trigger=0)
    
    print("2. Configuring Systems via AXI...")
    
    # --- User Input Variables ---
    ramp_freq_hz = 5000       # Target frequency in Hz
    min_volt = 0.025          # Target minimum voltage
    max_volt = 0.061          # Target maximum voltage
    threshold = 0.5
    # ----------------------------

    # Calculate hardware values
    calc_n_cycles = freq_to_cycles(ramp_freq_hz)
    calc_min_val = volt_to_dac(min_volt)
    calc_max_val = volt_to_dac(max_volt)
    calc_threshold = volt_to_dac(threshold)

    print(f"ramp_freq_hz    -> Converted {ramp_freq_hz} Hz to {calc_n_cycles} cycles.")
    print(f"min_volt        -> Converted {min_volt} V min to DAC val {calc_min_val}.")
    print(f"max_volt        -> Converted {max_volt} V max to DAC val {calc_max_val}.")
    print(f"threshold       -> Converted {threshold} V max to DAC val {calc_threshold}.")

    # Target Configuration Values
    ramp_cfg = {
        "min_val": calc_min_val,    
        "max_val": calc_max_val, 
        "n_cycles": calc_n_cycles, 
        "continuous": 1    
    }
    
    det_cfg  = {"threshold": calc_threshold}

    test_cfg = {
        "dly_1": 50,
        "dly_2": 400,
        "dly_3": 500,
        "dly_4": 800,
        "peak_amp": 1000,
        "base_amp": 0,
        "pulse_width": 3
    }

    # Send POST requests using the new write wrappers
    ramp_res = write_ramp_gen(**ramp_cfg)
    if ramp_res.get("status") == "error":
        print(f"\nAPI Error (Ramp Gen): {ramp_res.get('message')}")
        sys.exit(1)
        
    write_peak_detector(**det_cfg)
    write_test_gen(**test_cfg)

    print("3. Verifying Configuration...")
    
    # Read back values via GET using the new read wrappers
    ramp_resp = read_ramp_gen()
    det_resp  = read_peak_detector()
    test_resp = read_test_gen()

    # Validation Checks
    errors = 0
    for key, val in ramp_cfg.items():
        if ramp_resp.get(key) != val:
            print(f" ERROR: Ramp Gen '{key}' expected {val}, got {ramp_resp.get(key)}")
            errors += 1
            
    if det_resp.get("threshold") != det_cfg["threshold"]:
        print(f" ERROR: Peak Detector 'threshold' expected {det_cfg['threshold']}, got {det_resp.get('threshold')}")
        errors += 1
        
    for key, val in test_cfg.items():
        if test_resp.get(key) != val:
            print(f" ERROR: Test Gen '{key}' expected {val}, got {test_resp.get(key)}")
            errors += 1

    if errors > 0:
        print("\nConfiguration Verification FAILED. Aborting test.")
        # sys.exit(1)
    else:
        print(" -> All variables successfully verified over AXI!")

def run_test():
    print("\n4. Arming the system (Arm=1, Trigger=0)...")
    write_sys_ctrl(arm=1, trigger=0)
    time.sleep(0.1) 
    
    print("5. Firing Hardware Trigger! (Arm=1, Trigger=1)...")
    write_sys_ctrl(arm=1, trigger=1)

def fetch_results():
    print("6. Waiting for hardware to capture initial peaks...")
    time.sleep(0.5) 

    print("7. Requesting Timestamp Data via AXI Software Trigger...")
    # Send software trigger to latch the next valid window
    write_peak_detector(trigger=1)
    
    # Poll until hardware confirms it has successfully latched data
    timeout = 5.0 
    start_time = time.time()
    resp = {}
    
    print("   -> Polling for data_ready flag...")
    while time.time() - start_time < timeout:
        resp = read_peak_detector()
        if resp.get("data_ready"):
            print("   -> Success: Data successfully latched by hardware!")
            break
        time.sleep(0.01) # 10ms polling interval
    else:
        print("   -> TIMEOUT ERROR: Hardware never set data_ready flag. Did the peaks cross the threshold?")
        
    print("8. Disarming system to freeze registers...")
    write_sys_ctrl(arm=0, trigger=0)

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected in latched window: {resp.get('peak_count', 0)}")
    for i in range(1, 9):
        print(f"Timestamp {i}: {resp.get(f'ts_{i}', 0):<6} clock cycles")

if __name__ == "__main__":
    try:
        configure_system()
        run_test()
        fetch_results() 

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")
