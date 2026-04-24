`timescale 1ns/1ps
module prg_rom (
    input  wire        clk,
    input  wire [14:0] addr,
    output reg  [7:0]  dout
);
    reg [7:0] rom [0:32767];
    initial $readmemh("prg_rom.hex", rom);
    
    always @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule