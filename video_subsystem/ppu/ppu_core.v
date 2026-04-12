/* * File: ppu_core.v
 * Description: Top-level file for the NES Picture Processing Unit (Ricoh 2C02) 
 * internal memory structures and CPU-facing register interfaces.
 */

// =============================================================================
// Top-Level PPU Wrapper
// =============================================================================
module ppu_core (
    input  wire        clk,           // PPU Clock (5.369 MHz)
    input  wire        reset,         // Asynchronous reset

    // CPU Interface (8-bit data bus, 3-bit address bus for registers 0-7)
    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    output reg  [7:0]  cpu_data_out,
    input  wire        cpu_read_n,    // Active low read
    input  wire        cpu_write_n,   // Active low write

    // External Cartridge Interface (CHR-ROM Bus)
    output wire [13:0] chr_addr,
    input  wire [7:0]  chr_data_in,
    output wire        chr_read_n
);

    // Internal PPU Register States
    wire [7:0] ppu_ctrl;
    wire [7:0] ppu_mask;
    wire [7:0] ppu_status;
    wire [7:0] oam_addr;
    wire [14:0] vram_addr;        // The 15-bit internal PPU address pointer
    
    // Internal Memory Buses
    wire [7:0] vram_data_out;
    wire [7:0] palette_data_out;
    wire [7:0] oam_data_out;

    // CPU Register Interface Instance
    ppu_registers regs_inst (
        .clk            (clk),
        .reset          (reset),
        .cpu_addr       (cpu_addr),
        .cpu_data_in    (cpu_data_in),
        .cpu_read_n     (cpu_read_n),
        .cpu_write_n    (cpu_write_n),
        .cpu_data_out   (cpu_data_out),
        
        // PPU internal state outputs
        .ctrl_out       (ppu_ctrl),
        .mask_out       (ppu_mask),
        .vram_addr_out  (vram_addr),
        .oam_addr_out   (oam_addr)
    );

    // Nametable RAM (2KB VRAM)
    vram_2k nametable_ram (
        .clk    (clk),
        .addr   (vram_addr[10:0]), // VRAM is mirrored, only requires 11 bits
        .din    (cpu_data_in),
        .we     ((~cpu_write_n) && (cpu_addr == 3'd7) && (vram_addr >= 14'h2000) && (vram_addr < 14'h3F00)),
        .dout   (vram_data_out)
    );

    // Palette RAM (32 Bytes)
    palette_ram pal_ram (
        .clk    (clk),
        .addr   (vram_addr[4:0]),
        .din    (cpu_data_in),
        .we     ((~cpu_write_n) && (cpu_addr == 3'd7) && (vram_addr >= 14'h3F00)),
        .dout   (palette_data_out)
    );

    // Object Attribute Memory (256 Bytes for Sprites)
    oam_ram sprite_ram (
        .clk    (clk),
        .addr   (oam_addr),
        .din    (cpu_data_in),
        .we     ((~cpu_write_n) && (cpu_addr == 3'd4)), // Writes to 0x2004
        .dout   (oam_data_out)
    );

    // Route external CHR-ROM reads
    assign chr_addr = vram_addr[13:0];
    assign chr_read_n = ~(vram_addr < 14'h2000);

endmodule


// =============================================================================
// CPU to PPU Register Interface
// =============================================================================
module ppu_registers (
    input  wire        clk,
    input  wire        reset,
    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    input  wire        cpu_read_n,
    input  wire        cpu_write_n,
    
    output reg  [7:0]  cpu_data_out,
    
    output reg  [7:0]  ctrl_out,
    output reg  [7:0]  mask_out,
    output reg  [14:0] vram_addr_out,
    output reg  [7:0]  oam_addr_out
);

    // The 'W' toggle: 0 = first write, 1 = second write
    reg w_toggle; 
    
    // Internal registers
    reg [7:0] status_reg;
    reg [7:0] scroll_x;
    reg [7:0] scroll_y;
    reg [7:0] read_buffer; // PPUDATA read buffer quirk

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            w_toggle      <= 1'b0;
            ctrl_out      <= 8'h00;
            mask_out      <= 8'h00;
            status_reg    <= 8'h00;
            oam_addr_out  <= 8'h00;
            vram_addr_out <= 15'h0000;
            read_buffer   <= 8'h00;
        end else begin
            // CPU Write Logic
            if (!cpu_write_n) begin
                case (cpu_addr)
                    3'd0: ctrl_out <= cpu_data_in;        // 0x2000: PPUCTRL
                    3'd1: mask_out <= cpu_data_in;        // 0x2001: PPUMASK
                    3'd3: oam_addr_out <= cpu_data_in;    // 0x2003: OAMADDR
                    3'd4: oam_addr_out <= oam_addr_out + 1'b1; // 0x2004: OAMDATA write increments addr
                    
                    3'd5: begin                           // 0x2005: PPUSCROLL
                        if (!w_toggle) begin
                            scroll_x <= cpu_data_in;
                            w_toggle <= 1'b1;
                        end else begin
                            scroll_y <= cpu_data_in;
                            w_toggle <= 1'b0;
                        end
                    end
                    
                    3'd6: begin                           // 0x2006: PPUADDR
                        if (!w_toggle) begin
                            vram_addr_out[13:8] <= cpu_data_in[5:0]; // High byte (max 14 bits)
                            w_toggle <= 1'b1;
                        end else begin
                            vram_addr_out[7:0] <= cpu_data_in;       // Low byte
                            w_toggle <= 1'b0;
                        end
                    end
                    
                    3'd7: begin                           // 0x2007: PPUDATA
                        // Increment vram_addr by 1 or 32 based on PPUCTRL bit 2
                        vram_addr_out <= vram_addr_out + (ctrl_out[2] ? 15'd32 : 15'd1);
                    end
                endcase
            end

            // CPU Read Logic
            if (!cpu_read_n) begin
                case (cpu_addr)
                    3'd2: begin                           // 0x2002: PPUSTATUS
                        cpu_data_out <= status_reg;
                        w_toggle <= 1'b0;                 // Reading status clears the W toggle
                        status_reg[7] <= 1'b0;            // Reading status clears the VBlank flag
                    end
                    // Add PPUDATA read logic later when memory bus multiplexer is attached
                    default: cpu_data_out <= 8'h00;
                endcase
            end
        end
    end
endmodule


// =============================================================================
// Internal PPU Block RAM Definitions
// =============================================================================

// 2KB Video RAM (Nametables)
module vram_2k (
    input  wire        clk,
    input  wire [10:0] addr,
    input  wire [7:0]  din,
    input  wire        we,
    output reg  [7:0]  dout
);
    reg [7:0] ram [0:2047];
    always @(posedge clk) begin
        if (we) ram[addr] <= din;
        dout <= ram[addr];
    end
endmodule

// 32-Byte Palette RAM
module palette_ram (
    input  wire        clk,
    input  wire [4:0]  addr,
    input  wire [7:0]  din,
    input  wire        we,
    output reg  [7:0]  dout
);
    reg [7:0] ram [0:31];
    always @(posedge clk) begin
        if (we) ram[addr] <= din;
        dout <= ram[addr];
    end
endmodule

// 256-Byte Object Attribute Memory
module oam_ram (
    input  wire        clk,
    input  wire [7:0]  addr,
    input  wire [7:0]  din,
    input  wire        we,
    output reg  [7:0]  dout
);
    reg [7:0] ram [0:255];
    always @(posedge clk) begin
        if (we) ram[addr] <= din;
        dout <= ram[addr];
    end
endmodule