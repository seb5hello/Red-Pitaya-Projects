# Red Pitaya FPGA Development Setup & Uploading Process Documentation

This document outlines the workflow for converting, transferring, and loading a custom FPGA design onto a Red Pitaya board.

## 1. Prerequisites
* **Board:** Red Pitaya STEMlab 125-14 LN v1.1.
* **Operating System:** Red Pitaya OS 2.07-48.
* **SoC:** Xilinx Zynq-7000 (XC7Z010-1CLG400C).
* **Software:** Vivado 2020.1.

## 3. Creating of Red Pitaya Project

In order to create your first Red Pitaya project you need to first clone the github repository and then follow the instructions to automate the project generation.

1. Find out the specific board settings and locations of the Vivado `settings64.bat` and Red Pitaya cloned repository `RedPitaya-FPGA`. Also you should know which type of project you want to generate, in this case we are generating the basic `0.94v` project.

2. Create a file called `RedPitaya_Project_Builder.bat` that autamatically executes the correct tcl file through the vivado console to generates the appropite file.
```RedPitaya_Project_Builder.bat
@echo off
echo Setting up Vivado 2020.1 Environment...
call C:\...\Xilinx\Vivado\2020.1\settings64.bat

echo Navigating to Red Pitaya Project Root...
cd /d C:\...\RedPitaya-FPGA

echo Running TCL Script...
vivado -mode batch -source red_pitaya_vivado_project_Z10.tcl -tclargs v0.94

echo Project creation complete!
pause
```

3. Save the file and double click on it to run it. When it finishes it will create in our case a folder called `project` in directory `prj\0.94v`. 

## 3. Bitstream Conversion
The Red Pitaya FPGA Manager requires a binary bitstream format (`.bit.bin`). This conversion is handled by the `bootgen` utility using a Boot Image File (`.bif`).

### The Automation Script: `generate_bin.tcl`
To automate the creation of the binary file, use the following Tcl script:

```generate_bin.tcl
# generate_bin.tcl

set bit_file "red_pitaya_top.bit"
set bif_file "red_pitaya_top.bif"
set bin_file "red_pitaya_top.bit.bin"

puts "--- Starting automatic .bit to .bit.bin conversion ---"

# 1. Create the .bif file using native Tcl
set f [open $bif_file w]
puts $f "all:{ $bit_file }"
close $f

# 2. Run bootgen using exec
exec bootgen -image $bif_file -arch zynq -process_bitstream bin -o $bin_file -w

puts "--- Successfully generated $bin_file ---"
```

## 4. Automation Setup
To run this script automatically every time you click Generate Bitstream in Vivado:

1. Open Settings > Project Settings > Bitstream.  

2. In the tcl.post field, browse and select your generate_bin.tcl file.

3. Apply and click OK.

4. Apply and click OK.

## 5. Transfer and Load
Once the .bit.bin is generated in your project folder (e.g., ...\impl_1\), follow these steps to run it on the board:

Transfer via SCP
```Bash
scp red_pitaya_top.bit.bin root@<RP_IP_ADDRESS>:/root/
```

```Bash
ssh root@<RP_IP_ADDRESS>
cd /root/
fpgautil -b red_pitaya_top.bit.bin
```