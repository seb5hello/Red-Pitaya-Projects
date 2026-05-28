# 1. Define Names and Paths
set top_name [get_property top [current_fileset]]
set impl_dir [get_property DIRECTORY [current_run]]
set export_dir "./fpga_export_files"

# 2. Create the new directory if it doesn't exist
if {![file exists $export_dir]} {
    file mkdir $export_dir
    puts "Created directory: $export_dir"
}

# 3. Find the generated .bit file
set bit_files [glob -nocomplain "$impl_dir/*.bit"]

if {[llength $bit_files] == 0} {
    puts "CRITICAL ERROR: No .bit file found in $impl_dir!"
} else {
    set bit_file [lindex $bit_files 0]
    set bif_file "$export_dir/${top_name}.bif"
    
    # Official Red Pitaya naming convention required by overlay.sh
    set bin_output "$export_dir/fpga.bit.bin"

    # Create the .bif (Boot Image Format) file required by bootgen
    set fp [open $bif_file w]
    puts $fp "all:{ $bit_file }"
    close $fp

    # Use bootgen to convert the bitstream (The official Red Pitaya method)
    # The 'exec' command allows Vivado to run system console commands
    exec bootgen -image $bif_file -arch zynq -process_bitstream bin -o $bin_output -w
    
    puts "Generated formatted bitstream: $bin_output"
}

# 4. Copy the .dtbo file (if it exists)
set dtbo_file "$impl_dir/${top_name}.dtbo"
if {[file exists $dtbo_file]} {
    # Renamed to match the overlay.sh requirement
    file copy -force $dtbo_file "$export_dir/fpga.dtbo"
    puts "Copied Device Tree Overlay: $export_dir/fpga.dtbo"
} else {
    puts "WARNING: ${top_name}.dtbo not found. (Not needed if only logic changed, no new peripherals)."
}