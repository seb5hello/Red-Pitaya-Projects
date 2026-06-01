import requests
import time

# Replace with your Red Pitaya's local IP address
RP_IP = "192.168.1.100" 
BASE_URL = f"http://{RP_IP}:5000/api"

def configure_system():
    print("1. Configuring Ramp Generator...")
    requests.post(f"{BASE_URL}/ramp_gen", json={"min_val": 0, "max_val": 8000})
    
    print("2. Configuring Peak Detector Threshold...")
    # Set threshold slightly lower than the test peak amplitude
    requests.post(f"{BASE_URL}/peak_detector", json={"threshold": 4000})

    print("3. Configuring Test Generator...")
    requests.post(f"{BASE_URL}/test_gen", json={
        "dly_1": 150,  # Cycle 150
        "dly_2": 300,  # Cycle 300
        "dly_3": 450,  # Cycle 450
        "dly_4": 600,  # Cycle 600
        "peak_amp": 6000, # Amplitude above threshold
        "base_amp": 0
    })

def run_test():
    print("4. Arming the system (Arm=1, Trigger=0)...")
    requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": 1, "trigger": 0})
    time.sleep(0.1) # Brief pause to let hardware reset counters
    
    print("5. Firing Trigger! (Arm=1, Trigger=1)...")
    requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": 1, "trigger": 1})

def fetch_results():
    print("6. Polling for results...")
    
    # Wait for the FPGA 'done' flag to go high
    while True:
        resp = requests.get(f"{BASE_URL}/peak_detector").json()
        if resp['done']:
            break
        time.sleep(0.1)

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected: {resp['peak_count']}")
    print(f"Timestamp 1: {resp['ts_1']} clock cycles")
    print(f"Timestamp 2: {resp['ts_2']} clock cycles")
    print(f"Timestamp 3: {resp['ts_3']} clock cycles")
    print(f"Timestamp 4: {resp['ts_4']} clock cycles")
    
    # Disarm the system to reset
    print("\n7. Disarming system...")
    requests.post(f"{BASE_URL}/sys_ctrl", json={"arm": 0, "trigger": 0})

if __name__ == "__main__":
    try:
        configure_system()
        run_test()
        fetch_results()
    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")