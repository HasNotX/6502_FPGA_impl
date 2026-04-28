module nes_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);

    wire clk_25mhz;
    wire pll_locked;
    
    vga_pll pll_inst (
        .refclk   (CLOCK_50),
        .rst      (1'b0),          
        .outclk_0 (clk_25mhz),
        .locked   (pll_locked)
    );

    // =========================================================================
    // SYSTEM RESET (Mapped strictly to SW[9])
    // =========================================================================
    wire sys_reset = (~pll_locked) | SW[9];

    wire raw_cpu_ce;
    wire ppu_ce;

    nes_clock_generator clk_gen (
        .clk_25mhz (clk_25mhz),
        .reset     (sys_reset),
        .cpu_ce    (raw_cpu_ce),
        .ppu_ce    (ppu_ce)
    );

    wire dma_active;
    wire effective_cpu_ce = raw_cpu_ce && !dma_active; 

    wire [15:0] cpu_address;
    wire [7:0]  cpu_data_out;
    wire [7:0]  cpu_data_in;
    wire        cpu_write_en;
    
    wire [15:0] dma_address;
    wire [7:0]  dma_data_out;
    wire        dma_read_en;
    wire        dma_write_en;
    
    wire [15:0] sys_address  = dma_active ? dma_address  : cpu_address;
    wire [7:0]  sys_data_out = dma_active ? dma_data_out : cpu_data_out;
    wire        sys_write_en = dma_active ? dma_write_en : cpu_write_en;
    wire        sys_read_en  = dma_active ? dma_read_en  : ~cpu_write_en;

    oam_dma dma_inst (
        .clk          (clk_25mhz),
        .reset        (sys_reset),
        .cpu_ce       (raw_cpu_ce), 
        .cpu_addr_in  (cpu_address),
        .cpu_data_in  (cpu_data_out),
        .cpu_write_en (cpu_write_en),
        .dma_active   (dma_active),
        .dma_addr_out (dma_address),
        .dma_data_out (dma_data_out),
        .dma_read_en  (dma_read_en),
        .dma_write_en (dma_write_en),
        .mem_data_in  (cpu_data_in) 
    );

    wire [15:0] cpu_pc;          
    wire [5:0]  cpu_state;    
    wire        ppu_nmi;

    MOS_6502_CPU cpu_inst (
        .clk_25mhz     (clk_25mhz),
        .cpu_ce        (effective_cpu_ce), 
        .reset         (sys_reset), 
        .address       (cpu_address),
        .data_in       (cpu_data_in),
        .nmi_in        (ppu_nmi),
        .data_out      (cpu_data_out),
        .write_en      (cpu_write_en),
        .current_pc    (cpu_pc),     
        .current_state (cpu_state)   
    );

    // =========================================================================
    // MEMORY MAP DECODING & ARBITRATION
    // =========================================================================
    wire work_ram_cs = (sys_address < 16'h2000);
    wire ppu_cs      = (sys_address >= 16'h2000 && sys_address <= 16'h3FFF);
    wire ctrl_cs     = (sys_address == 16'h4016);
    wire prg_rom_cs  = (sys_address >= 16'h8000);
    
    wire [7:0] work_ram_data_out; 
    wire [7:0] ppu_data_out;
    wire [7:0] prg_data_out;
    wire [7:0] ctrl_data_out;

    assign cpu_data_in = ppu_cs      ? ppu_data_out :
                         ctrl_cs     ? ctrl_data_out :
                         prg_rom_cs  ? prg_data_out :
                         work_ram_cs ? work_ram_data_out : 8'h00;

    wire work_ram_we = sys_write_en && work_ram_cs;

    work_ram cpu_ram (
        .clk  (clk_25mhz),
        .addr (sys_address[10:0]),
        .din  (sys_data_out),
        .we   (work_ram_we),
        .dout (work_ram_data_out)
    );

    prg_rom cart_prg (
        .clk  (clk_25mhz),
        .addr (sys_address[14:0]),
        .dout (prg_data_out)
    );

    wire [13:0] chr_addr;
    wire [7:0]  chr_data_out;
    wire        chr_read_n;
    
    chr_rom cart_chr (
        .clk  (clk_25mhz),
        .addr (chr_addr[12:0]),
        .dout (chr_data_out)
    );

    // Edge detectors for clean single-cycle memory operations
    reg cpu_we_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) cpu_we_last <= 1'b0;
        else           cpu_we_last <= sys_write_en;
    end
    wire cpu_write_pulse = sys_write_en && !cpu_we_last;
    wire ppu_write_n = ~(cpu_write_pulse && ppu_cs);

    wire cpu_read_active = sys_read_en && ppu_cs;
    reg cpu_re_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) cpu_re_last <= 1'b0;
        else           cpu_re_last <= cpu_read_active;
    end
    wire cpu_read_pulse = cpu_read_active && !cpu_re_last;
    wire ppu_read_n  = ~cpu_read_pulse;
    
    // =========================================================================
    // CONTROLLER LOGIC & I/O MAPPING
    // =========================================================================
    wire ctrl_write_active = sys_write_en && ctrl_cs;
    reg  ctrl_we_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) ctrl_we_last <= 1'b0;
        else           ctrl_we_last <= ctrl_write_active;
    end
    wire ctrl_write_pulse = ctrl_write_active && !ctrl_we_last;

    wire ctrl_read_active = sys_read_en && ctrl_cs;
    reg  ctrl_re_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) ctrl_re_last <= 1'b0;
        else           ctrl_re_last <= ctrl_read_active;
    end
    
    // PATCH: Trigger on the FALLING EDGE (!active && last) 
    // This forces the shift register to wait until the CPU has safely latched the data.
    wire ctrl_read_pulse = !ctrl_read_active && ctrl_re_last;

    // Convert active-low KEYs to active-high logic
    wire [3:0] keys_pressed = ~KEY[3:0]; 
    
    // =========================================================================
    // HYBRID CONTROLLER MAPPING
    // =========================================================================
    wire [7:0] nes_button_state;
    
    // Core Gameplay (Momentary Push Buttons)
    assign nes_button_state[0] = keys_pressed[0]; // A (Jump)
    assign nes_button_state[1] = keys_pressed[1]; // B (Run)
    assign nes_button_state[7] = keys_pressed[2]; // Right
    assign nes_button_state[6] = keys_pressed[3]; // Left
    
    // Utility and State Actions (Toggle Switches)
    assign nes_button_state[5] = SW[1];           // Down (Pipes)
    assign nes_button_state[4] = SW[2];           // Up (Vines)
    assign nes_button_state[3] = SW[4];           // Start (Pause)
    assign nes_button_state[2] = SW[3];           // Select (Title Screen)

    nes_controller joypad1 (
        .clk              (clk_25mhz),
        .reset            (sys_reset),
        .ctrl_write_pulse (ctrl_write_pulse),
        .ctrl_read_pulse  (ctrl_read_pulse),
        .cpu_data_in      (sys_data_out),
        .cpu_data_out     (ctrl_data_out),
        .button_state     (nes_button_state)
    );

    wire [7:0]  ppu_dbg_ctrl;
    wire [7:0]  ppu_dbg_mask;
    wire [14:0] dbg_vram_addr;
    wire [7:0]  dbg_palette_00;
    wire [7:0]  dbg_nt_latch;
    
    wire [8:0] trap_y;
    wire [8:0] trap_x;

    video_subsystem_top video_engine (
        .clk_25mhz      (clk_25mhz),
        .reset          (sys_reset),
        .ppu_ce         (ppu_ce),
        
        .cpu_addr       (sys_address[2:0]),
        .cpu_data_in    (sys_data_out),
        .cpu_data_out   (ppu_data_out),
        .cpu_read_n     (ppu_read_n),
        .cpu_write_n    (ppu_write_n),
        
        .chr_addr       (chr_addr),     
        .chr_data_in    (chr_data_out), 
        .chr_read_n     (chr_read_n),    
        
        .vga_r          (VGA_R),
        .vga_g          (VGA_G),
        .vga_b          (VGA_B),
        .vga_hsync      (VGA_HS),
        .vga_vsync      (VGA_VS),
        .vga_blank_n    (VGA_BLANK_N),
        .vga_sync_n     (VGA_SYNC_N),
        .vga_clk        (VGA_CLK),
        
        .dbg_ctrl       (ppu_dbg_ctrl),
        .dbg_mask       (ppu_dbg_mask),
        .dbg_vram_addr  (dbg_vram_addr),
        .dbg_palette_00 (dbg_palette_00),
        .dbg_nt_latch   (dbg_nt_latch),
        .nmi_out        (ppu_nmi),
        
        .trap_y_out     (trap_y),
        .trap_x_out     (trap_x)
    );

    assign LEDR[7:0] = ppu_dbg_mask;
    assign LEDR[8]   = dma_active; 
    assign LEDR[9]   = pll_locked;

    wire [11:0] trap_y_hex = {3'b000, trap_y};
    wire [11:0] trap_x_hex = {3'b000, trap_x};

    hex_decoder hex5_inst (.hex_in(trap_y_hex[11:8]), .segments(HEX5));
    hex_decoder hex4_inst (.hex_in(trap_y_hex[7:4]),  .segments(HEX4));
    hex_decoder hex3_inst (.hex_in(trap_y_hex[3:0]),  .segments(HEX3));
    
    hex_decoder hex2_inst (.hex_in(trap_x_hex[11:8]), .segments(HEX2));
    hex_decoder hex1_inst (.hex_in(trap_x_hex[7:4]),  .segments(HEX1));
    hex_decoder hex0_inst (.hex_in(trap_x_hex[3:0]),  .segments(HEX0));

endmodule

module button_debouncer (
    input  wire clk,
    input  wire button_in,
    output reg  button_out
);
    reg [19:0] counter; 
    reg sync_0;
    reg sync_1;

    always @(posedge clk) begin
        sync_0 <= button_in;
        sync_1 <= sync_0;

        if (sync_1 == button_out) begin
            counter <= 20'd0;
        end else begin
            counter <= counter + 1'b1;
            if (counter == 20'hFFFFF) begin
                button_out <= sync_1;
                counter <= 20'd0;
            end
        end
    end
endmodule