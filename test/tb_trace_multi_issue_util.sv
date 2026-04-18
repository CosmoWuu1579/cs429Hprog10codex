`timescale 1ns/1ps
`include "tinker.sv"

module tb_trace_multi_issue_util;
    reg clk, reset;
    wire hlt;

    integer cyc;
    integer dual_issue_cycles;
    integer single_issue_cycles;
    integer ready_two_cycles;

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

    function [31:0] encL;
        input [4:0] op, d;
        input [11:0] L;
        begin
            encL = {op, d, 10'b0, L};
        end
    endfunction

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

    initial begin
        clk = 0;
        reset = 1;
        dual_issue_cycles = 0;
        single_issue_cycles = 0;
        ready_two_cycles = 0;

        // Pairable ALU/immediate stream.
        write_instr(64'h2000, encL(5'h19, 5'd1, 12'd1));
        write_instr(64'h2004, encL(5'h19, 5'd2, 12'd2));
        write_instr(64'h2008, encL(5'h19, 5'd3, 12'd3));
        write_instr(64'h200c, encL(5'h19, 5'd4, 12'd4));
        write_instr(64'h2010, enc3(5'h18, 5'd5, 5'd1, 5'd2));
        write_instr(64'h2014, enc3(5'h18, 5'd6, 5'd3, 5'd4));
        write_instr(64'h2018, enc3(5'h18, 5'd7, 5'd5, 5'd6));
        write_instr(64'h201c, enc3(5'h18, 5'd8, 5'd1, 5'd3));
        write_instr(64'h2020, enc3(5'h18, 5'd9, 5'd2, 5'd4));
        write_instr(64'h2024, enc3(5'h18, 5'd10, 5'd8, 5'd9));
        write_instr(64'h2028, enc3(5'h18, 5'd11, 5'd7, 5'd10));
        write_instr(64'h202c, enc3(5'h18, 5'd12, 5'd5, 5'd8));
        write_instr(64'h2030, enc3(5'h18, 5'd13, 5'd6, 5'd9));
        write_instr(64'h2034, enc3(5'h18, 5'd14, 5'd12, 5'd13));
        write_instr(64'h2038, enc3(5'h18, 5'd15, 5'd11, 5'd14));
        write_instr(64'h203c, enc_halt());

        @(posedge clk);
        @(posedge clk);
        reset = 0;

        for (cyc = 0; cyc < 200; cyc = cyc + 1) begin
            @(posedge clk);

            if (dut.alu0_iss_valid && dut.alu1_iss_valid)
                dual_issue_cycles = dual_issue_cycles + 1;

            if (dut.alu0_iss_valid && !dut.alu1_iss_valid)
                single_issue_cycles = single_issue_cycles + 1;

            if (dut.alu_rs.sel_found && dut.alu_rs.sel2_found) begin
                ready_two_cycles = ready_two_cycles + 1;
                if (!dut.alu1_iss_valid) begin
                    $display("TRACE multi suppress cyc=%0d rs_ready_two=1 issue0=%b issue1=%b disp0=%b disp1=%b stall=%b slot0=%b slot1=%b",
                        cyc, dut.alu0_iss_valid, dut.alu1_iss_valid,
                        dut.dispatch0_en, dut.dispatch1_en, dut.stall, dut.slot0_ok, dut.slot1_ok);
                end
            end

            if (hlt) begin
                $display("TRACE multi summary cyc=%0d dual=%0d single=%0d rs_ready_two=%0d",
                    cyc, dual_issue_cycles, single_issue_cycles, ready_two_cycles);
                $finish;
            end
        end

        $display("TRACE multi timeout dual=%0d single=%0d rs_ready_two=%0d",
            dual_issue_cycles, single_issue_cycles, ready_two_cycles);
        $finish;
    end
endmodule
