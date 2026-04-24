// =============================================================================
// Top-Level PPU Wrapper
// =============================================================================
module ppu_core (
    input  wire        clk,           
    input  wire        reset,         
    input  wire        vblank_pulse,  // NEW

    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    output wire [7:0]  cpu_data_out,  
    input  wire        cpu_read_n,    
    input  wire        cpu_write_n,   
    input  wire        clear_vblank_pulse, // NEW
    input  wire        sprite0_hit_pulse,  // NEW

    output wire [13:0] chr_addr,
    input  wire [7:0]  chr_data_in,
    output wire        chr_read_n,
    
    output wire [7:0]  dbg_ctrl,
    output wire [7:0]  dbg_mask,
    output wire [14:0] dbg_vram_addr,
    output wire [7:0]  dbg_palette_00,

    input  wire        nes_visible,
    input  wire [14:0] bg_mem_addr,
    output wire [7:0]  bg_mem_data,
    
    input  wire [4:0]  dac_palette_addr,
    output wire [7:0]  dac_palette_data,
    output wire nmi_out
);

    wire [7:0] ppu_ctrl;
    wire [7:0] ppu_mask;
    wire [7:0] oam_addr;
    wire [14:0] vram_addr;        
    
    assign dbg_ctrl = ppu_ctrl;
    assign dbg_mask = ppu_mask;
    assign dbg_vram_addr = vram_addr;
    
    wire [7:0] vram_data_out;
    wire [7:0] palette_data_out;
    wire [7:0] oam_data_out;

    wire [14:0] target_addr = nes_visible ? bg_mem_addr : vram_addr;
    wire target_we = nes_visible ? 1'b0 : ((~cpu_write_n) && (cpu_addr == 3'd7));

    wire [7:0] internal_mem_data_out = (target_addr >= 15'h3F00) ? palette_data_out :
                                       (target_addr >= 15'h2000) ? vram_data_out :
                                       chr_data_in;

    assign bg_mem_data = internal_mem_data_out;

    ppu_registers regs_inst (
        .clk            (clk),
        .reset          (reset),
        .vblank_pulse   (vblank_pulse), // NEW
        .cpu_addr       (cpu_addr),
        .cpu_data_in    (cpu_data_in),
        .cpu_read_n     (cpu_read_n),
        .cpu_write_n    (cpu_write_n),
        .cpu_data_out   (cpu_data_out),
        
        .mem_data_in    (internal_mem_data_out), 
        
        .ctrl_out       (ppu_ctrl),
        .mask_out       (ppu_mask),
        .vram_addr_out  (vram_addr),
        .oam_addr_out   (oam_addr),
        .nmi_out         (nmi_out)
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

    assign chr_addr = target_addr[13:0];
    assign chr_read_n = ~(target_addr < 15'h2000);

endmodule


// =============================================================================
// CPU to PPU Register Interface
// =============================================================================
module ppu_registers (
    input  wire        clk,
    input  wire        reset,
    input  wire        vblank_pulse,  // NEW
    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    input  wire        cpu_read_n,
    input  wire        cpu_write_n,
    input  wire [7:0]  mem_data_in,   
    input  wire        clear_vblank_pulse, // NEW
    input  wire        sprite0_hit_pulse,  // NEW
    
    output reg  [7:0]  cpu_data_out,
    output reg  [7:0]  ctrl_out,
    output reg  [7:0]  mask_out,
    output reg  [14:0] vram_addr_out,
    output reg  [7:0]  oam_addr_out,
    output wire nmi_out
);

    reg w_toggle; 
    reg [7:0] status_reg;
    reg [7:0] scroll_x;
    reg [7:0] scroll_y;
    reg [7:0] read_buffer; 

    // Trigger NMI if VBlank (status_reg[7]) and NMI Enable (ctrl_out[7]) are both high
    assign nmi_out = status_reg[7] & ctrl_out[7];

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
        
            
            // =================================================================
            // Hardware Event Flag Logic
            // =================================================================
            if (clear_vblank_pulse) begin
                status_reg[7] <= 1'b0;
                status_reg[6] <= 1'b0; // Clear Sprite 0 Hit
            end
            
            if (vblank_pulse) begin
                status_reg[7] <= 1'b1;
            end
            
            if (sprite0_hit_pulse) begin
                status_reg[6] <= 1'b1; // Trigger Fake Sprite 0 Hit!
            end

            // CPU Write Logic
            if (!cpu_write_n) begin
                case (cpu_addr)
                    3'd0: ctrl_out <= cpu_data_in;        
                    3'd1: mask_out <= cpu_data_in;        
                    3'd3: oam_addr_out <= cpu_data_in;    
                    3'd4: oam_addr_out <= oam_addr_out + 1'b1; 
                    
                    3'd5: begin                           
                        if (!w_toggle) begin
                            scroll_x <= cpu_data_in;
                            w_toggle <= 1'b1;
                        end else begin
                            scroll_y <= cpu_data_in;
                            w_toggle <= 1'b0;
                        end
                    end
                    
                    3'd6: begin                           
                        if (!w_toggle) begin
                            vram_addr_out[13:8] <= cpu_data_in[5:0]; 
                            w_toggle <= 1'b1;
                        end else begin
                            vram_addr_out[7:0] <= cpu_data_in;       
                            w_toggle <= 1'b0;
                        end
                    end
                    
                    3'd7: begin                           
                        vram_addr_out <= vram_addr_out + (ctrl_out[2] ? 15'd32 : 15'd1);
                    end
                endcase
            end

            // CPU Read Logic
            if (!cpu_read_n) begin
                case (cpu_addr)
                    3'd2: begin                           
                        // If VBlank sets exactly as we read it, the read wins and clears it.
                        cpu_data_out <= (vblank_pulse) ? {1'b1, status_reg[6:0]} : status_reg;
                        w_toggle <= 1'b0;                 
                        status_reg[7] <= 1'b0;            
                    end
                    
                    3'd7: begin                           
                        if (vram_addr_out >= 15'h3F00) begin
                            cpu_data_out <= mem_data_in; 
                            read_buffer  <= mem_data_in; 
                        end else begin
                            cpu_data_out <= read_buffer;
                            read_buffer  <= mem_data_in;
                        end
                        vram_addr_out <= vram_addr_out + (ctrl_out[2] ? 15'd32 : 15'd1);
                    end
                    
                    default: cpu_data_out <= 8'h00;
                endcase
            end
        end
    end
endmodule

// =============================================================================
// Internal PPU Block RAM Definitions
// =============================================================================

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