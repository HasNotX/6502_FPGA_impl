/*
 * File: oam_dma.v
 * Description: Cycle-accurate OAM DMA Controller.
 * Suspends the CPU and transfers 256 bytes to PPU OAM ($2004) when $4014 is written.
 */

module oam_dma (
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_ce,        // The 1.789 MHz heartbeat
    
    // CPU Interface (Snooping for $4014 trigger)
    input  wire [15:0] cpu_addr_in,
    input  wire [7:0]  cpu_data_in,
    input  wire        cpu_write_en,
    
    // DMA Output Interface (Taking over the bus)
    output reg         dma_active,    // Used to halt the CPU
    output reg  [15:0] dma_addr_out,
    output reg  [7:0]  dma_data_out,
    output reg         dma_read_en,
    output reg         dma_write_en,
    
    // Memory Data Input (Data read from system RAM/ROM)
    input  wire [7:0]  mem_data_in
);

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_HALT  = 2'd1;
    localparam STATE_READ  = 2'd2;
    localparam STATE_WRITE = 2'd3;

    reg [1:0] state;
    reg [7:0] page;
    reg [7:0] offset;
    reg       cpu_cycle_parity; // Tracks even/odd CPU cycles

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= STATE_IDLE;
            dma_active       <= 1'b0;
            dma_addr_out     <= 16'd0;
            dma_data_out     <= 8'd0;
            dma_read_en      <= 1'b0;
            dma_write_en     <= 1'b0;
            page             <= 8'd0;
            offset           <= 8'd0;
            cpu_cycle_parity <= 1'b0;
        end else begin
            
            // Toggle parity strictly on the CPU heartbeat
            if (cpu_ce) begin
                cpu_cycle_parity <= ~cpu_cycle_parity;
            end
            
            // The DMA engine also strictly advances on the 1.789 MHz CPU heartbeat
            if (cpu_ce) begin
                case (state)
                    STATE_IDLE: begin
                        dma_active   <= 1'b0;
                        dma_read_en  <= 1'b0;
                        dma_write_en <= 1'b0;
                        
                        // Trigger condition: CPU writes to $4014
                        if (cpu_write_en && cpu_addr_in == 16'h4014) begin
                            page       <= cpu_data_in;
                            offset     <= 8'd0;
                            dma_active <= 1'b1;
                            state      <= STATE_HALT;
                        end
                    end
                    
                    STATE_HALT: begin
                        // DMA aligns to the next even CPU cycle (Dummy read phase)
                        if (cpu_cycle_parity == 1'b1) begin
                            state <= STATE_READ;
                        end
                    end
                    
                    STATE_READ: begin
                        dma_write_en <= 1'b0;
                        dma_addr_out <= {page, offset};
                        dma_read_en  <= 1'b1;
                        state        <= STATE_WRITE;
                    end
                    
                    STATE_WRITE: begin
                        dma_read_en  <= 1'b0;
                        dma_addr_out <= 16'h2004; // PPU OAMDATA register
                        dma_data_out <= mem_data_in; // Route fetched memory data to PPU
                        dma_write_en <= 1'b1;
                        
                        offset <= offset + 1'b1;
                        
                        if (offset == 8'hFF) begin
                            state <= STATE_IDLE; // Transfer complete
                        end else begin
                            state <= STATE_READ; // Fetch next byte
                        end
                    end
                endcase
            end
        end
    end
endmodule