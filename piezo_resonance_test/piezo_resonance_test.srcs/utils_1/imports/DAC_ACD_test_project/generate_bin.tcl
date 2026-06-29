# generate_bin.tcl

set bit_file "DAC_ADC_test_top.bit"
set bif_file "DAC_ADC_test_top.bif"
set bin_file "DAC_ADC_test_top.bit.bin"

puts "--- Starting automatic .bit to .bit.bin conversion ---"

# 1. Create the .bif file using native Tcl
set f [open $bif_file w]
puts $f "all:{ $bit_file }"
close $f

# 2. Run bootgen using exec
exec bootgen -image $bif_file -arch zynq -process_bitstream bin -o $bin_file -w

puts "--- Successfully generated $bin_file ---"