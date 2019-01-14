/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//           Copyright (c) 2013 Phil Harman, VK6APH 
//------------------------------------------------------------------------------

// 2013 Jan 26 - varcic now accepts 2...40 as decimation and CFIR
//               replaced with Polyphase FIR - VK6APH

// 2015 Jan 31 - updated for Hermes-Lite 12bit Steve Haynal KF7O

module receiver(
  input clock,                  //61.44 MHz
  input [5:0] rate,             //48k....384k
  input [31:0] frequency,
  output out_strobe,
  input signed [13:0] in_data,
  output [23:0] out_data_I,
  output [23:0] out_data_Q,
  output signed [17:0] cordic_outdata_I,	// make cordic data available for VNA_SCAN_FPGA
  output signed [17:0] cordic_outdata_Q
  );

  parameter CICRATE;

// gain adjustment, Hermes reduced by 6dB to match previous receiver code.
// Hermes-Lite gain reduced to calibrate QtRadio
wire signed [23:0] out_data_I2;
wire signed [23:0] out_data_Q2;
assign out_data_I = out_data_I2;// <<< 1);
assign out_data_Q = out_data_Q2;// <<< 1);


//------------------------------------------------------------------------------
//                               cordic
//------------------------------------------------------------------------------

cordic cordic_inst(
  .clock(clock),
  .in_data(in_data),             //14 bit 
  .frequency(frequency),         //32 bit
  .out_data_I(cordic_outdata_I), //18 bit
  .out_data_Q(cordic_outdata_Q)
  );

  


//------------------------------------------------------------------------------
//                     register-based CIC decimator
//------------------------------------------------------------------------------
//I channel
//cic #(.STAGES(5), .DECIMATION(25), .IN_WIDTH(18), .ACC_WIDTH(43), .OUT_WIDTH(24))
//  cic_inst_I1(
//    .clock(clock),
//    .in_strobe(1'b1),
//    .out_strobe(cic_outstrobe_1),
//    .in_data(cordic_outdata_I),
//    .out_data(cic_outdata_I1)
//    );
//
////Q channel
//cic #(.STAGES(5), .DECIMATION(25), .IN_WIDTH(18), .ACC_WIDTH(43), .OUT_WIDTH(24))
//  cic_inst_Q1(
//    .clock(clock),
//    .in_strobe(1'b1),
//    .out_strobe(),
//    .in_data(cordic_outdata_Q),
//    .out_data(cic_outdata_Q1)
//    );
//
//wire cic_outstrobe_1;
//wire signed [23:0] cic_outdata_I1;
//wire signed [23:0] cic_outdata_Q1;
//
//

//////I channel
//varcic #(.STAGES(5), .IN_WIDTH(24), .ACC_WIDTH(51), .OUT_WIDTH(24), .CICRATE(5))
//  varcic_inst_I1(
//    .clock(clock),
//    .in_strobe(cic_outstrobe_1),
//    .decimation(rate),
//    .out_strobe(cic_outstrobe_2),
//    .in_data(cic_outdata_I1),
//    .out_data(cic_outdata_I2)
//    );
//
////Q channel
//varcic #(.STAGES(5), .IN_WIDTH(24), .ACC_WIDTH(51), .OUT_WIDTH(24), .CICRATE(5))
//  varcic_inst_Q1(
//    .clock(clock),
//    .in_strobe(cic_outstrobe_1),
//    .decimation(rate),
//    .out_strobe(),
//    .in_data(cic_outdata_Q1),
//    .out_data(cic_outdata_Q2)
//    );
//
//	 
//	 

//------------------------------------------------------------------------------
//                     register-based CIC decimator
//------------------------------------------------------------------------------
//I channel
cic #(.STAGES(5), .DECIMATION(50), .IN_WIDTH(18), .ACC_WIDTH(47), .OUT_WIDTH(24))
  cic_inst_I1(
    .clock(clock),
    .in_strobe(1'b1),
    .out_strobe(cic_outstrobe_1),
    .in_data(cordic_outdata_I),
    .out_data(cic_outdata_I1)
    );


//Q channel
cic #(.STAGES(5), .DECIMATION(50), .IN_WIDTH(18), .ACC_WIDTH(47), .OUT_WIDTH(24))
  cic_inst_Q1(
    .clock(clock),
    .in_strobe(1'b1),
    .out_strobe(),
    .in_data(cordic_outdata_Q),
    .out_data(cic_outdata_Q1)
    );


wire cic_outstrobe_1;
wire signed [23:0] cic_outdata_I1;
wire signed [23:0] cic_outdata_Q1;

//------------------------------------------------------------------------------
//                       memory-based CIC decimator
//------------------------------------------------------------------------------
memcic #(.STAGES(11), .DECIMATION(5), .ACC_WIDTH(48)) 
  memcic_inst_I(
    .clock(clock),
    .in_strobe(cic_outstrobe_1),
    .out_strobe(cic_outstrobe_2),
    .in_data(cic_outdata_I1),
    .out_data(cic_outdata_I2)
    );


memcic #(.STAGES(11), .DECIMATION(5), .ACC_WIDTH(48)) 
  memcic_inst_Q(
    .clock(clock),
    .in_strobe(cic_outstrobe_1),
    .out_strobe(),
    .in_data(cic_outdata_Q1),
    .out_data(cic_outdata_Q2)
    );


wire cic_outstrobe_2;
wire signed [23:0] cic_outdata_I2;
wire signed [23:0] cic_outdata_Q2;


firX2R2 fir3 (clock, cic_outstrobe_2, cic_outdata_I2, cic_outdata_Q2, out_strobe, out_data_I2, out_data_Q2);


endmodule
