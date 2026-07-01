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
import threading # Add this to your imports at the top

# ==============================================================================
# NETWORK CONFIGURATION
# ==============================================================================
RP_IP = "100.83.1.117" 
# RP_IP = "192.168.2.29" 
BASE_URL = f"http://{RP_IP}:5000/api"

# ==============================================================================
# GLOBAL HARDWARE CONFIGURATION PARAMETERS
# ==============================================================================
RAMP_FREQ_HZ = 6000    
MAX_VOLT = 0.110           
MIN_VOLT = 0.060           
THRESHOLD_VOLT = 0.5      

# Peak Detector Settings
DET_OFFSET_CYCLES = 0   
FILTER_MODE = 0           
EXPECTED_PEAKS = 1        
MERGE_THRESHOLD = 100       

# PID Controller Settings
PID_KP = 10              
PID_KI = 0               
PID_KD = 0              
TARGET_TS = 10000         
TS_SELECT = 0             

PID_OFFSET = 2000         
PID_MAX_OUT = 8191        
PID_MIN_OUT = 205       

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
    print("Disarming system to ensure safe configuration (Mode=0)...")
    write_sys_ctrl(mode=0, trigger=0)
    time.sleep(0.1) 
    
    print("Configuring Systems via AXI...")

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
    write_pid_ctrl(**pid_cfg)

    print("Verifying Configuration...")
    
    ramp_resp = read_ramp_gen()
    det_resp  = read_peak_detector()
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

    for key, val in pid_cfg.items():
        if pid_resp.get(key) != val:
            print(f" ERROR: PID Ctrl '{key}' expected {val}, got {pid_resp.get(key)}")
            errors += 1

    if errors > 0:
        print("\nConfiguration Verification FAILED. Aborting test.")
        sys.exit(1)
    else:
        print(" -> All variables successfully verified over AXI!")

def ramp_on():
    print("\nArming the system (Mode=1, Trigger=0)...")
    write_sys_ctrl(mode=1, trigger=0)
    time.sleep(0.1) 
    
    print("Firing Hardware Trigger! (Mode=1, Trigger=1)...")
    write_sys_ctrl(mode=1, trigger=1)
    write_sys_ctrl(mode=1, trigger=0)

def pid_idle():
    print("\nPID module set to idle (Mode=2, Trigger=0)...")
    write_sys_ctrl(mode=2, trigger=0)

def pid_on():
    print("\nEngaging PID (Mode=3, Trigger=0)...")
    write_sys_ctrl(mode=3, trigger=0)

def soft_disarm():
    print("\nInitiating Graceful Soft Disarm (Mode=0)...")
    write_sys_ctrl(mode=0, trigger=0)
    print("   -> System disarmed. Piezo Soft Output engine is walking the DAC down to 0.")
    time.sleep(1.0)
    print("   -> Disarm complete. Safe to power down or restart.")

def fetch_results():
    print("\nWaiting for hardware to capture initial peaks...")
    time.sleep(0.5) 

    print("Requesting Timestamp and PID Data via AXI Software Triggers...")
    # Trigger both modules simultaneously
    write_peak_detector(trigger=1)
    write_pid_ctrl(trigger_req=1)
    
    timeout = 5.0 
    start_time = time.time()
    resp = {}
    
    # Wait for the peak detector to assert data_ready
    while time.time() - start_time < timeout:
        resp = read_peak_detector()
        if resp.get("data_ready"):
            print("   -> Success: Data successfully latched by hardware!")
            break
        time.sleep(0.01) 
    else:
        print("   -> TIMEOUT ERROR: Hardware never set data_ready flag.")

    # Read the latched PID controller data
    pid_resp = read_pid_ctrl()

    print("\n--- TEST COMPLETE ---")
    print(f"Peaks Detected    : {resp.get('peak_count', 0)}")
    print(f"Filter Status     : {resp.get('filter_status_str')} (Raw Code: {resp.get('filter_status_raw')})")
    print(f"Preempted / Trunc : {resp.get('preempted', False)}")
    print("---------------------------------------")
    
    for i in range(1, 9):
        print(f"Filtered TS {i}   : {resp.get(f'ts_{i}', 0):<6} clock cycles")
        
    print("---------------------------------------")
    print("PID Controller Data:")
    print(f"Trigger Seen (Win): {pid_resp.get('trigger_seen', 0)}")
    print(f"Sampled Error     : {pid_resp.get('sampled_error', 0)} clock cycles")
    print(f"Sampled DAC Output: {pid_resp.get('sampled_dac_out', 0)}")


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
        # Added PID_Error and PID_DAC headers
        writer.writerow(["Timestamp", "Peak_Count", "PID_Error", "PID_DAC", "TS_1", "TS_2", "TS_3", "TS_4", "TS_5", "TS_6", "TS_7", "TS_8"])
    
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
    fig_track, axes_track_matrix = plt.subplots(3, 3, figsize=(15, 10))
    fig_track.canvas.manager.set_window_title("Filtered Timestamp & Peak Count Tracking (Max 3 Hours)")
    fig_track.subplots_adjust(hspace=0.6, wspace=0.4, bottom=0.1)
    
    axes_track = axes_track_matrix.flatten()
    lines_track = []
    
    for i in range(8):
        ax = axes_track[i]
        line, = ax.plot([], [], lw=2, color=f"C{i}")
        
        ax.set_title(f"TS {i+1} Variation", fontsize=10)
        ax.set_ylabel("Cycle Count", fontsize=8)
        ax.grid(True, linestyle=':', alpha=0.6)
        
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
        ax.tick_params(axis='x', rotation=45, labelsize=8)
        
        lines_track.append(line)

    ax_peaks = axes_track[8]
    line_peaks, = ax_peaks.plot([], [], lw=2, color='magenta')
    ax_peaks.set_title("Detected Peak Count", fontsize=10, fontweight='bold')
    ax_peaks.set_ylabel("Count", fontsize=8)
    ax_peaks.grid(True, linestyle=':', alpha=0.6)
    ax_peaks.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    ax_peaks.tick_params(axis='x', rotation=45, labelsize=8)

    # --- Figure 3: PID Error & Output Tracking ---
    fig_pid, (ax_error, ax_dac) = plt.subplots(2, 1, figsize=(10, 8))
    fig_pid.canvas.manager.set_window_title("Live PID Status")
    fig_pid.subplots_adjust(hspace=0.4)

    # Error Plot setup
    line_error, = ax_error.plot([], [], lw=2, color='red')
    ax_error.set_title("PID Error (Target - Current TS)", fontsize=10, fontweight='bold')
    ax_error.set_ylabel("Error (Clock Cycles)", fontsize=9)
    ax_error.grid(True, linestyle=':', alpha=0.6)
    ax_error.axhline(y=0, color='black', linestyle='-', linewidth=1, alpha=0.5) # Zero line
    ax_error.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    ax_error.tick_params(axis='x', rotation=45, labelsize=8)

    # DAC Output Plot setup
    line_dac, = ax_dac.plot([], [], lw=2, color='green')
    ax_dac.set_title("PID Output (DAC Value)", fontsize=10, fontweight='bold')
    ax_dac.set_ylabel("DAC Value (0-8191)", fontsize=9)
    ax_dac.grid(True, linestyle=':', alpha=0.6)
    ax_dac.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    ax_dac.tick_params(axis='x', rotation=45, labelsize=8)

    # Data structures for rolling history
    MAX_HISTORY_SECONDS = 3 * 3600 # 3 hours
    x_data = []
    y_data = [[] for _ in range(8)]
    y_data_peaks = [] 
    y_data_error = []
    y_data_dac = []

    def fetch_data():
        # Trigger Peak Detector and PID sampler at roughly the same time
        requests.post(f"{BASE_URL}/peak_detector", json={"trigger": 1})
        requests.post(f"{BASE_URL}/pid_ctrl", json={"trigger_req": 1})
        
        timeout = 2.0 
        start_time = time.time()
        
        peak_count = 0
        timestamps = [0] * 8
        pid_error = 0
        pid_dac = 0

        # Wait for peak detector data
        while time.time() - start_time < timeout:
            try:
                resp = requests.get(f"{BASE_URL}/peak_detector").json()
                if resp.get("data_ready"):
                    peak_count = resp.get("peak_count", 0)
                    timestamps = [resp.get(f"ts_{i}", 0) for i in range(1, 9)]
                    break
            except requests.exceptions.RequestException:
                pass 
            time.sleep(0.01) 
        
        # Fetch latched PID values
        try:
            pid_resp = requests.get(f"{BASE_URL}/pid_ctrl").json()
            pid_error = pid_resp.get("sampled_error", 0)
            pid_dac = pid_resp.get("sampled_dac_out", 0)
        except requests.exceptions.RequestException:
            pass

        return peak_count, timestamps, pid_error, pid_dac

    def update_plot(frame):
        peak_count, timestamps, pid_error, pid_dac = fetch_data()
        y_vals = list(range(1, 9))
        current_time = datetime.now()
        
        # Update CSV
        with open(csv_filename, mode='a', newline='') as file:
            writer = csv.writer(file)
            writer.writerow([current_time.isoformat(), peak_count, pid_error, pid_dac] + timestamps)

        # --- Update Main Plot ---
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
        
        # --- Update Data Queues ---
        x_data.append(current_time)
        y_data_peaks.append(peak_count)
        y_data_error.append(pid_error)
        y_data_dac.append(pid_dac)
        
        for i in range(8):
            y_data[i].append(timestamps[i])

        # Prune old data
        cutoff_time = current_time - timedelta(seconds=MAX_HISTORY_SECONDS)
        while len(x_data) > 0 and x_data[0] < cutoff_time:
            x_data.pop(0)
            y_data_peaks.pop(0)
            y_data_error.pop(0)
            y_data_dac.pop(0)
            for i in range(8):
                y_data[i].pop(0)

        # --- Update Figure 2 (Tracking Arrays) ---
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
                if padding == 0: padding = max_y * 0.05 if max_y != 0 else 100
                axes_track[i].set_ylim(max(0, min_y - padding), max_y + padding)

        line_peaks.set_data(x_data, y_data_peaks)
        if len(x_data) > 1:
            ax_peaks.set_xlim(x_data[0], x_data[-1])
        else:
            ax_peaks.set_xlim(x_data[0], x_data[0] + timedelta(seconds=1))
            
        if len(y_data_peaks) > 0:
            ax_peaks.set_ylim(max(0, min(y_data_peaks) - 1), max(y_data_peaks) + 1)

        # --- Update Figure 3 (PID) ---
        line_error.set_data(x_data, y_data_error)
        line_dac.set_data(x_data, y_data_dac)

        if len(x_data) > 1:
            ax_error.set_xlim(x_data[0], x_data[-1])
            ax_dac.set_xlim(x_data[0], x_data[-1])
        else:
            ax_error.set_xlim(x_data[0], x_data[0] + timedelta(seconds=1))
            ax_dac.set_xlim(x_data[0], x_data[0] + timedelta(seconds=1))

        if len(y_data_error) > 0:
            min_err, max_err = min(y_data_error), max(y_data_error)
            pad_err = (max_err - min_err) * 0.1
            if pad_err == 0: pad_err = 10
            ax_error.set_ylim(min_err - pad_err, max_err + pad_err)

        if len(y_data_dac) > 0:
            min_dac, max_dac = min(y_data_dac), max(y_data_dac)
            pad_dac = (max_dac - min_dac) * 0.1
            if pad_dac == 0: pad_dac = 100
            ax_dac.set_ylim(max(0, min_dac - pad_dac), min(8191, max_dac + pad_dac))

        # Redraw background figures
        fig_track.canvas.draw_idle()
        fig_pid.canvas.draw_idle()

        return [main_scatter, main_vlines] + main_texts

    print("\n8. Starting live plots... Close the pop-up windows to end the script.")
    
    ani = animation.FuncAnimation(fig_main, update_plot, interval=100, blit=False, cache_frame_data=False)
    
    plt.show()

def live_tuning_cli():
    """Background thread to accept tuning commands while plots run."""
    print("\n" + "="*50)
    print(" LIVE TUNING CLI ACTIVE")
    print(" Commands: 'kp <val>', 'ki <val>', 'kd <val>', 'target <val>'")
    print(" Example : 'kp 15' (Type 'help' for more, 'q' to hide)")
    print("="*50 + "\n")
    
    while True:
        try:
            # Block and wait for user input
            raw_input = input("PID_Tuner>> ").strip().lower()
            if not raw_input: 
                continue
                
            cmd_parts = raw_input.split()
            cmd = cmd_parts[0]
            
            if cmd in ['q', 'quit', 'exit']:
                print(" -> CLI minimized. Close matplotlib windows to fully exit.")
                break
            elif cmd == 'help':
                print(" -> Valid parameters: kp, ki, kd, target")
                continue
                
            if len(cmd_parts) != 2:
                print(" -> Invalid format. Use: <parameter> <value>")
                continue
                
            # Parse the value
            val = int(cmd_parts[1])
            
            # Route to the correct hardware abstraction
            if cmd == 'kp':
                write_pid_ctrl(kp=val)
                print(f" -> Success: Kp updated to {val}")
            elif cmd == 'ki':
                write_pid_ctrl(ki=val)
                print(f" -> Success: Ki updated to {val}")
            elif cmd == 'kd':
                write_pid_ctrl(kd=val)
                print(f" -> Success: Kd updated to {val}")
            elif cmd == 'target':
                write_pid_ctrl(target_ts=val)
                print(f" -> Success: Target TS updated to {val} cycles")
            else:
                print(f" -> Unknown parameter '{cmd}'")
                
        except ValueError:
            print(" -> Invalid value. Please enter a valid integer.")
        except Exception as e:
            print(f" -> Network/Hardware Error: {e}")

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

if __name__ == "__main__":
    try:     
        configure_system()
        ramp_on()
        pid_idle()
        fetch_results() 
        pid_on()
        
        # --- START LIVE TUNING THREAD ---
        cli_thread = threading.Thread(target=live_tuning_cli, daemon=True)
        cli_thread.start()
        
        # Start blocking animation
        live_plot() 
        
        pid_idle()
        soft_disarm()

    except requests.exceptions.ConnectionError:
        print("Error: Could not connect to the Red Pitaya. Is the server running and the IP correct?")