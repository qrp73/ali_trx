// audio_I2S.v

//
//  HPSDR - High Performance Software Defined Radio
//
//  Angelia code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// (C) Phil Harman VK6PH - 2014 

/*

		LRCLK    ---------------+													   +-----------------------------------------+
										|													   |														|
										+-----------------------------------------+														+-----

		BCLK      --+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+
					   |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
					   +--+  +--+  +--+  +--+  +--+  +  +  +--+  +--+  +  +  +--+  +--+  +--+  +  +  +--+  +--+  +  +  +--+  +--

		DIN       --------------------+-----+-----+-- --+-----+-----+ --    ----+-----+-- --+-----+-----+-----+------
		(data bit)							| 31  | 30  |  // |  17 |  16 |  15 //    | 15  | 14  |     |  1  |  0  |
					 --------------------+-----+-----+-- --+-----+-----+ --    ----+-----+-----+-- --+-----+-----+------
												<-----------  left channel ---------------><----------- right channel --------------> 
												
								+-----+																										+-----+
								|	   |																										|     |
		get_data	---------+		+-----------------------------------------------------------------------------+	   +-----------------  				
												
												
												
		TLV320 is in slave, I2S mode.
		
		NOTE:  BCLK in PLL_IF is set at 180 degrees so that LRCLK changes on negative edge to comply with I2S format 					 
					 
*/

// 

module audio_I2S 
	( 
		input [31:0]data_in,
		input empty,
		input BCLK,
		input LRCLK,
		output get_data,
		output reg data_out	
	);
	
	
reg [4:0] state;
reg [4:0] data_count;
reg shift = 0;

always @ (posedge BCLK)
begin 
	if(!empty)		// only run code if fifo has data available
	begin
		case (state)

		0:	begin
				if (LRCLK) state <= 1;		// loop until LRCLK is high
			end 
			
		1:  begin 
				if (!LRCLK) begin 		// loop until LRCLK is low
					shift <= 1;
					data_count <= 5'd31;
					state <= 2;
				end
			end
			
		2: begin
				if (data_count == 16) begin 
					shift <= 0;
					if(LRCLK) begin 
						data_count <= 15;
						shift <= 1;
						state <= 3;
					end 			
				end 
				else begin
					data_count <= data_count - 5'd1;
				end
			end
			
		3:	begin 
				if (data_count == 0) begin
					shift <= 0;
					state <= 0;
				end
				else data_count <= data_count - 5'd1;
			end 
			
		default: state <= 0;
		endcase
	end 
end 

// clock data out on negedge of BCLK so it can be read on postive edge by TLV320	
// request data just before falling edge of LRCLK 
reg [5:0] get_count;		
always @ (negedge BCLK)
begin 
		if (shift) data_out <= data_in[data_count];
		else data_out <= 0;
		if (!LRCLK) get_count <= 0;
		else get_count <= get_count + 6'd1;
end 
			
assign get_data = (get_count == 6'd30); //  & !empty);  // only request data if fifo is not empty
			
			
endmodule
	