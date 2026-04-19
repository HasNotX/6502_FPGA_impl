module bresenham_fsm (
    input  wire        clk,
    input  wire        reset,
    input  wire        draw_req,
    input  wire [7:0]  cx_in,         // NEW: Dynamic X center
    input  wire [6:0]  cy_in,         // NEW: Dynamic Y center
    input  wire [5:0]  radius_in,     
    input  wire [2:0]  color_in,      
    
    output wire [14:0] ram_addr,
    output wire [2:0]  ram_data,
    output wire        ram_wren,
    output wire [3:0]  fsm_state_out
);

    localparam S_CLEAR_INIT = 4'd0,
               S_CLEAR_LOOP = 4'd1,
               S_IDLE       = 4'd2,
               S_INIT       = 4'd3,
               S_DRAW_1     = 4'd4,
               S_DRAW_2     = 4'd5,
               S_DRAW_3     = 4'd6,
               S_DRAW_4     = 4'd7,
               S_DRAW_5     = 4'd8,
               S_DRAW_6     = 4'd9,
               S_DRAW_7     = 4'd10,
               S_DRAW_8     = 4'd11,
               S_UPDATE     = 4'd12;

    reg [3:0] current_state;
    reg [3:0] next_state;
    
    assign fsm_state_out = current_state;

    reg dp_clear_req;
    reg dp_init_req;
    reg dp_update_req;
    reg [2:0] dp_octant_sel;
    reg dp_wren;

    wire dp_clear_done;
    wire dp_draw_done;

    always @(posedge clk or posedge reset) begin
        if (reset)
            current_state <= S_CLEAR_INIT;
        else
            current_state <= next_state;
    end

    always @(*) begin
        next_state    = current_state;
        dp_clear_req  = 1'b0;
        dp_init_req   = 1'b0;
        dp_update_req = 1'b0;
        dp_octant_sel = 3'd0;
        dp_wren       = 1'b0;

        case (current_state)
            S_CLEAR_INIT: begin
                dp_clear_req = 1'b1;
                next_state = S_CLEAR_LOOP;
            end
            
            S_CLEAR_LOOP: begin
                dp_wren = 1'b1;
                if (dp_clear_done)
                    next_state = S_IDLE;
            end

            S_IDLE: begin
                if (draw_req) begin
                    dp_init_req = 1'b1;
                    next_state = S_DRAW_1;
                end
            end

            S_DRAW_1: begin dp_wren = 1'b1; dp_octant_sel = 3'd0; next_state = S_DRAW_2; end
            S_DRAW_2: begin dp_wren = 1'b1; dp_octant_sel = 3'd1; next_state = S_DRAW_3; end
            S_DRAW_3: begin dp_wren = 1'b1; dp_octant_sel = 3'd2; next_state = S_DRAW_4; end
            S_DRAW_4: begin dp_wren = 1'b1; dp_octant_sel = 3'd3; next_state = S_DRAW_5; end
            S_DRAW_5: begin dp_wren = 1'b1; dp_octant_sel = 3'd4; next_state = S_DRAW_6; end
            S_DRAW_6: begin dp_wren = 1'b1; dp_octant_sel = 3'd5; next_state = S_DRAW_7; end
            S_DRAW_7: begin dp_wren = 1'b1; dp_octant_sel = 3'd6; next_state = S_DRAW_8; end
            
            S_DRAW_8: begin 
                dp_wren = 1'b1; 
                dp_octant_sel = 3'd7; 
                next_state = S_UPDATE; 
            end

            S_UPDATE: begin
                dp_update_req = 1'b1;
                if (dp_draw_done)
                    next_state = S_IDLE;
                else
                    next_state = S_DRAW_1;
            end
            
            default: next_state = S_CLEAR_INIT;
        endcase
    end

    reg signed [15:0] x, y, d;
    reg [7:0] cx, cy;
    reg [2:0] current_color;
    
    reg [7:0] clear_x;
    reg [6:0] clear_y;
    
    assign dp_clear_done = (clear_x == 8'd159) && (clear_y == 7'd119);
    assign dp_draw_done  = (x > y);

    reg [7:0] plot_x;
    reg [6:0] plot_y;
    
    always @(*) begin
        if (current_state == S_CLEAR_LOOP) begin
            plot_x = clear_x;
            plot_y = clear_y;
        end else begin
            case (dp_octant_sel)
                3'd0: begin plot_x = cx + x[7:0]; plot_y = cy + y[6:0]; end
                3'd1: begin plot_x = cx - x[7:0]; plot_y = cy + y[6:0]; end
                3'd2: begin plot_x = cx + x[7:0]; plot_y = cy - y[6:0]; end
                3'd3: begin plot_x = cx - x[7:0]; plot_y = cy - y[6:0]; end
                3'd4: begin plot_x = cx + y[7:0]; plot_y = cy + x[6:0]; end
                3'd5: begin plot_x = cx - y[7:0]; plot_y = cy + x[6:0]; end
                3'd6: begin plot_x = cx + y[7:0]; plot_y = cy - x[6:0]; end
                3'd7: begin plot_x = cx - y[7:0]; plot_y = cy - x[6:0]; end
            endcase
        end
    end

    assign ram_addr = (plot_y * 160) + plot_x;
    assign ram_data = (current_state == S_CLEAR_LOOP) ? 3'b000 : current_color;
    assign ram_wren = dp_wren;

    always @(posedge clk) begin
        if (dp_clear_req) begin
            clear_x <= 8'd0;
            clear_y <= 7'd0;
        end else if (current_state == S_CLEAR_LOOP) begin
            if (clear_x == 8'd159) begin
                clear_x <= 8'd0;
                clear_y <= clear_y + 1'b1;
            end else begin
                clear_x <= clear_x + 1'b1;
            end
        end

        if (dp_init_req) begin
            cx <= cx_in; // Dynamically latch X
            cy <= cy_in; // Dynamically latch Y
            x  <= 16'sd0;
            
            if (radius_in > 6'd59) begin
                y <= 16'sd59;
                d <= 3 - (2 * 59);
            end else begin
                y <= {10'b0, radius_in}; 
                d <= 3 - (2 * {10'b0, radius_in});
            end
            
            current_color <= color_in;
        end

        if (dp_update_req) begin
            if (d < 0) begin
                d <= d + (4 * x) + 6;
            end else begin
                d <= d + (4 * (x - y)) + 10;
                y <= y - 1;
            end
            x <= x + 1;
        end
    end

endmodule
