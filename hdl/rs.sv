module rs #(
    parameter DEPTH = 8
) (
    input  clk,
    input  reset,
    input  wire flush,  // squash all entries with rob_idx > flush_rob_idx
    input  wire [3:0] flush_rob_idx,

    // Dispatch port 0
    input  wire        disp0_en,
    input  wire [4:0]  disp0_op,
    input  wire [5:0]  disp0_dest_preg,
    input  wire [3:0]  disp0_rob_idx,
    input  wire [5:0]  disp0_s_preg,
    input  wire [63:0] disp0_s_val,
    input  wire        disp0_s_rdy,
    input  wire [5:0]  disp0_t_preg,
    input  wire [63:0] disp0_t_val,
    input  wire        disp0_t_rdy,
    input  wire [11:0] disp0_L,
    input  wire [63:0] disp0_pc,
    // 3rd source (rd) for brgt; use rd_rdy=1 for all other instructions
    input  wire [5:0]  disp0_rd_preg,
    input  wire [63:0] disp0_rd_val,
    input  wire        disp0_rd_rdy,

    // Dispatch port 1
    input  wire        disp1_en,
    input  wire [4:0]  disp1_op,
    input  wire [5:0]  disp1_dest_preg,
    input  wire [3:0]  disp1_rob_idx,
    input  wire [5:0]  disp1_s_preg,
    input  wire [63:0] disp1_s_val,
    input  wire        disp1_s_rdy,
    input  wire [5:0]  disp1_t_preg,
    input  wire [63:0] disp1_t_val,
    input  wire        disp1_t_rdy,
    input  wire [11:0] disp1_L,
    input  wire [63:0] disp1_pc,
    input  wire [5:0]  disp1_rd_preg,
    input  wire [63:0] disp1_rd_val,
    input  wire        disp1_rd_rdy,

    // CDB snoop (2 buses)
    input  wire        cdb0_valid,
    input  wire [5:0]  cdb0_preg,
    input  wire [63:0] cdb0_data,
    input  wire        cdb1_valid,
    input  wire [5:0]  cdb1_preg,
    input  wire [63:0] cdb1_data,

    output reg         issue_valid,
    output reg  [4:0]  issue_op,
    output reg  [5:0]  issue_dest_preg,
    output reg  [3:0]  issue_rob_idx,
    output reg  [63:0] issue_src1,
    output reg  [63:0] issue_src2,
    output reg  [11:0] issue_L,
    output reg  [63:0] issue_pc,
    output reg  [63:0] issue_rd_val,
    output wire        full,
    output wire        one_avail,
    output wire        two_avail
);
    reg        v       [0:DEPTH-1];
    reg [4:0]  op      [0:DEPTH-1];
    reg [5:0]  dest_pr [0:DEPTH-1];
    reg [3:0]  rob_idx [0:DEPTH-1];
    reg [5:0]  s_preg  [0:DEPTH-1];
    reg [63:0] s_val   [0:DEPTH-1];
    reg        s_rdy   [0:DEPTH-1];
    reg [5:0]  t_preg  [0:DEPTH-1];
    reg [63:0] t_val   [0:DEPTH-1];
    reg        t_rdy   [0:DEPTH-1];
    reg [11:0] L_f     [0:DEPTH-1];
    reg [63:0] pc_f    [0:DEPTH-1];
    reg [5:0]  rd_preg [0:DEPTH-1];  // 3rd source preg (brgt rd target)
    reg [63:0] rd_val  [0:DEPTH-1];  // 3rd source value
    reg        rd_rdy  [0:DEPTH-1];  // 3rd source ready (1 for non-brgt)

    integer i;

    reg [3:0] free_count;
    reg [2:0] free0, free1;
    reg       fnd0, fnd1;
    reg [2:0]  sel;
    reg        sel_found;
    reg [3:0]  sel_rob;
    always @(*) begin
        free_count = 0;
        free0 = 0; free1 = 0; fnd0 = 0; fnd1 = 0;
        sel = 0; sel_found = 0; sel_rob = 4'hF;
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (!v[i]) begin
                free_count = free_count + 1;
                if (!fnd0) begin free0 = i[2:0]; fnd0 = 1; end
                else if (!fnd1) begin free1 = i[2:0]; fnd1 = 1; end
            end
            if (v[i] && s_rdy[i] && t_rdy[i] && rd_rdy[i]) begin
                if (!sel_found || rob_idx[i] < sel_rob) begin
                    sel = i[2:0]; sel_rob = rob_idx[i]; sel_found = 1;
                end
            end
        end
    end

    assign full = (free_count < 2);
    assign one_avail = (free_count != 0);
    assign two_avail = (free_count >= 2);
    always @(posedge clk) begin
        if (reset || flush) begin
            for (i = 0; i < DEPTH; i = i + 1) v[i] <= 0;
            issue_valid <= 0;
            issue_op <= 0;
            issue_dest_preg <= 0;
            issue_rob_idx <= 0;
            issue_src1 <= 0;
            issue_src2 <= 0;
            issue_L <= 0;
            issue_pc <= 0;
            issue_rd_val <= 0;
        end else begin
            issue_valid <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                if (v[i]) begin
                    if (!s_rdy[i]) begin
                        if (cdb0_valid && s_preg[i] == cdb0_preg) begin
                            s_val[i] <= cdb0_data; s_rdy[i] <= 1;
                        end else if (cdb1_valid && s_preg[i] == cdb1_preg) begin
                            s_val[i] <= cdb1_data; s_rdy[i] <= 1;
                        end
                    end
                    if (!t_rdy[i]) begin
                        if (cdb0_valid && t_preg[i] == cdb0_preg) begin
                            t_val[i] <= cdb0_data; t_rdy[i] <= 1;
                        end else if (cdb1_valid && t_preg[i] == cdb1_preg) begin
                            t_val[i] <= cdb1_data; t_rdy[i] <= 1;
                        end
                    end
                    if (!rd_rdy[i]) begin
                        if (cdb0_valid && rd_preg[i] == cdb0_preg) begin
                            rd_val[i] <= cdb0_data; rd_rdy[i] <= 1;
                        end else if (cdb1_valid && rd_preg[i] == cdb1_preg) begin
                            rd_val[i] <= cdb1_data; rd_rdy[i] <= 1;
                        end
                    end
                end
            end
            if (sel_found) begin
                issue_valid <= 1;
                issue_op <= op[sel];
                issue_dest_preg <= dest_pr[sel];
                issue_rob_idx <= rob_idx[sel];
                issue_src1 <= s_val[sel];
                issue_src2 <= t_val[sel];
                issue_L <= L_f[sel];
                issue_pc <= pc_f[sel];
                issue_rd_val <= rd_val[sel];
                v[sel] <= 0;
            end
            if (disp0_en && fnd0) begin
                v[free0] <= 1;
                op[free0] <= disp0_op;
                dest_pr[free0] <= disp0_dest_preg;
                rob_idx[free0] <= disp0_rob_idx;
                s_preg[free0] <= disp0_s_preg;
                t_preg[free0] <= disp0_t_preg;
                L_f[free0] <= disp0_L;
                pc_f[free0] <= disp0_pc;
                rd_preg[free0] <= disp0_rd_preg;
                if (!disp0_s_rdy && cdb0_valid && disp0_s_preg == cdb0_preg) begin
                    s_val[free0] <= cdb0_data; s_rdy[free0] <= 1;
                end else if (!disp0_s_rdy && cdb1_valid && disp0_s_preg == cdb1_preg) begin
                    s_val[free0] <= cdb1_data; s_rdy[free0] <= 1;
                end else begin
                    s_val[free0] <= disp0_s_val; s_rdy[free0] <= disp0_s_rdy;
                end
                if (!disp0_t_rdy && cdb0_valid && disp0_t_preg == cdb0_preg) begin
                    t_val[free0] <= cdb0_data; t_rdy[free0] <= 1;
                end else if (!disp0_t_rdy && cdb1_valid && disp0_t_preg == cdb1_preg) begin
                    t_val[free0] <= cdb1_data; t_rdy[free0] <= 1;
                end else begin
                    t_val[free0] <= disp0_t_val; t_rdy[free0] <= disp0_t_rdy;
                end
                if (!disp0_rd_rdy && cdb0_valid && disp0_rd_preg == cdb0_preg) begin
                    rd_val[free0] <= cdb0_data; rd_rdy[free0] <= 1;
                end else if (!disp0_rd_rdy && cdb1_valid && disp0_rd_preg == cdb1_preg) begin
                    rd_val[free0] <= cdb1_data; rd_rdy[free0] <= 1;
                end else begin
                    rd_val[free0] <= disp0_rd_val; rd_rdy[free0] <= disp0_rd_rdy;
                end
            end
            if (disp1_en && fnd1) begin
                v[free1] <= 1;
                op[free1] <= disp1_op;
                dest_pr[free1] <= disp1_dest_preg;
                rob_idx[free1] <= disp1_rob_idx;
                s_preg[free1] <= disp1_s_preg;
                t_preg[free1] <= disp1_t_preg;
                L_f[free1] <= disp1_L;
                pc_f[free1] <= disp1_pc;
                rd_preg[free1] <= disp1_rd_preg;
                if (!disp1_s_rdy && cdb0_valid && disp1_s_preg == cdb0_preg) begin
                    s_val[free1] <= cdb0_data; s_rdy[free1] <= 1;
                end else if (!disp1_s_rdy && cdb1_valid && disp1_s_preg == cdb1_preg) begin
                    s_val[free1] <= cdb1_data; s_rdy[free1] <= 1;
                end else begin
                    s_val[free1] <= disp1_s_val; s_rdy[free1] <= disp1_s_rdy;
                end
                if (!disp1_t_rdy && cdb0_valid && disp1_t_preg == cdb0_preg) begin
                    t_val[free1] <= cdb0_data; t_rdy[free1] <= 1;
                end else if (!disp1_t_rdy && cdb1_valid && disp1_t_preg == cdb1_preg) begin
                    t_val[free1] <= cdb1_data; t_rdy[free1] <= 1;
                end else begin
                    t_val[free1] <= disp1_t_val; t_rdy[free1] <= disp1_t_rdy;
                end
                if (!disp1_rd_rdy && cdb0_valid && disp1_rd_preg == cdb0_preg) begin
                    rd_val[free1] <= cdb0_data; rd_rdy[free1] <= 1;
                end else if (!disp1_rd_rdy && cdb1_valid && disp1_rd_preg == cdb1_preg) begin
                    rd_val[free1] <= cdb1_data; rd_rdy[free1] <= 1;
                end else begin
                    rd_val[free1] <= disp1_rd_val; rd_rdy[free1] <= disp1_rd_rdy;
                end
            end
        end
    end
endmodule
