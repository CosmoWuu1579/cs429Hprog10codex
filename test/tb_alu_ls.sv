// Unit tests for alu_ls.sv — combinational integer ALU.
// Tests every opcode for correct result, reg_write, mem_* signals, and next_pc.
`timescale 1ns/1ps
`include "hdl/alu_ls.sv"

module tb_alu_ls;
    reg  [4:0]  opcode;
    reg  [63:0] src1, src2, L64, pc, r31, mem_val, rd_val;
    reg  [11:0] L;

    wire [63:0] result, mem_addr, mem_wdata, next_pc;
    wire        reg_write, mem_write, mem_read;

    alu_ls dut (
        .opcode(opcode), .src1(src1), .src2(src2), .L(L),
        .pc(pc), .r31(r31), .mem_val(mem_val), .rd_val(rd_val),
        .result(result), .reg_write(reg_write),
        .mem_write(mem_write), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_read(mem_read), .next_pc(next_pc)
    );

    integer failures = 0;

    task check_alu;
        input [63:0] exp_result;
        input        exp_rw;
        input [63:0] exp_next_pc;
        input [63:0] test_id;
        begin
            #1;
            if (result !== exp_result || reg_write !== exp_rw || next_pc !== exp_next_pc) begin
                $display("FAIL test %0d: result=%h rw=%b npc=%h | expect result=%h rw=%b npc=%h",
                    test_id, result, reg_write, next_pc,
                    exp_result, exp_rw, exp_next_pc);
                failures = failures + 1;
            end
        end
    endtask

    task check_mem_write;
        input [63:0] exp_addr, exp_data;
        input [63:0] test_id;
        begin
            #1;
            if (!mem_write || mem_addr !== exp_addr || mem_wdata !== exp_data) begin
                $display("FAIL test %0d (mem_write): mw=%b addr=%h data=%h | expect addr=%h data=%h",
                    test_id, mem_write, mem_addr, mem_wdata, exp_addr, exp_data);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        pc = 64'h2000; r31 = 64'h1000; mem_val = 64'h3000; rd_val = 64'h5000;
        src1 = 0; src2 = 0; L = 0;

        // --- Logic ---
        // and: 0xAA & 0x55 = 0
        opcode = 5'h00; src1 = 64'hAA; src2 = 64'h55; L = 0;
        check_alu(64'h0, 1, 64'h2004, 1);

        // and: 0xFF & 0x0F = 0x0F
        opcode = 5'h00; src1 = 64'hFF; src2 = 64'h0F;
        check_alu(64'h0F, 1, 64'h2004, 2);

        // or: 0xA0 | 0x0B = 0xAB
        opcode = 5'h01; src1 = 64'hA0; src2 = 64'h0B;
        check_alu(64'hAB, 1, 64'h2004, 3);

        // xor: 0xFF ^ 0x0F = 0xF0
        opcode = 5'h02; src1 = 64'hFF; src2 = 64'h0F;
        check_alu(64'hF0, 1, 64'h2004, 4);

        // not: ~0xAA = all-ones xor 0xAA
        opcode = 5'h03; src1 = 64'hAA; src2 = 0;
        check_alu(~64'hAA, 1, 64'h2004, 5);

        // --- Shifts ---
        // shftr: 0x80 >> 3 = 0x10
        opcode = 5'h04; src1 = 64'h80; src2 = 64'd3;
        check_alu(64'h10, 1, 64'h2004, 6);

        // shftri: L=4, src1=0x100 >> 4 = 0x10
        opcode = 5'h05; src1 = 64'h100; L = 12'd4;
        check_alu(64'h10, 1, 64'h2004, 7);

        // shftl: 1 << 8 = 256
        opcode = 5'h06; src1 = 64'h1; src2 = 64'd8;
        check_alu(64'd256, 1, 64'h2004, 8);

        // shftli: L=3, src1=1 << 3 = 8
        opcode = 5'h07; src1 = 64'h1; L = 12'd3;
        check_alu(64'd8, 1, 64'h2004, 9);

        // --- Branches ---
        // br rd: next_pc = src1 (no reg write)
        opcode = 5'h08; src1 = 64'h4000; L = 0;
        check_alu(64'b0, 0, 64'h4000, 10);

        // brr rd: next_pc = pc + src1
        opcode = 5'h09; src1 = 64'h10; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h2010, 11);

        // brr L: pc=0x2000, L=8 → 0x2008
        opcode = 5'h0a; L = 12'd8;
        check_alu(64'b0, 0, 64'h2008, 12);

        // brr L negative: L=12'hFF8 (-8 sign extended) → 0x1FF8
        opcode = 5'h0a; L = 12'hFF8; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h2000 + {{52{1'b1}},12'hFF8}, 13);

        // brnz: src2 != 0 → take branch to src1
        opcode = 5'h0b; src1 = 64'h8000; src2 = 64'd5; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h8000, 14);

        // brnz: src2 == 0 → pc+4
        opcode = 5'h0b; src1 = 64'h8000; src2 = 64'd0; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h2004, 15);

        // --- Call ---
        opcode = 5'h0c; src1 = 64'h9000; pc = 64'h2000; r31 = 64'h1000; L = 0;
        #1;
        if (!mem_write || mem_addr !== 64'hFF8 || mem_wdata !== 64'h2004 || next_pc !== 64'h9000) begin
            $display("FAIL test 16 (call): mw=%b addr=%h wdata=%h npc=%h",
                mem_write, mem_addr, mem_wdata, next_pc);
            failures = failures + 1;
        end

        // --- Return ---
        opcode = 5'h0d; mem_val = 64'h3000; r31 = 64'h1000; pc = 64'h2000;
        #1;
        if (!mem_read || mem_addr !== 64'hFF8 || next_pc !== 64'h3000) begin
            $display("FAIL test 17 (return): mr=%b addr=%h npc=%h", mem_read, mem_addr, next_pc);
            failures = failures + 1;
        end

        // --- brgt: src1 > src2 → take branch to rd_val ---
        opcode = 5'h0e; src1 = 64'd10; src2 = 64'd5; rd_val = 64'h7000; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h7000, 18);

        // brgt: src1 <= src2 → pc+4
        opcode = 5'h0e; src1 = 64'd5; src2 = 64'd10; rd_val = 64'h7000; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h2004, 19);

        // brgt: signed compare, src1 = -1, src2 = 0 → not taken
        opcode = 5'h0e; src1 = 64'hFFFF_FFFF_FFFF_FFFF; src2 = 64'd0; pc = 64'h2000;
        check_alu(64'b0, 0, 64'h2004, 20);

        // --- Data movement ---
        // mov rd, rs: result = src1
        opcode = 5'h11; src1 = 64'hDEAD; src2 = 0;
        check_alu(64'hDEAD, 1, 64'h2004, 21);

        // movl: {src1[63:12], L}
        opcode = 5'h12; src1 = 64'hABCD_EF01_2345_6789; L = 12'hABC;
        #1;
        begin
            reg [63:0] exp;
            exp = {64'hABCD_EF01_2345_6789 >> 12, 12'hABC};  // upper bits from src1, lower from L
            // Actually: result = {src1[63:12], L} = src1 with bits [11:0] replaced by L
            exp = {src1[63:12], 12'hABC};
            if (result !== exp || !reg_write) begin
                $display("FAIL test 22 (movl): result=%h expect=%h rw=%b", result, exp, reg_write);
                failures = failures + 1;
            end
        end

        // --- Integer arithmetic ---
        // add
        opcode = 5'h18; src1 = 64'd100; src2 = 64'd200; L = 0;
        check_alu(64'd300, 1, 64'h2004, 23);

        // add overflow (wrap)
        opcode = 5'h18; src1 = 64'hFFFF_FFFF_FFFF_FFFF; src2 = 64'd1;
        check_alu(64'd0, 1, 64'h2004, 24);

        // addi: src1 + L (zero-extended)
        opcode = 5'h19; src1 = 64'd10; L = 12'd5;
        check_alu(64'd15, 1, 64'h2004, 25);

        // sub
        opcode = 5'h1a; src1 = 64'd300; src2 = 64'd100;
        check_alu(64'd200, 1, 64'h2004, 26);

        // subi
        opcode = 5'h1b; src1 = 64'd20; L = 12'd7;
        check_alu(64'd13, 1, 64'h2004, 27);

        // mul
        opcode = 5'h1c; src1 = 64'd12; src2 = 64'd3;
        check_alu(64'd36, 1, 64'h2004, 28);

        // div
        opcode = 5'h1d; src1 = 64'd36; src2 = 64'd6;
        check_alu(64'd6, 1, 64'h2004, 29);

        // div by zero → 0
        opcode = 5'h1d; src1 = 64'd100; src2 = 64'd0;
        check_alu(64'd0, 1, 64'h2004, 30);

        // div: large value (confirm truncation toward zero)
        opcode = 5'h1d; src1 = 64'd1000; src2 = 64'd7;
        check_alu(64'd142, 1, 64'h2004, 31);

        if (failures == 0)
            $display("PASS: alu_ls — all 31 tests passed");
        else
            $display("FAIL: alu_ls — %0d test(s) failed", failures);
        $finish;
    end
endmodule
