//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
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


//  Sidetone - 2014  (C) Phil Harman VK6PH

/*************************************************************************

The sidetone is generated using an 1000 value sine wave ROM look-up table.
The speed of addressing the ROM sets the tone frequency.

The amplitude of the sine wave is set by multiplying the samples by the 
sidetone_level.  Finaly a raised cosine profile is applied to the leading
and trailing edges of the sine wave. The tone is produced whilst CW_PTT is
active.

**************************************************************************/



module sidetone ( input clock,							// 122.88MHz 
						input [11:0]tone_freq,
						input [7:0]sidetone_level,			// 0 to 0x7F since doing signed multiply
						input CW_PTT,
						input [15:0] profile,
						output signed [15:0]C122_sidetone						
					  );

reg sidetone_clock;
wire [9:0] side_count; 
wire [15:0] sidetone_divide;
wire signed [15:0] prof_sidetone;

// calculate clock for sidetone generator 
//sidetone_divide = (122880000/(1000 * tone_freq))/2 - 1 = (61440/tone_freq) - 1
divide2	divide2_inst (.denom (tone_freq),.numer (48000),.quotient (sidetone_divide));

// generate clock 
always @ (posedge clock)
begin
	if (side_count == (sidetone_divide - 16'd1)) begin
		side_count <= 0;
		sidetone_clock <= ~sidetone_clock;
	end 
	else side_count <= side_count + 10'd1;
end		
		

// generate sine  wave at selected frequency using ROM look-up table		
		
reg [9:0] sine_address;
reg signed [15:0] sine_data;

sine_table sine_table_inst (.address(sine_address), .clock(sidetone_clock), .q(sine_data));
						 
always @ (posedge sidetone_clock)
	begin
		if (CW_PTT)
		begin 
			if (sine_address == 999)
				sine_address <= 0;
			else sine_address <= sine_address + 7'd1;
		end 
		else sine_address <= 0;   // start tone from 0  when key is pressed
	end 

wire [15:0]	C122_profile;

// move  profile into the 122.88MHz clock domain
cdc_sync #(16)	profile2 (.siga(profile), .rstb(), .clkb(clock), .sigb(C122_profile)); 
	
wire signed [15:0] sidetone;

// Since we are using signed values multiply the sidetone vales by 2 to restore full range.
// The max value of the profile has been slected to give the maximum output of the RF DAC taking into account
// the CORDIC gain. If we multiply the profile by 1.75 we can achieve the same max sidetone volume as the PC generated version.

Multiply2	Multiply16x8  (.dataa (sine_data), .datab ({sidetone_level, 8'b0}), .result (sidetone));   	// multiply sidetone by sidetone_level
Multiply2	Multiply16x16 (.dataa (sidetone << 1),  .datab (C122_profile + (C122_profile >> 1) + (C122_profile >> 2)), .result (prof_sidetone));  		// multiply sidetone by raised cosine profile

// move sidetone into 122.88MHz clock domain
cdc_sync #(16)	tone (.siga(prof_sidetone), .rstb(), .clkb(clock), .sigb(C122_sidetone)); 

endmodule
