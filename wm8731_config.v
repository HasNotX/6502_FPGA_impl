module wm8731_config (
    input  wire clk_50mhz,
    input  wire reset,
    output reg  i2c_sclk,
    inout  wire i2c_sdat
);

    // ── Configuration ROM ─────────────────────────────────────────
    reg [15:0] rom [0:8];
    initial begin
        rom[0] = 16'h1200; // R9: Disable interface
        rom[1] = 16'h0C00; // R6: Power On all (except Mic/Line)
        rom[2] = 16'h0E02; // R7: Digital Audio Format -> I2S, 16-bit
        rom[3] = 16'h0812; // R4: Audio Path -> DAC selected, Mic muted
        rom[4] = 16'h0A00; // R5: Digital Path -> Disable soft mute
        rom[5] = 16'h1000; // R8: Sample Rate -> Normal mode, 256fs
        rom[6] = 16'h047F; // R2: Left Headphone Volume -> Max (0dB)
        rom[7] = 16'h067F; // R3: Right Headphone Volume -> Max (0dB)
        rom[8] = 16'h1201; // R9: Enable interface
    end

    // ── I2C Timing Generator (~50 kHz) ────────────────────────────
    reg [9:0] timer;
    always @(posedge clk_50mhz) timer <= timer + 1'b1;
    wire tick = (timer == 10'd0); 

    // ── State Machine ─────────────────────────────────────────────
    reg [1:0]  phase;
    reg [5:0]  bit_idx;
    reg [3:0]  cmd_idx;
    reg [23:0] shift_reg;
    reg        sda_out;

    // Open-drain driver for I2C data line
    assign i2c_sdat = sda_out ? 1'bz : 1'b0;

    reg [2:0] state;
    localparam IDLE  = 0, START = 1, DATA  = 2, ACK = 3, STOP  = 4, DONE = 5;

    always @(posedge clk_50mhz) begin
        if (reset) begin
            state    <= IDLE;
            cmd_idx  <= 0;
            i2c_sclk <= 1;
            sda_out  <= 1;
            phase    <= 0;
        end else if (tick) begin
            case (state)
                IDLE: begin
                    if (cmd_idx < 9) begin
                        shift_reg <= {8'h34, rom[cmd_idx]}; // Append Device ID
                        bit_idx   <= 0;
                        phase     <= 0;
                        state     <= START;
                    end else begin
                        state     <= DONE;
                    end
                end
                
                START: begin
                    case (phase)
                        0: begin sda_out <= 1; i2c_sclk <= 1; phase <= 1; end
                        1: begin sda_out <= 0; i2c_sclk <= 1; phase <= 2; end // START condition
                        2: begin sda_out <= 0; i2c_sclk <= 0; phase <= 0; state <= DATA; end
                    endcase
                end
                
                DATA: begin
                    case (phase)
                        0: begin sda_out <= shift_reg[23]; i2c_sclk <= 0; phase <= 1; end // Setup Data
                        1: begin i2c_sclk <= 1; phase <= 2; end                           // SCL High
                        2: begin 
                            i2c_sclk  <= 0;                                               // SCL Low
                            phase     <= 0; 
                            shift_reg <= {shift_reg[22:0], 1'b0};
                            bit_idx   <= bit_idx + 1'b1;
                            
                            if (bit_idx == 7 || bit_idx == 15 || bit_idx == 23)
                                state <= ACK;
                        end
                    endcase
                end
                
                ACK: begin
                    case (phase)
                        0: begin sda_out <= 1; i2c_sclk <= 0; phase <= 1; end // Release SDA for ACK
                        1: begin i2c_sclk <= 1; phase <= 2; end               // SCL High
                        2: begin 
                            i2c_sclk <= 0;                                    // SCL Low
                            phase    <= 0;
                            if (bit_idx == 24) state <= STOP;
                            else               state <= DATA;
                        end
                    endcase
                end
                
                STOP: begin
                    case (phase)
                        0: begin sda_out <= 0; i2c_sclk <= 0; phase <= 1; end
                        1: begin sda_out <= 0; i2c_sclk <= 1; phase <= 2; end
                        2: begin 
                            sda_out  <= 1; i2c_sclk <= 1; phase <= 0;         // STOP condition
                            cmd_idx  <= cmd_idx + 1'b1;
                            state    <= IDLE;
                        end
                    endcase
                end
                
                DONE: begin
                    sda_out  <= 1;
                    i2c_sclk <= 1;
                end
            endcase
        end
    end
endmodule