/*
 * File: ppu_core.v
 * Description: Top-Level PPU Wrapper. Phase 1 Implementation.
 * Integrates True Loopy Scrolling V and T registers directly into hardware.
 */
module ppu_core (
    input  wire        clk,           
    input  wire        reset,         
    input  wire        vblank_pulse,  
    input  wire        clear_vblank_pulse, 
    input  wire        sprite0_hit_pulse,  
    output wire        nmi_out,

    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    output wire [7:0]  cpu_data_out,  
    input  wire        cpu_read_n,    
    input  wire        cpu_write_n,   

    output wire [13:0] chr_addr,
    input  wire [7:0]  chr_data_in,
    output wire        chr_read_n,
    
    output wire [7:0]  dbg_ctrl,
    output wire [7:0]  dbg_mask,
    output wire [14:0] active_v_reg,
    output wire [2:0]  fine_x_scroll,

    input  wire [7:0]  nes_x,
    input  wire        nes_visible,
    input  wire [14:0] bg_mem_addr,
    output wire [7:0]  bg_mem_data,
    
    input  wire [4:0]  dac_palette_addr,
    output wire [7:0]  dac_palette_data,
    output wire [7:0]  dbg_palette_00
);

    wire [7:0] ppu_ctrl;
    wire [7:0] ppu_mask;
    wire [7:0] oam_addr;
    wire [14:0] vram_addr;        
    
    assign dbg_ctrl = ppu_ctrl;
    assign dbg_mask = ppu_mask;
    assign active_v_reg = vram_addr;
    
    wire [7:0] vram_data_out;
    wire [7:0] palette_data_out;
    wire [7:0] oam_data_out;

    wire [14:0] target_addr = nes_visible ? bg_mem_addr : vram_addr;
    wire target_we = nes_visible ? 1'b0 : ((~cpu_write_n) && (cpu_addr == 3'd7));
    
    wire [7:0] internal_mem_data_out = (target_addr >= 15'h3F00) ? palette_data_out :
                                       (target_addr >= 15'h2000) ? vram_data_out :
                                       chr_data_in;
                                       
    assign bg_mem_data = internal_mem_data_out;
    assign chr_addr = target_addr[13:0];
    assign chr_read_n = ~(target_addr < 15'h2000);

    // Phase Tracking 
    reg [7:0] last_nes_x;
    reg       phase;
    always @(posedge clk) begin
        last_nes_x <= nes_x;
        if (nes_x != last_nes_x) phase <= 1'b1;
        else                     phase <= ~phase;
    end
    wire nes_pixel_tick = phase;

    reg [8:0] internal_x;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            internal_x <= 9'd0;
        end else if (nes_pixel_tick) begin
            if (nes_visible) internal_x <= {1'b0, nes_x};
            else begin
                if (internal_x == 9'd340) internal_x <= 9'd0; 
                else                      internal_x <= internal_x + 9'd1;
            end
        end
    end

    ppu_registers regs_inst (
        .clk                (clk),
        .reset              (reset),
        .vblank_pulse       (vblank_pulse), 
        .clear_vblank_pulse (clear_vblank_pulse),
        .sprite0_hit_pulse  (sprite0_hit_pulse),
        
        .cpu_addr           (cpu_addr),
        .cpu_data_in        (cpu_data_in),
        .cpu_read_n         (cpu_read_n),
        .cpu_write_n        (cpu_write_n),
        .cpu_data_out       (cpu_data_out),
        .mem_data_in        (internal_mem_data_out), 
        
        .ctrl_out           (ppu_ctrl),
        .mask_out           (ppu_mask),
        .vram_addr_out      (vram_addr),
        .oam_addr_out       (oam_addr),
        .fine_x_out         (fine_x_scroll),
        .nmi_out            (nmi_out),
        
        .nes_pixel_tick     (nes_pixel_tick),
        .internal_x         (internal_x),
        .nes_visible        (nes_visible)
    );

    vram_2k nametable_ram (
        .clk    (clk),
        .addr   (target_addr[10:0]), 
        .din    (cpu_data_in),       
        .we     (target_we && (target_addr >= 15'h2000) && (target_addr < 15'h3F00)),
        .dout   (vram_data_out)
    );

    palette_ram pal_ram (
        .clk              (clk),
        .addr             (target_addr[4:0]),  
        .din              (cpu_data_in),
        .we               (target_we && (target_addr >= 15'h3F00)),
        .dout             (palette_data_out),
        .dac_addr         (dac_palette_addr), 
        .dac_dout         (dac_palette_data),  
        .dbg_palette_00   (dbg_palette_00)     
    );

    oam_ram sprite_ram (
        .clk    (clk),
        .addr   (oam_addr),
        .din    (cpu_data_in),
        .we     ((~cpu_write_n) && (cpu_addr == 3'd4)), 
        .dout   (oam_data_out)
    );

endmodule


// =============================================================================
// CPU to PPU Register Interface & True Loopy Scroll Logic
// =============================================================================
module ppu_registers (
    input  wire        clk,
    input  wire        reset,
    input  wire        vblank_pulse,  
    input  wire        clear_vblank_pulse,
    input  wire        sprite0_hit_pulse, 
    
    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    input  wire        cpu_read_n,
    input  wire        cpu_write_n,
    input  wire [7:0]  mem_data_in,   
    output reg  [7:0]  cpu_data_out,
    
    output reg  [7:0]  ctrl_out,
    output reg  [7:0]  mask_out,
    output wire [14:0] vram_addr_out,
    output reg  [7:0]  oam_addr_out,
    output wire [2:0]  fine_x_out,
    output wire        nmi_out,
    
    input  wire        nes_pixel_tick,
    input  wire [8:0]  internal_x,
    input  wire        nes_visible
);
    reg [7:0] status_reg;
    reg [7:0] read_buffer; 

    // True Ricoh 2C02 Loopy Registers
    reg [14:0] v; 
    reg [14:0] t; 
    reg [2:0]  fine_x; 
    reg        w; 

    assign nmi_out = status_reg[7] & ctrl_out[7];
    assign vram_addr_out = v; 
    assign fine_x_out = fine_x;
    
    wire rendering_enabled = mask_out[3] | mask_out[4];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            w             <= 1'b0;
            ctrl_out      <= 8'h00;
            mask_out      <= 8'h00;
            status_reg    <= 8'h00;
            oam_addr_out  <= 8'h00;
            read_buffer   <= 8'h00;
            v             <= 15'd0;
            t             <= 15'd0;
            fine_x        <= 3'd0;
        end else begin
            // --- Flags ---
            if (clear_vblank_pulse) begin
                status_reg[7] <= 1'b0;
                status_reg[6] <= 1'b0; 
            end
            if (vblank_pulse)      status_reg[7] <= 1'b1;
            if (sprite0_hit_pulse) status_reg[6] <= 1'b1;

            // --- CPU Writes ---
            if (!cpu_write_n) begin
                case (cpu_addr)
                    3'd0: begin 
                        ctrl_out <= cpu_data_in;
                        t[11:10] <= cpu_data_in[1:0]; 
                    end
                    3'd1: mask_out     <= cpu_data_in; 
                    3'd3: oam_addr_out <= cpu_data_in; 
                    3'd4: oam_addr_out <= oam_addr_out + 1'b1; 
                    3'd5: begin 
                        if (!w) begin
                            t[4:0] <= cpu_data_in[7:3];
                            fine_x <= cpu_data_in[2:0];
                            w      <= 1'b1;
                        end else begin
                            t[9:5]   <= cpu_data_in[7:3];
                            t[14:12] <= cpu_data_in[2:0];
                            w        <= 1'b0;
                        end
                    end
                    3'd6: begin 
                        if (!w) begin
                            t[13:8] <= cpu_data_in[5:0];
                            t[14]   <= 1'b0;
                            w       <= 1'b1;
                        end else begin
                            t[7:0] <= cpu_data_in;
                            v      <= {t[14:8], cpu_data_in}; 
                            w      <= 1'b0;
                        end
                    end
                    3'd7: begin 
                        v <= v + (ctrl_out[2] ? 15'd32 : 15'd1);
                    end
                endcase
            end

            // --- CPU Reads ---
            if (!cpu_read_n) begin
                case (cpu_addr)
                    3'd2: begin 
                        cpu_data_out  <= (vblank_pulse) ? {1'b1, status_reg[6:0]} : status_reg;
                        w             <= 1'b0;
                        status_reg[7] <= 1'b0;            
                    end
                    3'd7: begin 
                        if (v >= 15'h3F00) begin
                            cpu_data_out <= mem_data_in;
                            read_buffer  <= mem_data_in; 
                        end else begin
                            cpu_data_out <= read_buffer;
                            read_buffer  <= mem_data_in;
                        end
                        v <= v + (ctrl_out[2] ? 15'd32 : 15'd1);
                    end
                    default: cpu_data_out <= 8'h00;
                endcase
            end

            // --- Hardware Loopy Operations ---
            if (rendering_enabled && nes_pixel_tick) begin
                
                // 1. Coarse X Increment (Every 8 pixels)
                if ((nes_visible || (internal_x >= 320 && internal_x <= 336)) && (internal_x[2:0] == 3'd7)) begin
                    if (v[4:0] == 31) begin
                        v[4:0] <= 0;
                        v[10]  <= ~v[10]; 
                    end else begin
                        v[4:0] <= v[4:0] + 1;
                    end
                end

                // 2. Y Increment (End of scanline)
                if (internal_x == 256) begin
                    if (v[14:12] < 7) begin
                        v[14:12] <= v[14:12] + 1;
                    end else begin
                        v[14:12] <= 0;
                        if (v[9:5] == 29) begin
                            v[9:5] <= 0;
                            v[11]  <= ~v[11]; 
                        end else if (v[9:5] == 31) begin
                            v[9:5] <= 0;
                        end else begin
                            v[9:5] <= v[9:5] + 1;
                        end
                    end
                end

                // 3. Horizontal Copy (Start of scanline)
                if (internal_x == 257) begin
                    v[4:0] <= t[4:0];
                    v[10]  <= t[10];
                end
            end
            
            // 4. Vertical Copy (Frame start / Pre-render line proxy)
            if (clear_vblank_pulse && rendering_enabled) begin
                v[9:5]   <= t[9:5];
                v[11]    <= t[11];
                v[14:12] <= t[14:12];
            end
        end
    end
endmodule

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

module palette_ram (
    input  wire        clk,
    input  wire [4:0]  addr,
    input  wire [7:0]  din,
    input  wire        we,
    output wire [7:0]  dout,
    input  wire [4:0]  dac_addr,
    output wire [7:0]  dac_dout,
    output wire [7:0]  dbg_palette_00 
);
    reg [7:0] ram [0:31];
    integer i;
    initial begin
        for (i=0; i<32; i=i+1) ram[i] = 8'h00;
    end
    always @(posedge clk) begin
        if (we) ram[addr] <= din;
    end
    assign dout = ram[addr];
    assign dac_dout = ram[dac_addr];
    assign dbg_palette_00 = ram[0];
endmodule

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