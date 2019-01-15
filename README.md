# ali_trx
Building your own SDR DDC/DUC transceiver with DIY modules from aliexpress

## Project Info
![Language](https://img.shields.io/badge/language-verilog-yellow.svg)
[![License](https://img.shields.io/badge/license-GNU%20GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.html)


## Circuit Diagram
![Circuit Diagram](pictures/module-diagram.png?raw=true)


## AD6645 module mods and power supply

The module can be used just out of the box, the one thing you're need to make sure is that the resistor RT1 is installed on the board. Sometimes it is missing. The resistor value should be 60 Ohm. The other way is to use 50 Ohm pass-through dummy load on the input connector. With 50 Ohm pass-through dummy load you will get for about 47 Ohm input impedance. 

According to the AD6645 datasheet, it is preffered to install back-to-back Schottky diodes across the secondry coil of the CLK transformer. It will limit excessive amplitude swings from the clock into the AD6645 to approximately 0.8 Vpp differential. This helps to prevent the large voltage swings of the clock from feeding through to other portions of the AD6645 and limits the noise presented to the encode inputs.

![AD6645 CLK Schottky diodes](https://i.imgur.com/VZSisCf.png)

Unfortunately these diodes are missing from aliexpress module. But I recommend to install it.

The power supply for the module should be low noise 5V. You can use bipolar power supply, but unipolar is more easy. Just connect -5V and GND together and provide +5V to the power supply connector. The AD6645 module together with TCXO consumes for about 300-330 mA on 5V line. The AD6645 chip is very-very hot, so I recommend to install the heatsink on it.

![Install heatsink](https://i.imgur.com/qluExOd.jpg)

## [Optional] AD6645 module mod to improve Noise Figure and reduce distortions

In order to improve Noise Figure and reduce distortions, you can replace operational amplifier on the AD6645 module with RF transformer. The board is already prepared for such mod. AD6645 is very famous ADC and we can find possible solutions in the book Kenton Williston "Digital Signal Processing World Class Designs":

![Improve ADC noise figure](https://i.imgur.com/UiNLvjO.png)

Since evaluation board for AD6645 from Analog Devices uses ADT4-1WT transformer on the input, it looks like the better solution indeed.

## LPF

Currently I'm using the following 7-th Chebyshev Low Pass Filter with 31 MHz cut-off :

![LPF circuit](https://i.imgur.com/ZNwHBFF.png) ![LPF response](https://i.imgur.com/eexpmrS.jpg)

Don't take attention to the "BPF YU1LM" text (I just reused PCB which is designed for VHF BPF). 

I build this LPF with EC24-R39K and EC24-R47K inductors and it works, but it appears that it has too high loss on 15+ MHz, so I'm planning to redesign it later.


## DIY Modules

AD6645: https://www.aliexpress.com/item/1PC-14-105M-high-speed-ADC-module-data-acquisition-module/32730197994.html

![AD6645 module](https://i.imgur.com/VDfjFQM.jpg)

HEATSINK FOR AD6645: https://www.aliexpress.com/item/10Pcs-Aluminum-Alloy-Stepper-Motor-Drive-Special-Cooling-Heat-Sink-For-TMC2100-3D-Printer-Parts/32840397703.html

![HEATSINK FOR AD6645](https://i.imgur.com/pFud16l.jpg)

FPGA: https://www.aliexpress.com/item/fpga-development-board-EP4CE22E22C8N-board-altera-fpga-board-altera-board-USB-Blaster/32834582202.html

![FPGA](https://i.imgur.com/tBZgi8r.jpg)

Remark: currently this FPGA module is not available, but it can be replaced with more powerful https://www.aliexpress.com/store/product/cyclone-iv-board-E22-core-board-altera-fpga-board-altera-board-fpga-development-board-EP4CE22f17C8N/620372_32853228751.html

LAN8720: https://www.aliexpress.com/item/LAN8720-Module-Physical-Layer-Transceiver-PHY-Module-Embedded-Web-Server-RMII-Interface-MDIX-Regulator-I-O/32845851676.html

![LAN8720](https://i.imgur.com/WoWGo0s.jpg)

TCXO 96 MHz: https://www.aliexpress.com/item/116MHz-96MHz-104MHz-114MHZ-160MHz-high-precision-temperature-compensation-crystal-oscillator-TCXO-0-1ppm-high-stable/32794136550.html

![TCXO](https://i.imgur.com/1rjW7vK.jpg)

WM8731: https://www.aliexpress.com/item/FREE-SHIPPING-Wm8731-module-audio-module-mcu-fpga-music/1674210328.html

![WM8731](https://i.imgur.com/W0RaJWr.jpg)

ATT 6 dB: https://www.aliexpress.com/item/2W-SMA-DC-6GHz-Coaxial-Fixed-Attenuators-Frequency-6GHz-SMA-Fixed-Connectors/32896198417.html

![ATT 6 dB](https://i.imgur.com/c58DhRB.jpg)

ADT4-1WT: https://www.aliexpress.com/item/Free-Shipping-PIC16F1829-I-SS-PIC16F1829-SSOP20-new-and-Original-in-stock/32295905036.html

![ADT4-1WT](https://i.imgur.com/E99LSdG.jpg)









