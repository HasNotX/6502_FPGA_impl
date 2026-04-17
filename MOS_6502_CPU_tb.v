`timescale 1ns/1ps

module MOS_6502_CPU_tb;

reg clk;
reg reset;

wire [15:0] address_bus;
wire        read_write_n;
wire [7:0]  data_bus;

// Instantiate CPU
MOS_6502_CPU uut (
    .clk          (clk),
    .reset        (reset),
    .data_bus     (data_bus),
    .address_bus  (address_bus),
    .read_write_n (read_write_n)
);

// Clock: 10ns period
initial clk = 0;
always #5 clk = ~clk;

initial begin
    $display("--- Starting 6502 Simulation ---");
    reset = 1;
    repeat(5) @(posedge clk);
    @(negedge clk);
    reset = 0;
    
    // 5000ns is enough to see the reset and the first few instructions
    #5000; 
    $display("--- Simulation Finished ---");
    $stop;
end

// Monitor internal signals using the corrected paths
initial begin
    $monitor("Time=%0t | PC=%h | State=%0d | Instr=%h | Accum=%h | X=%h | Y=%h | Flags=%b | Addr=%h | Data=%h",
             $time, 
             uut.fsm_inst.PC, 
             uut.fsm_inst.state, 
             uut.fsm_inst.inst_reg, 
             uut.fsm_inst.accum, 
             uut.fsm_inst.X, 
             uut.fsm_inst.Y, 
             uut.fsm_inst.s_reg, 
             address_bus, 
             data_bus);
end

endmodule