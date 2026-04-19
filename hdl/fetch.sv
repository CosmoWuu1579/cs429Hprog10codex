// Two-wide fetch front-end with BTB state.
module fetch (
    input  clk,
    input  reset,
    input  wire        stall,
    input  wire        consume,
    input  wire        consume_slot0_only,
    input  wire        flush,
    input  wire [63:0] flush_pc,
    input  wire        bp0_update,
    input  wire [63:0] bp0_pc,
    input  wire        bp0_taken,
    input  wire [63:0] bp0_target,
    input  wire        bp1_update,
    input  wire [63:0] bp1_pc,
    input  wire        bp1_taken,
    input  wire [63:0] bp1_target,
    input  wire [31:0] mem_instr0,
    input  wire [31:0] mem_instr1,
    output wire [63:0] fetch_pc0,
    output wire [63:0] fetch_pc1,
    output reg         out_valid0,
    output reg  [31:0] out_instr0,
    output reg  [63:0] out_pc0,
    output reg         out_valid1,
    output reg  [31:0] out_instr1,
    output reg  [63:0] out_pc1,
    output reg  [63:0] out_pred_pc0,
    output reg  [63:0] out_pred_pc1,
    output reg  [63:0] out_pred_pc
);
    reg [63:0] pc;

    reg        btb_valid [0:15];
    reg [63:0] btb_tag   [0:15];
    reg [63:0] btb_tgt   [0:15];
    reg [1:0]  btb_ctr   [0:15];

    integer i;

    function slot0_kills_slot1;
        input [63:0] base_pc;
        input [31:0] instr0;
        reg [4:0] op0;
        reg [63:0] pred_tgt;
        begin
            op0 = instr0[31:27];
            pred_tgt = base_pc + 64'd4;
            if (op0 == 5'h0a) begin
                pred_tgt = base_pc + {{52{instr0[11]}}, instr0[11:0]};
                slot0_kills_slot1 = (pred_tgt != base_pc + 64'd4);
            end else if ((op0 == 5'h08) || (op0 == 5'h09) || (op0 == 5'h0b) ||
                         (op0 == 5'h0c) || (op0 == 5'h0d) || (op0 == 5'h0e)) begin
                if (btb_valid[base_pc[5:2]] && btb_tag[base_pc[5:2]] == base_pc) begin
                    pred_tgt = btb_tgt[base_pc[5:2]];
                    if (pred_tgt == base_pc + 64'd4)
                        slot0_kills_slot1 = 1'b0;
                    else
                        slot0_kills_slot1 = 1'b1;
                end else begin
                    slot0_kills_slot1 = 1'b1;
                end
            end else begin
                slot0_kills_slot1 = 1'b0;
            end
        end
    endfunction

    function [63:0] predict_next_pc;
        input [63:0] base_pc;
        input [31:0] instr0;
        input [31:0] instr1;
        reg [4:0] op0;
        reg [4:0] op1;
        reg [11:0] l0;
        reg [11:0] l1;
        reg [63:0] pc1;
        reg [63:0] slot0_tgt;
        reg        slot0_allows_slot1;
        begin
            op0 = instr0[31:27];
            op1 = instr1[31:27];
            l0 = instr0[11:0];
            l1 = instr1[11:0];
            pc1 = base_pc + 4;
            predict_next_pc = base_pc + 8;
            slot0_tgt = pc1;
            slot0_allows_slot1 = 1'b1;

            if (op0 == 5'h0a) begin
                slot0_tgt = base_pc + {{52{l0[11]}}, l0};
                if (slot0_tgt != pc1) begin
                    predict_next_pc = slot0_tgt;
                    slot0_allows_slot1 = 1'b0;
                end
            end else if ((op0 == 5'h08 || op0 == 5'h09 || op0 == 5'h0b ||
                          op0 == 5'h0c || op0 == 5'h0d || op0 == 5'h0e)) begin
                if (btb_valid[base_pc[5:2]] && btb_tag[base_pc[5:2]] == base_pc &&
                    btb_ctr[base_pc[5:2]][1]) begin
                    slot0_tgt = btb_tgt[base_pc[5:2]];
                    if (slot0_tgt != pc1) begin
                        predict_next_pc = slot0_tgt;
                        slot0_allows_slot1 = 1'b0;
                    end
                end else begin
                    predict_next_pc = pc1;
                    slot0_allows_slot1 = 1'b0;
                end
            end

            if (slot0_allows_slot1) begin
                if (op1 == 5'h0a) begin
                predict_next_pc = pc1 + {{52{l1[11]}}, l1};
                end else if ((op1 == 5'h08 || op1 == 5'h09 || op1 == 5'h0b ||
                              op1 == 5'h0c || op1 == 5'h0d || op1 == 5'h0e) &&
                             btb_valid[pc1[5:2]] && btb_tag[pc1[5:2]] == pc1 &&
                             btb_ctr[pc1[5:2]][1]) begin
                    predict_next_pc = btb_tgt[pc1[5:2]];
                end
            end
        end
    endfunction

    assign fetch_pc0 = flush ? flush_pc : pc;
    assign fetch_pc1 = flush ? (flush_pc + 64'd4) : (pc + 64'd4);

    always @(posedge clk) begin
        if (reset) begin
            pc <= 64'h2000;
            out_valid0 <= 0;
            out_valid1 <= 0;
            out_instr0 <= 32'b0;
            out_instr1 <= 32'b0;
            out_pc0 <= 64'b0;
            out_pc1 <= 64'b0;
            out_pred_pc0 <= 64'h2008;
            out_pred_pc1 <= 64'h2008;
            out_pred_pc <= 64'h2008;
            for (i = 0; i < 16; i = i + 1) begin
                btb_valid[i] <= 0;
                btb_tag[i] <= 64'b0;
                btb_tgt[i] <= 64'b0;
                btb_ctr[i] <= 2'b01;
            end
        end else begin
            if (bp0_update) begin
                btb_valid[bp0_pc[5:2]] <= 1'b1;
                btb_tag[bp0_pc[5:2]] <= bp0_pc;
                btb_tgt[bp0_pc[5:2]] <= bp0_target;
                if (bp0_taken) begin
                    if (btb_ctr[bp0_pc[5:2]] != 2'b11) begin
                        btb_ctr[bp0_pc[5:2]] <= btb_ctr[bp0_pc[5:2]] + 1'b1;
                    end
                end else begin
                    if (btb_ctr[bp0_pc[5:2]] != 2'b00) begin
                        btb_ctr[bp0_pc[5:2]] <= btb_ctr[bp0_pc[5:2]] - 1'b1;
                    end
                end
            end

            if (bp1_update) begin
                btb_valid[bp1_pc[5:2]] <= 1'b1;
                btb_tag[bp1_pc[5:2]] <= bp1_pc;
                btb_tgt[bp1_pc[5:2]] <= bp1_target;
                if (bp1_taken) begin
                    if (btb_ctr[bp1_pc[5:2]] != 2'b11) begin
                        btb_ctr[bp1_pc[5:2]] <= btb_ctr[bp1_pc[5:2]] + 1'b1;
                    end
                end else begin
                    if (btb_ctr[bp1_pc[5:2]] != 2'b00) begin
                        btb_ctr[bp1_pc[5:2]] <= btb_ctr[bp1_pc[5:2]] - 1'b1;
                    end
                end
            end

            if (flush) begin
                pc <= flush_pc;
                out_valid0 <= 0;
                out_valid1 <= 0;
                out_instr0 <= 32'b0;
                out_instr1 <= 32'b0;
                out_pc0 <= 64'b0;
                out_pc1 <= 64'b0;
                out_pred_pc0 <= flush_pc + 8;
                out_pred_pc1 <= flush_pc + 8;
                out_pred_pc <= flush_pc + 8;
            end else if (consume_slot0_only) begin
                pc <= out_pc1 + 64'd4;
                out_valid0 <= out_valid1;
                out_instr0 <= out_instr1;
                out_pc0 <= out_pc1;
                out_valid1 <= 1'b0;
                out_instr1 <= 32'b0;
                out_pc1 <= out_pc1 + 64'd4;
                out_pred_pc0 <= predict_next_pc(out_pc1, out_instr1, 32'b0);
                out_pred_pc1 <= predict_next_pc(out_pc1 + 64'd4, 32'b0, 32'b0);
                out_pred_pc <= predict_next_pc(out_pc1, out_instr1, 32'b0);
            end else if (stall) begin
                if (consume) begin
                    out_valid0 <= 1'b0;
                    out_valid1 <= 1'b0;
                    out_pred_pc0 <= out_pred_pc0;
                    out_pred_pc1 <= out_pred_pc1;
                end else begin
                    out_valid0 <= out_valid0;
                    out_valid1 <= out_valid1 && !slot0_kills_slot1(out_pc0, out_instr0);
                    out_instr0 <= out_instr0;
                    out_instr1 <= out_instr1;
                    out_pc0 <= out_pc0;
                    out_pc1 <= out_pc1;
                    out_pred_pc0 <= predict_next_pc(out_pc0, out_instr0, out_instr1);
                    out_pred_pc1 <= predict_next_pc(out_pc1, out_instr1, 32'b0);
                    out_pred_pc <= predict_next_pc(out_pc0, out_instr0, out_instr1);
                end
            end else begin
                out_valid0 <= 1'b1;
                out_valid1 <= !slot0_kills_slot1(pc, mem_instr0);
                out_instr0 <= mem_instr0;
                out_instr1 <= mem_instr1;
                out_pc0 <= pc;
                out_pc1 <= pc + 4;
                out_pred_pc0 <= predict_next_pc(pc, mem_instr0, mem_instr1);
                out_pred_pc1 <= predict_next_pc(pc + 64'd4, mem_instr1, 32'b0);
                out_pred_pc <= predict_next_pc(pc, mem_instr0, mem_instr1);
                pc <= predict_next_pc(pc, mem_instr0, mem_instr1);
            end
        end
    end
endmodule
