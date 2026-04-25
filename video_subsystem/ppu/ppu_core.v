// =============================================================================
// Top-Level PPU Wrapper
// =============================================================================
module ppu_core (
    input  wire        clk,           
    input  wire        reset,         
    input  wire        vblank_pulse,  
    input  wire        clear_vblank_pulse, 
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
    output wire [14:0] dbg_vram_addr,
    output wire [7:0]  dbg_palette_00,

    input  wire [7:0]  nes_x,
    input  wire        nes_visible,
    input  wire [14:0] bg_mem_addr,
    output wire [7:0]  bg_mem_data,
    
    input  wire [4:0]  dac_palette_addr,
    output wire [7:0]  dac_palette_data,

    output wire [7:0]   dbg_scroll_x,
    output wire [7:0]   dbg_scroll_y,

    output wire [7:0]  loopy_scroll_x,
    output wire [7:0]  loopy_scroll_y,
    output wire        loopy_nt_x,
    output wire        loopy_nt_y,
    
    // NEW: Sprite subsystem connections
    input  wire [7:0]  nes_y,
    input  wire        true_sprite0_hit,
    output wire [3:0]  sprite_color_idx,
    output wire        sprite_bg_priority,
    output wire        sprite0_active,
    output wire        dbg_status
);

    wire [7:0] ppu_ctrl;
    wire [7:0] ppu_mask;
    wire [7:0] cpu_oam_addr;
    wire [14:0] vram_addr;        
    
    assign dbg_ctrl = ppu_ctrl;
    assign dbg_mask = ppu_mask;
    assign dbg_vram_addr = vram_addr;
    assign dbg_status = dbg_ppu_reg_status;
    wire [7:0] vram_data_out;
    wire [7:0] palette_data_out;
    wire [7:0] oam_data_out;

    // ─────────────────────────────────────────────────────────────────────────
    // Bus Multiplexing
    // ─────────────────────────────────────────────────────────────────────────
    wire is_sprite_fetch; // NEW: Driven dynamically by the sprite module!
    wire [13:0] sprite_chr_addr;
    
    wire [14:0] target_addr = is_sprite_fetch ? {1'b0, sprite_chr_addr} : 
                              nes_visible     ? bg_mem_addr : vram_addr;
                              
    wire target_we = (nes_visible || is_sprite_fetch) ? 1'b0 : ((~cpu_write_n) && (cpu_addr == 3'd7));

    // OAM Bus Arbiter
    wire [7:0] sprite_oam_addr;
    wire active_rendering = (nes_visible || is_sprite_fetch);
    wire [7:0] active_oam_addr = active_rendering ? sprite_oam_addr : cpu_oam_addr;
    wire oam_we = ((~cpu_write_n) && (cpu_addr == 3'd4) && !active_rendering);

    wire [7:0] internal_mem_data_out = (target_addr >= 15'h3F00) ? palette_data_out :
                                       (target_addr >= 15'h2000) ? vram_data_out :
                                       chr_data_in;

    assign bg_mem_data = internal_mem_data_out;
    assign chr_addr    = target_addr[13:0];
    assign chr_read_n  = ~(target_addr < 15'h2000);

    // ─────────────────────────────────────────────────────────────────────────
    // Subsystem Instantiations (Inside ppu_core.v)
    // ─────────────────────────────────────────────────────────────────────────
    wire [7:0] scroll_x;
    wire [7:0] scroll_y;

    assign dbg_scroll_x = scroll_x;
    assign dbg_scroll_y = scroll_y;

    wire dbg_ppu_reg_status; // NEW: Expose PPUSTATUS for debugging

    ppu_registers regs_inst (
        .clk                (clk),
        .reset              (reset),
        .vblank_pulse       (vblank_pulse),
        .clear_vblank_pulse (clear_vblank_pulse),
        .sprite0_hit_pulse  (true_sprite0_hit), 
        .cpu_addr           (cpu_addr),
        .cpu_data_in        (cpu_data_in),
        .cpu_read_n         (cpu_read_n),
        .cpu_write_n        (cpu_write_n),
        .cpu_data_out       (cpu_data_out),
        .mem_data_in        (internal_mem_data_out), 
        .ctrl_out           (ppu_ctrl),
        .mask_out           (ppu_mask),
        .vram_addr_out      (vram_addr),
        .oam_addr_out       (cpu_oam_addr),
        .nmi_out            (nmi_out),
        .loopy_scroll_x     (loopy_scroll_x), // NEW
        .loopy_scroll_y     (loopy_scroll_y), // NEW
        .loopy_nt_x         (loopy_nt_x),     // NEW
        .loopy_nt_y         (loopy_nt_y),      // NEW
        .status_out          (dbg_ppu_reg_status) // NEW
    );

    ppu_sprite_render spr_render (
        .clk                (clk),
        .reset              (reset),
        .nes_x              (nes_x),
        .nes_y              (nes_y),
        .nes_visible        (nes_visible),
        .ppu_ctrl_reg       (ppu_ctrl),
        .oam_addr           (sprite_oam_addr),
        .oam_data           (oam_data_out),
        .chr_addr           (sprite_chr_addr),
        .chr_data           (chr_data_in),
        .sprite_color_idx   (sprite_color_idx),
        .sprite_bg_priority (sprite_bg_priority),
        .sprite0_active     (sprite0_active),
        .is_fetching        (is_sprite_fetch)  // Plumbed to Arbitrator!
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
        .addr   (active_oam_addr),
        .din    (cpu_data_in),
        .we     (oam_we), 
        .dout   (oam_data_out)
    );

endmodule

// =============================================================================
// CPU to PPU Register Interface
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
    output wire        nmi_out,
    
    // NEW: Decoded Loopy Signals
    output wire [7:0]  loopy_scroll_x,
    output wire [7:0]  loopy_scroll_y,
    output wire        loopy_nt_x,
    output wire        loopy_nt_y,
    output wire [7:0]  status_out // NEW: Expose PPUSTATUS for debugging
);

    reg [7:0] status_reg;
    reg [7:0] read_buffer; 
    assign status_out = status_reg; // Expose PPUSTATUS for debugging

    // The Unified "Loopy" Registers
    reg [14:0] v;       // Current VRAM address (15 bits)
    reg [14:0] t;       // Temporary VRAM address (15 bits)
    reg [2:0]  fine_x;  // Fine X scroll (3 bits)
    reg        w;       // First/Second write toggle (1 bit)

    assign nmi_out = status_reg[7] & ctrl_out[7];
    
    // Dynamically decode the V register for the renderer
    assign vram_addr_out  = v;
    assign loopy_scroll_x = {v[4:0], fine_x};
    assign loopy_scroll_y = {v[9:5], v[14:12]};
    assign loopy_nt_x     = v[10];
    assign loopy_nt_y     = v[11];

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
        
            if (clear_vblank_pulse) begin
                status_reg[7] <= 1'b0;
                status_reg[6] <= 1'b0; 
                v <= t; // HARDWARE FIX: Camera resets to 't' at the start of every frame!
            end
            
            if (vblank_pulse) begin
                status_reg[7] <= 1'b1;
            end
            
            if (sprite0_hit_pulse) begin
                status_reg[6] <= 1'b1;
            end

            // CPU Write Logic
            if (!cpu_write_n) begin
                case (cpu_addr)
                    3'd0: begin 
                        ctrl_out <= cpu_data_in;        
                        t[11:10] <= cpu_data_in[1:0]; // Base nametable updates 't'!
                    end
                    3'd1: mask_out     <= cpu_data_in;        
                    3'd3: oam_addr_out <= cpu_data_in;    
                    3'd4: oam_addr_out <= oam_addr_out + 1'b1; 
                    
                    3'd5: begin // $2005 PPUSCROLL
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
                    
                    3'd6: begin // $2006 PPUADDR
                        if (!w) begin
                            t[13:8] <= cpu_data_in[5:0];
                            t[14]   <= 1'b0;
                            w       <= 1'b1;
                        end else begin
                            t[7:0] <= cpu_data_in;
                            v      <= {t[14:8], cpu_data_in}; // Snap v to t!
                            w      <= 1'b0;
                        end
                    end
                    
                    3'd7: begin // $2007 PPUDATA
                        v <= v + (ctrl_out[2] ? 15'd32 : 15'd1);
                    end
                endcase
            end

            // CPU Read Logic
            if (!cpu_read_n) begin
                case (cpu_addr)
                    3'd2: begin                           
                        cpu_data_out  <= (vblank_pulse) ? {1'b1, status_reg[6:0]} : status_reg;
                        w             <= 1'b0; // Reading Status clears the toggle!                 
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