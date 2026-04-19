/* * Module: nes_vga_core
 * Description: Generates standard 640x480@60Hz VGA timing and maps physical 
 * screen coordinates to the NES 256x240 internal resolution.
 * Applies 2x integer scaling and pillarboxing.
 */

module nes_vga_core (
    input  wire        clk_25mhz,     // 25.175 MHz pixel clock
    input  wire        reset,         // Asynchronous active-high reset

    // Raw VGA Output Signals (To DE10 Board DAC)
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_blank_n,   // Active low blanking signal

    // Mapped NES Interface (To PPU rendering pipeline)
    output wire [7:0]  nes_x,         // 0 to 255
    output wire [7:0]  nes_y,         // 0 to 239
    output wire        nes_visible    // High when the beam is inside the active NES rendering area
);

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    wire [9:0] h_count_wire;
    wire [9:0] v_count_wire;
    wire       active_video;

    // -------------------------------------------------------------------------
    // Instantiate Sync Generator
    // -------------------------------------------------------------------------
    vga_sync_generator sync_gen (
        .clk        (clk_25mhz),
        .reset      (reset),
        .h_sync     (vga_hsync),
        .v_sync     (vga_vsync),
        .video_on   (active_video),
        .pixel_x    (h_count_wire),
        .pixel_y    (v_count_wire)
    );

    // The DE10 Video DAC requires a blanking signal. It is simply the active video flag.
    assign vga_blank_n = active_video;

    // -------------------------------------------------------------------------
    // Instantiate Coordinate Mapper
    // -------------------------------------------------------------------------
    nes_coordinate_mapper coord_map (
        .pixel_x     (h_count_wire),
        .pixel_y     (v_count_wire),
        .video_on    (active_video),
        .nes_x       (nes_x),
        .nes_y       (nes_y),
        .nes_visible (nes_visible)
    );

endmodule


// =============================================================================
// Sub-Module: VGA Sync Generator (640x480 @ 60Hz)
// =============================================================================
module vga_sync_generator (
    input  wire        clk,
    input  wire        reset,
    output reg         h_sync,
    output reg         v_sync,
    output reg         video_on,
    output reg  [9:0]  pixel_x,
    output reg  [9:0]  pixel_y
);

    // VGA 640x480@60Hz Horizontal Timing Parameters
    localparam H_DISPLAY       = 10'd640;
    localparam H_FRONT_PORCH   = 10'd16;
    localparam H_SYNC_PULSE    = 10'd96;
    localparam H_BACK_PORCH    = 10'd48;
    localparam H_TOTAL         = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    // VGA 640x480@60Hz Vertical Timing Parameters
    localparam V_DISPLAY       = 10'd480;
    localparam V_FRONT_PORCH   = 10'd10;
    localparam V_SYNC_PULSE    = 10'd2;
    localparam V_BACK_PORCH    = 10'd33;
    localparam V_TOTAL         = V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    // Counter logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pixel_x <= 10'd0;
            pixel_y <= 10'd0;
        end else begin
            if (pixel_x == H_TOTAL - 1) begin
                pixel_x <= 10'd0;
                if (pixel_y == V_TOTAL - 1) begin
                    pixel_y <= 10'd0;
                end else begin
                    pixel_y <= pixel_y + 1'b1;
                end
            end else begin
                pixel_x <= pixel_x + 1'b1;
            end
        end
    end

    // Sync generation logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            h_sync   <= 1'b1;
            v_sync   <= 1'b1;
            video_on <= 1'b0;
        end else begin
            // HSYNC is active low
            h_sync <= ~((pixel_x >= H_DISPLAY + H_FRONT_PORCH) && 
                        (pixel_x < H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE));
            
            // VSYNC is active low
            v_sync <= ~((pixel_y >= V_DISPLAY + V_FRONT_PORCH) && 
                        (pixel_y < V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE));

            // Video is on only during the active display area
            video_on <= (pixel_x < H_DISPLAY) && (pixel_y < V_DISPLAY);
        end
    end

endmodule


// =============================================================================
// Sub-Module: NES Coordinate Mapper
// =============================================================================
module nes_coordinate_mapper (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       video_on,
    
    output wire [7:0] nes_x,
    output wire [7:0] nes_y,
    output wire       nes_visible
);

    // Pillarbox parameters
    localparam H_OFFSET = 10'd64;  // (640 - (256 * 2)) / 2
    localparam V_OFFSET = 10'd0;   // (480 - (240 * 2)) / 2
    
    localparam NES_WIDTH_SCALED  = 10'd512;
    localparam NES_HEIGHT_SCALED = 10'd480;

    // Check if the current pixel is within the 512x480 scaled NES window
    wire is_within_nes_window = video_on && 
                                (pixel_x >= H_OFFSET) && 
                                (pixel_x < (H_OFFSET + NES_WIDTH_SCALED)) &&
                                (pixel_y >= V_OFFSET) && 
                                (pixel_y < (V_OFFSET + NES_HEIGHT_SCALED));

    assign nes_visible = is_within_nes_window;

    // Calculate NES coordinates by removing the offset and downshifting (dividing by 2)
    // The conditional operator ensures coordinates stay at 0 when outside the window, 
    // preventing potential floating wire issues or unexpected memory reads.
    assign nes_x = is_within_nes_window ? ((pixel_x - H_OFFSET) >> 1) : 8'd0;
    assign nes_y = is_within_nes_window ? ((pixel_y - V_OFFSET) >> 1) : 8'd0;

endmodule
