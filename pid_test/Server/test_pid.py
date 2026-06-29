import requests
import sys
import time

# ==============================================================================
# Configuration
# ==============================================================================
# UPDATE THIS to match your Red Pitaya's actual IP address on your network
IP_ADDRESS = "192.168.2.29" 
API_URL = f"http://{IP_ADDRESS}:5000/api/pid_ctrl"
INPUT_FILE = "golden_vectors.txt"
OUTPUT_FILE = "verilog_output.txt"
TIMEOUT_SEC = 2.0 # Failsafe to prevent infinite polling loops

def write_sys_ctrl(arm, trigger):
    return requests.post(f"http://{IP_ADDRESS}:5000/api/sys_ctrl", json={"arm": arm, "trigger": trigger}).json()

def read_sys_ctrl():
    resp = requests.get(f"http://{IP_ADDRESS}:5000/api/sys_ctrl")
    return resp.json() if resp.ok else {"error": "GET not implemented"}

def run_hardware_tests():
    print(f"Starting hardware tests using {INPUT_FILE}...")
    
    try:
        with open(OUTPUT_FILE, 'w') as f_out:
            f_out.write("# target_ts actual_ts kp ki kd expected_dac_out verilog_dac_out\n")

            with open(INPUT_FILE, 'r') as f_in:
                for line_num, line in enumerate(f_in, start=1):
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue

                    parts = line.split()
                    if len(parts) < 6:
                        continue

                    target_ts = int(parts[0])
                    actual_ts = int(parts[1])
                    kp = int(parts[2])
                    ki = int(parts[3])
                    kd = int(parts[4])
                    expected_dac = int(parts[5])

                    try:
                        # STEP 1: Load all configuration data WITHOUT the trigger
                        payload_data = {
                            "target_timestamp": target_ts,
                            "current_timestamp": actual_ts,
                            "kp": kp,
                            "ki": ki,
                            "kd": kd
                        }
                        requests.post(API_URL, json=payload_data).raise_for_status()

                        # STEP 2: Send the Trigger independently
                        requests.post(API_URL, json={"trigger": 1}).raise_for_status()

                        # STEP 3: Poll the Hardware until 'ready' asserts
                        is_ready = 0
                        start_time = time.time()
                        result_data = {}
                        
                        while not is_ready:
                            if time.time() - start_time > TIMEOUT_SEC:
                                raise TimeoutError("Hardware failed to assert ready flag.")
                                
                            get_resp = requests.get(API_URL)
                            get_resp.raise_for_status()
                            result_data = get_resp.json()
                            is_ready = result_data.get("ready", 0)
                            
                            # Small sleep to prevent hammering the CPU/API too hard
                            time.sleep(0.001) 

                        # STEP 4: Extract the latched value (already contained in our last GET response)
                        verilog_dac_out = result_data.get("dac_out", 0)

                        # Log the result
                        out_line = f"{target_ts} {actual_ts} {kp} {ki} {kd} {expected_dac} {verilog_dac_out}"
                        f_out.write(out_line + "\n")
                        
                        print(f"Vector {line_num} -> Exp: {expected_dac:5d} | HW: {verilog_dac_out:5d} | Match: {expected_dac == verilog_dac_out}")

                    except requests.exceptions.RequestException as e:
                        print(f"API Error on line {line_num}: {e}")
                        break
                    except TimeoutError as e:
                        print(f"Timeout Error on line {line_num}: {e}")
                        break
                        
    except FileNotFoundError:
        print(f"Error: Could not find '{INPUT_FILE}'.")

if __name__ == "__main__":
    print(f"Disarming PID...")
    write_sys_ctrl(0,0)
    print(f"Arming PID...")
    write_sys_ctrl(1,1)
    run_hardware_tests()
    print(f"\nTesting complete. Output saved to {OUTPUT_FILE}.")