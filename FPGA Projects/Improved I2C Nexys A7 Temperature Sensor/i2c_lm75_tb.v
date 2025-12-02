`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench for I2C Communication with LM75 Temperature Sensor
//
// Description: Simulates I2C master-slave communication between FPGA and LM75
//              temperature sensor. Includes behavioral model of LM75.
//
// LM75 Characteristics:
// - I2C Address: 0x48 (1001000) + R/W bit -> 0x90 (Write), 0x91 (Read)
// - Temperature Format: 11-bit, two's complement
// - MSB First: D10-D3 in first byte, D2-D0 in bits [7:5] of second byte
//////////////////////////////////////////////////////////////////////////////////

module i2c_lm75_tb();

    // Testbench signals
    reg clk_100MHz;
    reg clk_200KHz;
    wire SDA;
    wire SCL;
    wire [7:0] temp_data;

    // SDA control signals
    reg master_sda = 1'b1;
    reg slave_sda = 1'b1;
    reg tb_sda = 1'b1;

    // Bidirectional SDA: pull-up behavior (wired-AND)
    assign SDA = (master_sda & slave_sda & tb_sda) ? 1'bz : 1'b0;

    // LM75 Sensor Model Variables
    reg [15:0] lm75_temp_register = 16'h1900;  // 25°C = 0x1900 (binary: 0001_1001_0000_0000)
    reg [3:0] lm75_bit_counter = 0;
    reg [7:0] lm75_address_received = 0;
    reg lm75_address_match = 0;
    reg lm75_sending_data = 0;
    reg [7:0] lm75_data_byte = 0;

    // LM75 States
    localparam LM75_IDLE         = 4'd0;
    localparam LM75_REC_ADDR     = 4'd1;
    localparam LM75_SEND_ACK     = 4'd2;
    localparam LM75_SEND_MSB     = 4'd3;
    localparam LM75_REC_ACK_MSB  = 4'd4;
    localparam LM75_SEND_LSB     = 4'd5;
    localparam LM75_REC_NACK     = 4'd6;

    reg [3:0] lm75_state = LM75_IDLE;

    // Clock Generation
    initial begin
        clk_100MHz = 0;
        forever #5 clk_100MHz = ~clk_100MHz;  // 100MHz -> 10ns period
    end

    // 200KHz Clock Generation (for I2C master)
    integer clk_200k_counter = 0;
    initial begin
        clk_200KHz = 1;
        forever begin
            #2500;  // 2500ns = 2.5us -> 200KHz
            clk_200KHz = ~clk_200KHz;
        end
    end

    // Instantiate I2C Master (Modified for LM75)
    // Note: The original i2c_master uses address 0x97 for ADT7420
    // For LM75, we need address 0x91 (0x48 << 1 | 0x01)
    i2c_master_lm75 i2c_master_inst (
        .clk_200KHz(clk_200KHz),
        .temp_data(temp_data),
        .SDA(master_sda),
        .SCL(SCL)
    );

    // LM75 Behavioral Model - Slave Response
    reg sda_prev = 1'b1;
    reg scl_prev = 1'b1;
    wire start_condition = sda_prev & ~SDA & SCL;
    wire stop_condition = ~sda_prev & SDA & SCL;
    wire scl_posedge = ~scl_prev & SCL;
    wire scl_negedge = scl_prev & ~SCL;

    always @(posedge clk_100MHz) begin
        sda_prev <= SDA;
        scl_prev <= SCL;
    end

    // LM75 State Machine
    always @(posedge clk_100MHz) begin
        if (start_condition) begin
            lm75_state <= LM75_REC_ADDR;
            lm75_bit_counter <= 0;
            lm75_address_received <= 0;
            slave_sda <= 1'b1;
            $display("[%0t] LM75: START condition detected", $time);
        end
        else if (stop_condition) begin
            lm75_state <= LM75_IDLE;
            slave_sda <= 1'b1;
            $display("[%0t] LM75: STOP condition detected", $time);
        end
        else begin
            case (lm75_state)
                LM75_IDLE: begin
                    slave_sda <= 1'b1;
                end

                LM75_REC_ADDR: begin
                    if (scl_posedge) begin
                        lm75_address_received <= {lm75_address_received[6:0], SDA};
                        lm75_bit_counter <= lm75_bit_counter + 1;

                        if (lm75_bit_counter == 7) begin
                            // Check if address matches (0x91 for read = 0b10010001)
                            // Expected: 1001000 (0x48) + 1 (read bit)
                            if (lm75_address_received[7:1] == 7'b1001000 && SDA == 1'b1) begin
                                lm75_address_match <= 1'b1;
                                lm75_state <= LM75_SEND_ACK;
                                $display("[%0t] LM75: Address match! Received: 0x%h", $time, {lm75_address_received[6:0], SDA});
                            end
                            else begin
                                lm75_address_match <= 1'b0;
                                lm75_state <= LM75_IDLE;
                                $display("[%0t] LM75: Address mismatch. Received: 0x%h", $time, {lm75_address_received[6:0], SDA});
                            end
                        end
                    end
                end

                LM75_SEND_ACK: begin
                    if (scl_negedge) begin
                        slave_sda <= 1'b0;  // Send ACK (pull SDA low)
                        $display("[%0t] LM75: Sending ACK", $time);
                    end
                    if (scl_posedge) begin
                        lm75_state <= LM75_SEND_MSB;
                        lm75_bit_counter <= 0;
                        lm75_data_byte <= lm75_temp_register[15:8];  // MSB
                        $display("[%0t] LM75: Preparing to send MSB: 0x%h", $time, lm75_temp_register[15:8]);
                    end
                end

                LM75_SEND_MSB: begin
                    if (scl_negedge) begin
                        slave_sda <= lm75_data_byte[7];
                        lm75_data_byte <= {lm75_data_byte[6:0], 1'b0};
                        lm75_bit_counter <= lm75_bit_counter + 1;

                        if (lm75_bit_counter == 7) begin
                            lm75_state <= LM75_REC_ACK_MSB;
                            slave_sda <= 1'b1;  // Release SDA for master ACK
                        end
                    end
                end

                LM75_REC_ACK_MSB: begin
                    if (scl_posedge) begin
                        if (SDA == 1'b0) begin
                            $display("[%0t] LM75: ACK received after MSB", $time);
                            lm75_state <= LM75_SEND_LSB;
                            lm75_bit_counter <= 0;
                            lm75_data_byte <= lm75_temp_register[7:0];  // LSB
                            $display("[%0t] LM75: Preparing to send LSB: 0x%h", $time, lm75_temp_register[7:0]);
                        end
                        else begin
                            $display("[%0t] LM75: NACK received after MSB", $time);
                            lm75_state <= LM75_IDLE;
                        end
                    end
                end

                LM75_SEND_LSB: begin
                    if (scl_negedge) begin
                        slave_sda <= lm75_data_byte[7];
                        lm75_data_byte <= {lm75_data_byte[6:0], 1'b0};
                        lm75_bit_counter <= lm75_bit_counter + 1;

                        if (lm75_bit_counter == 7) begin
                            lm75_state <= LM75_REC_NACK;
                            slave_sda <= 1'b1;  // Release SDA for master NACK
                        end
                    end
                end

                LM75_REC_NACK: begin
                    if (scl_posedge) begin
                        if (SDA == 1'b1) begin
                            $display("[%0t] LM75: NACK received after LSB (expected)", $time);
                        end
                        else begin
                            $display("[%0t] LM75: ACK received after LSB (unexpected)", $time);
                        end
                        lm75_state <= LM75_IDLE;
                    end
                end

                default: lm75_state <= LM75_IDLE;
            endcase
        end
    end

    // Monitor I2C Transactions
    always @(posedge SCL) begin
        if (lm75_state == LM75_REC_ADDR && lm75_bit_counter < 8)
            $display("[%0t] I2C: Address bit %0d = %b", $time, lm75_bit_counter, SDA);
    end

    // Monitor temperature data output
    always @(temp_data) begin
        $display("[%0t] Master received temperature data: 0x%h (%d°C)", $time, temp_data, temp_data);
    end

    // Test Stimulus
    initial begin
        $display("=================================================================");
        $display("Starting I2C LM75 Temperature Sensor Simulation");
        $display("=================================================================");
        $display("LM75 Temperature Register = 0x%h (Should be 25°C)", lm75_temp_register);
        $display("");

        // Initialize
        tb_sda = 1'b1;

        // Run simulation for enough time to complete several I2C transactions
        #50000000;  // 50ms

        $display("");
        $display("=================================================================");
        $display("Simulation Complete");
        $display("=================================================================");
        $finish;
    end

    // Optional: VCD dump for waveform viewing
    initial begin
        $dumpfile("i2c_lm75_tb.vcd");
        $dumpvars(0, i2c_lm75_tb);
    end

endmodule


//////////////////////////////////////////////////////////////////////////////////
// Modified I2C Master for LM75 Sensor
// Changes from original:
// - Address changed from 0x97 (ADT7420) to 0x91 (LM75)
// - Uses same protocol structure
//////////////////////////////////////////////////////////////////////////////////
module i2c_master_lm75(
    input clk_200KHz,
    output reg SDA,
    output [7:0] temp_data,
    output SCL
    );

    // Generate 10kHz SCL clock from 200kHz
    reg [3:0] counter = 4'b0;
    reg clk_reg = 1'b1;
    assign SCL = clk_reg;

    // Signal Declarations
    parameter [7:0] sensor_address_plus_read = 8'b1001_0001;  // 0x91 for LM75
    reg [7:0] tMSB = 8'b0;
    reg [7:0] tLSB = 8'b0;
    reg o_bit = 1'b1;
    reg [11:0] count = 12'b0;
    reg [7:0] temp_data_reg;

    // State Declarations
    localparam [4:0] POWER_UP   = 5'h00,
                     START      = 5'h01,
                     SEND_ADDR6 = 5'h02,
                     SEND_ADDR5 = 5'h03,
                     SEND_ADDR4 = 5'h04,
                     SEND_ADDR3 = 5'h05,
                     SEND_ADDR2 = 5'h06,
                     SEND_ADDR1 = 5'h07,
                     SEND_ADDR0 = 5'h08,
                     SEND_RW    = 5'h09,
                     REC_ACK    = 5'h0A,
                     REC_MSB7   = 5'h0B,
                     REC_MSB6   = 5'h0C,
                     REC_MSB5   = 5'h0D,
                     REC_MSB4   = 5'h0E,
                     REC_MSB3   = 5'h0F,
                     REC_MSB2   = 5'h10,
                     REC_MSB1   = 5'h11,
                     REC_MSB0   = 5'h12,
                     SEND_ACK   = 5'h13,
                     REC_LSB7   = 5'h14,
                     REC_LSB6   = 5'h15,
                     REC_LSB5   = 5'h16,
                     REC_LSB4   = 5'h17,
                     REC_LSB3   = 5'h18,
                     REC_LSB2   = 5'h19,
                     REC_LSB1   = 5'h1A,
                     REC_LSB0   = 5'h1B,
                     NACK       = 5'h1C;

    reg [4:0] state_reg = POWER_UP;
    wire i_bit;
    assign i_bit = SDA;

    always @(posedge clk_200KHz) begin
        // Counter logic for SCL generation
        if(counter == 9) begin
            counter <= 4'b0;
            clk_reg <= ~clk_reg;
        end
        else
            counter <= counter + 1;

        count <= count + 1;

        // State Machine Logic
        case(state_reg)
            POWER_UP: begin
                if(count == 12'd1999)
                    state_reg <= START;
            end

            START: begin
                if(count == 12'd2004)
                    o_bit <= 1'b0;
                if(count == 12'd2013)
                    state_reg <= SEND_ADDR6;
            end

            SEND_ADDR6: begin
                o_bit <= sensor_address_plus_read[7];
                if(count == 12'd2033)
                    state_reg <= SEND_ADDR5;
            end

            SEND_ADDR5: begin
                o_bit <= sensor_address_plus_read[6];
                if(count == 12'd2053)
                    state_reg <= SEND_ADDR4;
            end

            SEND_ADDR4: begin
                o_bit <= sensor_address_plus_read[5];
                if(count == 12'd2073)
                    state_reg <= SEND_ADDR3;
            end

            SEND_ADDR3: begin
                o_bit <= sensor_address_plus_read[4];
                if(count == 12'd2093)
                    state_reg <= SEND_ADDR2;
            end

            SEND_ADDR2: begin
                o_bit <= sensor_address_plus_read[3];
                if(count == 12'd2113)
                    state_reg <= SEND_ADDR1;
            end

            SEND_ADDR1: begin
                o_bit <= sensor_address_plus_read[2];
                if(count == 12'd2133)
                    state_reg <= SEND_ADDR0;
            end

            SEND_ADDR0: begin
                o_bit <= sensor_address_plus_read[1];
                if(count == 12'd2153)
                    state_reg <= SEND_RW;
            end

            SEND_RW: begin
                o_bit <= sensor_address_plus_read[0];
                if(count == 12'd2169)
                    state_reg <= REC_ACK;
            end

            REC_ACK: begin
                o_bit <= 1'b1;  // Release SDA
                if(count == 12'd2189)
                    state_reg <= REC_MSB7;
            end

            REC_MSB7: begin
                tMSB[7] <= i_bit;
                if(count == 12'd2209)
                    state_reg <= REC_MSB6;
            end

            REC_MSB6: begin
                tMSB[6] <= i_bit;
                if(count == 12'd2229)
                    state_reg <= REC_MSB5;
            end

            REC_MSB5: begin
                tMSB[5] <= i_bit;
                if(count == 12'd2249)
                    state_reg <= REC_MSB4;
            end

            REC_MSB4: begin
                tMSB[4] <= i_bit;
                if(count == 12'd2269)
                    state_reg <= REC_MSB3;
            end

            REC_MSB3: begin
                tMSB[3] <= i_bit;
                if(count == 12'd2289)
                    state_reg <= REC_MSB2;
            end

            REC_MSB2: begin
                tMSB[2] <= i_bit;
                if(count == 12'd2309)
                    state_reg <= REC_MSB1;
            end

            REC_MSB1: begin
                tMSB[1] <= i_bit;
                if(count == 12'd2329)
                    state_reg <= REC_MSB0;
            end

            REC_MSB0: begin
                tMSB[0] <= i_bit;
                o_bit <= 1'b0;  // Send ACK
                if(count == 12'd2349)
                    state_reg <= SEND_ACK;
            end

            SEND_ACK: begin
                o_bit <= 1'b0;  // Keep sending ACK
                if(count == 12'd2369)
                    state_reg <= REC_LSB7;
            end

            REC_LSB7: begin
                o_bit <= 1'b1;  // Release SDA
                tLSB[7] <= i_bit;
                if(count == 12'd2389)
                    state_reg <= REC_LSB6;
            end

            REC_LSB6: begin
                tLSB[6] <= i_bit;
                if(count == 12'd2409)
                    state_reg <= REC_LSB5;
            end

            REC_LSB5: begin
                tLSB[5] <= i_bit;
                if(count == 12'd2429)
                    state_reg <= REC_LSB4;
            end

            REC_LSB4: begin
                tLSB[4] <= i_bit;
                if(count == 12'd2449)
                    state_reg <= REC_LSB3;
            end

            REC_LSB3: begin
                tLSB[3] <= i_bit;
                if(count == 12'd2469)
                    state_reg <= REC_LSB2;
            end

            REC_LSB2: begin
                tLSB[2] <= i_bit;
                if(count == 12'd2489)
                    state_reg <= REC_LSB1;
            end

            REC_LSB1: begin
                tLSB[1] <= i_bit;
                if(count == 12'd2509)
                    state_reg <= REC_LSB0;
            end

            REC_LSB0: begin
                tLSB[0] <= i_bit;
                o_bit <= 1'b1;  // Send NACK
                if(count == 12'd2529)
                    state_reg <= NACK;
            end

            NACK: begin
                o_bit <= 1'b1;  // Keep NACK high
                if(count == 12'd2559) begin
                    count <= 12'd2000;
                    state_reg <= START;
                end
            end
        endcase
    end

    // Buffer for temperature data
    always @(posedge clk_200KHz)
        if(state_reg == NACK)
            temp_data_reg <= {tMSB[6:0], tLSB[7]};

    // Control direction of SDA
    wire SDA_dir;
    assign SDA_dir = (state_reg == POWER_UP || state_reg == START ||
                      state_reg == SEND_ADDR6 || state_reg == SEND_ADDR5 ||
                      state_reg == SEND_ADDR4 || state_reg == SEND_ADDR3 ||
                      state_reg == SEND_ADDR2 || state_reg == SEND_ADDR1 ||
                      state_reg == SEND_ADDR0 || state_reg == SEND_RW ||
                      state_reg == SEND_ACK || state_reg == NACK) ? 1 : 0;

    always @(*) begin
        if (SDA_dir)
            SDA = o_bit;
        else
            SDA = 1'bz;
    end

    assign temp_data = temp_data_reg;

endmodule
