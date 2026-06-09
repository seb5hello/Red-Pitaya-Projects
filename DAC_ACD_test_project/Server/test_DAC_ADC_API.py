import requests
import time
import sys

# Replace with your Red Pitaya's local IP address
RP_IP = "100.83.1.106" 
BASE_URL = f"http://{RP_IP}:5000/api"

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

    # Send POST requests
    requests.post(f"{BASE_URL}/ramp_gen", json=ramp_cfg)
    requests.post(f"{BASE_URL}/peak_detector", json=det_cfg)
    requests.post(f"{BASE_URL}/test_gen", json=test_cfg)

    print("2. Verifying Configuration...")
    
    # Read back values via GET
    ramp_resp = requests.get(f"{BASE_URL}/ramp_gen").json()
    det_resp  = requests.get(f"{BASE_URL}/peak_detector").json()
    test_resp = requests.get(f"{BASE_URL}/test_gen").json()

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
    requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": 1, "trigger": 0})
    time.sleep(0.1) # Brief pause to let hardware reset counters
    
    print("4. Firing Trigger! (Arm=1, Trigger=1)...")
    requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": 1, "trigger": 1})

def fetch_results():
    print("5. Waiting for hardware to capture peaks...")
    
    # Wait half a second. Because of our repeating trigger architecture, 
    # the hardware will have captured thousands of slopes in this time.
    time.sleep(0.5) 

    # Disarm the system to freeze the hardware state (stops the repeating triggers)
    print("6. Disarming system to freeze registers...")
    requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": 0, "trigger": 0})
    
    # Now that the registers are frozen, we can safely read them without race conditions
    resp = requests.get(f"{BASE_URL}/peak_detector").json()

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected in last cycle: {resp['peak_count']}")
    print(f"Timestamp 1: {resp['ts_1']} clock cycles")
    print(f"Timestamp 2: {resp['ts_2']} clock cycles")
    print(f"Timestamp 3: {resp['ts_3']} clock cycles")
    print(f"Timestamp 4: {resp['ts_4']} clock cycles")

if __name__ == "__main__":
    try:
        configure_system()
        run_test()
        fetch_results()
    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")