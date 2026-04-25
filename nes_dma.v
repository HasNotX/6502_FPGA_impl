/*
 * File: nes_dma.v
 * Description: Direct Memory Access Controller for OAM transfers.
 * Hijacks the system bus to copy 256 bytes from Work RAM to PPU OAM ($2004).
 */

module nes_dma (
    input  wire        clk,
    input  wire        reset,
    
    input  wire        dma_start,
    input  wire [7:0]  page_in,      
    input  wire [7:0]  ram_data_in,  
    
    output reg         dma_active,
    output reg  [15:0] dma_addr,
    output reg  [7:0]  dma_data_out,
    output reg         dma_we
);

    reg [1:0] state;
    reg [7:0] offset;
    reg [7:0] base_page;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dma_active   <= 1'b0;
            state        <= 2'd0;
            offset       <= 8'd0;
            dma_we       <= 1'b0;
            dma_addr     <= 16'd0;
            dma_data_out <= 8'd0;
        end else begin
            if (!dma_active) begin
                if (dma_start) begin
                    dma_active <= 1'b1;
                    base_page  <= page_in;
                    offset     <= 8'd0;
                    state      <= 2'd1;
                end
            end else begin
                case (state)
                    2'd1: begin 
                        // Phase 1: Set address to read from CPU RAM
                        dma_addr <= {base_page, offset};
                        dma_we   <= 1'b0;
                        state    <= 2'd2;
                    end
                    2'd2: begin 
                        // Phase 2: 1-Cycle Wait for BRAM read latency
                        state    <= 2'd3;
                    end
                    2'd3: begin 
                        // Phase 3: Setup Write to PPU OAM Port
                        dma_addr     <= 16'h2004;
                        dma_data_out <= ram_data_in;
                        dma_we       <= 1'b1;
                        state        <= 2'd0; 
                    end
                    2'd0: begin
                        // Phase 4: Clear Write Enable and Loop
                        dma_we <= 1'b0;
                        if (offset == 8'hFF) begin
                            dma_active <= 1'b0; 
                        end else begin
                            offset <= offset + 8'd1;
                            state  <= 2'd1;
                        end
                    end
                endcase
            end
        end
    end

endmodule