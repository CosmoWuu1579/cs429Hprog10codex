`timescale 1ns/1ps
`include "tinker.sv"

module tb_memory_stream_hidden;
    reg clk;
    reg reset;
    wire hlt;

    integer cyc;
    integer i;
    reg [31:0] prog [0:43];

    tinker_core dut (
        .clk(clk),
        .reset(reset),
        .hlt(hlt)
    );

    always #5 clk = ~clk;

    task write_instr(input [63:0] addr, input [31:0] word);
    begin
        dut.memory.bytes[addr]   = word[7:0];
        dut.memory.bytes[addr+1] = word[15:8];
        dut.memory.bytes[addr+2] = word[23:16];
        dut.memory.bytes[addr+3] = word[31:24];
    end
    endtask

    task write_u64(input [63:0] addr, input [63:0] word);
    begin
        dut.memory.bytes[addr]   = word[7:0];
        dut.memory.bytes[addr+1] = word[15:8];
        dut.memory.bytes[addr+2] = word[23:16];
        dut.memory.bytes[addr+3] = word[31:24];
        dut.memory.bytes[addr+4] = word[39:32];
        dut.memory.bytes[addr+5] = word[47:40];
        dut.memory.bytes[addr+6] = word[55:48];
        dut.memory.bytes[addr+7] = word[63:56];
    end
    endtask

    initial begin
        clk = 0;
        reset = 1;

        prog[0]  = 32'h10000000;
        prog[1]  = 32'hc8000000;
        prog[2]  = 32'h3800000c;
        prog[3]  = 32'hc8000000;
        prog[4]  = 32'h3800000c;
        prog[5]  = 32'hc8000000;
        prog[6]  = 32'h3800000c;
        prog[7]  = 32'hc8000001;
        prog[8]  = 32'h3800000c;
        prog[9]  = 32'hc8000000;
        prog[10] = 32'h38000004;
        prog[11] = 32'hc8000000;
        prog[12] = 32'h15294000;
        prog[13] = 32'hcd000000;
        prog[14] = 32'h3d00000c;
        prog[15] = 32'hcd000000;
        prog[16] = 32'h3d00000c;
        prog[17] = 32'hcd000000;
        prog[18] = 32'h3d00000c;
        prog[19] = 32'hcd000000;
        prog[20] = 32'h3d00000c;
        prog[21] = 32'hcd000206;
        prog[22] = 32'h3d000004;
        prog[23] = 32'hcd000004;
        prog[24] = 32'h9540007f;
        prog[25] = 32'h82000000;
        prog[26] = 32'h82400008;
        prog[27] = 32'h82800010;
        prog[28] = 32'h82c00018;
        prog[29] = 32'h83000020;
        prog[30] = 32'h83400028;
        prog[31] = 32'h83800030;
        prog[32] = 32'h83c00038;
        prog[33] = 32'h84000040;
        prog[34] = 32'h84400048;
        prog[35] = 32'h84800050;
        prog[36] = 32'h84c00058;
        prog[37] = 32'h85800060;
        prog[38] = 32'h85c00068;
        prog[39] = 32'h86000070;
        prog[40] = 32'h86400078;
        prog[41] = 32'hdd400001;
        prog[42] = 32'h5d2a0000;
        prog[43] = 32'h78000000;

        for (i = 0; i < 524288; i = i + 1)
            dut.memory.bytes[i] = 0;

        for (i = 0; i < 44; i = i + 1)
            write_instr(64'h2000 + i * 4, prog[i]);

        for (i = 0; i < 16; i = i + 1)
            write_u64(64'h10000 + i * 8, i + 1);

        @(posedge clk);
        @(posedge clk);
        reset = 0;

        cyc = 0;
        while (!hlt && cyc < 200000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        if (!hlt) begin
            $display("FAIL: memory_stream hidden timed out at %0d cycles", cyc);
            $finish;
        end

        if (dut.reg_file.registers[8]  !== 64'd1  ||
            dut.reg_file.registers[9]  !== 64'd2  ||
            dut.reg_file.registers[10] !== 64'd3  ||
            dut.reg_file.registers[11] !== 64'd4  ||
            dut.reg_file.registers[12] !== 64'd5  ||
            dut.reg_file.registers[13] !== 64'd6  ||
            dut.reg_file.registers[14] !== 64'd7  ||
            dut.reg_file.registers[15] !== 64'd8  ||
            dut.reg_file.registers[16] !== 64'd9  ||
            dut.reg_file.registers[17] !== 64'd10 ||
            dut.reg_file.registers[18] !== 64'd11 ||
            dut.reg_file.registers[19] !== 64'd12 ||
            dut.reg_file.registers[20] !== 64'd8292 ||
            dut.reg_file.registers[21] !== 64'd0 ||
            dut.reg_file.registers[22] !== 64'd13 ||
            dut.reg_file.registers[23] !== 64'd14 ||
            dut.reg_file.registers[24] !== 64'd15 ||
            dut.reg_file.registers[25] !== 64'd16) begin
            $display("FAIL: memory_stream hidden state mismatch r8=%0d r12=%0d r21=%0d r22=%0d r25=%0d",
                     dut.reg_file.registers[8],
                     dut.reg_file.registers[12],
                     dut.reg_file.registers[21],
                     dut.reg_file.registers[22],
                     dut.reg_file.registers[25]);
            $finish;
        end

        $display("PASS: memory_stream hidden exact image in %0d cycles", cyc);
        $finish;
    end
endmodule
