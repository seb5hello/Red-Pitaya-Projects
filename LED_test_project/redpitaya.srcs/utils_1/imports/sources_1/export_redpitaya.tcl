# 1. Define Names and Paths
set top_name [get_property top [current_fileset]]
set impl_dir [get_property DIRECTORY [current_run]]
set export_dir "./fpga_export_files"

# 2. Create the new directory if it doesn't exist
if {![file exists $export_dir]} {
    file mkdir $export_dir
    puts "Created directory: $export_dir"
}

# 3. Generate the byte-swapped .bit.bin file
# This is the headerless format required to avoid I/O errors [cite: 30, 32]
set bit_file "$impl_dir/${top_name}.bit"
set bin_output "$export_dir/${top_name}.bit.bin"

write_cfgmem -force -format bin -interface smapx32 -disablebitswap -loadbit "up 0x0 $bit_file" $bin_output
puts "Generated formatted bitstream: $bin_output"

# 4. Copy the .dtbo file
# Note: This assumes your .dtbo is located in the implementation or project folder
set dtbo_file "$impl_dir/${top_name}.dtbo"

if {[file exists $dtbo_file]} {
    file copy -force $dtbo_file "$export_dir/${top_name}.dtbo"
    puts "Copied Device Tree Overlay: $export_dir/${top_name}.dtbo"
} else {
    puts "WARNING: ${top_name}.dtbo not found in $impl_dir. Ensure your DTBO generation script ran."
}