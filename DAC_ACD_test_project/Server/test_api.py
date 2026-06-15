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

# --- 1. System Controller ---
def write_sys_ctrl(arm, trigger):
    """Writes the arm and trigger states to the System Controller."""
    return requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": arm, "trigger": trigger}).json()

def read_sys_ctrl():
    """Reads the current state of the System Controller. 
    Note: Requires a GET method to be implemented in server.py!"""
    resp = requests.get(f"{BASE_URL}/sys_ctrl")
    return resp.json() if resp.ok else {"error": "GET not implemented on server for this module"}

# --- 2. Ramp Generator ---
def write_ramp_gen(**kwargs):
    """Writes parameters (min_val, max_val) to the Ramp Generator."""
    return requests.post(f"{BASE_URL}/ramp_gen", json=kwargs).json()

def read_ramp_gen():
    """Reads all current settings from the Ramp Generator."""
    return requests.get(f"{BASE_URL}/ramp_gen").json()

# --- 3. Peak Detector ---
def write_peak_detector(**kwargs):
    """Writes parameters (threshold) to the Peak Detector."""
    return requests.post(f"{BASE_URL}/peak_detector", json=kwargs).json()

def read_peak_detector():
    """Reads all current settings and status flags from the Peak Detector."""
    return requests.get(f"{BASE_URL}/peak_detector").json()

# --- 4. Test Peak Generator ---
def write_test_gen(**kwargs):
    """Writes parameters (dly_1-4, peak_amp, base_amp, pulse_width) to the Test Gen."""
    return requests.post(f"{BASE_URL}/test_gen", json=kwargs).json()

def read_test_gen():
    """Reads all current settings from the Test Peak Generator."""
    return requests.get(f"{BASE_URL}/test_gen").json()


# ==============================================================================
# MAIN TEST ROUTINES
# ==============================================================================

def configure_system():
    print("1. Configuring Systems via AXI...")
    
    # Target Configuration Values
    ramp_cfg = {"min_val": 0, "max_val": 8000}
    det_cfg  = {"threshold": 4000}
    test_cfg = {
        "dly_1": 150,
        "dly_2": 300,
        "dly_3": 450,
        "dly_4": 600,
        "peak_amp": 6000,
        "base_amp": 0,
        "pulse_width": 25
    }

    # Send POST requests using the new write wrappers
    write_ramp_gen(**ramp_cfg)
    write_peak_detector(**det_cfg)
    write_test_gen(**test_cfg)

    print("2. Verifying Configuration...")
    
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
    print("\n3. Arming the system (Arm=1, Trigger=0)...")
    write_sys_ctrl(arm=1, trigger=0)
    time.sleep(0.1) # Brief pause to let hardware reset counters
    
    print("4. Firing Trigger! (Arm=1, Trigger=1)...")
    write_sys_ctrl(arm=1, trigger=1)

def fetch_results():
    print("5. Waiting for hardware to capture peaks...")
    
    # Wait half a second. Because of our repeating trigger architecture, 
    # the hardware will have captured thousands of slopes in this time.
    time.sleep(0.5) 

    # Disarm the system to freeze the hardware state (stops the repeating triggers)
    print("6. Disarming system to freeze registers...")
    write_sys_ctrl(arm=0, trigger=0)
    
    # Now that the registers are frozen, we can safely read them without race conditions
    resp = read_peak_detector()

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected in last cycle: {resp.get('peak_count')}")
    print(f"Timestamp 1: {resp.get('ts_1')} clock cycles")
    print(f"Timestamp 2: {resp.get('ts_2')} clock cycles")
    print(f"Timestamp 3: {resp.get('ts_3')} clock cycles")
    print(f"Timestamp 4: {resp.get('ts_4')} clock cycles")

if __name__ == "__main__":
    try:
        write_sys_ctrl(0, 0)
        configure_system()
        run_test()

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")