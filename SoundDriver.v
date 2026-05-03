// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

// CLK is 24Mhz. MCLK is divided by two (12Mhz). 24Mhz divide by 16 produces SCLK.
// Divide by 48 produces LRCK.
// produce LRCK = 32kHz. We output 16-bit samples, but internally the DAC
// is in 24-bit mode. SCLK ratio is 48 * 32kHz.
module SoundDriver(input CLK, input [15:0] write_data, input write_left, input write_right,
                   output AUD_MCLK, output AUD_LRCK, output AUD_SCK, output AUD_SDIN);
  reg lrck;
  reg [15:0] leftbuf;
  reg [15:0] rightbuf;
  reg [16:0] currbuf;
  reg [3:0] sclk_div;
  reg [4:0] bitcnt_24;   // Counts 0-23
  wire [4:0] bitcnt_24_new = bitcnt_24 + 1;
  always @(posedge CLK) begin
    sclk_div <= sclk_div + 1;
    
    if (sclk_div == 4'b1111) begin
        currbuf <= {currbuf[15:0], 1'b0};
        bitcnt_24 <= bitcnt_24_new;
        
        if (bitcnt_24_new[4:3] == 2'b11) begin
            bitcnt_24[4:3] <= 2'b00;
            lrck <= !lrck;
            // Only load new data HERE — at the exact moment we flip LRCK
            // This is the only safe moment; mid-frame loads cause tearing
            if (lrck)
                currbuf[15:0] <= leftbuf;
            else
                currbuf[15:0] <= rightbuf;
        end
    end
    
    // Only accept new sample data when we're at the frame boundary
    // write_left/right now act as enables, but we also gate on lrck edge
    if (write_left  && sclk_div == 4'b1111 && bitcnt_24_new[4:3] == 2'b11 && !lrck)
        leftbuf  <= write_data;
    if (write_right && sclk_div == 4'b1111 && bitcnt_24_new[4:3] == 2'b11 && lrck)
        rightbuf <= write_data;
end
  assign AUD_MCLK = sclk_div[0];
  assign AUD_SCK = sclk_div[3]; // BCLK = 25MHz / 16 ≈ 1.5MHz
  assign AUD_SDIN = currbuf[16];
  assign AUD_LRCK = lrck;
  

endmodule