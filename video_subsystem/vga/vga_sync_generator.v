/*
 * File: vga_sync_generator.v
 * Description: Generates standard 640x480@60Hz VGA timing signals.
 */

module vga_sync_generator (
    input  wire        clk,       // 25.175 MHz pixel clock
    input  wire        reset,     // Active high reset
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