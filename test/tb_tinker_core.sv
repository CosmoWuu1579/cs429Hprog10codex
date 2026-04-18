`timescale 1ns/1ps
`include "tinker.sv"

module tb_tinker_core;
    reg clk, reset;
    wire hlt;

    tinker_core dut (.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    task clear_mem;
        integer i;
        begin
            for (i = 0; i < 524288; i = i + 1)
                dut.memory.bytes[i] = 8'h00;
        end
    endtask

    task clear_regs;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                dut.reg_file.registers[i] = 64'd0;
            dut.reg_file.registers[31] = 64'd524288;
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

    task boot_core;
        begin
            reset = 1;
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            @(posedge clk);
        end
    endtask

    task wait_for_halt;
        output integer timeout;
        begin
            timeout = 0;
            while (!hlt && timeout < 500) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
        end
    endtask

    integer timeout;
    integer failures;

    initial begin
        clk = 0;
        reset = 1;
        failures = 0;

        clear_mem();
        clear_regs();
        write_instr(64'h2000, enc3(5'h18, 5'd2, 5'd0, 5'd1));
        write_instr(64'h2004, enc_halt());
        boot_core();
        dut.reg_file.registers[0] = 64'd17;
        dut.reg_file.registers[1] = 64'd27;
        wait_for_halt(timeout);
        if (timeout >= 500 || dut.reg_file.registers[2] !== 64'd44) begin
            $display("FAIL test1_add_halt: timeout=%0d r2=%0d", timeout, dut.reg_file.registers[2]);
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, enc3(5'h08, 5'd1, 5'd0, 5'd0));
        write_instr(64'h2004, encL(5'h19, 5'd0, 12'd1));
        write_instr(64'h2008, encL(5'h19, 5'd0, 12'd10));
        write_instr(64'h200C, enc_halt());
        boot_core();
        dut.reg_file.registers[0] = 64'd100;
        dut.reg_file.registers[1] = 64'h2008;
        wait_for_halt(timeout);
        if (timeout >= 500 || dut.reg_file.registers[0] !== 64'd110) begin
            $display("FAIL test2_branch_skip: timeout=%0d r0=%0d", timeout, dut.reg_file.registers[0]);
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, encL(5'h1b, 5'd2, 12'd1));
        write_instr(64'h2004, enc3(5'h0b, 5'd1, 5'd2, 5'd0));
        write_instr(64'h2008, enc_halt());
        boot_core();
        dut.reg_file.registers[1] = 64'h2000;
        dut.reg_file.registers[2] = 64'd3;
        wait_for_halt(timeout);
        if (timeout >= 500 || dut.reg_file.registers[2] !== 64'd0) begin
            $display("FAIL test3_branch_loop: timeout=%0d r2=%0d", timeout, dut.reg_file.registers[2]);
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, enc3(5'h11, 5'd3, 5'd3, 5'd0));
        write_instr(64'h2004, enc3(5'h13, 5'd2, 5'd1, 5'd0));
        write_instr(64'h2008, enc_halt());
        boot_core();
        dut.reg_file.registers[1] = 64'h1122_3344_5566_7788;
        dut.reg_file.registers[2] = 64'h3000;
        wait_for_halt(timeout);
        if (timeout >= 500 || {dut.memory.bytes[64'h3007], dut.memory.bytes[64'h3006],
                     dut.memory.bytes[64'h3005], dut.memory.bytes[64'h3004],
                     dut.memory.bytes[64'h3003], dut.memory.bytes[64'h3002],
                     dut.memory.bytes[64'h3001], dut.memory.bytes[64'h3000]}
                    !== 64'h1122_3344_5566_7788) begin
            $display("FAIL test4_slot1_store");
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, 32'h9804_0008);
        write_instr(64'h2004, enc_halt());
        boot_core();
        dut.reg_file.registers[2] = 64'd71;
        wait_for_halt(timeout);
        @(posedge clk);
        if (timeout >= 500 || {dut.memory.bytes[64'd15], dut.memory.bytes[64'd14],
                     dut.memory.bytes[64'd13], dut.memory.bytes[64'd12],
                     dut.memory.bytes[64'd11], dut.memory.bytes[64'd10],
                     dut.memory.bytes[64'd9], dut.memory.bytes[64'd8]}
                    !== 64'd71) begin
            $display("FAIL test5_store_offset_halt");
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, encL(5'h19, 5'd0, 12'd1));
        write_instr(64'h2004, encL(5'h19, 5'd1, 12'd1));
        write_instr(64'h2008, encL(5'h19, 5'd2, 12'd1));
        write_instr(64'h200C, encL(5'h19, 5'd3, 12'd1));
        write_instr(64'h2010, encL(5'h19, 5'd4, 12'd1));
        write_instr(64'h2014, encL(5'h19, 5'd5, 12'd1));
        write_instr(64'h2018, encL(5'h19, 5'd6, 12'd1));
        write_instr(64'h201C, encL(5'h19, 5'd7, 12'd1));
        write_instr(64'h2020, encL(5'h19, 5'd8, 12'd1));
        write_instr(64'h2024, encL(5'h19, 5'd9, 12'd1));
        write_instr(64'h2028, encL(5'h19, 5'd10, 12'd1));
        write_instr(64'h202C, encL(5'h19, 5'd11, 12'd1));
        write_instr(64'h2030, enc_halt());
        boot_core();
        wait_for_halt(timeout);
        if (timeout >= 500 || dut.reg_file.registers[11] !== 64'd1) begin
            $display("FAIL test6_rename_pressure: timeout=%0d r11=%0d", timeout, dut.reg_file.registers[11]);
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, encL(5'h19, 5'd0, 12'd1));
        write_instr(64'h2004, encL(5'h19, 5'd1, 12'd1));
        write_instr(64'h2008, encL(5'h19, 5'd2, 12'd1));
        write_instr(64'h200C, encL(5'h19, 5'd3, 12'd1));
        write_instr(64'h2010, encL(5'h19, 5'd4, 12'd1));
        write_instr(64'h2014, encL(5'h19, 5'd5, 12'd1));
        write_instr(64'h2018, encL(5'h19, 5'd6, 12'd1));
        write_instr(64'h201C, encL(5'h19, 5'd7, 12'd1));
        write_instr(64'h2020, encL(5'h19, 5'd8, 12'd1));
        write_instr(64'h2024, encL(5'h19, 5'd9, 12'd1));
        write_instr(64'h2028, encL(5'h19, 5'd10, 12'd1));
        write_instr(64'h202C, encL(5'h19, 5'd11, 12'd1));
        write_instr(64'h2030, encL(5'h19, 5'd12, 12'd1));
        write_instr(64'h2034, encL(5'h19, 5'd13, 12'd1));
        write_instr(64'h2038, encL(5'h19, 5'd14, 12'd1));
        write_instr(64'h203C, encL(5'h19, 5'd15, 12'd1));
        write_instr(64'h2040, encL(5'h19, 5'd16, 12'd1));
        write_instr(64'h2044, encL(5'h19, 5'd17, 12'd1));
        write_instr(64'h2048, encL(5'h19, 5'd18, 12'd1));
        write_instr(64'h204C, encL(5'h19, 5'd19, 12'd1));
        write_instr(64'h2050, encL(5'h19, 5'd20, 12'd1));
        write_instr(64'h2054, enc_halt());
        boot_core();
        wait_for_halt(timeout);
        if (timeout >= 500 ||
            dut.reg_file.registers[10] !== 64'd1 ||
            dut.reg_file.registers[11] !== 64'd1 ||
            dut.reg_file.registers[12] !== 64'd1 ||
            dut.reg_file.registers[16] !== 64'd1 ||
            dut.reg_file.registers[17] !== 64'd1 ||
            dut.reg_file.registers[20] !== 64'd1) begin
            $display("FAIL test7_rob_wrap_issue: timeout=%0d r10=%0d r11=%0d r12=%0d r16=%0d r17=%0d r20=%0d",
                     timeout, dut.reg_file.registers[10], dut.reg_file.registers[11],
                     dut.reg_file.registers[12], dut.reg_file.registers[16],
                     dut.reg_file.registers[17], dut.reg_file.registers[20]);
            failures = failures + 1;
        end

        clear_mem();
        clear_regs();
        write_instr(64'h2000, encL(5'h19, 5'd1, 12'd1));
        write_instr(64'h2004, encL(5'h19, 5'd2, 12'd1));
        write_instr(64'h2008, encL(5'h19, 5'd17, 12'd1));
        write_instr(64'h200C, encL(5'h19, 5'd18, 12'd1));
        write_instr(64'h2010, encL(5'h19, 5'd29, 12'd1));
        write_instr(64'h2014, encL(5'h19, 5'd30, 12'd1));
        write_instr(64'h2018, enc_halt());
        boot_core();
        wait_for_halt(timeout);
        if (timeout >= 500 ||
            dut.reg_file.registers[1] !== 64'd1 ||
            dut.reg_file.registers[2] !== 64'd1 ||
            dut.reg_file.registers[17] !== 64'd1 ||
            dut.reg_file.registers[18] !== 64'd1 ||
            dut.reg_file.registers[29] !== 64'd1 ||
            dut.reg_file.registers[30] !== 64'd1) begin
            $display("FAIL test8_forwarding_boundary: timeout=%0d r1=%0d r2=%0d r17=%0d r18=%0d r29=%0d r30=%0d",
                     timeout, dut.reg_file.registers[1], dut.reg_file.registers[2],
                     dut.reg_file.registers[17], dut.reg_file.registers[18],
                     dut.reg_file.registers[29], dut.reg_file.registers[30]);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: tinker_core regression tests passed");
        else
            $display("FAIL: tinker_core regression failures=%0d", failures);

        $finish;
    end
endmodule
