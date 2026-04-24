`timescale 1ns/1ps
module chr_rom (
    input  wire        clk,
    input  wire [12:0] addr,
    output reg  [7:0]  dout
);
    reg [7:0] rom [0:8191];
    initial $readmemh("chr_rom.hex", rom);
    
    always @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule