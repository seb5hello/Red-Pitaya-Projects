# Red Pitaya Development Environment & Resource Index

This document serves as a structured reference for the Red Pitaya development workflow, specifically tailored for the STEMlab 125-14 LN platform.

## 1. System Specifications & Environment
* **Hardware Platform:** Red Pitaya STEMlab 125-14 LN v1.1
* **Operating System:** Red Pitaya OS 2.07-48
* **Target SoC:** Xilinx Zynq-7000 (XC7Z010-1CLG400C)
* **Host Development Path:** `C:\Users\Gaming\Documents\fpga_projects\RedPitaya`
* **Primary FPGA Toolset:** Vivado 2020.1 (Windows-based)
* **Software Development Toolset:** Xilinx SDK 2019.1 (Linux-based)

## 2. Core FPGA Development Workflow
The following resources cover the end-to-end process from project initialization to hardware deployment.

* **Initialization:** [Creating an FPGA project in Vivado](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/getting_started/project_creation.html)
* **Logic Modification:** [Modifying the FPGA project](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/getting_started/modify_project.html)
* **Deployment:** [FPGA Reprogramming Guide](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/getting_started/reprogram_fpga.html)
* **Version Control/Iterating:** [Creating a copy for a new project](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/getting_started/copy_project.html)

## 3. Advanced FPGA & Hardware Interfacing
Resources for low-level system configuration and custom hardware integration.

* **Automation Utilities:** [Tutorial Helper: configure_fpga.sh](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/fpga_tutorials/configure_fpga.html)
* **Hardware Mapping:** [Signal Mapping Reference](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/advanced/signal_mapping.html)
* **Dynamic Loading:** [Advanced FPGA Loading](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/advanced/fpga_advanced_loading.html)
* **Kernel Integration:** [Device Tree Configuration](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/advanced/device_tree.html)
* **Boot Persistence:** [FPGA Boot Loading Configuration](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/advanced/fpga_boot_loading.html)

## 4. Repository & Register Map References
Technical documentation for the Red Pitaya open-source IP cores and register sets.

* **Source Code:** [Official RedPitaya-FPGA Repository](https://github.com/RedPitaya/RedPitaya-FPGA.git)
* **Project Overview:** [FPGA Projects Documentation](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/projects/top.html#fpga-projects)
* **Base Architecture:** [Base FPGA Project Reference](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/fpga_tutorials/base_project/top.html)
* **Release Specifics (v0.94):** [FPGA project v0.94 Documentation](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/projects/v0_94.html#fpga-project-v0-94)
* **Memory Mapping:**
    * [Register Map: v0.94](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/regset/2.07-48/v0.94.html)
    * [Register Map: stream_app](https://redpitaya.readthedocs.io/en/latest/developerGuide/fpga/regset/2.07-48/stream_app.html)

## 5. Software Development & Web APIs
Guidance on developing applications that interface with the FPGA logic.

* **General Software Development:** [Application Development Overview](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/app_development/app_development.html)
* **System Architecture:** [Software System Overview](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/app_development/webapp/sysOver.html)
* **Programming Interfaces:** [C++ and Python API Guide](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/app_development/C_and_Python_API.html)
* **Web Integration:**
    * [Creating Web Applications](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/app_development/webapp/webApps.html)
    * [Step-by-Step: First Web App](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/app_development/webapp/firstApp.html)

## 6. Maintenance & Compatibility
* [OS Version Compatibility Matrix](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/troubleshooting/os_compatibility.html)
* [Known Software Issues & Bug Tracking](https://redpitaya.readthedocs.io/en/latest/developerGuide/software/troubleshooting/known_issues/known_sw_issues.html)
