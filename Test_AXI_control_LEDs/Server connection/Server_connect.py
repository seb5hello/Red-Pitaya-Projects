import requests
import time

# Replace with your Red Pitaya's actual IP address
RP_IP = "192.168.1.100" 
PORT = "8080"

def toggle_led(state):
    """
    Sends a command to the Red Pitaya server.
    state: 1 for ON, 0 for OFF
    """
    url = f"http://{RP_IP}:{PORT}/control/{state}"
    try:
        response = requests.get(url)
        print(f"Status: {response.status_code} | Message: {response.text}")
    except Exception as e:
        print(f"Connection failed: {e}")

# Example: Blink the LED from your PC 5 times
for i in range(5):
    toggle_led(1)  # Turn LED/Logic ON
    time.sleep(0.5)
    toggle_led(0)  # Turn LED/Logic OFF
    time.sleep(0.5)