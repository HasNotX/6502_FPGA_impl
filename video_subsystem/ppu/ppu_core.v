module ppu_core (
    input  wire        clk,           
    input  wire        reset,         
    input  wire        ppu_ce,
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
    output wire [14:0] active_v_reg,
    output wire [2:0]  fine_x_scroll,

    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire        ppu_visible,
    input  wire [14:0] bg_mem_addr,
    output wire [7:0]  bg_mem_data,
    
    input  wire [4:0]  dac_palette_addr,
    output wire [7:0]  dac_palette_data,
    output wire [7:0]  dbg_palette_00,

    output wire [8:0]  trap_y_out,
    output wire [8:0]  trap_x_out,
    
    input  wire [3:0]  bg_pixel_idx
);

    wire [7:0] ppu_ctrl;
    wire [7:0] ppu_mask;
    wire [7:0] cpu_oam_addr;
    wire [14:0] vram_addr;

    assign dbg_ctrl = ppu_ctrl;
    assign dbg_mask = ppu_mask;
    assign active_v_reg = vram_addr;
    
    wire rendering_enabled = ppu_mask[3] | ppu_mask[4];
    wire is_active_frame   = rendering_enabled && (ppu_y < 9'd240 || ppu_y == 9'd261);

    // =========================================================================
    // OAM Subsystem Arbitration
    // =========================================================================
    wire [7:0] eval_oam_addr;
    wire [7:0] active_oam_addr = is_active_frame ? eval_oam_addr : cpu_oam_addr;
    wire       active_oam_we   = is_active_frame ? 1'b0 : ((~cpu_write_n) && (cpu_addr == 3'd4));
    wire [7:0] oam_data_out;

    wire [4:0] eval_sec_oam_addr;
    wire [7:0] eval_sec_oam_data;
    wire       eval_sec_oam_we;
    
    wire [4:0] render_sec_oam_addr;
    wire [7:0] sec_oam_data_out;
    
    // PATCHED: Hand over the bus at Dot 256 so the render primer fetch succeeds
    wire [4:0] active_sec_oam_addr = (ppu_x >= 9'd256) ? render_sec_oam_addr : eval_sec_oam_addr;

    wire sprite_0_active;
    wire sprite_overflow;

    ppu_sprite_eval eval_inst (
        .clk             (clk),
        .reset           (reset),
        .ppu_ce          (ppu_ce),
        .ppu_x           (ppu_x),
        .ppu_y           (ppu_y),
        .ppu_ctrl_reg    (ppu_ctrl),
        .oam_addr        (eval_oam_addr),
        .oam_data        (oam_data_out),
        .sec_oam_addr    (eval_sec_oam_addr),
        .sec_oam_data    (eval_sec_oam_data),
        .sec_oam_we      (eval_sec_oam_we),
        .sprite_0_active (sprite_0_active),
        .sprite_overflow (sprite_overflow)
    );

    wire [13:0] sprite_chr_addr;
    wire [3:0]  sprite_pixel_idx;
    wire        sprite_priority;
    wire        sprite_0_hit_pulse;

    ppu_sprite_render render_inst (
        .clk                (clk),
        .reset              (reset),
        .ppu_ce             (ppu_ce),
        .ppu_x              (ppu_x),
        .ppu_y              (ppu_y),
        .ppu_ctrl_reg       (ppu_ctrl),
        .sec_oam_addr       (render_sec_oam_addr),
        .sec_oam_data       (sec_oam_data_out),
        .chr_addr           (sprite_chr_addr),
        .chr_data           (chr_data_in),
        .sprite_pixel_idx   (sprite_pixel_idx),
        .sprite_priority    (sprite_priority),
        .sprite_0_hit_pulse (sprite_0_hit_pulse),
        .sprite_0_active    (sprite_0_active),
        .bg_pixel_idx       (bg_pixel_idx),
        .rendering_enabled  (rendering_enabled)
    );

    // =========================================================================
    // Memory Bus Arbitration
    // =========================================================================
    wire is_sprite_chr_window = is_active_frame && (ppu_x >= 9'd257 && ppu_x <= 9'd320);
    
    wire [14:0] target_addr = is_sprite_chr_window ? {1'b0, sprite_chr_addr} :
                              ppu_visible ? bg_mem_addr : vram_addr;
                              
    wire target_we = ppu_visible ? 1'b0 : ((~cpu_write_n) && (cpu_addr == 3'd7));
    
    wire [7:0] vram_data_out;
    wire [7:0] palette_data_out;
    
    wire [7:0] internal_mem_data_out = (target_addr >= 15'h3F00) ? palette_data_out :
                                       (target_addr >= 15'h2000) ? vram_data_out :
                                       chr_data_in;

    assign bg_mem_data = internal_mem_data_out;
    assign chr_addr = target_addr[13:0];
    assign chr_read_n = ~(target_addr < 15'h2000);

    ppu_registers regs_inst (
        .clk                (clk),
        .reset              (reset),
        .ppu_ce             (ppu_ce),
        .vblank_pulse       (vblank_pulse), 
        .clear_vblank_pulse (clear_vblank_pulse),
        .sprite0_hit_pulse  (sprite_0_hit_pulse), 
        
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
        .fine_x_out         (fine_x_scroll),
        .nmi_out            (nmi_out),
        
        .ppu_x              (ppu_x),
        .ppu_y              (ppu_y),
        .ppu_visible        (ppu_visible),
        
        .trap_y             (trap_y_out),
        .trap_x             (trap_x_out)
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
        .we     (active_oam_we), 
        .dout   (oam_data_out)
    );

    sec_oam_ram sec_sprite_ram (
        .clk    (clk),
        .addr   (active_sec_oam_addr),
        .din    (eval_sec_oam_data),
        .we     (eval_sec_oam_we && is_active_frame),
        .dout   (sec_oam_data_out)
    );

endmodule

module ppu_registers (
    input  wire        clk,
    input  wire        reset,
    input  wire        ppu_ce,
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
    
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire        ppu_visible,

    output reg  [8:0]  trap_y,
    output reg  [8:0]  trap_x
);

    reg [7:0] status_reg;
    reg [7:0] read_buffer; 

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
            trap_y        <= 9'd0;
            trap_x        <= 9'd0;
        end else begin
            if (clear_vblank_pulse) begin
                status_reg[7] <= 1'b0;
                status_reg[6] <= 1'b0; 
            end
            if (vblank_pulse)      status_reg[7] <= 1'b1;
            if (sprite0_hit_pulse) status_reg[6] <= 1'b1;

            if (!cpu_write_n) begin
                
                // HARDWARE SURGERY: Latch the exact PPU coordinate if the CPU writes to 
                // the scroll registers ($2005 or $2006) during the visible frame.
                if ((cpu_addr == 3'd5 || cpu_addr == 3'd6) && ppu_y < 9'd240) begin
                    trap_y <= ppu_y;
                    trap_x <= ppu_x;
                end

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

            if (rendering_enabled && ppu_ce) begin
                if ((ppu_x < 9'd256 || ppu_x >= 9'd320) && ppu_x[2:0] == 3'd7) begin
                    if (v[4:0] == 31) begin
                        v[4:0] <= 0;
                        v[10]  <= ~v[10]; 
                    end else begin
                        v[4:0] <= v[4:0] + 1;
                    end
                end

                if (ppu_x == 9'd256) begin
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

                if (ppu_x == 9'd257) begin
                    v[4:0] <= t[4:0];
                    v[10]  <= t[10];
                end

                if (ppu_y == 9'd261 && ppu_x >= 9'd280 && ppu_x <= 9'd304) begin
                    v[9:5]   <= t[9:5];
                    v[11]    <= t[11];
                    v[14:12] <= t[14:12];
                end
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
        for (i = 0; i < 32; i = i + 1) begin
            ram[i] = 8'h0F; // Initialize entirely to NES Black
        end
    end
    
    // NES Hardware Quirk: Addresses ending in 00, 04, 08, 0C in the sprite palette 
    // ($3F10-$3F1F) mirror directly to the background palette ($3F00-$3F0F).
    wire [4:0] mapped_write_addr = (addr[1:0] == 2'b00) ? {1'b0, addr[3:0]} : addr;
    wire [4:0] mapped_read_addr  = (addr[1:0] == 2'b00) ? {1'b0, addr[3:0]} : addr;
    wire [4:0] mapped_dac_addr   = (dac_addr[1:0] == 2'b00) ? {1'b0, dac_addr[3:0]} : dac_addr;

    always @(posedge clk) begin
        if (we) ram[mapped_write_addr] <= din;
    end
    
    assign dout = ram[mapped_read_addr];
    assign dac_dout = ram[mapped_dac_addr];
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

module sec_oam_ram (
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