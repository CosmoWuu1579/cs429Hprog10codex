`timescale 1ns/1ps
`include "tinker.sv"

module tb_debug_control;
    reg clk, reset;
    wire hlt;

    tinker_core dut (.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    task clear_program;
        integer i;
        begin
            for (i = 64'h2000; i < 64'h2100; i = i + 1)
                dut.memory.bytes[i] = 8'h00;
        end
    endtask

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

    function [31:0] encL;
        input [4:0] op, d;
        input [11:0] L;
        begin
            encL = {op, d, 10'b0, L};
        end
    endfunction

    function [31:0] enc_halt;
        begin
            enc_halt = {5'h0f, 27'b0};
        end
    endfunction

    task bring_out_of_reset;
        begin
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            @(posedge clk);
        end
    endtask

    task wait_for_halt;
        output integer cycles;
        begin
            cycles = 0;
            while (!hlt && cycles < 200) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    integer cycles;
    integer failures;

    initial begin
        clk = 0;
        reset = 1;
        failures = 0;

        // Test 1: taken branch must squash younger addi.
        clear_program();
        write_instr(64'h2000, enc3(5'h08, 5'd1, 5'd0, 5'd0));  // br r1
        write_instr(64'h2004, encL(5'h19, 5'd0, 12'd1));       // addi r0, 1
        write_instr(64'h2010, enc_halt());
        bring_out_of_reset();
        dut.reg_file.registers[0] = 64'd110;
        dut.reg_file.registers[1] = 64'h2010;
        wait_for_halt(cycles);
        if (!hlt || dut.reg_file.registers[0] !== 64'd110) begin
            $display("FAIL branch_case: hlt=%b r0=%0d", hlt, dut.reg_file.registers[0]);
            failures = failures + 1;
        end

        reset = 1;

        // Test 2: store must commit to memory.
        clear_program();
        write_instr(64'h2000, enc3(5'h13, 5'd2, 5'd1, 5'd0));  // store [r2], r1
        write_instr(64'h2004, enc_halt());
        bring_out_of_reset();
        dut.reg_file.registers[1] = 64'h1122_3344_5566_7788;
        dut.reg_file.registers[2] = 64'h3000;
        wait_for_halt(cycles);
        if (!hlt || {dut.memory.bytes[64'h3007], dut.memory.bytes[64'h3006],
                     dut.memory.bytes[64'h3005], dut.memory.bytes[64'h3004],
                     dut.memory.bytes[64'h3003], dut.memory.bytes[64'h3002],
                     dut.memory.bytes[64'h3001], dut.memory.bytes[64'h3000]}
                    !== 64'h1122_3344_5566_7788) begin
            $display("FAIL store_case");
            failures = failures + 1;
        end

        reset = 1;

        // Test 3: call stores link and return branches back to halt.
        clear_program();
        write_instr(64'h2000, enc3(5'h0c, 5'd1, 5'd0, 5'd0));  // call r1
        write_instr(64'h2004, enc_halt());
        write_instr(64'h2010, enc3(5'h0d, 5'd0, 5'd0, 5'd0));  // return
        bring_out_of_reset();
        dut.reg_file.registers[1] = 64'h2010;
        wait_for_halt(cycles);
        if (!hlt || {dut.memory.bytes[64'd524287], dut.memory.bytes[64'd524286],
                     dut.memory.bytes[64'd524285], dut.memory.bytes[64'd524284],
                     dut.memory.bytes[64'd524283], dut.memory.bytes[64'd524282],
                     dut.memory.bytes[64'd524281], dut.memory.bytes[64'd524280]}
                    !== 64'h0000_0000_0000_2004) begin
            $display("FAIL call_return_case");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: debug control cases passed");
        else
            $display("FAIL: debug control cases failures=%0d", failures);
        $finish;
    end
endmodule
