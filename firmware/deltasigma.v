module SigmaDeltaModulator(in, clk, out);
parameter WIDTH = 16;
input[WIDTH-1:0] in;
input clk;
output out;

reg[WIDTH:0] acc = 0;
assign out = acc[WIDTH];

always @(posedge clk) acc <= acc + in + out - (out << WIDTH);

endmodule