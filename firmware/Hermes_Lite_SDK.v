//
//  Hermes Lite Core Wrapper for BeMicro CV
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
//
// (C) Steve Haynal KF7O 2014
// modified by alex_m
//

module Hermes_Lite(
    //input clk50mhz,
    input [1:0] dipsw,
    input ptt_i,
    output exp_ptt_n,
    input [13:0] ADC_in,
    output [13:0] DAC_out,
    input ADC_ready,
    input ADC_OVR,
    input ADC_DRY,          // pass-through pin for ADC_ready
    output DAC_CLK,
    output preamp,
    output audio_l,
    output audio_r,
    output [6:0] userout,
    output [3:0] LEDS,

    //audio codec (WM8731 / TLV320AIC23B)
    output AC_BCLK,         // [CBCLK] 3072 kHz
    output AC_DALRC,        // [CLRCOUT] 48 kHz
    output AC_ADCLRC,       // [CLRCIN] 48 kHz
    output AC_MCLK,         // [CMCLK] 12288 kHz
    inout AC_IIC_DAT,       // [i2c_sda]
    output AC_IIC_SCK,      // [i2c_scl]
    output AC_DACDAT,       // [CDIN] audio data to TLV320
    input  AC_ADCDAT,       // [CDOUT] mic data from TLV320

    // RMII Ethernet PHY
    output [1:0] rmii_tx,
    output rmii_tx_en,
    input [1:0] rmii_rx,
    input rmii_osc,
    input rmii_crs_dv,
    inout PHY_MDIO,
    output PHY_MDC
);

// PARAMETERS

// Ethernet Interface
parameter MAC = {8'h00,8'h1c,8'hc0,8'ha2,8'h22,8'h5d};
parameter IP = {8'd0,8'd0,8'd0,8'd0};

// Clock Frequency
//parameter CLK_FREQ = 61440000;
parameter CLK_FREQ = 96000000;

// Number of Receivers
parameter NR = 1; // number of receivers to implement

wire IF_locked;
wire AC_locked;

wire pll_96000;
wire pll_48;
wire pll_12288;     // audio
wire pll_3072;      // audio
wire pll_800;       // audio

assign DAC_CLK = pll_96000;
assign AC_DALRC = pll_48;
assign AC_ADCLRC = pll_48;
assign AC_BCLK = pll_3072;
assign AC_MCLK = pll_12288;

PLL_IF PLL_IF_inst(
    .inclk0(ADC_ready),
    .c0(pll_96000), 
    .c1(pll_48),
    .locked(IF_locked));

PLL_AUDIO PLL_AUDIO_inst(
    .inclk0(pll_96000),
    .c0(pll_12288),
    .c1(pll_3072), 
    .c2(pll_800),
    .locked(AC_locked));


// RMII2MII Conversion
wire [3:0] PHY_TX;
wire PHY_TX_EN;         //PHY Tx enable
reg PHY_TX_CLOCK;       //PHY Tx data clock
wire [3:0] PHY_RX;
wire RX_DV;             //PHY has data flag
reg PHY_RX_CLOCK;       //PHY Rx data clock
wire PHY_RESET_N;

RMII2MII_rev2 RMII2MII_inst(
    .clk(rmii_osc),
    .resetn(1'b1),
    .phy_RXD(rmii_rx),
    .phy_CRS(rmii_crs_dv),
    .mac_RXD(PHY_RX),
    .mac_RX_CLK(PHY_RX_CLOCK),
    .mac_RX_DV(RX_DV),
    .mac_TXD(PHY_TX),
    .mac_TX_EN(PHY_TX_EN),
    .phy_TXD(rmii_tx),
    .phy_TX_EN(rmii_tx_en),
    .mac_TX_CLK(PHY_TX_CLOCK),
    .mac_MDC_in(),
    .phy_MDC_out(),
    .mac_MDO_oen(),
    .mac_MDO_in(),
    .phy_MDIO(),
    .mac_MDI_out(),
    .phy_resetn()
);


// Hermes Lite Core
hermes_lite_core #(
    .MAC(MAC),
    .IP(IP),
    .CLK_FREQ(CLK_FREQ),
    .NR(NR)) 

    hermes_lite_core_inst(
        //.clk50mhz(clk50mhz),
        .ADC_CLK(pll_96000),

        .IF_locked(1'b1),
        .IF_CLRCLK(pll_48),
        .leds(LEDS),
        .preamp (preamp),
        .audio_l (audio_l),
        .audio_r (audio_r),
        .exp_ptt_n(exp_ptt_n),
        .pll_3072(pll_3072),
        .pll_12288(pll_12288),
        .pll_800(pll_800),
        .userout(userout),
        .dipsw({dipsw[1],dipsw}),


        .ptt_i(ptt_i),


        .DAC_out(DAC_out),
        .ADC_in(ADC_in),
        .ADC_ready(ADC_ready),
        .ADC_ovr(ADC_OVR),
   
        .AC_IIC_DAT(AC_IIC_DAT),
        .AC_IIC_SCK(AC_IIC_SCK),
        .AC_ADCDAT(AC_ADCDAT),
        .AC_DACDAT(AC_DACDAT),


        // MMI Ethernet PHY
        .PHY_TX(PHY_TX),
        .PHY_TX_EN(PHY_TX_EN),        
        .PHY_TX_CLOCK(PHY_TX_CLOCK),
        .PHY_RX(PHY_RX),     
        .RX_DV(RX_DV),
        .PHY_RX_CLOCK(PHY_RX_CLOCK),         
        .PHY_RESET_N(PHY_RESET_N),
        .PHY_MDIO(PHY_MDIO),             
        .PHY_MDC(PHY_MDC)
);             

endmodule 
