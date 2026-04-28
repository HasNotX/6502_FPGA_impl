module work_ram (
    input  wire        clk,
    input  wire [10:0] addr,
    input  wire [7:0]  din,
    input  wire        we,
    output reg  [7:0]  dout
);
    reg [7:0] ram [0:2047];
    
    // NEW: Force SRAM to zero to prevent the "Luigi Bug"
    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1) begin
            ram[i] = 8'h00;
        end
    end

    always @(posedge clk) begin
        if (we) ram[addr] <= din;
        dout <= ram[addr];
    end
endmodule