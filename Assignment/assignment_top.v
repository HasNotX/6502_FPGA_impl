module assignment_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,      
    input  wire [9:0]  SW,       
    
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK,
    
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5
);

    wire clk_25mhz;
    wire rst = ~KEY[3]; 
    
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

    // -------------------------------------------------------------------------
    // 1. Clock Generation
    // -------------------------------------------------------------------------
    wire pll_locked;
    vga_pll pll_inst (
        .refclk   (CLOCK_50),
        .rst      (rst),
        .outclk_0 (clk_25mhz),
        .locked   (pll_locked)
    );

    // -------------------------------------------------------------------------
    // 2. Hardware Input Parsing
    // -------------------------------------------------------------------------
    reg draw_btn_sync_0, draw_btn_sync_1, draw_btn_last;
    wire manual_draw_req = (~draw_btn_sync_1) & draw_btn_last;

    always @(posedge clk_25mhz) begin
        draw_btn_sync_0 <= KEY[0];
        draw_btn_sync_1 <= draw_btn_sync_0;
        draw_btn_last   <= draw_btn_sync_1;
    end

    wire [5:0] manual_radius = {1'b0, SW[7:3]};
    wire challenge_mode      = SW[9];

    // -------------------------------------------------------------------------
    // 3. Challenge Automation Generator
    // -------------------------------------------------------------------------
    wire       chal_draw_req;
    wire [7:0] chal_cx;
    wire [6:0] chal_cy;
    wire [5:0] chal_radius;
    wire [2:0] chal_color;

    challenge_generator gen_inst (
        .clk          (clk_25mhz),
        .reset        (rst),
        .enable       (challenge_mode),
        .gen_draw_req (chal_draw_req),
        .gen_cx       (chal_cx),
        .gen_cy       (chal_cy),
        .gen_radius   (chal_radius),
        .gen_color    (chal_color)
    );

    // -------------------------------------------------------------------------
    // 4. Data Multiplexing & Bresenham FSM
    // -------------------------------------------------------------------------
    wire [14:0] fsm_ram_addr;
    wire [2:0]  fsm_ram_data;
    wire        fsm_ram_wren;
    wire [3:0]  current_fsm_state; 

    // MUX: Route inputs based on SW[9] status
    wire        mux_draw_req = challenge_mode ? chal_draw_req : manual_draw_req;
    wire [7:0]  mux_cx       = challenge_mode ? chal_cx       : 8'd80;
    wire [6:0]  mux_cy       = challenge_mode ? chal_cy       : 7'd60;
    wire [5:0]  mux_radius   = challenge_mode ? chal_radius   : manual_radius;
    wire [2:0]  mux_color    = challenge_mode ? chal_color    : SW[2:0];

    bresenham_fsm fsm_inst (
        .clk           (clk_25mhz),
        .reset         (rst),
        .draw_req      (mux_draw_req),
        .cx_in         (mux_cx),
        .cy_in         (mux_cy),
        .radius_in     (mux_radius),
        .color_in      (mux_color),
        .ram_addr      (fsm_ram_addr),
        .ram_data      (fsm_ram_data),
        .ram_wren      (fsm_ram_wren),
        .fsm_state_out (current_fsm_state)
    );

    // -------------------------------------------------------------------------
    // 5. Dual-Port Framebuffer
    // -------------------------------------------------------------------------
    wire [14:0] vga_ram_addr;
    wire [2:0]  vga_ram_data_out;

    framebuffer_ram fb_ram (
        .clock      (clk_25mhz),
        .data       (fsm_ram_data),
        .rdaddress  (vga_ram_addr),
        .wraddress  (fsm_ram_addr),
        .wren       (fsm_ram_wren),
        .q          (vga_ram_data_out)
    );

    // -------------------------------------------------------------------------
    // 6. VGA Sync Generator & Video Output
    // -------------------------------------------------------------------------
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire       video_on;

    vga_sync_generator sync_gen (
        .clk        (clk_25mhz),
        .reset      (rst),
        .h_sync     (VGA_HS),
        .v_sync     (VGA_VS),
        .video_on   (video_on),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y)
    );

    wire [7:0] read_x = pixel_x[9:2]; 
    wire [6:0] read_y = pixel_y[9:2]; 
    
    assign vga_ram_addr = (read_y * 160) + read_x;

    assign VGA_BLANK_N = video_on;
    assign VGA_SYNC_N  = 1'b0;
    assign VGA_CLK     = clk_25mhz;

    assign VGA_R = (video_on && vga_ram_data_out[2]) ? 8'hFF : 8'h00;
    assign VGA_G = (video_on && vga_ram_data_out[1]) ? 8'hFF : 8'h00;
    assign VGA_B = (video_on && vga_ram_data_out[0]) ? 8'hFF : 8'h00;

    // -------------------------------------------------------------------------
    // 7. HARDWARE TELEMETRY & DEBUGGING
    // -------------------------------------------------------------------------
    hex_decoder hex0_inst (
        .hex_in   (current_fsm_state),
        .segments (HEX0)
    );
    
    reg sticky_draw_flag;
    always @(posedge clk_25mhz) begin
        if (rst) sticky_draw_flag <= 1'b0;
        else if (mux_draw_req) sticky_draw_flag <= 1'b1;
    end
    
    assign LEDR[9] = challenge_mode; // Indicate which mode is active
    assign LEDR[8] = pll_locked;    
    assign LEDR[7] = 1'b0;          
    assign LEDR[6] = fsm_ram_wren;  
    assign LEDR[5] = 1'b0;
    assign LEDR[4] = sticky_draw_flag; 
    assign LEDR[3:0] = current_fsm_state; 

endmodule

// Internal Dual-Port RAM Module
module framebuffer_ram (
    input  wire        clock,
    input  wire [2:0]  data,
    input  wire [14:0] rdaddress,
    input  wire [14:0] wraddress,
    input  wire        wren,
    output reg  [2:0]  q
);
    reg [2:0] ram [0:19199];
    
    always @(posedge clock) begin
        if (wren) ram[wraddress] <= data;
        q <= ram[rdaddress]; 
    end
endmodule
