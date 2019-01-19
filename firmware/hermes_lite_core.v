//
//  Hermes Lite
// 
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

// (C) Phil Harman VK6APH, Kirk Weedman KD7IRS  2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014 
// (C) Steve Haynal KF7O 2014, 2015, 2016

// New VNA mode added by James C. Ahlstrom, N2ADR, 1 December 2016

// This is a port of the Hermes project from www.openhpsdr.org to work with
// the Hermes-Lite hardware described at http://github.com/softerhardware/Hermes-Lite.
// It was forked from Hermes V2.5 but kept up to date to v3.1

module hermes_lite_core(

    //input clk50mhz,
    input exp_present,
    input ADC_CLK,
    input IF_locked,
    input IF_CLRCLK,
    input pll_12288,
    input pll_3072,
    input pll_800,
    output [3:0] leds, 
    input [13:0] ADC_in,
    output [13:0] DAC_out,
    input ADC_ready,
    input ADC_ovr,
    output exp_ptt_n,
	 output preamp,
	 output audio_l,
	 output audio_r,
    output [6:0] userout,
    input [2:0] dipsw,
    input ptt_i,
 
    //audio codec (TLV320AIC23B)
    inout AC_IIC_DAT,					// i2c_sda
    output AC_IIC_SCK,					// i2c_scl
    input  AC_ADCDAT,               // Mic data from TLV320  
    output AC_DACDAT,               // RX data to TLV320

    // MII Ethernet PHY
    output [3:0]PHY_TX,
    output PHY_TX_EN,              //PHY Tx enable
    input  PHY_TX_CLOCK,           //PHY Tx data clock
    output PHY_TX_CLOCK_out,       //Output for RGMII
    input  [3:0]PHY_RX,     
    input  RX_DV,                  //PHY has data flag
    input  PHY_RX_CLOCK,           //PHY Rx data clock
    output PHY_RESET_N,  
    inout PHY_MDIO,
    output PHY_MDC

);

// PARAMETERS

// Ethernet Interface
parameter MAC;
parameter IP;
parameter GIGABIT = 0;

// ADC Oscillator
parameter CLK_FREQ = 96000000;

// B57 = 2^57.   M2 = B57/OSC
// 61440000
//localparam M2 = 32'd2345624805; 1501199875
// 61440000-400
//localparam M2 = 32'd2345640077;
//localparam M2 = 32'd1172820039;

localparam M2 = 32'd1501199875;//(CLK_FREQ == 61440000) ? 32'd2345640077 : (CLK_FREQ == 79872000) ? 32'd1804326773 : (CLK_FREQ == 76800000) ? 32'd1876499845 : 32'd1954687338;

// M3 = 2^24 to round as version 2.7
localparam M3 = 32'd16777216;

// Decimation rates
localparam RATE48  = 6'd40;
localparam RATE96  =  RATE48  >> 1;
localparam RATE192 =  RATE96  >> 1;
localparam RATE384 =  RATE192 >> 1;

localparam CICRATE = (CLK_FREQ == 61440000) ? 6'd10 : (CLK_FREQ == 79872000) ? 6'd13 : (CLK_FREQ == 76800000) ? 6'd05 : 6'd08;
//localparam GBITS = (CLK_FREQ == 61440000) ? 30 : (CLK_FREQ == 79872000) ? 31 : (CLK_FREQ == 76800000) ? 31 : 31;
//localparam RRRR = (CLK_FREQ == 61440000) ? 160 : (CLK_FREQ == 79872000) ? 208 : (CLK_FREQ == 76800000) ? 200 : 192;


// VNA Settings for VNA_SCAN_PC
localparam VNATXGAIN = 6'h10;
localparam DUPRXMAXGAIN = 6'h12;
localparam DUPRXMINGAIN = 6'h06;

// Number of Receivers
parameter NR; // number of receivers to implement
wire [7:0]AssignNR;         // IP address read from EEPROM
assign AssignNR = NR;

// Number of transmitters Be very careful when using more than 1 transmitter!
parameter NT = 1;

// Experimental Predistort On=1 Off=0
parameter PREDISTORT = 0;

wire FPGA_PTT;

parameter M_TPD   = 4;
parameter IF_TPD  = 2;

parameter  Hermes_serialno = 8'd32;     // Serial number of this version
localparam Penny_serialno = 8'd00;      // Use same value as equ1valent Penny code 
localparam Merc_serialno = 8'd00;       // Use same value as equivalent Mercury code

localparam RX_FIFO_SZ  = 4096;          // 16 by 4096 deep RX FIFO
localparam TX_FIFO_SZ  = 1024;          // 16 by 1024 deep TX FIFO  
localparam SP_FIFO_SZ = 2048;           // 16 by 8192 deep SP FIFO, was 16384 but wouldn't fit




//--------------------------------------------------------------
// Reset Lines - C122_rst, IF_rst
//--------------------------------------------------------------

wire  IF_rst;
    
assign IF_rst    = (!IF_locked || reset);       // hold code in reset until PLLs are locked & PHY operational

// transfer IF_rst to 122.88MHz clock domain to generate C122_rst
cdc_sync #(1)
    reset_C122 (.siga(IF_rst), .rstb(IF_rst), .clkb(ADC_CLK), .sigb(C122_rst)); // 122.88MHz clock domain reset
    
//---------------------------------------------------------
//      CLOCKS
//---------------------------------------------------------

//wire CLRCLK;
//
//wire C122_cbclk, C122_cbrise, C122_cbfall;
//Hermes_clk_lrclk_gen #(.CLK_FREQ('d96000000)) clrgen (.reset(C122_rst), .CLK_IN(ADC_CLK), .BCLK(C122_cbclk),
//                           .Brise(C122_cbrise), .Bfall(C122_cbfall), .LRCLK(CLRCLK));
//

wire Tx_clock_2;
wire Tx_fifo_rdreq;
wire [10:0] PHY_Tx_rdused;
wire PHY_data_clock;
wire Rx_enable;
wire [7:0] Rx_fifo_data;

wire this_MAC;
wire run;
wire reset;

ethernet #(.MAC(MAC), .IP(IP), .Hermes_serialno(Hermes_serialno)) ethernet_inst (

    //.clk50mhz(clk50mhz),

    // Send to ethernet
    .Tx_clock_2_o(Tx_clock_2),
    .Tx_fifo_rdreq_o(Tx_fifo_rdreq),
    .PHY_Tx_data_i(PHY_Tx_data),
    .PHY_Tx_rdused_i(PHY_Tx_rdused),

    .sp_fifo_rddata_i(sp_fifo_rddata),  
    .sp_data_ready_i(sp_data_ready),
    .sp_fifo_rdreq_o(sp_fifo_rdreq),

    // Receive from ethernet
    .PHY_data_clock_o(PHY_data_clock),
    .Rx_enable_o(Rx_enable),
    .Rx_fifo_data_o(Rx_fifo_data),

    // Status
    .this_MAC_o(this_MAC),
    .run_o(run),
    .IF_rst_i(IF_rst),
    .reset_o(reset),
    .dipsw_i(dipsw[1:0]),
    .AssignNR(AssignNR),

    // MII Ethernet PHY
    .PHY_TX(PHY_TX),
    .PHY_TX_EN(PHY_TX_EN),              //PHY Tx enable
    .PHY_TX_CLOCK(PHY_TX_CLOCK),           //PHY Tx data clock
    .PHY_TX_CLOCK_out(PHY_TX_CLOCK_out),
    .PHY_RX(PHY_RX),     
    .RX_DV(RX_DV),                  //PHY has data flag
    .PHY_RX_CLOCK(PHY_RX_CLOCK),           //PHY Rx data clock
    .PHY_RESET_N(PHY_RESET_N),  
    .PHY_MDIO(PHY_MDIO),
    .PHY_MDC(PHY_MDC)
    );

//---------------------------------------------------------
// 		Set up TLV320 using SPI 
//---------------------------------------------------------

tlv320_i2c TLV (
	.inclk_i2c(pll_800), 
	.CMODE(), 
	.i2c_sda(AC_IIC_DAT), 
	.i2c_scl(AC_IIC_SCK), 
	.boost(IF_Mic_boost), 
	.line(IF_Line_In), 
	.line_in_gain(IF_Line_In_Gain));
	 
	 

//----------------------------------------------------
//   Receive PHY FIFO 
//----------------------------------------------------

/*
                        PHY_Rx_fifo (16k bytes) 
                    
                        ---------------------
      Rx_fifo_data |data[7:0]     wrfull | PHY_wrfull ----> Flash LED!
                        |                        |
        Rx_enable   |wrreq                 |
                        |                         |                                     
    PHY_data_clock  |>wrclk                |
                        ---------------------                               
  IF_PHY_drdy     |rdreq          q[15:0]| IF_PHY_data [swap Endian] 
                       |                          |                             
                    |                rdempty| IF_PHY_rdempty 
                     |                    |                             
             ADC_CLK |>rdclk rdusedw[12:0]|          
                       ---------------------                                
                       |                    |
             IF_rst  |aclr                |                             
                       ---------------------                                
 
 NOTE: the rdempty stays asserted until enough words have been written to the input port to fill an entire word on the 
 output port. Hence 4 writes must take place for this to happen. 
 Also, rdusedw indicates how many 16 bit samples are available to be read. 
 
*/

wire PHY_wrfull;
wire IF_PHY_rdempty;
wire IF_PHY_drdy;


PHY_Rx_fifo PHY_Rx_fifo_inst(.wrclk (PHY_data_clock),.rdreq (IF_PHY_drdy),.rdclk (ADC_CLK),.wrreq(Rx_enable),
                .data (Rx_fifo_data),.q ({IF_PHY_data[7:0],IF_PHY_data[15:8]}), .rdempty(IF_PHY_rdempty),
                .wrfull(PHY_wrfull),.aclr(IF_rst | PHY_wrfull));


                     
                     
//------------------------------------------------
//   SP_fifo  (16384 words) dual clock FIFO
//------------------------------------------------

/*
        The spectrum data FIFO is 16 by 16384 words long on the input.
        Output is in Bytes for easy interface to the PHY code
        NB: The output flags are only valid after a read/write clock has taken place

       
                               SP_fifo
                        ---------------------
          temp_ADC |data[15:0]     wrfull| sp_fifo_wrfull
                        |                        |
    sp_fifo_wrreq   |wrreq       wrempty| sp_fifo_wrempty
                        |                        |
            C122_clk    |>wrclk              | 
                        ---------------------
    sp_fifo_rdreq   |rdreq         q[7:0]| sp_fifo_rddata
                        |                    | 
                        |                        |
        Tx_clock_2  |>rdclk              | 
                        |                      | 
                        ---------------------
                        |                    |
     C122_rst OR   |aclr                |
        !run       |                    |
                        ---------------------
        
*/

wire  sp_fifo_rdreq;
wire [7:0]sp_fifo_rddata;
wire sp_fifo_wrempty;
wire sp_fifo_wrfull;
wire sp_fifo_wrreq;
wire have_sp_data;

//--------------------------------------------------
//   Wideband Spectrum Data 
//--------------------------------------------------

//  When wide_spectrum is set and sp_fifo_wrempty then fill fifo with 16k words 
// of consecutive ADC samples.  Pass have_sp_data to Tx_MAC to indicate that 
// data is available.
// Reset fifo when !run so the data always starts at a known state.

//111
SP_fifo  SPF (.aclr(C122_rst | !run), .wrclk (ADC_CLK), .rdclk(Tx_clock_2), 
            .wrreq (sp_fifo_wrreq), .data ({{2{temp_ADC[13]}},temp_ADC}), .rdreq (sp_fifo_rdreq),
             .q(sp_fifo_rddata), .wrfull(sp_fifo_wrfull), .wrempty(sp_fifo_wrempty));                    
                     
                     
sp_rcv_ctrl SPC (.clk(ADC_CLK), .reset(C122_rst), .sp_fifo_wrempty(sp_fifo_wrempty),
                 .sp_fifo_wrfull(sp_fifo_wrfull), .write(sp_fifo_wrreq), .have_sp_data(have_sp_data));  
                 
// the wideband data is presented too fast for the PC to swallow so slow down 

wire sp_data_ready;

generate
    if (GIGABIT == 0) begin: SLOWTXCLOCK
        // rate is 12.5e6/2**16
        reg [15:0]sp_delay;   
        always @ (posedge Tx_clock_2)
            sp_delay <= sp_delay + 15'd1;
        assign sp_data_ready = (sp_delay == 0 && have_sp_data); 
    end else begin: FASTTXCLOCK
        // rate is 125e6/2**19
        reg [18:0]sp_delay;   
        always @ (posedge Tx_clock_2)
            sp_delay <= sp_delay + 15'd1;
        assign sp_data_ready = (sp_delay == 0 && have_sp_data);     
    end
endgenerate

//assign IF_mic_Data = 0;


reg [13:0]temp_ADC;

wire rxclipp = (temp_ADC == 14'b01111111111111);
wire rxclipn = (temp_ADC == 14'b10000000000000);

// Near clips occur just over 1 dB from full range
// 2**12 = 4096
// (6.02*12)+1.76 = 74
// 2**11.8074 = 3584
// 4096-3584 = 512 (256 from positive and 256 from negtive clips)
// (6.02*11.8074)+1.76 = 72.84
// 74 - 72.84 = ~1.16 dB from full range
wire rxnearclip = (temp_ADC[13:10] == 4'b0111) | (temp_ADC[13:10] == 4'b1000);



assign exp_ptt_n = FPGA_PTT;
assign userout = IF_OC;

always @ (posedge ADC_ready)temp_ADC <= ADC_in;


//reg [3:0] incnt;
//always @ (posedge ADC_CLK)
//  begin
//			// Test sine wave
//        case (incnt)
//            4'h0 : temp_ADC = 12'h000;
//            4'h1 : temp_ADC = 12'hfcb;
//            4'h2 : temp_ADC = 12'hf9f;
//            4'h3 : temp_ADC = 12'hf81;
//            4'h4 : temp_ADC = 12'hf76;
//            4'h5 : temp_ADC = 12'hf81;
//            4'h6 : temp_ADC = 12'hf9f;
//            4'h7 : temp_ADC = 12'hfcb;
//            4'h8 : temp_ADC = 12'h000;
//            4'h9 : temp_ADC = 12'h035;
//            4'ha : temp_ADC = 12'h061;
//            4'hb : temp_ADC = 12'h07f;
//            4'hc : temp_ADC = 12'h08a;
//            4'hd : temp_ADC = 12'h07f;
//            4'he : temp_ADC = 12'h061;
//            4'hf : temp_ADC = 12'h035;
//        endcase
//		incnt <= incnt + 4'h1; 
//	end
  
wire [31:0] Rx_audio;

//`define AC_GENERATOR

`ifndef AC_GENERATOR

assign Rx_audio = CW_PTT && (sidetone_level != 0) ? {C122_sidetone, C122_sidetone}  : {IF_Left_Data,IF_Right_Data}; 

`else 	//AC_GENERATOR
reg [15:0] snd_sample;
reg [4:0] snd_index;
always @(negedge IF_CLRCLK) begin
	snd_index <= snd_index + 1;
end
always @(posedge IF_CLRCLK) begin
	case (snd_index)
//		// 1500 Hz
//		5'h00: snd_sample <= 16'h0000;
//		5'h01: snd_sample <= 16'h18f8;
//		5'h02: snd_sample <= 16'h30fb;
//		5'h03: snd_sample <= 16'h471c;
//		5'h04: snd_sample <= 16'h5a81;
//		5'h05: snd_sample <= 16'h6a6c;
//		5'h06: snd_sample <= 16'h7640;
//		5'h07: snd_sample <= 16'h7d89;
//		5'h08: snd_sample <= 16'h7fff;
//		5'h09: snd_sample <= 16'h7d89;
//		5'h0a: snd_sample <= 16'h7640;
//		5'h0b: snd_sample <= 16'h6a6c;
//		5'h0c: snd_sample <= 16'h5a81;
//		5'h0d: snd_sample <= 16'h471c;
//		5'h0e: snd_sample <= 16'h30fb;
//		5'h0f: snd_sample <= 16'h18f8;
//		5'h10: snd_sample <= 16'h0000;
//		5'h11: snd_sample <= 16'he708;
//		5'h12: snd_sample <= 16'hcf05;
//		5'h13: snd_sample <= 16'hb8e4;
//		5'h14: snd_sample <= 16'ha57f;
//		5'h15: snd_sample <= 16'h9594;
//		5'h16: snd_sample <= 16'h89c0;
//		5'h17: snd_sample <= 16'h8277;
//		5'h18: snd_sample <= 16'h8001;
//		5'h19: snd_sample <= 16'h8277;
//		5'h1a: snd_sample <= 16'h89c0;
//		5'h1b: snd_sample <= 16'h9594;
//		5'h1c: snd_sample <= 16'ha57f;
//		5'h1d: snd_sample <= 16'hb8e4;
//		5'h1e: snd_sample <= 16'hcf05;
//		5'h1f: snd_sample <= 16'he708;		

		// 1500 + 3000 Hz
		5'h00: snd_sample <= 16'h0000;
		5'h01: snd_sample <= 16'h24f9;
		5'h02: snd_sample <= 16'h45be;
		5'h03: snd_sample <= 16'h5eae;
		5'h04: snd_sample <= 16'h6d40;
		5'h05: snd_sample <= 16'h7056;
		5'h06: snd_sample <= 16'h6861;
		5'h07: snd_sample <= 16'h5742;
		5'h08: snd_sample <= 16'h3fff;
		5'h09: snd_sample <= 16'h2647;
		5'h0a: snd_sample <= 16'h0ddf;
		5'h0b: snd_sample <= 16'hfa17;
		5'h0c: snd_sample <= 16'hed42;
		5'h0d: snd_sample <= 16'he86e;
		5'h0e: snd_sample <= 16'heb3d;
		5'h0f: snd_sample <= 16'hf3ff;
		5'h10: snd_sample <= 16'h0000;
		5'h11: snd_sample <= 16'h0c01;
		5'h12: snd_sample <= 16'h14c3;
		5'h13: snd_sample <= 16'h1792;
		5'h14: snd_sample <= 16'h12be;
		5'h15: snd_sample <= 16'h05e9;
		5'h16: snd_sample <= 16'hf221;
		5'h17: snd_sample <= 16'hd9b9;
		5'h18: snd_sample <= 16'hc001;
		5'h19: snd_sample <= 16'ha8be;
		5'h1a: snd_sample <= 16'h979f;
		5'h1b: snd_sample <= 16'h8faa;
		5'h1c: snd_sample <= 16'h92c0;
		5'h1d: snd_sample <= 16'ha152;
		5'h1e: snd_sample <= 16'hba42;
		5'h1f: snd_sample <= 16'hdb07;		
		
		default: snd_sample <= 16'h0000;
	endcase
end
assign Rx_audio = {snd_sample,snd_sample}; 
`endif	//AC_GENERATOR


//---------------------------------------------------------
//		Send L/R audio to TLV320 in I2S format
//---------------------------------------------------------
             
// send receiver audio to TLV320 in I2S format
audio_I2S audio_I2S_inst (
	.BCLK(pll_3072), 
	.empty(), 
	.LRCLK(IF_CLRCLK), 
	.data_in(Rx_audio), 
	.data_out(AC_DACDAT), 
	.get_data()); 	

      
//------------------------------------------------------------------------------
//                 Transfer  Data from IF clock to 122.88MHz clock domain
//------------------------------------------------------------------------------

// cdc_sync is used to transfer from a slow to a fast clock domain

wire  [31:0] C122_LR_data;
wire  C122_DFS0, C122_DFS1;
wire  C122_rst;
wire  signed [15:0] C122_I_PWM;
wire  signed [15:0] C122_Q_PWM;

cdc_sync #(32)
    freq0 (.siga(IF_frequency[0]), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_frequency_HZ_Tx)); // transfer Tx frequency

cdc_sync #(2)
    rates (.siga({IF_DFS1,IF_DFS0}), .rstb(C122_rst), .clkb(ADC_CLK), .sigb({C122_DFS1, C122_DFS0})); // sample rate
    
cdc_sync #(16)
    Tx_I  (.siga(IF_I_PWM), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_I_PWM )); // Tx I data
    
cdc_sync #(16)
    Tx_Q  (.siga(IF_Q_PWM), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_Q_PWM)); // Tx Q data
    
   

reg signed [15:0]C122_cic_i;
reg signed [15:0]C122_cic_q;
wire C122_ce_out_i;
wire C122_ce_out_q; 

//------------------------------------------------------------------------------
//                 Pulse generators
//------------------------------------------------------------------------------

//wire IF_CLRCLK;

//  Create short pulse from posedge of CLRCLK synced to ADC_CLK for RXF read timing
//  First transfer CLRCLK into IF clock domain
//cdc_sync cdc_CRLCLK (.siga(CLRCLK), .rstb(IF_rst), .clkb(ADC_CLK), .sigb(IF_CLRCLK)); 
//  Now generate the pulse
pulsegen cdc_m   (.sig(IF_CLRCLK), .rst(IF_rst), .clk(ADC_CLK), .pulse(IF_get_samples));


//---------------------------------------------------------
//      Convert frequency to phase word 
//---------------------------------------------------------

/*  
     Calculates  ratio = fo/fs = frequency/122.88Mhz where frequency is in MHz
     Each calculation should take no more than 1 CBCLK

     B scalar multiplication will be used to do the F/122.88Mhz function
     where: F * C = R
     0 <= F <= 65,000,000 hz
     C = 1/122,880,000 hz
     0 <= R < 1

     This method will use a 32 bit by 32 bit multiply to obtain the answer as follows:
     1. F will never be larger than 65,000,000 and it takes 26 bits to hold this value. This will
        be a B0 number since we dont need more resolution than 1 Hz - i.e. fractions of a hertz.
     2. C is a constant.  Notice that the largest value we could multiply this constant by is B26
        and have a signed value less than 1.  Multiplying again by B31 would give us the biggest
        signed value we could hold in a 32 bit number.  Therefore we multiply by B57 (26+31).
        This gives a value of M2 = 1,172,812,403 (B57/122880000)
     3. Now if we multiply the B0 number by the B57 number (M2) we get a result that is a B57 number.
        This is the result of the desire single 32 bit by 32 bit multiply.  Now if we want a scaled
        32 bit signed number that has a range -1 <= R < 1, then we want a B31 number.  Thus we shift
        the 64 bit result right 32 bits (B57 -> B31) or merely select the appropriate bits of the
        64 bit result. Sweet!  However since R is always >= 0 we will use an unsigned B32 result
*/

//------------------------------------------------------------------------------
//                 All DSP code is in the Receiver module
//------------------------------------------------------------------------------

reg       [31:0] C122_frequency_HZ [0:NR-1];   // frequency control bits for CORDIC
reg       [31:0] C122_frequency_HZ_Tx;
reg       [31:0] C122_last_freq [0:NR-1];
reg       [31:0] C122_last_freq_Tx;
wire      [31:0] C122_sync_phase_word [0:NR-1];
wire      [31:0] C122_sync_phase_word_Tx;
wire      [63:0] C122_ratio [0:NR-1];
wire      [63:0] C122_ratio_Tx;
wire      [23:0] rx_I [0:NR-1];
wire      [23:0] rx_Q [0:NR-1];
wire             strobe [0:NR-1];
wire		 [31:0] Rx2_phase_word;
wire              IF_IQ_Data_rdy;
wire         [47:0] IF_IQ_Data;
wire             test_strobe3;

// Pipeline for adc fanout
reg [13:0] adcpipe [0:3];
always @ (posedge ADC_CLK) begin
    adcpipe[0] <= temp_ADC;
    adcpipe[1] <= temp_ADC;
//    adcpipe[2] <= temp_ADC;
//    adcpipe[3] <= temp_ADC;
end


// set the decimation rate 40 = 48k.....2 = 960k
    
    reg [5:0] rate;
    
    always @ ({C122_DFS1, C122_DFS0})
    begin 
        case ({C122_DFS1, C122_DFS0})

        0: rate <= RATE48;     //  48ksps 
        1: rate <= RATE96;     //  96ksps
        2: rate <= RATE192;     //  192ksps
        3: rate <= RATE384;      //  384ksps        
        default: rate <= RATE48;        

        endcase
    end 

// This firmware supports two VNA modes: scanning by the PC (original method) and scanning in the FPGA.
// The VNA bit must be turned on for either.  So VNA is one for either method, and zero otherwise.
// The scan method depends on the number of VNA scan points, IF_VNA_count.  This is zero for the original method.
wire VNA_SCAN_PC   = VNA & (IF_VNA_count == 0);
wire VNA_SCAN_FPGA = VNA & (IF_VNA_count != 0);

wire signed [17:0] cordic_data_I, cordic_data_Q;
wire [31:0] rx0_frequency;
wire vna_strobe, rx0_strobe;
wire signed [23:0] vna_out_I, vna_out_Q, rx0_out_I, rx0_out_Q;
wire [15:0] C122_VNA_count;
wire C122_VNA_bit;

assign rx0_frequency = VNA ? C122_phase_word_Tx : C122_sync_phase_word[0];
assign strobe[0] = VNA_SCAN_FPGA ? vna_strobe : rx0_strobe;
assign rx_I[0] = VNA_SCAN_FPGA ? vna_out_I : rx0_out_I;
assign rx_Q[0] = VNA_SCAN_FPGA ? vna_out_Q : rx0_out_Q;

cdc_sync #(16)
    vna_cnt  (.siga(IF_VNA_count), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_VNA_count));

cdc_sync #(1)
    vna_bit  (.siga(VNA), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_VNA_bit));

vna_scanner #(.CICRATE(CICRATE), .RATE48(RATE48)) rx_vna (	// use this output for VNA_SCAN_FPGA
    //control
    .clock(ADC_CLK),
    .freq_delta(C122_sync_phase_word[0]),
    .output_strobe(vna_strobe),
    //input
    .cordic_data_I(cordic_data_I),
    .cordic_data_Q(cordic_data_Q),
    //output
    .out_data_I(vna_out_I),
    .out_data_Q(vna_out_Q),
    // VNA mode data
    .vna(C122_VNA_bit),
    .Tx_frequency_in(C122_sync_phase_word_Tx),
    .Tx_frequency_out(C122_phase_word_Tx),
    .vna_count(C122_VNA_count)
    );

// create the first receiver

cdc_mcp #(48)           // Transfer the receiver data and strobe from ADC_CLK to ADC_CLK
        IQ_sync0 (.a_data ({rx_I[0], rx_Q[0]}), .a_clk(ADC_CLK),.b_clk(ADC_CLK), .a_data_rdy(strobe[0]),
                .a_rst(C122_rst), .b_rst(IF_rst), .b_data(IF_M_IQ_Data[0]), .b_data_ack(IF_M_IQ_Data_rdy[0]));

// transfer Rx1 frequency to the receiver clock ADC_CLK
cdc_sync #(32)
        freqRx0 (.siga(IF_frequency[1]), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_frequency_HZ[0]));
assign C122_sync_phase_word[0] = C122_frequency_HZ[0];

receiver #(.CICRATE(CICRATE)) receiver_inst0 (	// This first receiver is used for transceiver and VNA_SCAN_PC.
    //control
    .clock(ADC_CLK),
    .rate(rate),
    .frequency(rx0_frequency),
    .out_strobe(rx0_strobe),
    //input
    .in_data(adcpipe[0]),
    //output
    .out_data_I(rx0_out_I),
    .out_data_Q(rx0_out_Q),
    .cordic_outdata_I(cordic_data_I),
    .cordic_outdata_Q(cordic_data_Q)
    );

assign C122_sync_phase_word[1] = C122_frequency_HZ[1];


cdc_mcp #(48)           // Transfer the receiver data and strobe from AD9866clkX1 to IF_clk
        IQ_sync (.a_data ({rx_I[1], rx_Q[1]}), .a_clk(ADC_CLK),.b_clk(ADC_CLK), .a_data_rdy(strobe[1]),
                .a_rst(C122_rst), .b_rst(IF_rst), .b_data(IF_M_IQ_Data[1]), .b_data_ack(IF_M_IQ_Data_rdy[1]));

//assign phase word for Rx2 depending upon whether common_Merc_freq is asserted
assign Rx2_phase_word = common_Merc_freq ? C122_sync_phase_word[0] : C122_sync_phase_word[1];					 
					 
receiver #(.CICRATE(CICRATE)) receiver_inst (	// This first receiver is used for transceiver and VNA_SCAN_PC.
    //control
    .clock(ADC_CLK),
    .rate(rate),
    .frequency(FPGA_PTT ? C122_sync_phase_word[0] : Rx2_phase_word),
    .out_strobe(strobe[1]),
    //input
    .in_data(FPGA_PTT ? C122_cordic_i_out[14:1] : adcpipe[1]),
    //output
    .out_data_I(rx_I[1]),
    .out_data_Q(rx_Q[1])
    );

cdc_sync #(32)
        freq (.siga(IF_frequency[2]), .rstb(C122_rst), .clkb(ADC_CLK), .sigb(C122_frequency_HZ[1])); 

assign C122_sync_phase_word_Tx = C122_frequency_HZ_Tx;



//---------------------------------------------------------
//    ADC SPI interface 
//---------------------------------------------------------

wire [11:0] AIN1;
wire [11:0] AIN2;
wire [11:0] AIN3;
wire [11:0] AIN4;
wire [11:0] AIN5;  // holds 12 bit ADC value of Forward Power detector.
wire [11:0] AIN6;  // holds 12 bit ADC of 13.8v measurement 

//Hermes_ADC ADC_SPI(.clock(C122_cbclk), .SCLK(ADCCLK), .nCS(nADCCS), .MISO(ADCMISO), .MOSI(ADCMOSI),
//                   .AIN1(AIN1), .AIN2(AIN2), .AIN3(AIN3), .AIN4(AIN4), .AIN5(AIN5), .AIN6(AIN6));   

assign AIN1 = 0;
assign AIN2 = 0;
assign AIN3 = 0;
assign AIN4 = 0;
assign AIN5 =  200;
assign AIN6 = 1000;
    
wire [15:0] CW_RF;
wire [15:0] profile;
wire CW_PTT, CWX;
assign  CWX = (IF_I_PWM[0] & internal_CW);
profile profile_sidetone (.clock(IF_CLRCLK), .CW_char(CWX), .profile(profile),  .delay(8'd0));
profile profile_CW       (.clock(IF_CLRCLK), .CW_char(CWX), .profile(CW_RF),    .delay(RF_delay), .hang(hang), .PTT(CW_PTT));

wire signed [15:0] C122_sidetone;
sidetone sidetone_inst( .clock(ADC_CLK), .tone_freq(tone_freq), .sidetone_level(sidetone_level), .CW_PTT(CW_PTT),
                        .C122_sidetone(C122_sidetone),  .profile(profile));	

//reg IF_Filter;
//reg IF_Tuner;
//reg IF_autoTune;

//---------------------------------------------------------
//                 Transmitter code 
//--------------------------------------------------------- 

/* 
    The gain distribution of the transmitter code is as follows.
    Since the CIC interpolating filters do not interpolate by 2^n they have an overall loss.
    
    The overall gain in the interpolating filter is ((RM)^N)/R.  So in this case its 2560^4.
    This is normalised by dividing by ceil(log2(2560^4)).
    
    In which case the normalized gain would be (2560^4)/(2^46) = .6103515625
    
    The CORDIC has an overall gain of 1.647.
    
    Since the CORDIC takes 16 bit I & Q inputs but output needs to be truncated to 14 bits, in order to
    interface to the DAC, the gain is reduced by 1/4 to 0.41175
    
    We need to be able to drive to DAC to its full range in order to maximise the S/N ratio and 
    minimise the amount of PA gain.  We can increase the output of the CORDIC by multiplying it by 4.
    This is simply achieved by setting the CORDIC output width to 16 bits and assigning bits [13:0] to the DAC.
    
    The gain distripution is now:
    
    0.61 * 0.41174 * 4 = 1.00467 
    
    This means that the DAC output will wrap if a full range 16 bit I/Q signal is received. 
    This can be prevented by reducing the output of the CIC filter.
    
    If we subtract 1/128 of the CIC output from itself the level becomes
    
    1 - 1/128 = 0.9921875
    
    Hence the overall gain is now 
    
    0.61 * 0.9921875 * 0.41174 * 4 = 0.996798
    

*/  

reg signed [15:0]C122_fir_i;
reg signed [15:0]C122_fir_q;

// latch I&Q data on strobe from FIR
always @ (posedge ADC_CLK)
begin 
    if (req1) begin 
        C122_fir_i = C122_I_PWM;
        C122_fir_q = C122_Q_PWM;    
    end 
end 


// Interpolate I/Q samples from 48 kHz to the clock frequency

wire req1, req2;
wire [19:0] y1_r, y1_i; 
wire [15:0] y2_r, y2_i;

FirInterp8_1024 fi (ADC_CLK, req2, req1, C122_fir_i, C122_fir_q, y1_r, y1_i);  // req2 enables an output sample, req1 requests next input sample.

// GBITS reduced to 30
CicInterpM5 #(.RRRR(250), .IBITS(20), .OBITS(16), .GBITS(32)) in2 ( ADC_CLK, 1'd1, req2, y1_r, y1_i, y2_r, y2_i);



//---------------------------------------------------------
//    CORDIC NCO 
//---------------------------------------------------------

// Code rotates input at set frequency and produces I & Q 

wire signed [14:0] C122_cordic_i_out;
wire signed [14:0] C122_cordic_q_out;
wire signed [31:0] C122_phase_word_Tx;

wire signed [15:0] I;
wire signed [15:0] Q;

//assign                  I = VNA ? 16'd1927 : y2_i;    // select VNA mode if active. Set CORDIC for max DAC output
//assign                  Q = VNA  ? 0 : y2_r;                   // taking into account CORDICs gain i.e. 0x7FFF/1.7

assign                  I = (VNA ) ? 16'd19274 : (CW_PTT ? CW_RF : y2_i);   	// select VNA, EER or CW mode if active. Set CORDIC for max DAC output
assign                  Q = (VNA | CW_PTT)  ? 16'd0 : y2_r; 					// taking into account CORDICs gain i.e. 0x7FFF/1.7


 
// NOTE:  I and Q inputs reversed to give correct sideband out 
 
cpl_cordic #(.OUT_WIDTH(16))
        cordic_inst (.clock(ADC_CLK), .frequency(C122_phase_word_Tx), .in_data_I(I),            
        .in_data_Q(Q), .out_data_I(C122_cordic_i_out), .out_data_Q(C122_cordic_q_out));      
                 
/* 
  We can use either the I or Q output from the CORDIC directly to drive the DAC.

    exp(jw) = cos(w) + j sin(w)

  When multplying two complex sinusoids f1 and f2, you get only f1 + f2, no
  difference frequency.

      Z = exp(j*f1) * exp(j*f2) = exp(j*(f1+f2))
        = cos(f1 + f2) + j sin(f1 + f2)
*/

// the CORDIC output is stable on the negative edge of the clock

//reg [15:0] DACD;

always @ (negedge ADC_CLK)
    DAC_out <= C122_cordic_i_out[14:1]+14'd8192;






//---------------------------------------------------------
//  Receive DOUT and CDOUT data to put in TX FIFO
//---------------------------------------------------------

wire   [15:0] IF_P_mic_Data;
wire          IF_P_mic_Data_rdy;
wire   [47:0] IF_M_IQ_Data [0:NR-1];
wire [NR-1:0] IF_M_IQ_Data_rdy;
wire   [63:0] IF_tx_IQ_mic_data;
reg           IF_tx_IQ_mic_rdy;
wire   [15:0] IF_mic_Data;
wire    [4:0] IF_chan;
wire    [2:0] IF_last_chan;

always @*
begin
  if (IF_rst)
    IF_tx_IQ_mic_rdy = 1'b0;
  else 
      IF_tx_IQ_mic_rdy = IF_M_IQ_Data_rdy[0];   // this the strobe signal from the ADC now in IF clock domain
end

assign IF_IQ_Data = IF_M_IQ_Data[IF_chan];

// concatenate the IQ and Mic data to form a 64 bit data word
assign IF_tx_IQ_mic_data = {IF_IQ_Data, IF_mic_Data};  

//----------------------------------------------------------------------------
//		Get mic data from  TLV320 in I2S format and transfer to IF_clk domain
//---------------------------------------------------------------------------- 

      
mic_I2S mic_I2S_inst (
	.clock(pll_3072), 
	.CLRCLK(IF_CLRCLK), 
	.in(AC_ADCDAT), 
	.mic_data(IF_mic_Data), 
	.ready());




//----------------------------------------------------------------------------
//     Tx_fifo Control - creates IF_tx_fifo_wdata and IF_tx_fifo_wreq signals
//----------------------------------------------------------------------------

localparam RFSZ = clogb2(RX_FIFO_SZ-1);  // number of bits needed to hold 0 - (RX_FIFO_SZ-1)
localparam TFSZ = clogb2(TX_FIFO_SZ-1);  // number of bits needed to hold 0 - (TX_FIFO_SZ-1)
localparam SFSZ = clogb2(SP_FIFO_SZ-1);  // number of bits needed to hold 0 - (SP_FIFO_SZ-1)

wire     [15:0] IF_tx_fifo_wdata;           // LTC2208 ADC uses this to send its data to Tx FIFO
wire            IF_tx_fifo_wreq;            // set when we want to send data to the Tx FIFO
wire            IF_tx_fifo_full;
wire [TFSZ-1:0] IF_tx_fifo_used;
wire            IF_tx_fifo_rreq;
wire            IF_tx_fifo_empty;

wire [RFSZ-1:0] IF_Rx_fifo_used;            // read side count
wire            IF_Rx_fifo_full;

wire            clean_dash;                 // debounced dash key
wire            clean_dot;                  // debounced dot key

wire     [11:0] Penny_ALC;

wire   [RFSZ:0] RX_USED;
wire            IF_tx_fifo_clr;

assign RX_USED = {IF_Rx_fifo_full,IF_Rx_fifo_used};


assign Penny_ALC = AIN5; 

wire VNA_start = VNA_SCAN_PC && IF_Rx_save && (IF_Rx_ctrl_0[7:1] == 7'b0000_001);  // indicates a frequency change for the VNA.


wire IO4;
wire IO5;
wire IO6;
wire IO8;
wire OVERFLOW;
assign IO4 = 1'b1;
assign IO5 = 1'b1;
assign IO6 = 1'b1;
assign IO8 = 1'b1;

reg OVERFLOW_acc;
reg IF_CLRCLK_prev;
always @ (posedge ADC_CLK)
begin
    IF_CLRCLK_prev <= IF_CLRCLK;
    if (IF_CLRCLK & !IF_CLRCLK_prev) 
        begin
            OVERFLOW <= OVERFLOW_acc;
            OVERFLOW_acc <= ADC_ovr;
        end 
    else
        OVERFLOW_acc <= OVERFLOW_acc | ADC_ovr;
end



Hermes_Tx_fifo_ctrl #(RX_FIFO_SZ, TX_FIFO_SZ) TXFC 
           (IF_rst, ADC_CLK, IF_tx_fifo_wdata, IF_tx_fifo_wreq, IF_tx_fifo_full,
            IF_tx_fifo_used, IF_tx_fifo_clr, IF_tx_IQ_mic_rdy,
            IF_tx_IQ_mic_data, IF_chan, IF_last_chan, clean_dash, clean_dot, (CW_PTT | clean_ptt), OVERFLOW,
            Penny_serialno, Merc_serialno, Hermes_serialno, Penny_ALC, AIN1, AIN2,
            AIN3, AIN4, AIN6, IO4, IO5, IO6, IO8, VNA_start, VNA);

//------------------------------------------------------------------------
//   Tx_fifo  (1024 words) Dual clock FIFO - Altera Megafunction (dcfifo)
//------------------------------------------------------------------------

/*
        Data from the Tx FIFO Controller  is written to the FIFO using IF_tx_fifo_wreq. 
        FIFO is 1024 WORDS long.
        NB: The output flags are only valid after a read/write clock has taken place
        
        
                            --------------------
    IF_tx_fifo_wdata    |data[15:0]      wrful| IF_tx_fifo_full
                           |                         |
    IF_tx_fifo_wreq |wreq            wrempty| IF_tx_fifo_empty
                           |                       |
        ADC_CLK          |>wrclk  wrused[9:0]| IF_tx_fifo_used
                           ---------------------
    Tx_fifo_rdreq       |rdreq         q[7:0]| PHY_Tx_data
                           |                          |
       Tx_clock_2       |>rdclk       rdempty| 
                           |          rdusedw[10:0]| PHY_Tx_rdused  (0 to 2047 bytes)
                           ---------------------
                           |                    |
 IF_tx_fifo_clr OR      |aclr                |
    IF_rst              ---------------------
                
        

*/


Tx_fifo Tx_fifo_inst(.wrclk (ADC_CLK),.rdreq (Tx_fifo_rdreq),.rdclk (Tx_clock_2),.wrreq (IF_tx_fifo_wreq), 
                .data ({IF_tx_fifo_wdata[7:0], IF_tx_fifo_wdata[15:8]}),.q (PHY_Tx_data),.wrusedw(IF_tx_fifo_used), .wrfull(IF_tx_fifo_full),
                .rdempty(),.rdusedw(PHY_Tx_rdused),.wrempty(IF_tx_fifo_empty),.aclr(IF_rst || IF_tx_fifo_clr ));

wire [7:0] PHY_Tx_data;
reg [3:0]sync_TD;
wire PHY_Tx_rdempty;             
             


//---------------------------------------------------------
//   Rx_fifo  (2048 words) single clock FIFO
//---------------------------------------------------------

wire [15:0] IF_Rx_fifo_rdata;
reg         IF_Rx_fifo_rreq;    // controls reading of fifo
wire [15:0] IF_PHY_data;

wire [15:0] IF_Rx_fifo_wdata;
reg         IF_Rx_fifo_wreq;

FIFO #(RX_FIFO_SZ) RXF (.rst(IF_rst), .clk (ADC_CLK), .full(IF_Rx_fifo_full), .usedw(IF_Rx_fifo_used), 
          .wrreq (IF_Rx_fifo_wreq), .data (IF_PHY_data), 
          .rdreq (IF_Rx_fifo_rreq), .q (IF_Rx_fifo_rdata) );


//------------------------------------------------------------
//   Sync and  C&C  Detector
//------------------------------------------------------------

/*

  Read the value of IF_PHY_data whenever IF_PHY_drdy is set.
  Look for sync and if found decode the C&C data.
  Then send subsequent data to Rx FIF0 until end of frame.
    
*/

reg   [2:0] IF_SYNC_state;
reg   [2:0] IF_SYNC_state_next;
reg   [7:0] IF_SYNC_frame_cnt;  // 256-4 words = 252 words
reg   [7:0] IF_Rx_ctrl_0;           // control C0 from PC
reg   [7:0] IF_Rx_ctrl_1;           // control C1 from PC
reg   [7:0] IF_Rx_ctrl_2;           // control C2 from PC
reg   [7:0] IF_Rx_ctrl_3;           // control C3 from PC
reg   [7:0] IF_Rx_ctrl_4;           // control C4 from PC
reg         IF_Rx_save;


localparam SYNC_IDLE   = 1'd0,
           SYNC_START  = 1'd1,
           SYNC_RX_1_2 = 2'd2,
           SYNC_RX_3_4 = 2'd3,
           SYNC_FINISH = 3'd4;

always @ (posedge ADC_CLK)
begin
  if (IF_rst)
    IF_SYNC_state <= #IF_TPD SYNC_IDLE;
  else
    IF_SYNC_state <= #IF_TPD IF_SYNC_state_next;

  if (IF_rst)
    IF_Rx_save <= #IF_TPD 1'b0;
  else
    IF_Rx_save <= #IF_TPD IF_PHY_drdy && (IF_SYNC_state == SYNC_RX_3_4);

  if (IF_PHY_drdy && (IF_SYNC_state == SYNC_START) && (IF_PHY_data[15:8] == 8'h7F))
    IF_Rx_ctrl_0  <= #IF_TPD IF_PHY_data[7:0];

  if (IF_PHY_drdy && (IF_SYNC_state == SYNC_RX_1_2))
  begin
    IF_Rx_ctrl_1  <= #IF_TPD IF_PHY_data[15:8];
    IF_Rx_ctrl_2  <= #IF_TPD IF_PHY_data[7:0];
  end

  if (IF_PHY_drdy && (IF_SYNC_state == SYNC_RX_3_4))
  begin
    IF_Rx_ctrl_3  <= #IF_TPD IF_PHY_data[15:8];
    IF_Rx_ctrl_4  <= #IF_TPD IF_PHY_data[7:0];
  end

  if (IF_SYNC_state == SYNC_START)
    IF_SYNC_frame_cnt <= 0;                                         // reset sync counter
  else if (IF_PHY_drdy && (IF_SYNC_state == SYNC_FINISH))
    IF_SYNC_frame_cnt <= IF_SYNC_frame_cnt + 1'b1;          // increment if we have data to store
end

always @*
begin
  case (IF_SYNC_state)
    // state SYNC_IDLE  - loop until we find start of sync sequence
    SYNC_IDLE:
    begin
      IF_Rx_fifo_wreq  = 1'b0;             // Note: Sync bytes not saved in Rx_fifo

      if (IF_rst || !IF_PHY_drdy) 
        IF_SYNC_state_next = SYNC_IDLE;    // wait till we get data from PC
      else if (IF_PHY_data == 16'h7F7F)
        IF_SYNC_state_next = SYNC_START;   // possible start of sync
      else
        IF_SYNC_state_next = SYNC_IDLE;
    end 

    // check for 0x7F  sync character & get Rx control_0 
    SYNC_START:
    begin
      IF_Rx_fifo_wreq  = 1'b0;             // Note: Sync bytes not saved in Rx_fifo

      if (!IF_PHY_drdy)              
        IF_SYNC_state_next = SYNC_START;   // wait till we get data from PC
      else if (IF_PHY_data[15:8] == 8'h7F)
        IF_SYNC_state_next = SYNC_RX_1_2;  // have sync so continue
      else
        IF_SYNC_state_next = SYNC_IDLE;    // start searching for sync sequence again
    end

    
    SYNC_RX_1_2:                             // save Rx control 1 & 2
    begin
      IF_Rx_fifo_wreq  = 1'b0;             // Note: Rx control 1 & 2 not saved in Rx_fifo

      if (!IF_PHY_drdy)              
        IF_SYNC_state_next = SYNC_RX_1_2;  // wait till we get data from PC
      else
        IF_SYNC_state_next = SYNC_RX_3_4;
    end

    SYNC_RX_3_4:                             // save Rx control 3 & 4
    begin
      IF_Rx_fifo_wreq  = 1'b0;             // Note: Rx control 3 & 4 not saved in Rx_fifo

      if (!IF_PHY_drdy)              
        IF_SYNC_state_next = SYNC_RX_3_4;  // wait till we get data from PC
      else
        IF_SYNC_state_next = SYNC_FINISH;
    end

    // Remainder of data goes to Rx_fifo, re-start looking
    // for a new SYNC at end of this frame. 
    // Note: due to the use of IF_PHY_drdy data will only be written to the 
    // Rx fifo if there is room. Also the frame_count will only be incremented if IF_PHY_drdy is true.
    SYNC_FINISH:
    begin    
      IF_Rx_fifo_wreq  = IF_PHY_drdy;
      if (IF_PHY_drdy & (IF_SYNC_frame_cnt == ((512-8)/2)-1)) begin  // frame ended, go get sync again
        IF_SYNC_state_next = SYNC_IDLE;
      end 
      else IF_SYNC_state_next = SYNC_FINISH;
    end

    default:
    begin
      IF_Rx_fifo_wreq  = 1'b0;
      IF_SYNC_state_next = SYNC_IDLE;
    end
    endcase
end

wire have_room;
assign have_room = (IF_Rx_fifo_used < RX_FIFO_SZ - ((512-8)/2)) ? 1'b1 : 1'b0;  // the /2 is because we send 16 bit values

// prevent read from PHY fifo if empty and writing to Rx fifo if not enough room 
assign  IF_PHY_drdy = have_room & ~IF_PHY_rdempty;

//assign IF_PHY_drdy = ~IF_PHY_rdempty;



//---------------------------------------------------------
//              Decode Command & Control data
//---------------------------------------------------------

/*
    Decode IF_Rx_ctrl_0....IF_Rx_ctrl_4.
    Decode frequency (both Tx and Rx if full duplex selected), PTT, Speed etc
    The current frequency is set by the PC by decoding 
    IF_Rx_ctrl_1... IF_Rx_ctrl_4 when IF_Rx_ctrl_0[7:1] = 7'b0000_001
        
      The Rx Sampling Rate, either 192k, 96k or 48k is set by
      the PC by decoding IF_Rx_ctrl_1 when IF_Rx_ctrl_0[7:1] are all zero. IF_Rx_ctrl_1
      decodes as follows:
      IF_Rx_ctrl_1 = 8'bxxxx_xx00  - 48kHz
      IF_Rx_ctrl_1 = 8'bxxxx_xx01  - 96kHz
      IF_Rx_ctrl_1 = 8'bxxxx_xx10  - 192kHz
    Decode PTT from PC. Held in IF_Rx_ctrl_0[0] as follows
    
    0 = PTT inactive
    1 = PTT active
    
    Decode Attenuator settings on Alex, when IF_Rx_ctrl_0[7:1] = 0, IF_Rx_ctrl_3[1:0] indicates the following 
    
    00 = 0dB
    01 = 10dB
    10 = 20dB
    11 = 30dB
    
    Decode ADC & Attenuator settings on Hermes, when IF_Rx_ctrl_0[7:1] = 0, IF_Rx_ctrl_3[4:2] indicates the following
    
    000 = Random, Dither, Preamp OFF
    1xx = Random ON
    x1x = Dither ON
    xx1 = Preamp ON **** replace with attenuator
    
    Decode Rx relay settings on Alex, when IF_Rx_ctrl_0[7:1] = 0, IF_Rx_ctrl_3[6:5] indicates the following
    
    00 = None
    01 = Rx 1
    10 = Rx 2
    11 = Transverter
    
    Decode Tx relay settigs on Alex, when IF_Rx_ctrl_0[7:1] = 0, IF_Rx_ctrl_4[1:0] indicates the following
    
    00 = Tx 1
    01 = Tx 2
    10 = Tx 3
    
    Decode Rx_1_out relay settigs on Alex, when IF_Rx_ctrl_0[7:1] = 0, IF_Rx_ctrl_3[7] indicates the following
    1 = Rx_1_out on 
    When IF_Rx_ctrl_0[7:1] == 7'b0001_010 decodes as follows:
    
    IF_Line_In_Gain     <= IF_Rx_ctrl2[4:0] // decode 5-bit line gain setting
    
*/

reg   [6:0] IF_OC;                  // open collectors on Hermes
//reg         IF_mode;              // normal or Class E PA operation 
reg         IF_RAND;                // when set randomizer in ADCon
reg         IF_DITHER;              // when set dither in ADC on
//reg   [1:0] IF_ATTEN;             // decode attenuator setting on Alex
reg         Preamp;                 // selects input attenuator setting, 0 = 20dB, 1 = 0dB (preamp ON)
reg   [1:0] IF_TX_relay;            // Tx relay setting on Alex
reg         IF_Rout;                // Rx1 out on Alex
reg   [1:0] IF_RX_relay;            // Rx relay setting on Alex 
reg  [31:0] IF_frequency[0:32];     // Tx, Rx1, Rx2, Rx3, Rx4, ..., Rx32
reg         IF_duplex;
reg         IF_DFS1;
reg         IF_DFS0;
reg   [7:0] IF_Drive_Level;         // Tx drive level
reg			common_Merc_freq;		// when set forces Rx2 freq to Rx1 freq
reg         IF_Mic_boost;           // Mic boost 0 = 0dB, 1 = 20dB
reg         IF_Line_In;             // Selects input, mic = 0, line = 1
reg   [4:0] IF_Line_In_Gain;        // Sets Line-In Gain value (00000=-32.4 dB to 11111=+12 dB in 1.5 dB steps)
reg         IF_Apollo;              // Selects Alex (0) or Apollo (1)
reg             VNA;                        // Selects VNA mode when set. 
reg        Alex_manual;             // set if manual selection of Alex relays active
reg         Alex_6m_preamp;         // set if manual selection and 6m preamp selected
reg   [6:0] Alex_manual_LPF;        // Alex LPF relay selection in manual mode
reg   [5:0] Alex_manual_HPF;        // Alex HPF relay selection in manual mode
reg   [4:0] Hermes_atten;           // 0-31 dB Heremes attenuator value
reg         Hermes_atten_enable; // enable/disable bit for Hermes attenuator
reg         internal_CW;			// set when internal CW generation selected
reg   [7:0] sidetone_level;		// 0 - 100, sets internal sidetone level
reg   [7:0] RF_delay;				// 0 - 255, sets delay in mS from CW Key activation to RF out
reg   [9:0] hang;						// 0 - 1000, sets delay in mS from release of CW Key to dropping of PTT
reg  [11:0] tone_freq;				// 200 to 2250 Hz, sets sidetone frequency.
reg         key_reverse;		   // reverse CW keyes if set
reg   [5:0] keyer_speed; 			// CW keyer speed 0-60 WPM
reg   [1:0] keyer_mode;				// 00 = straight/external/bug, 01 = Mode A, 10 = Mode B
reg   [7:0] keyer_weight;			// keyer weight 33-66
reg         keyer_spacing;			// 0 = off, 1 = on

reg         TR_relay_disable;       // Alex T/R relay disable option
reg         IF_Pure_signal;              // 
reg   [3:0]  IF_Predistortion;              // 
reg  [15:0] IF_VNA_count;			// number of points when the FPGA scans the VNA frequencies

always @ (posedge ADC_CLK)
begin 
  if (IF_rst)
  begin // set up default values - 0 for now
    // RX_CONTROL_1
    IF_DFS1 <= 1'b0; // decode speed
    IF_DFS0 <= 1'b0; 
    // RX_CONTROL_2
//    IF_mode            <= 1'b0;       // decode mode, normal or Class E PA
    IF_OC              <= 7'b0;     // decode open collectors on Hermes
    // RX_CONTROL_3
//    IF_ATTEN           <= 2'b0;       // decode Alex attenuator setting 
    Preamp             <= 1'b1;     // decode Preamp (Attenuator), default on
    IF_DITHER          <= 1'b1;     // decode dither on or off
    IF_RAND            <= 1'b0;     // decode randomizer on or off
    IF_RX_relay        <= 2'b0;     // decode Alex Rx relays
    IF_Rout            <= 1'b0;     // decode Alex Rx_1_out relay
     TR_relay_disable   <= 1'b0;     // decode Alex T/R relay disable
    // RX_CONTROL_4
    IF_TX_relay        <= 2'b0;     // decode Alex Tx Relays
    IF_duplex          <= 1'b0;     // not in duplex mode
     IF_last_chan       <= 3'b000;    // default single receiver
    IF_Mic_boost       <= 1'b0;     // mic boost off 
    IF_Drive_Level     <= 8'b0;    // drive at minimum
     IF_Line_In           <= 1'b0;      // select Mic input, not Line in
//   IF_Filter            <= 1'b0;      // Apollo filter disabled (bypassed)
//   IF_Tuner             <= 1'b0;      // Apollo tuner disabled (bypassed)
//   IF_autoTune         <= 1'b0;       // Apollo auto-tune disabled
     IF_Apollo            <= 1'b0;     //   Alex selected       
     VNA                      <= 1'b0;      // VNA disabled
     Alex_manual          <= 1'b0;      // default manual Alex filter selection (0 = auto selection, 1 = manual selection)
     Alex_manual_HPF      <= 6'b0;      // default manual settings, no Alex HPF filters selected
     Alex_6m_preamp   <= 1'b0;      // default not set
     Alex_manual_LPF      <= 7'b0;     // default manual settings, no Alex LPF filters selected
     IF_Line_In_Gain      <= 5'b0;     // default line-in gain at min
     Hermes_atten         <= 5'b0;     // default zero input attenuation
     Hermes_atten_enable <= 1'b0;       // default disable Hermes attenuator
	      internal_CW        <= 1'b0;		// default internal CW generation is off
    sidetone_level     <= 8'b0;		// default sidetone level is 0
    RF_delay           <= 8'b0;	   // default CW Key activation to RF out
    hang               <= 10'b0;		// default hang time 
	 tone_freq  		  <= 12'b0;		// default sidetone frequency
    key_reverse		  <= 1'b0;     // reverse CW keyes if set
    keyer_speed        <= 6'b0; 		// CW keyer speed 0-60 WPM
    keyer_mode         <= 2'b0;	   // 00 = straight/external/bug, 01 = Mode A, 10 = Mode B
    keyer_weight       <= 8'b0;		// keyer weight 33-66
    keyer_spacing      <= 1'b0;	   // 0 = off, 1 = on
     IF_Pure_signal      <= 1'b0;      // default disable pure signal
     IF_Predistortion    <= 4'b0000;   // default disable predistortion
     IF_VNA_count       <= 16'd0;		// number of points when the FPGA scans the VNA frequencies
    
  end
  else if (IF_Rx_save)                  // all Rx_control bytes are ready to be saved
  begin                                         // Need to ensure that C&C data is stable 
    if (IF_Rx_ctrl_0[7:1] == 7'b0000_000)
    begin
      // RX_CONTROL_1
      IF_DFS1  <= IF_Rx_ctrl_1[1]; // decode speed 
      IF_DFS0  <= IF_Rx_ctrl_1[0]; // decode speed 
      // RX_CONTROL_2
//      IF_mode             <= IF_Rx_ctrl_2[0];   // decode mode, normal or Class E PA
      IF_OC               <= IF_Rx_ctrl_2[7:1]; // decode open collectors on Penelope
      // RX_CONTROL_3
//      IF_ATTEN            <= IF_Rx_ctrl_3[1:0]; // decode Alex attenuator setting 
      Preamp              <= IF_Rx_ctrl_3[2];  // decode Preamp (Attenuator)  1 = On (0dB atten), 0 = Off (20dB atten)
      IF_DITHER           <= IF_Rx_ctrl_3[3];   // decode dither on or off
      IF_RAND             <= IF_Rx_ctrl_3[4];   // decode randomizer on or off
      IF_RX_relay         <= IF_Rx_ctrl_3[6:5]; // decode Alex Rx relays
      IF_Rout             <= IF_Rx_ctrl_3[7];   // decode Alex Rx_1_out relay
      // RX_CONTROL_4
      IF_TX_relay         <= IF_Rx_ctrl_4[1:0]; // decode Alex Tx Relays
      IF_duplex           <= IF_Rx_ctrl_4[2];   // save duplex mode
      IF_last_chan        <= IF_Rx_ctrl_4[5:3]; // number of IQ streams to send to PC
		common_Merc_freq	  <= IF_Rx_ctrl_4[7];   // diversity mode, Rx1/Rx2 freq forced equal if set
    end
    if (IF_Rx_ctrl_0[7:1] == 7'b0001_001)
    begin
      IF_Drive_Level      <= IF_Rx_ctrl_1;          // decode drive level 
      IF_Mic_boost        <= IF_Rx_ctrl_2[0];       // decode mic boost 0 = 0dB, 1 = 20dB  
      IF_Line_In          <= IF_Rx_ctrl_2[1];       // 0 = Mic input, 1 = Line In
//    IF_Filter           <= IF_Rx_ctrl_2[2];       // 1 = enable Apollo filter
//    IF_Tuner            <= IF_Rx_ctrl_2[3];       // 1 = enable Apollo tuner
//    IF_autoTune         <= IF_Rx_ctrl_2[4];       // 1 = begin Apollo auto-tune
      IF_Apollo         <= IF_Rx_ctrl_2[5];      // 1 = Apollo enabled, 0 = Alex enabled 
      Alex_manual         <= IF_Rx_ctrl_2[6];       // manual Alex HPF/LPF filter selection (0 = disable, 1 = enable)
      VNA                     <= IF_Rx_ctrl_2[7];       // 1 = enable VNA mode
      Alex_manual_HPF     <= IF_Rx_ctrl_3[5:0];     // Alex HPF filters select
      Alex_6m_preamp      <= IF_Rx_ctrl_3[6];       // 6M low noise amplifier (0 = disable, 1 = enable)
      TR_relay_disable  <= IF_Rx_ctrl_3[7];     // Alex T/R relay disable option (0=TR relay enabled, 1=TR relay disabled)
      Alex_manual_LPF     <= IF_Rx_ctrl_4[6:0];     // Alex LPF filters select    
      IF_VNA_count <= {IF_Rx_ctrl_3, IF_Rx_ctrl_4};			// number of points when the FPGA scans the VNA frequencies
    end
    if (IF_Rx_ctrl_0[7:1] == 7'b0001_010)
    begin
      IF_Line_In_Gain   <= IF_Rx_ctrl_2[4:0];       // decode line-in gain setting
      IF_Pure_signal    <= IF_Rx_ctrl_2[6];       // decode pure signal setting
        Hermes_atten      <= IF_Rx_ctrl_4[4:0];    // decode input attenuation setting
      Hermes_atten_enable <= IF_Rx_ctrl_4[5];    // decode Hermes attenuator enable/disable
    end
	 if (IF_Rx_ctrl_0[7:1] == 7'b0001_011)
	begin
	 key_reverse		  <= IF_Rx_ctrl_2[6];     	// reverse CW keyes if set
    keyer_speed        <= IF_Rx_ctrl_3[5:0];  	// CW keyer speed 0-60 WPM
    keyer_mode         <= IF_Rx_ctrl_3[7:6];	   // 00 = straight/external/bug, 01 = Mode A, 10 = Mode B
    keyer_weight       <= IF_Rx_ctrl_4[6:0];		// keyer weight 33-66
    keyer_spacing      <= IF_Rx_ctrl_4[7];	   // 0 = off, 1 = on
	end
	
	if (IF_Rx_ctrl_0[7:1] == 7'b0001_111)
	begin
	  internal_CW       <= IF_Rx_ctrl_1[0];		// decode internal CW 0 = off, 1 = on
	  sidetone_level    <= IF_Rx_ctrl_2;			// decode CW sidetone volume
	  RF_delay			  <= IF_Rx_ctrl_3;			// decode delay from pressing CW Key to RF out	
	end
	if (IF_Rx_ctrl_0[7:1] == 7'b0010_000)
	begin
		hang[9:2]			<= IF_Rx_ctrl_1;			// decode CW hang time, 10 bits
		hang[1:0]	 		<= IF_Rx_ctrl_2[1:0];
		tone_freq [11:4]  <= IF_Rx_ctrl_3;			// decode sidetone frequency, 12 bits
		tone_freq [3:0]   <= IF_Rx_ctrl_4[3:0];	
	end	
	 
     if (IF_Rx_ctrl_0[7:1] == 7'b0101_011)
    begin
     // DACLUT[{IF_Rx_ctrl_1[3:0], IF_Rx_ctrl_2[7:0]}]<= {IF_Rx_ctrl_3[3:0], IF_Rx_ctrl_4[7:0]};
      if(IF_Rx_ctrl_1==8'b0000_0000)//predistortion control sub index
      begin
      IF_Predistortion <= IF_Rx_ctrl_2[3:0];
      end
     end
  end
end 

// Always compute frequency
// This really should be done on the PC....
wire [63:0] freqcomp;
assign freqcomp = {IF_Rx_ctrl_1, IF_Rx_ctrl_2, IF_Rx_ctrl_3, IF_Rx_ctrl_4} * M2 + M3;

// Pipeline freqcomp
reg [31:0] freqcompp [0:1];
reg IF_Rx_savep;
reg [6:0] chanp [0:1];

always @ (posedge ADC_CLK) begin
    if (IF_Rx_save) begin
        freqcompp[0] <= freqcomp[56:25];
        freqcompp[1] <= freqcomp[56:25];
//        freqcompp[2] <= freqcomp[56:25];
//        freqcompp[3] <= freqcomp[56:25];  
        chanp[0] <= IF_Rx_ctrl_0[7:1];
        chanp[1] <= IF_Rx_ctrl_0[7:1];
//        chanp[2] <= IF_Rx_ctrl_0[7:1];
//        chanp[3] <= IF_Rx_ctrl_0[7:1];    
    end
end

always @ (posedge ADC_CLK) begin
    if (IF_rst)
        IF_Rx_savep <= 1'b0;
    else
        IF_Rx_savep <= IF_Rx_save;
end


always @ (posedge ADC_CLK)
begin 
  if (IF_rst)
  begin // set up default values - 0 for now
    IF_frequency[0] <= 32'd0;
    IF_frequency[1] <= 32'd0;
  end
  else if (IF_Rx_savep)
  begin
    if (chanp[0] == 7'b0000_001) begin // decode IF_frequency[0]
        IF_frequency[0]   <= freqcompp[0]; //freqcomp[56:25];
        if (!IF_duplex && (IF_last_chan == 5'b00000)) IF_frequency[1] <= IF_frequency[0];
    end
        
    if (chanp[0] == 7'b0000_010) begin // decode Rx1 frequency
        if (!IF_duplex && (IF_last_chan == 5'b00000)) IF_frequency[1] <= IF_frequency[0];
        else IF_frequency[1] <= freqcompp[0]; //freqcomp[56:25];
    end
  end
end

always @ (posedge ADC_CLK) begin
        if (IF_rst) IF_frequency[2] <= 32'd0;
        else if (IF_Rx_savep) begin
            if (chanp[1] == ((1 < 7) ? 1+2 : 1+11)) begin
           
                IF_frequency[2] <= freqcompp[1]; //freqcomp[56:25];
 
            end                 
        end
    end
assign FPGA_PTT = IF_Rx_ctrl_0[0] | CW_PTT | clean_ptt; // IF_Rx_ctrl_0 only updated when we get correct sync sequence

always @*
begin
  if (Hermes_atten < 5'd19)
    preamp = 1'b1;
  else
    preamp = 1'b0;
end

//assign preamp = Preamp;



//---------------------------------------------------------
//   State Machine to manage PWM interface
//---------------------------------------------------------
/*

    The code loops until there are at least 4 words in the Rx_FIFO.

    The first word is the Left audio followed by the Right audio
    which is followed by I data and finally the Q data.
        
    The words sent to the D/A converters must be sent at the sample rate
    of the A/D converters (48kHz) so is synced to the negative edge of the CLRCLK (via IF_get_rx_data).
*/

reg   [2:0] IF_PWM_state;      // state for PWM
reg   [2:0] IF_PWM_state_next; // next state for PWM
reg  [15:0] IF_Left_Data;      // Left 16 bit PWM data for D/A converter
reg  [15:0] IF_Right_Data;     // Right 16 bit PWM data for D/A converter
reg  [15:0] IF_I_PWM;          // I 16 bit PWM data for D/A conveter
reg  [15:0] IF_Q_PWM;          // Q 16 bit PWM data for D/A conveter
wire        IF_get_samples;
wire        IF_get_rx_data;

assign IF_get_rx_data = IF_get_samples;

localparam PWM_IDLE     = 0,
           PWM_START    = 1,
           PWM_LEFT     = 2,
           PWM_RIGHT    = 3,
           PWM_I_AUDIO  = 4,
           PWM_Q_AUDIO  = 5;




always @ (posedge ADC_CLK) 
begin
  if (IF_rst)
    IF_PWM_state   <= #IF_TPD PWM_IDLE;
  else
    IF_PWM_state   <= #IF_TPD IF_PWM_state_next;

	 // get Left audio
  if (IF_PWM_state == PWM_LEFT)
    IF_Left_Data   <= #IF_TPD IF_Rx_fifo_rdata;
	 
  // get Right audio
  if (IF_PWM_state == PWM_RIGHT)
    IF_Right_Data  <= #IF_TPD IF_Rx_fifo_rdata;
	 
  // get I audio
  if (IF_PWM_state == PWM_I_AUDIO)
    IF_I_PWM       <= #IF_TPD IF_Rx_fifo_rdata;

  // get Q audio
  if (IF_PWM_state == PWM_Q_AUDIO)
    IF_Q_PWM       <= #IF_TPD IF_Rx_fifo_rdata;

end    

//SigmaDeltaModulator(.in(IF_Left_Data+16'd32767), .clk(ADC_CLK), .out(audio_l));
//SigmaDeltaModulator(.in(IF_Right_Data+16'd32767), .clk(ADC_CLK), .out(audio_r));
SigmaDeltaModulator(.in(CW_PTT ? {C122_sidetone+16'd32767} : IF_Left_Data+16'd32767), .clk(ADC_CLK), .out(audio_l));
SigmaDeltaModulator(.in(CW_PTT ? {C122_sidetone+16'd32767} : IF_Right_Data+16'd32767), .clk(ADC_CLK), .out(audio_r));

//CW_PTT ? {C122_sidetone+16'd32767} : IF_Left_Data+16'd32767

always @*
begin
  case (IF_PWM_state)
    PWM_IDLE:
    begin
      IF_Rx_fifo_rreq = 1'b0;

      if (!IF_get_rx_data  || RX_USED[RFSZ:2] == 1'b0 ) // RX_USED < 4
        IF_PWM_state_next = PWM_IDLE;    // wait until time to get the donuts every 48kHz from oven (RX_FIFO)
      else
        IF_PWM_state_next = PWM_START;   // ah! now it's time to get the donuts
    end

    // Start packaging the donuts
    PWM_START:
    begin
      IF_Rx_fifo_rreq    = 1'b1;
      IF_PWM_state_next  = PWM_LEFT;
    end

    // get Left audio
    PWM_LEFT:
    begin
      IF_Rx_fifo_rreq    = 1'b1;
      IF_PWM_state_next  = PWM_RIGHT;
    end

    // get Right audio
    PWM_RIGHT:
    begin
      IF_Rx_fifo_rreq    = 1'b1;
      IF_PWM_state_next  = PWM_I_AUDIO;
    end

    // get I audio
   PWM_I_AUDIO:
    begin
      IF_Rx_fifo_rreq    = 1'b1;
      IF_PWM_state_next  = PWM_Q_AUDIO;
    end

    // get Q audio
    PWM_Q_AUDIO:
    begin
      IF_Rx_fifo_rreq    = 1'b0;
      IF_PWM_state_next  = PWM_IDLE; // truck has left the shipping dock
    end

   default:
    begin
      IF_Rx_fifo_rreq    = 1'b0;
      IF_PWM_state_next  = PWM_IDLE;
    end
  endcase
end





// 5 ms debounce with 48 MHz clock
wire clean_ptt;
debounce de_ptt(.clean_pb(clean_ptt), .pb(~ptt_i), .clk(ADC_CLK));






// Really 0.16 seconds at Hermes-Lite 61.44 MHz clock
//localparam half_second = 10000000; // at 48MHz clock rate
//
//
//Led_flash Flash_LED4(.clock(ADC_CLK), .signal(this_MAC), .LED(leds[4]), .period(half_second));
//Led_flash Flash_LED5(.clock(ADC_CLK), .signal(run), .LED(leds[5]), .period(half_second));
//Led_flash Flash_LED6(.clock(ADC_CLK), .signal(IF_SYNC_state == SYNC_RX_1_2), .LED(leds[6]), .period(half_second));   
Led_flash Flash_LED0(.clock(ADC_CLK), .signal(rxnearclip), .LED(leds[0]), .period(half_second));
Led_flash Flash_LED1(.clock(ADC_CLK), .signal(rxclipp), .LED(leds[1]), .period(half_second));
Led_flash Flash_LED2(.clock(ADC_CLK), .signal(rxclipn), .LED(leds[2]), .period(half_second));
Led_flash Flash_LED3(.clock(ADC_CLK), .signal(OVERFLOW), .LED(leds[3]), .period(half_second));



function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction


endmodule 
