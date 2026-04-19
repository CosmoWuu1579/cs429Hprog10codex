`timescale 1ns/1ps
`include "tinker.sv"

module tb_trace_branch_bubble;
    reg clk, reset;
    wire hlt;

    integer cyc;
    integer pending0_cycle, pending1_cycle;
    reg [63:0] pending0_pc, pending1_pc;

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

    initial begin
        clk = 0;
        reset = 1;
        pending0_cycle = -1;
        pending1_cycle = -1;

        write_instr(64'h2000, encL(5'h1b, 5'd21, 12'd1));       // subi r21,1
        write_instr(64'h2004, enc3(5'h0b, 5'd20, 5'd21, 5'd0)); // brnz r20,r21
        write_instr(64'h2008, enc_halt());
        write_instr(64'h200c, enc3(5'h08, 5'd22, 5'd0, 5'd0));   // b1: br r22
        write_instr(64'h2010, enc3(5'h08, 5'd23, 5'd0, 5'd0));   // b2: br r23
        write_instr(64'h2014, enc3(5'h08, 5'd24, 5'd0, 5'd0));   // b3: br r24
        write_instr(64'h2018, enc3(5'h08, 5'd25, 5'd0, 5'd0));   // b4: br r25
        write_instr(64'h201c, enc3(5'h08, 5'd26, 5'd0, 5'd0));   // b5: br r26

        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);

        dut.reg_file.registers[20] = 64'h200c;
        dut.reg_file.registers[21] = 64'd8;
        dut.reg_file.registers[22] = 64'h2010;
        dut.reg_file.registers[23] = 64'h2014;
        dut.reg_file.registers[24] = 64'h2018;
        dut.reg_file.registers[25] = 64'h201c;
        dut.reg_file.registers[26] = 64'h2000;

        for (cyc = 0; cyc < 300; cyc = cyc + 1) begin
            @(posedge clk);

            if (dut.dispatch0_en &&
                (dut.f_instr0[31:27] >= 5'h08 && dut.f_instr0[31:27] <= 5'h0e)) begin
                $display("TRACE br disp0 cyc=%0d pc=%h instr=%h pred=%h ft=%h",
                    cyc, dut.f_pc0, dut.f_instr0, dut.f_pred_pc0,
                    (dut.f_valid1 ? (dut.f_pc0 + 64'd8) : (dut.f_pc0 + 64'd4)));
            end
            if (dut.dispatch1_en &&
                (dut.f_instr1[31:27] >= 5'h08 && dut.f_instr1[31:27] <= 5'h0e)) begin
                $display("TRACE br disp1 cyc=%0d pc=%h instr=%h pred=%h ft=%h",
                    cyc, dut.f_pc1, dut.f_instr1, dut.f_pred_pc1, (dut.f_pc1 + 64'd4));
            end

            if (dut.alu0_v_r && dut.alu0_br_r && dut.alu0_taken_r) begin
                pending0_cycle = cyc;
                pending0_pc = dut.alu0_apc_r;
                $display("TRACE br resolve alu0 cyc=%0d pc=%h target=%h pred=%h mis=%b",
                    cyc, dut.alu0_pc_r, dut.alu0_apc_r, dut.alu0_pred_pc, dut.alu0_mis_r);
            end
            if (dut.alu1_v_r && dut.alu1_br_r && dut.alu1_taken_r) begin
                pending1_cycle = cyc;
                pending1_pc = dut.alu1_apc_r;
                $display("TRACE br resolve alu1 cyc=%0d pc=%h target=%h pred=%h mis=%b",
                    cyc, dut.alu1_pc_r, dut.alu1_apc_r, dut.alu1_pred_pc, dut.alu1_mis_r);
            end

            if (pending0_cycle >= 0 &&
                ((dut.dispatch0_en && dut.f_pc0 == pending0_pc) ||
                 (dut.dispatch1_en && dut.f_pc1 == pending0_pc))) begin
                $display("TRACE br dispatch target=%h resolve_cyc=%0d dispatch_cyc=%0d bubble=%0d",
                    pending0_pc, pending0_cycle, cyc, cyc - pending0_cycle);
                pending0_cycle = -1;
            end
            if (pending1_cycle >= 0 &&
                ((dut.dispatch0_en && dut.f_pc0 == pending1_pc) ||
                 (dut.dispatch1_en && dut.f_pc1 == pending1_pc))) begin
                $display("TRACE br dispatch target=%h resolve_cyc=%0d dispatch_cyc=%0d bubble=%0d",
                    pending1_pc, pending1_cycle, cyc, cyc - pending1_cycle);
                pending1_cycle = -1;
            end

            if (hlt) begin
                $display("TRACE branch bubble run halted at cyc=%0d", cyc);
                $finish;
            end
        end

        $display("TRACE branch bubble timeout");
        $finish;
    end
endmodule
