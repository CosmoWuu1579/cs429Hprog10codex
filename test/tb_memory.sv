// Unit tests for memory.sv — byte-addressable 512KB memory.
// Tests: instruction fetch (dual-port), data read, clocked data write.
`timescale 1ns/1ps
`include "hdl/memory.sv"

module tb_memory;
    reg  clk, reset;
    reg  [63:0] pc_address, pc_address2;
    reg  [63:0] rd_addr;
    reg         mem_write;
    reg  [63:0] wr_addr, wr_data;

    wire [31:0] instruction, instruction2;
    wire [63:0] rd_data;

    memory dut (
        .clk(clk), .reset(reset),
        .pc_address(pc_address), .instruction(instruction),
        .pc_address2(pc_address2), .instruction2(instruction2),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .mem_write(mem_write), .wr_addr(wr_addr), .wr_data(wr_data)
    );

    always #5 clk = ~clk;

    integer failures = 0;

    initial begin
        clk = 0; reset = 0;
        mem_write = 0; wr_addr = 0; wr_data = 0;
        pc_address = 0; pc_address2 = 0; rd_addr = 0;

        // --- Pre-load bytes for instruction fetch test ---
        // Little-endian: instr[7:0] at byte 0, instr[31:24] at byte 3
        // Write instruction 0xDEADBEEF at address 0x2000
        dut.bytes[64'h2000] = 8'hEF;
        dut.bytes[64'h2001] = 8'hBE;
        dut.bytes[64'h2002] = 8'hAD;
        dut.bytes[64'h2003] = 8'hDE;
        // Write instruction 0x12345678 at address 0x2004
        dut.bytes[64'h2004] = 8'h78;
        dut.bytes[64'h2005] = 8'h56;
        dut.bytes[64'h2006] = 8'h34;
        dut.bytes[64'h2007] = 8'h12;

        // --- Test 1: instruction fetch port 0 ---
        pc_address = 64'h2000;
        #1;
        if (instruction !== 32'hDEAD_BEEF) begin
            $display("FAIL test 1: instruction=%h expect DEADBEEF", instruction);
            failures = failures + 1;
        end

        // --- Test 2: instruction fetch port 1 ---
        pc_address2 = 64'h2004;
        #1;
        if (instruction2 !== 32'h1234_5678) begin
            $display("FAIL test 2: instruction2=%h expect 12345678", instruction2);
            failures = failures + 1;
        end

        // --- Test 3: dual-port fetch same cycle ---
        pc_address = 64'h2000; pc_address2 = 64'h2004;
        #1;
        if (instruction !== 32'hDEAD_BEEF || instruction2 !== 32'h1234_5678) begin
            $display("FAIL test 3: dual port: instr0=%h instr1=%h", instruction, instruction2);
            failures = failures + 1;
        end

        // --- Test 4: data read (8 bytes little-endian) ---
        // Pre-load 8 bytes at 0x3000 = 64'hCAFEBABE_DEADBEEF
        dut.bytes[64'h3000] = 8'hEF; dut.bytes[64'h3001] = 8'hBE;
        dut.bytes[64'h3002] = 8'hAD; dut.bytes[64'h3003] = 8'hDE;
        dut.bytes[64'h3004] = 8'hBE; dut.bytes[64'h3005] = 8'hBA;
        dut.bytes[64'h3006] = 8'hFE; dut.bytes[64'h3007] = 8'hCA;
        rd_addr = 64'h3000;
        #1;
        if (rd_data !== 64'hCAFE_BABE_DEAD_BEEF) begin
            $display("FAIL test 4: rd_data=%h expect CAFEBABE_DEADBEEF", rd_data);
            failures = failures + 1;
        end

        // --- Test 5: clocked write then read ---
        mem_write = 1; wr_addr = 64'h4000; wr_data = 64'hABCD_1234_5678_EF00;
        @(posedge clk); #1;
        mem_write = 0;
        rd_addr = 64'h4000;
        #1;
        if (rd_data !== 64'hABCD_1234_5678_EF00) begin
            $display("FAIL test 5: rd_data=%h expect ABCD12345678EF00", rd_data);
            failures = failures + 1;
        end

        // --- Test 6: write does not take effect before clock edge ---
        mem_write = 1; wr_addr = 64'h5000; wr_data = 64'hFFFF_FFFF_FFFF_FFFF;
        rd_addr = 64'h5000;
        #1;
        // Should still read 0 (write latched on clk)
        if (rd_data !== 64'd0) begin
            $display("FAIL test 6: write before clk: rd_data=%h expect 0", rd_data);
            failures = failures + 1;
        end
        @(posedge clk); #1;
        mem_write = 0;
        if (rd_data !== 64'hFFFF_FFFF_FFFF_FFFF) begin
            $display("FAIL test 6b: after clk: rd_data=%h expect FFFF...", rd_data);
            failures = failures + 1;
        end

        // --- Test 7: instruction at byte address 0 (initial value = 0) ---
        pc_address = 64'd0;
        #1;
        if (instruction !== 32'h0) begin
            $display("FAIL test 7: byte0 instruction=%h expect 0", instruction);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: memory — all 7 tests passed");
        else
            $display("FAIL: memory — %0d test(s) failed", failures);
        $finish;
    end
endmodule
