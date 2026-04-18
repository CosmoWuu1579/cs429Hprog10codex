`timescale 1ns/1ps
`include "tinker.sv"

module tb_trace_memory_stream_cycles;
    reg clk;
    reg reset;
    wire hlt;

    integer cyc;
    integer i;
    reg [31:0] prog [0:43];
    integer last_commit_cycle;
    integer stuck_cycles;

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
        last_commit_cycle = 0;
        stuck_cycles = 0;
        while (!hlt && cyc < 20000) begin
            @(posedge clk);
            cyc = cyc + 1;

            if (dut.commit0_en || dut.commit1_en || dut.dispatch0_en || dut.dispatch1_en)
                last_commit_cycle = cyc;
            stuck_cycles = cyc - last_commit_cycle;

            $display("TRACE mem cyc=%0d pc=%h disp0=%b/%h disp1=%b/%h rob=%0d lq=%0d cq=%0d sq=%0d stall=%b slot0=%b slot1=%b ldv=%b grant=%b hlt=%b r21=%0d",
                cyc,
                dut.fetch_unit.fetch_pc0,
                dut.dispatch0_en, dut.f_instr0,
                dut.dispatch1_en, dut.f_instr1,
                dut.rob_inst.count,
                dut.lsq_inst.lq_count,
                dut.lsq_inst.cq_count,
                dut.lsq_inst.sq_count,
                dut.stall,
                dut.slot0_ok,
                dut.slot1_ok,
                dut.lsq_ld_cdb_v,
                dut.lsq_ld_cdb_grant,
                hlt,
                dut.reg_file.registers[21]);

            if (dut.commit0_en && dut.commit0_reg_wr && dut.commit0_areg == 5'd21) begin
                $display("TRACE r21 commit0 cyc=%0d result=%0d fetch_pc=%h instr0=%h instr1=%h",
                    cyc, dut.commit0_result, dut.fetch_unit.out_pc0, dut.fetch_unit.out_instr0, dut.fetch_unit.out_instr1);
            end
            if (dut.commit1_en && dut.commit1_reg_wr && dut.commit1_areg == 5'd21) begin
                $display("TRACE r21 commit1 cyc=%0d result=%0d fetch_pc=%h instr0=%h instr1=%h",
                    cyc, dut.commit1_result, dut.fetch_unit.out_pc0, dut.fetch_unit.out_instr0, dut.fetch_unit.out_instr1);
            end

            if (stuck_cycles >= 50) begin
                $display("TRACE stuck cyc=%0d last_progress=%0d pc=%h last_disp0=%h rob=%0d lq=%0d cq=%0d sq=%0d stall=%b slot0=%b slot1=%b",
                    cyc, last_commit_cycle, dut.fetch_unit.fetch_pc0, dut.f_instr0,
                    dut.rob_inst.count, dut.lsq_inst.lq_count, dut.lsq_inst.cq_count, dut.lsq_inst.sq_count,
                    dut.stall, dut.slot0_ok, dut.slot1_ok);
                $finish;
            end
        end

        $display("TRACE done cyc=%0d hlt=%b r12=%0d r21=%0d r25=%0d",
            cyc, hlt, dut.reg_file.registers[12], dut.reg_file.registers[21], dut.reg_file.registers[25]);
        $finish;
    end
endmodule
