`timescale 1ns/1ps

module ram_sim (
    input            clk,
    input  [15:0]    addr,
    input  [7:0]     data_in,
    input            write_en,
    output [7:0]     data_out 
);

// ==========================================================
// SIMULATION BLOCK (Visible to ModelSim, hidden from Quartus)
// ==========================================================
// synthesis translate_off
reg [7:0] mem [0:65535];
assign data_out = mem[addr];

always @(posedge clk) begin
    if (write_en)
        mem[addr] <= data_in;
end

integer i;
initial begin
    for (i = 0; i < 65536; i = i + 1)
        mem[i] = 8'hEA;   // NOP sled default
    // !! REMOVE THESE TWO LINES !!
    // mem[16'hFFFC] = 8'h00;   // These overwrite Klaus's vector ($0400)
    // mem[16'hFFFD] = 8'h80;   // after $readmemh loads it
end
// synthesis translate_on


// ==========================================================
// SYNTHESIS DUMMY (Visible to Quartus, hidden from ModelSim)
// ==========================================================
// This prevents "Output has no driver" errors during synthesis.
// synthesis read_comments_as_HDL on
// assign data_out = 8'h00;
// synthesis read_comments_as_HDL off

endmodule