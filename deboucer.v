module debounce (
    input  wire clk,
    input  wire noisy,
    output reg  clean
);
    reg [19:0] count;
    reg        sync;

    always @(posedge clk) begin
        sync <= noisy;
        if (sync == clean)
            count <= 0;
        else begin
            count <= count + 1;
            if (count == 20'hFFFFF)
                clean <= sync;
        end
    end
endmodule