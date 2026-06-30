import requests
import time
import sys
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import matplotlib.gridspec as gridspec
from collections import deque
import csv
from datetime import datetime, timedelta
import matplotlib.dates as mdates

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
    time.sleep(0.1) 
    
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

# ==============================================================================
# LIVE PLOTTING ROUTINE
# ==============================================================================

def live_plot():
    calc_n_cycles = freq_to_cycles(RAMP_FREQ_HZ)
    window_max = 2 * calc_n_cycles

    # --- Data Logging Setup ---
    csv_filename = f"pulse_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    with open(csv_filename, mode='w', newline='') as file:
        writer = csv.writer(file)
        # Added Peak_Count to the CSV header
        writer.writerow(["Timestamp", "Peak_Count", "TS_1", "TS_2", "TS_3", "TS_4", "TS_5", "TS_6", "TS_7", "TS_8"])
    
    print(f"\n -> Saving live data to: {csv_filename}")

    # --- Figure 1: Main Plot (Lollipop Chart) ---
    fig_main, ax_main = plt.subplots(figsize=(10, 6))
    fig_main.canvas.manager.set_window_title("Live Pulse Detection")
    
    main_vlines = ax_main.vlines([], [], [], colors='blue', linewidth=1.2, zorder=2)
    main_scatter = ax_main.scatter([], [], c='blue', s=40, zorder=3)
    main_texts = [] 

    ax_main.set_xlim(0, window_max)
    ax_main.set_ylim(0, 9.5) 
    ax_main.set_yticks(range(1, 9))
    ax_main.set_ylabel("Timestamp Index")
    ax_main.set_xlabel("Clock Cycles")
    ax_main.set_title("Live Filtered Timestamp Positions in Detection Window")
    ax_main.grid(True, linestyle=':', alpha=0.6, zorder=0)
    ax_main.axvline(x=calc_n_cycles, color='red', linestyle='--', linewidth=2, label='Start of 2nd Half')
    ax_main.legend(loc="upper right")
    fig_main.tight_layout()

    # --- Figure 2: Variation Tracking Plots (3x3 Grid) ---
    # Expanded grid to 3 rows, 3 columns to fit 9 plots
    fig_track, axes_track_matrix = plt.subplots(3, 3, figsize=(15, 10))
    fig_track.canvas.manager.set_window_title("Filtered Timestamp & Peak Count Tracking (Max 3 Hours)")
    fig_track.subplots_adjust(hspace=0.6, wspace=0.4, bottom=0.1)
    
    axes_track = axes_track_matrix.flatten()
    lines_track = []
    
    # 1. Setup the first 8 plots for individual timestamps
    for i in range(8):
        ax = axes_track[i]
        line, = ax.plot([], [], lw=2, color=f"C{i}")
        
        ax.set_title(f"TS {i+1} Variation", fontsize=10)
        ax.set_ylabel("Cycle Count", fontsize=8)
        ax.grid(True, linestyle=':', alpha=0.6)
        
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
        ax.tick_params(axis='x', rotation=45, labelsize=8)
        
        lines_track.append(line)

    # 2. Setup the 9th plot for the Peak Count
    ax_peaks = axes_track[8]
    line_peaks, = ax_peaks.plot([], [], lw=2, color='magenta')
    ax_peaks.set_title("Detected Peak Count", fontsize=10, fontweight='bold')
    ax_peaks.set_ylabel("Count", fontsize=8)
    ax_peaks.grid(True, linestyle=':', alpha=0.6)
    ax_peaks.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    ax_peaks.tick_params(axis='x', rotation=45, labelsize=8)

    # Data structures for rolling history
    MAX_HISTORY_SECONDS = 3 * 3600 # 3 hours
    x_data = []
    y_data = [[] for _ in range(8)]
    y_data_peaks = [] # New list to track peak count over time

    def fetch_data():
        requests.post(f"{BASE_URL}/peak_detector", json={"trigger": 1})
        
        timeout = 2.0 
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                resp = requests.get(f"{BASE_URL}/peak_detector").json()
                if resp.get("data_ready"):
                    # Return both the peak count and the array of timestamps
                    peak_count = resp.get("peak_count", 0)
                    timestamps = [resp.get(f"ts_{i}", 0) for i in range(1, 9)]
                    return peak_count, timestamps
            except requests.exceptions.RequestException:
                pass 
            time.sleep(0.01) 
            
        print("Warning: Fetch timeout. No peaks detected or connection lost.")
        return 0, [0] * 8 

    def update_plot(frame):
        peak_count, timestamps = fetch_data()
        y_vals = list(range(1, 9))
        current_time = datetime.now()
        
        # --- Save to CSV ---
        with open(csv_filename, mode='a', newline='') as file:
            writer = csv.writer(file)
            writer.writerow([current_time.isoformat(), peak_count] + timestamps)

        # --- 1. Update Figure 1 (Main Plot) ---
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
        
        # --- 2. Update Figure 2 (Tracking Data) ---
        x_data.append(current_time)
        y_data_peaks.append(peak_count)
        
        for i in range(8):
            y_data[i].append(timestamps[i])

        # Prune data older than 3 hours
        cutoff_time = current_time - timedelta(seconds=MAX_HISTORY_SECONDS)
        while len(x_data) > 0 and x_data[0] < cutoff_time:
            x_data.pop(0)
            y_data_peaks.pop(0)
            for i in range(8):
                y_data[i].pop(0)

        # Update the line charts and dynamic axes for timestamps
        for i in range(8):
            lines_track[i].set_data(x_data, y_data[i])
            
            if len(x_data) > 1:
                axes_track[i].set_xlim(x_data[0], x_data[-1])
            else:
                axes_track[i].set_xlim(x_data[0], x_data[0] + timedelta(seconds=1))
            
            if len(y_data[i]) > 0:
                min_y = min(y_data[i])
                max_y = max(y_data[i])
                padding = (max_y - min_y) * 0.05
                if padding == 0: 
                    padding = max_y * 0.05 if max_y != 0 else 100
                axes_track[i].set_ylim(max(0, min_y - padding), max_y + padding)

        # Update the Peak Count tracking plot
        line_peaks.set_data(x_data, y_data_peaks)
        if len(x_data) > 1:
            ax_peaks.set_xlim(x_data[0], x_data[-1])
        else:
            ax_peaks.set_xlim(x_data[0], x_data[0] + timedelta(seconds=1))
            
        if len(y_data_peaks) > 0:
            # Set Y limits to tightly bound the count, ensuring it stays readable
            ax_peaks.set_ylim(max(0, min(y_data_peaks) - 1), max(y_data_peaks) + 1)

        fig_track.canvas.draw_idle()

        return [main_scatter, main_vlines] + main_texts

    print("\n8. Starting live plots... Close the pop-up windows to end the script.")
    
    ani = animation.FuncAnimation(fig_main, update_plot, interval=100, blit=False, cache_frame_data=False)
    
    plt.show()

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

if __name__ == "__main__":
    try:        
        configure_system()
        run_test()
        fetch_results() 
        # live_plot()
        # run_pid()
        # soft_disarm()

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")