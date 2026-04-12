`timescale 1ns/1ps
module MOS_6502_CPU_tb;

reg clk;
reg reset;

wire [15:0] address_bus;
wire        read_write_n;
wire [7:0]  data_bus;

// Instantiate CPU — no external memory needed anymore
MOS_6502_CPU uut (
    .clk         (clk),
    .reset       (reset),
    .data_bus    (data_bus),
    .address_bus (address_bus),
    .read_write_n(read_write_n)
);

// Clock
initial clk = 0;
always #5 clk = ~clk;

// Stimulus
initial begin
    reset = 1;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    @(negedge clk);
    reset = 0;
repeat(100) @(posedge clk);
    $stop;
end

// Monitor
initial begin
    $monitor("Time=%0t | reset=%b | state=%0d | PC=%h | inst_reg=%h | accum=%h | sreg=%b | RW=%b | addr=%h",
             $time, reset, uut.fsm_inst.state, uut.fsm_inst.PC,
             uut.fsm_inst.inst_reg, uut.fsm_inst.accum,
             uut.fsm_inst.s_reg, read_write_n, address_bus);
end

endmodule