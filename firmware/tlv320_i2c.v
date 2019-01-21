// Based on (C) Phil Harman VK6APH 2006, 2007, 2008, 2009, 2010, 2011, 2012 tlv320_spi module
// and WM8731 interface I2C from https://github.com/emard/vhdl_phoenix/blob/master/rtl_dar/wm8731_dac.vhd
// adapted and modified by UR5KIM
// added init delay by alex_m

// inclk = 800 kHz 
module tlv320_i2c(inclk_i2c, boost, line, line_in_gain, i2c_scl, i2c_sda);

input wire inclk_i2c;
input wire boost;
input wire line;   // set when using line rather than mic input
input wire [4:0] line_in_gain;
output i2c_scl;
inout i2c_sda;


reg [7:0] I2C_addr = 8'b00110100;   // 7 bits device address and 1 bit write operation
reg i2c_scl;
reg i2c_sda;
reg NewData;
reg [15:0] I2C_data;
reg [2:0] I2C_WordCnt;
reg [1:0] I2C_BitPhase;
reg [4:0] I2C_BitCnt;
reg prev_boost;
reg prev_line;
reg [4:0] prev_line_in_gain;

// Set up TLV320 data to send 
always @*
begin
    case (I2C_WordCnt)	// data to load into TLV320
        3'd0: I2C_data <= 16'h1E00;                             // Reset chip
        3'd1: I2C_data <= 16'h1201;                             // set digital interface active
        3'd2: I2C_data <= line ? 16'h0810 : (16'h0814 + boost); // D/A on, line input	:	D/A on, mic input, mic 20dB boost on/off
        3'd3: I2C_data <= 16'h0C00;                             // All chip power on
        3'd4: I2C_data <= 16'h0E02;                             // Slave, 16 bit, I2S
        3'd5: I2C_data <= 16'h1000;                             // 48k, Normal mode
        3'd6: I2C_data <= 16'h0A00;                             // turn D/A mute off  
        3'd7: I2C_data <= {11'b0, line_in_gain};                // set line in gain
    endcase
end



// State machine to send data to TLV320 via I2C interface

reg [19:0] i2c_delay_counter;

always@(posedge inclk_i2c)
begin
    if (i2c_delay_counter != (200*800))        // 200 [ms]
        i2c_delay_counter <= i2c_delay_counter + 20'd1;
    else 
    begin
        if (I2C_BitPhase == 2) 
            begin
                I2C_BitPhase <= 0;
                if (I2C_BitCnt == 31)
                    begin
                        if (I2C_WordCnt == 7)
                            begin   // stop when all data sent, and wait for boost to change           
                                if (boost != prev_boost || line != prev_line || line_in_gain != prev_line_in_gain) 
                                    begin                                   // has boost or line in or line-in gain changed?
                                        prev_boost <= boost;                // save the current boost setting 
                                        prev_line <= line;                  // save the current line in setting
                                        prev_line_in_gain <= line_in_gain;  // save the current line-in gain setting
                                        I2C_WordCnt <= 1'd0;
                                        I2C_BitCnt <= 1'd0;
                                        NewData <= 1'd1;
                                    end
                                else
                                    NewData <= 1'd0;
                            end
                        else
                            begin
                                I2C_BitCnt <= 0;
                                I2C_WordCnt <= I2C_WordCnt + 1'd1;
                            end
                    end  
                else
                    I2C_BitCnt <= I2C_BitCnt + 1'd1;
            end
        else
            I2C_BitPhase <= I2C_BitPhase + 1'd1; 

        if (NewData)        // update the codec settings
            begin
                // I2C clock:
                if (I2C_BitCnt == 0)
                    i2c_scl <= 1'd1;
                else if (I2C_BitCnt == 1)
                    begin
                        if (I2C_BitPhase == 0)
                            i2c_scl <= 1'd1;
                        else                        
                            i2c_scl <= 1'd0;
                    end
                else if (I2C_BitCnt == 29)
                    begin
                        if (I2C_BitPhase == 0)
                            i2c_scl <= 1'd0;
                        else 
                            i2c_scl <= 1'd1;
                    end
                else if (I2C_BitCnt == 30)
                    i2c_scl <= 1'd1;
                else if (I2C_BitCnt == 31)
                    i2c_scl <= 1'd1;
                else if (I2C_BitPhase == 1)
                    i2c_scl <= 1'd1;
                else
                    i2c_scl <= 1'd0;

                // I2C data:
                case (I2C_BitCnt)
                    5'd1: i2c_sda <= 1'd0;          // start condition
                    5'd2: i2c_sda <= I2C_addr[7];   // 8 bits I2C address
                    5'd3: i2c_sda <= I2C_addr[6];
                    5'd4: i2c_sda <= I2C_addr[5];
                    5'd5: i2c_sda <= I2C_addr[4];
                    5'd6: i2c_sda <= I2C_addr[3];
                    5'd7: i2c_sda <= I2C_addr[2];
                    5'd8: i2c_sda <= I2C_addr[1];
                    5'd9: i2c_sda <= I2C_addr[0];
                    5'd10: i2c_sda <= 1'bz;         // 1 bit acknowledge
                    5'd11: i2c_sda <= I2C_data[15]; // 8 bits I2C data 
                    5'd12: i2c_sda <= I2C_data[14]; 
                    5'd13: i2c_sda <= I2C_data[13]; 
                    5'd14: i2c_sda <= I2C_data[12]; 
                    5'd15: i2c_sda <= I2C_data[11]; 
                    5'd16: i2c_sda <= I2C_data[10]; 
                    5'd17: i2c_sda <= I2C_data[9]; 
                    5'd18: i2c_sda <= I2C_data[8]; 
                    5'd19: i2c_sda <= 1'bz;         // 1 bit acknowledge
                    5'd20: i2c_sda <= I2C_data[7];  // 8bits I2C data 
                    5'd21: i2c_sda <= I2C_data[6]; 
                    5'd22: i2c_sda <= I2C_data[5]; 
                    5'd23: i2c_sda <= I2C_data[4]; 
                    5'd24: i2c_sda <= I2C_data[3]; 
                    5'd25: i2c_sda <= I2C_data[2]; 
                    5'd26: i2c_sda <= I2C_data[1]; 
                    5'd27: i2c_sda <= I2C_data[0]; 
                    5'd28: i2c_sda <= 1'bz;         // 1 bit acknowledge
                    5'd29: i2c_sda <= 1'd0;         // stop condition
                    default: i2c_sda <= 1'd1; 
                endcase
            end
    end
end
endmodule