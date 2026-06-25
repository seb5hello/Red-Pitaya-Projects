import requests
import time
import sys
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import matplotlib.gridspec as gridspec
from collections import deque

# ==============================================================================
# NETWORK CONFIGURATION
# ==============================================================================
RP_IP = "100.83.1.106" 
# RP_IP = "192.168.2.29" 
BASE_URL = f"http://{RP_IP}:5000/api"

# ==============================================================================
# GLOBAL HARDWARE CONFIGURATION PARAMETERS
# ==============================================================================
RAMP_FREQ_HZ = 6000      # Target frequency in Hz
MIN_VOLT = 0.025          # Target minimum voltage (V)
MAX_VOLT = 0.061          # Target maximum voltage (V)
THRESHOLD_VOLT = 0.5      # Peak detector threshold (V)

# Test Generator Settings
TEST_DLY_1 = 50
TEST_DLY_2 = 1500
TEST_DLY_3 = 3500
TEST_DLY_4 = 5000
TEST_PEAK_AMP = 4000
TEST_BASE_AMP = 0
TEST_PULSE_WIDTH = 3

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
    print("1. Disarming system to ensure safe configuration...")
    write_sys_ctrl(arm=0, trigger=0)
    
    print("2. Configuring Systems via AXI...")

    calc_n_cycles = freq_to_cycles(RAMP_FREQ_HZ)
    calc_min_val = volt_to_dac(MIN_VOLT)
    calc_max_val = volt_to_dac(MAX_VOLT)
    calc_threshold = volt_to_dac(THRESHOLD_VOLT)

    print(f"ramp_freq_hz    -> Converted {RAMP_FREQ_HZ} Hz to {calc_n_cycles} cycles.")
    print(f"min_volt        -> Converted {MIN_VOLT} V min to DAC val {calc_min_val}.")
    print(f"max_volt        -> Converted {MAX_VOLT} V max to DAC val {calc_max_val}.")
    print(f"threshold       -> Converted {THRESHOLD_VOLT} V max to DAC val {calc_threshold}.")

    ramp_cfg = {
        "min_val": calc_min_val,    
        "max_val": calc_max_val, 
        "n_cycles": calc_n_cycles, 
        "continuous": 1    
    }
    
    det_cfg  = {"threshold": calc_threshold}

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
            
    if det_resp.get("threshold") != det_cfg["threshold"]:
        print(f" ERROR: Peak Detector 'threshold' expected {det_cfg['threshold']}, got {det_resp.get('threshold')}")
        errors += 1
        
    for key, val in test_cfg.items():
        if test_resp.get(key) != val:
            print(f" ERROR: Test Gen '{key}' expected {val}, got {test_resp.get(key)}")
            errors += 1

    if errors > 0:
        print("\nConfiguration Verification FAILED. Aborting test.")
    else:
        print(" -> All variables successfully verified over AXI!")

def run_test():
    print("\n4. Arming the system (Arm=1, Trigger=0)...")
    write_sys_ctrl(arm=1, trigger=0)
    time.sleep(0.1) 
    
    print("5. Firing Hardware Trigger! (Arm=1, Trigger=1)...")
    write_sys_ctrl(arm=1, trigger=1)
    write_sys_ctrl(arm=1, trigger=0)

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
    print(f"Peaks Detected in latched window: {resp.get('peak_count', 0)}")
    for i in range(1, 9):
        print(f"Timestamp {i}: {resp.get(f'ts_{i}', 0):<6} clock cycles")

# ==============================================================================
# LIVE PLOTTING ROUTINE
# ==============================================================================

def live_plot():
    calc_n_cycles = freq_to_cycles(RAMP_FREQ_HZ)
    window_max = 2 * calc_n_cycles

    # --- Figure 1: Main Plot (Lollipop Chart) ---
    fig_main, ax_main = plt.subplots(figsize=(10, 6))
    fig_main.canvas.manager.set_window_title("Live Pulse Detection")
    
    # Initialize empty elements
    main_vlines = ax_main.vlines([], [], [], colors='blue', linewidth=1.2, zorder=2)
    main_scatter = ax_main.scatter([], [], c='blue', s=40, zorder=3)
    main_texts = [] 

    ax_main.set_xlim(0, window_max)
    ax_main.set_ylim(0, 9.5) 
    ax_main.set_yticks(range(1, 9))
    ax_main.set_ylabel("Timestamp Index")
    ax_main.set_xlabel("Clock Cycles")
    ax_main.set_title("Live Timestamp Positions in Detection Window")
    ax_main.grid(True, linestyle=':', alpha=0.6, zorder=0)
    ax_main.axvline(x=calc_n_cycles, color='red', linestyle='--', linewidth=2, label='Start of 2nd Half')
    ax_main.legend(loc="upper right")
    fig_main.tight_layout()

    # --- Figure 2: Variation Tracking Plots (2x4 Grid) ---
    fig_track, axes_track_matrix = plt.subplots(2, 4, figsize=(14, 6))
    fig_track.canvas.manager.set_window_title("Timestamp Variation Tracking")
    fig_track.subplots_adjust(hspace=0.5, wspace=0.4)
    
    # Flatten the 2x4 matrix into a simple list of 8 axes for easy looping
    axes_track = axes_track_matrix.flatten()
    lines_track = []
    
    for i in range(8):
        ax = axes_track[i]
        line, = ax.plot([], [], lw=2, color=f"C{i}")
        
        ax.set_title(f"TS {i+1} Variation", fontsize=10)
        ax.set_xlabel("Instance", fontsize=8)
        ax.set_ylabel("Cycle Count", fontsize=8)
        ax.grid(True, linestyle=':', alpha=0.6)
        
        lines_track.append(line)

    # Data structures for rolling history
    HISTORY_LEN = 100
    x_data = deque(maxlen=HISTORY_LEN)
    y_data = [deque(maxlen=HISTORY_LEN) for _ in range(8)]
    instance_counter = [0] 

    def fetch_timestamps():
        requests.post(f"{BASE_URL}/peak_detector", json={"trigger": 1})
        
        timeout = 2.0 
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                resp = requests.get(f"{BASE_URL}/peak_detector").json()
                if resp.get("data_ready"):
                    return [resp.get(f"ts_{i}", 0) for i in range(1, 9)]
            except requests.exceptions.RequestException:
                pass 
            time.sleep(0.01) 
            
        print("Warning: Fetch timeout. No peaks detected or connection lost.")
        return [0] * 8 

    def update_plot(frame):
        timestamps = fetch_timestamps()
        y_vals = list(range(1, 9))
        
        # 1. Update Figure 1 (Main Plot)
        main_scatter.set_offsets(list(zip(timestamps, y_vals)))
        
        segments = [[(x, 0), (x, y)] for x, y in zip(timestamps, y_vals)]
        main_vlines.set_segments(segments)
        
        for txt in main_texts:
            txt.remove()
        main_texts.clear()
        
        for x, y in zip(timestamps, y_vals):
            txt = ax_main.text(
                x, y + 0.25, f"{x} cyc", 
                ha='center', va='bottom', fontsize=9, 
                fontweight='bold', color='darkblue'
            )
            main_texts.append(txt)
        
        # 2. Update Figure 2 (Tracking Data)
        curr_inst = instance_counter[0]
        x_data.append(curr_inst)
        instance_counter[0] += 1

        for i in range(8):
            y_data[i].append(timestamps[i])
            lines_track[i].set_data(x_data, y_data[i])
            
            axes_track[i].set_xlim(max(0, curr_inst - HISTORY_LEN), max(HISTORY_LEN, curr_inst))
            
            if len(y_data[i]) > 0:
                min_y = min(y_data[i])
                max_y = max(y_data[i])
                padding = (max_y - min_y) * 0.05
                if padding == 0: 
                    padding = max_y * 0.05 if max_y != 0 else 100
                axes_track[i].set_ylim(max(0, min_y - padding), max_y + padding)

        # Explicitly tell the second figure to redraw itself
        fig_track.canvas.draw_idle()

        return [main_scatter, main_vlines] + main_texts

    print("\n8. Starting live plots... Close the pop-up windows to end the script.")
    
    # The animation loop is bound to fig_main, but updates both
    ani = animation.FuncAnimation(fig_main, update_plot, interval=100, blit=False, cache_frame_data=False)
    
    # plt.show() will display all initialized figures and start the event loop
    plt.show()

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

if __name__ == "__main__":
    try:
        write_sys_ctrl(arm=0, trigger=0)
        configure_system()
        run_test()
        fetch_results() 
        live_plot()

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")