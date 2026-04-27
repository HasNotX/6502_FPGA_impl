/*
 * File: ppu_sprite_eval.v
 * Description: Cycle-accurate Primary to Secondary OAM evaluation engine.
 * Operates during dots 1-256 to stage up to 8 sprites for the next scanline.
 */

module ppu_sprite_eval (
    input  wire        clk,
    input  wire        reset,
    input  wire        ppu_ce,
    
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire [7:0]  ppu_ctrl_reg,
    
    // Interface to Primary OAM
    output reg  [7:0]  oam_addr,
    input  wire [7:0]  oam_data,
    
    // Interface to Secondary OAM
    output reg  [4:0]  sec_oam_addr,
    output reg  [7:0]  sec_oam_data,
    output reg         sec_oam_we,
    
    // Evaluation Flags
    output reg         sprite_0_active,
    output reg         sprite_overflow
);

    wire [4:0] sprite_height = ppu_ctrl_reg[5] ? 5'd16 : 5'd8;
    
    reg [5:0] n; // Primary OAM index (0 to 63)
    reg [2:0] m; // Secondary OAM index (0 to 7)
    reg [1:0] b; // Byte offset within sprite (0 to 3)
    
    reg eval_done;
    reg overflow_search;
    reg s0_hit_staged;

    wire even_dot = ~ppu_x[0];
    
    wire [8:0] diff = ppu_y - oam_data;
    wire is_in_range = (diff >= 9'd0) && (diff < {4'd0, sprite_height});

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            oam_addr        <= 8'd0;
            sec_oam_addr    <= 5'd0;
            sec_oam_data    <= 8'hFF;
            sec_oam_we      <= 1'b0;
            sprite_0_active <= 1'b0;
            sprite_overflow <= 1'b0;
            n               <= 6'd0;
            m               <= 3'd0;
            b               <= 2'd0;
            eval_done       <= 1'b0;
            overflow_search <= 1'b0;
            s0_hit_staged   <= 1'b0;
        end else if (ppu_ce) begin
            
            // Default inactive state
            sec_oam_we <= 1'b0;
            
            // Initialization at Dot 0
            if (ppu_x == 9'd0) begin
                n               <= 6'd0;
                m               <= 3'd0;
                b               <= 2'd0;
                eval_done       <= 1'b0;
                overflow_search <= 1'b0;
                sprite_0_active <= s0_hit_staged; 
                s0_hit_staged   <= 1'b0;
            end
            
            // Phase 1: Clear Secondary OAM (Dots 1 to 64)
            else if (ppu_x >= 9'd1 && ppu_x <= 9'd64) begin
                if (even_dot) begin
                    sec_oam_addr <= ppu_x[5:1] - 5'd1;
                    sec_oam_data <= 8'hFF;
                    sec_oam_we   <= 1'b1;
                end
            end
            
            // Phase 2: Sprite Evaluation (Dots 65 to 256)
            else if (ppu_x >= 9'd65 && ppu_x <= 9'd256) begin
                if (!eval_done) begin
                    if (!even_dot) begin
                        // Odd dot: Request data from Primary OAM
                        oam_addr <= {n, b};
                    end else begin
                        // Even dot: Evaluate or Copy
                        if (overflow_search) begin
                            // Looking for 9th sprite
                            if (b == 2'd0) begin
                                if (is_in_range) begin
                                    sprite_overflow <= 1'b1;
                                    eval_done       <= 1'b1;
                                end else begin
                                    n <= n + 1'b1;
                                    if (n == 6'd63) eval_done <= 1'b1;
                                end
                            end
                        end else begin
                            // Normal Evaluation
                            if (b == 2'd0) begin
                                // Evaluate Y coordinate
                                if (is_in_range) begin
                                    sec_oam_addr <= {m, b};
                                    sec_oam_data <= oam_data;
                                    sec_oam_we   <= 1'b1;
                                    b            <= b + 1'b1;
                                    if (n == 6'd0) s0_hit_staged <= 1'b1;
                                end else begin
                                    n <= n + 1'b1;
                                    if (n == 6'd63) eval_done <= 1'b1;
                                end
                            end else begin
                                // Copying remaining 3 bytes
                                sec_oam_addr <= {m, b};
                                sec_oam_data <= oam_data;
                                sec_oam_we   <= 1'b1;
                                
                                if (b == 2'd3) begin
                                    b <= 2'd0;
                                    n <= n + 1'b1;
                                    m <= m + 1'b1;
                                    
                                    if (n == 6'd63) eval_done <= 1'b1;
                                    if (m == 3'd7)  overflow_search <= 1'b1;
                                end else begin
                                    b <= b + 1'b1;
                                end
                            end
                        end
                    end
                end
            end
        end
    end
endmodule