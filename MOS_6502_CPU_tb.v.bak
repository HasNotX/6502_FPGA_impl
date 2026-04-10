`timescale 1ns/1ps

module MOS_6502_CPU_tb;

// Clock and reset
reg clk;
reg reset;

// CPU interface signals
wire [15:0] address_bus;
wire        read_write_n;
reg  [7:0]  mem_data_out;

// Tristate data bus
// When CPU reads (read_write_n=1), memory drives the bus
// When CPU writes (read_write_n=0), CPU drives the bus
wire [7:0] data_bus;
assign data_bus = (read_write_n) ? mem_data_out : 8'hzz;

// Instantiate the CPU
MOS_6502_CPU uut (
    .clk         (clk),
    .reset       (reset),
    .data_bus    (data_bus),
    .address_bus (address_bus),
    .read_write_n(read_write_n)
);

// Clock generation: 10ns period = 100MHz
initial clk = 0;
always #5 clk = ~clk;

// Simple memory model
// Returns NOP (0xEA) for every address so the CPU loops cleanly
always @(*) begin
    mem_data_out = 8'hEA; // NOP opcode — CPU fetches, does nothing, repeats
end

// Stimulus
initial begin
    // Apply reset for 4 clock cycles
    reset = 1;
    @(posedge clk); // cycle 1
    @(posedge clk); // cycle 2
    @(posedge clk); // cycle 3
    @(posedge clk); // cycle 4
    
    // Release reset
    @(negedge clk); // release on falling edge to avoid setup violations
    reset = 0;
    
    // Let the CPU run for 40 cycles and observe
    repeat(40) @(posedge clk);
    
    $stop; // pause simulation — lets you inspect waveforms
end

// Monitor: prints to console every clock edge so you can follow along
initial begin
    $monitor("Time=%0t | reset=%b | state=%0d | PC=%h | inst_reg=%h | RW=%b | addr=%h",
             $time, reset, uut.state, uut.PC, uut.inst_reg, read_write_n, address_bus);
end

endmodule