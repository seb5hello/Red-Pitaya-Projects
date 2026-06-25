import requests
import sys
import time

# ==============================================================================
# Configuration
# ==============================================================================
# UPDATE THIS to match your Red Pitaya's actual IP address on your network
RP_IP = "192.168.2.29" 
BASE_URL = f"http://{IP_ADDRESS}:5000/api/pid_ctrl"

INPUT_FILE = "golden_vectors.txt"
OUTPUT_FILE = "verilog_outputs.txt"

def test_pid():
    print(f"Starting hardware PID validation against {IP_ADDRESS}...")
    
    try:
        with open(INPUT_FILE, 'r') as infile, open(OUTPUT_FILE, 'w') as outfile:
            
            # Write a header for the output file
            outfile.write("Target_TS\tCurrent_TS\tKp\tKi\tKd\tDAC_Out\n")
            outfile.write("-" * 65 + "\n")
            
            lines = infile.readlines()
            
            for line_num, line in enumerate(lines, 1):
                line = line.strip()
                
                # Skip empty lines or header/comment lines
                if not line or line.startswith('#') or line.lower().startswith('target'):
                    continue 

                # Normalize delimiters (converts commas to spaces, then splits)
                parts = line.replace(',', ' ').split()
                
                if len(parts) < 5:
                    print(f"Line {line_num}: Skipping malformed line -> '{line}'")
                    continue

                # Extract variables
                try:
                    target_ts  = int(parts[0])
                    current_ts = int(parts[1])
                    kp = int(parts[2])
                    ki = int(parts[3])
                    kd = int(parts[4])
                except ValueError:
                    print(f"Line {line_num}: Non-integer values found, skipping...")
                    continue

                # 1. Formulate the payload
                payload = {
                    "target_timestamp": target_ts,
                    "current_timestamp": current_ts,
                    "kp": kp,
                    "ki": ki,
                    "kd": kd,
                    "trigger": 1
                }

                # 2. Push variables to hardware and trigger the 1-cycle calculation
                post_res = requests.post(BASE_URL, json=payload)
                if post_res.status_code != 200:
                    print(f"API Error (POST) on line {line_num}: {post_res.text}")
                    continue

                # 3. Read the latched result back from the hardware
                get_res = requests.get(BASE_URL)
                if get_res.status_code != 200:
                    print(f"API Error (GET) on line {line_num}: {get_res.text}")
                    continue
                
                data = get_res.json()
                dac_out = data.get("dac_out", 0)

                # 4. Format and write to output file
                out_line = f"{target_ts}\t{current_ts}\t{kp}\t{ki}\t{kd}\t{dac_out}\n"
                outfile.write(out_line)
                
                # Optional: Print to console for real-time monitoring
                print(f"Vector {line_num:03d} -> Target: {target_ts}, Curr: {current_ts} | Out: {dac_out}")

    except FileNotFoundError:
        print(f"CRITICAL ERROR: Could not find '{INPUT_FILE}'. Please ensure it is in the same directory.")
        sys.exit(1)
    except requests.exceptions.ConnectionError:
        print(f"CRITICAL ERROR: Could not connect to {BASE_URL}. Is the Flask server running on the Red Pitaya?")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    test_pid()
    print(f"\nValidation complete. Results successfully saved to '{OUTPUT_FILE}'.")