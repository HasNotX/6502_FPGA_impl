module challenge_generator (
    input  wire       clk,
    input  wire       reset,
    input  wire       enable,
    
    output reg        gen_draw_req,
    output reg [7:0]  gen_cx,
    output reg [6:0]  gen_cy,
    output reg [5:0]  gen_radius,
    output reg [2:0]  gen_color
);

    // 16-bit Linear Feedback Shift Register
    reg [15:0] lfsr;
    wire lfsr_feedback = lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3];

    // Delay counter (2.5 million cycles @ 25MHz = ~0.1 seconds)
    reg [23:0] delay_counter;
    localparam DELAY_MAX = 24'd2_500_000;

    // Coordinate Mapping
    // Ensure random X is within 0-159, and random Y is within 0-119
    wire [7:0] rand_x = (lfsr[7:0] > 8'd159) ? lfsr[7:0] - 8'd96 : lfsr[7:0];
    wire [6:0] rand_y = (lfsr[14:8] > 7'd119) ? lfsr[14:8] - 7'd8 : lfsr[14:8];
    
    // Prevent drawing black circles on a black background
    wire [2:0] rand_color = (lfsr[15:13] == 3'b000) ? 3'b111 : lfsr[15:13];
	 //wire [2:0] rand_color = 3'b111; // Draw only white circles (Experimental)

    // Max Radius Calculation (Distance to the closest edge)
    wire [7:0] dist_x_0 = rand_x;
    wire [7:0] dist_x_1 = 8'd159 - rand_x;
    wire [7:0] dist_y_0 = {1'b0, rand_y};
    wire [7:0] dist_y_1 = 8'd119 - {1'b0, rand_y};

    wire [7:0] min_x = (dist_x_0 < dist_x_1) ? dist_x_0 : dist_x_1;
    wire [7:0] min_y = (dist_y_0 < dist_y_1) ? dist_y_0 : dist_y_1;
    wire [7:0] max_rad = (min_x < min_y) ? min_x : min_y;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            lfsr          <= 16'hACE1; // Non-zero seed
            delay_counter <= 24'd0;
            gen_draw_req  <= 1'b0;
            gen_cx        <= 8'd80;
            gen_cy        <= 7'd60;
            gen_radius    <= 6'd0;
            gen_color     <= 3'b111;
        end else if (enable) begin
            if (delay_counter < DELAY_MAX) begin
                delay_counter <= delay_counter + 1'b1;
                gen_draw_req  <= 1'b0;
                // Shift LFSR while waiting
                lfsr <= {lfsr[14:0], lfsr_feedback}; 
            end else begin
                // Lock in the normalized random values
                gen_cx       <= rand_x;
                gen_cy       <= rand_y;
                gen_radius   <= max_rad[5:0];
                gen_color    <= rand_color;
                
                gen_draw_req <= 1'b1; // Trigger the FSM
                delay_counter <= 24'd0;
            end
        end else begin
            // Reset delay if disabled so it starts immediately when toggled
            delay_counter <= 24'd0;
            gen_draw_req  <= 1'b0;
        end
    end

endmodule
