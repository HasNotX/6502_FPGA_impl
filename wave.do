onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix decimal /MOS_6502_CPU_tb/clk
add wave -noupdate /MOS_6502_CPU_tb/reset
add wave -noupdate -radix unsigned -childformat {{{/MOS_6502_CPU_tb/address_bus[15]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[14]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[13]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[12]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[11]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[10]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[9]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[8]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[7]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[6]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[5]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[4]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[3]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[2]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[1]} -radix unsigned} {{/MOS_6502_CPU_tb/address_bus[0]} -radix unsigned}} -subitemconfig {{/MOS_6502_CPU_tb/address_bus[15]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[14]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[13]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[12]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[11]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[10]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[9]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[8]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[7]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[6]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[5]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[4]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[3]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[2]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[1]} {-radix unsigned} {/MOS_6502_CPU_tb/address_bus[0]} {-radix unsigned}} /MOS_6502_CPU_tb/address_bus
add wave -noupdate /MOS_6502_CPU_tb/read_write_n
add wave -noupdate -radix hexadecimal /MOS_6502_CPU_tb/mem_data_out
add wave -noupdate -radix hexadecimal /MOS_6502_CPU_tb/data_bus
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {198321 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 236
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {199262 ps} {199686 ps}
