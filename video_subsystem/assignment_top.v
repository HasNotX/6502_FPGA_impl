module assignment_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,      
    input  wire [9:0]  SW,       
    
    // DE10-Standard VGA DAC 
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK,
    
    // NEW: Debug Output Ports
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5
);

    wire clk_25mhz;
    wire rst = ~KEY[3]; // Active high reset internally
    
    // Turn off unused HEX displays (Active Low)
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
    // 2. Button Edge Detection (Single pulse generation for KEY[0])
    // -------------------------------------------------------------------------
    reg draw_btn_sync_0, draw_btn_sync_1, draw_btn_last;
    wire draw_req = (~draw_btn_sync_1) & draw_btn_last; // Detect falling edge (press)

    always @(posedge clk_25mhz) begin
        draw_btn_sync_0 <= KEY[0];
        draw_btn_sync_1 <= draw_btn_sync_0;
        draw_btn_last   <= draw_btn_sync_1;
    end

    // -------------------------------------------------------------------------
    // 3. Bresenham FSM and Datapath
    // -------------------------------------------------------------------------
    wire [14:0] fsm_ram_addr;
    wire [2:0]  fsm_ram_data;
    wire        fsm_ram_wren;
    wire [3:0]  current_fsm_state; // Exported FSM State

    wire [5:0] target_radius = {1'b0, SW[7:3]};

    bresenham_fsm fsm_inst (
        .clk           (clk_25mhz),
        .reset         (rst),
        .draw_req      (draw_req),
        .radius_in     (target_radius),
        .color_in      (SW[2:0]),
        .ram_addr      (fsm_ram_addr),
        .ram_data      (fsm_ram_data),
        .ram_wren      (fsm_ram_wren),
        .fsm_state_out (current_fsm_state)
    );

    // -------------------------------------------------------------------------
    // 4. Dual-Port Framebuffer (160x120 = 19,200 addresses)
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
    // 5. VGA Sync Generator
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

    // -------------------------------------------------------------------------
    // 6. Video Output Mapping
    // -------------------------------------------------------------------------
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
    
    // HEX0 Displays the raw FSM State Number
    hex_decoder hex0_inst (
        .hex_in   (current_fsm_state),
        .segments (HEX0)
    );
    
    // Sticky Flag: Turns on permanently the nanosecond KEY[0] is detected
    reg sticky_draw_flag;
    always @(posedge clk_25mhz) begin
        if (rst) sticky_draw_flag <= 1'b0;
        else if (draw_req) sticky_draw_flag <= 1'b1;
    end
    
    // LED Indicators
    assign LEDR[9] = video_on;      
    assign LEDR[8] = pll_locked;    
    assign LEDR[7] = 1'b0;          
    assign LEDR[6] = fsm_ram_wren;  
    assign LEDR[5] = 1'b0;
    assign LEDR[4] = sticky_draw_flag; // Will pop ON and stay ON when you press KEY0
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