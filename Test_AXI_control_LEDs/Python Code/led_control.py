from flask import Flask, render_template_string
import subprocess

app = Flask(__name__)

# The memory address for System Bus Region 6
REG_ADDR = "0x40600000"

# HTML Template with buttons
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Red Pitaya LED Control</title>
    <style>
        body { font-family: sans-serif; text-align: center; padding-top: 50px; background: #f0f0f0; }
        .button { 
            padding: 20px 40px; font-size: 20px; margin: 10px; cursor: pointer;
            border: none; border-radius: 5px; color: white;
        }
        .on { background-color: #4CAF50; }
        .off { background-color: #f44336; }
    </style>
</head>
<body>
    <h1>Red Pitaya LAN LED Control</h1>
    <p>Target Address: {{ addr }}</p>
    <form action="/led/255" method="POST"><button class="button on">ALL ON</button></form>
    <form action="/led/0" method="POST"><button class="button off">ALL OFF</button></form>
    <br>
    <form action="/led/1" method="POST"><button class="button on" style="padding:10px">LED 0</button></form>
    <form action="/led/128" method="POST"><button class="button on" style="padding:10px">LED 7</button></form>
</body>
</html>
"""

def set_leds(value):# Executes the 'monitor' command using its absolute path
    # on the Red Pitaya OS[cite: 1]
    cmd = ["/opt/redpitaya/bin/monitor", REG_ADDR, hex(value)]
    
    # Adding check=True ensures Python throws an error if the command itself fails
    subprocess.run(cmd, check=True)

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, addr=REG_ADDR)

@app.route('/led/<int:value>', methods=['POST'])
def control_led(value):
    set_leds(value)
    return render_template_string(HTML_TEMPLATE, addr=REG_ADDR)

if __name__ == '__main__':
    # Runs the server on port 5000, accessible by any device on the LAN
    app.run(host='0.0.0.0', port=5000)