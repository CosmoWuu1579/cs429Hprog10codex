`timescale 1ns/1ps
`include "tinker.sv"

module tb_tinker_core;
    reg clk, reset;
    wire hlt;

    tinker_core dut (.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    task write_instr;
        input [63:0] addr;
        input [31:0] instr;
        begin
            dut.memory.bytes[addr]   = instr[7:0];
            dut.memory.bytes[addr+1] = instr[15:8];
            dut.memory.bytes[addr+2] = instr[23:16];
            dut.memory.bytes[addr+3] = instr[31:24];
        end
    endtask

    function [31:0] enc3;
        input [4:0] op, d, s, t;
        begin
            enc3 = {op, d, s, t, 12'b0};
        end
    endfunction

    function [31:0] enc_halt;
        begin
            enc_halt = {5'h0f, 27'b0};
        end
    endfunction

    integer timeout;

    initial begin
        clk = 0;
        reset = 1;

        write_instr(64'h2000, enc3(5'h18, 5'd2, 5'd0, 5'd1));
        write_instr(64'h2004, enc_halt());

        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);

        dut.reg_file.registers[0] = 64'd17;
        dut.reg_file.registers[1] = 64'd27;

        timeout = 0;
        while (!hlt && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (!hlt) begin
            $display("FAIL: tinker_core timeout");
        end else if (dut.reg_file.registers[2] !== 64'd44) begin
            $display("FAIL: tinker_core r2=%0d expect 44", dut.reg_file.registers[2]);
        end else begin
            $display("PASS: tinker_core smoke test passed");
        end

        $finish;
    end
endmodule
