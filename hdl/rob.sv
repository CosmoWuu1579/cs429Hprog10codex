module rob (
    input  clk,
    input  reset,

    // Allocation (dispatch) — in-order, up to 2/cycle
    input  wire        alloc0_en,
    input  wire [1:0]  alloc0_fu_type,
    input  wire [4:0]  alloc0_dest_areg,
    input  wire [5:0]  alloc0_dest_preg,
    input  wire [5:0]  alloc0_old_preg,
    input  wire        alloc0_reg_write,
    input  wire        alloc0_is_store,
    input  wire        alloc0_is_branch,
    input  wire        alloc0_is_halt,
    input  wire [63:0] alloc0_pred_pc,
    input  wire [191:0] alloc0_rat_snap,
    output wire [3:0]  alloc0_idx,

    input  wire        alloc1_en,
    input  wire [1:0]  alloc1_fu_type,
    input  wire [4:0]  alloc1_dest_areg,
    input  wire [5:0]  alloc1_dest_preg,
    input  wire [5:0]  alloc1_old_preg,
    input  wire        alloc1_reg_write,
    input  wire        alloc1_is_store,
    input  wire        alloc1_is_branch,
    input  wire        alloc1_is_halt,
    input  wire [63:0] alloc1_pred_pc,
    input  wire [191:0] alloc1_rat_snap,
    output wire [3:0]  alloc1_idx,

    output wire        rob_full,
    output wire        rob_one_avail,
    output wire [3:0]  rob_head_idx,

    // CDB write-back: mark entries complete
    input  wire        cdb0_valid,
    input  wire [3:0]  cdb0_rob_idx,
    input  wire [63:0] cdb0_result,
    input  wire        cdb0_mis_pred,
    input  wire [63:0] cdb0_actual_pc,

    input  wire        cdb1_valid,
    input  wire [3:0]  cdb1_rob_idx,
    input  wire [63:0] cdb1_result,
    input  wire        cdb1_mis_pred,
    input  wire [63:0] cdb1_actual_pc,

    output reg         commit0_en,
    output reg  [4:0]  commit0_areg,
    output reg  [5:0]  commit0_preg,
    output reg  [5:0]  commit0_old_preg,
    output reg  [63:0] commit0_result,
    output reg         commit0_reg_write,
    output reg         commit0_is_store,
    output reg         commit1_en,
    output reg  [4:0]  commit1_areg,
    output reg  [5:0]  commit1_preg,
    output reg  [5:0]  commit1_old_preg,
    output reg  [63:0] commit1_result,
    output reg         commit1_reg_write,
    output reg         commit1_is_store,
    output reg         flush,
    output reg  [63:0] flush_pc,
    output reg  [191:0] flush_rat_snap,
    output reg  [3:0]  flush_rob_idx,

    // Halt output
    output reg         hlt
);
    localparam ROB_SIZE = 16;

    reg        r_valid    [0:ROB_SIZE-1];
    reg        r_ready    [0:ROB_SIZE-1];
    reg [1:0]  r_fu_type  [0:ROB_SIZE-1];
    reg [4:0]  r_dareg    [0:ROB_SIZE-1];
    reg [5:0]  r_dpreg    [0:ROB_SIZE-1];
    reg [5:0]  r_old_preg [0:ROB_SIZE-1];
    reg        r_reg_write[0:ROB_SIZE-1];
    reg        r_is_store [0:ROB_SIZE-1];
    reg        r_is_branch[0:ROB_SIZE-1];
    reg        r_is_halt  [0:ROB_SIZE-1];
    reg [63:0] r_result   [0:ROB_SIZE-1];
    reg [63:0] r_pred_pc  [0:ROB_SIZE-1];
    reg        r_mis_pred [0:ROB_SIZE-1];
    reg [63:0] r_actual_pc[0:ROB_SIZE-1];
    reg [191:0] r_rat_snap[0:ROB_SIZE-1];

    reg [3:0]  head, tail;
    reg [4:0]  count; // 0..16

    wire [3:0] head1 = head + 1'b1;
    wire head_cdb0_hit = cdb0_valid && (cdb0_rob_idx == head);
    wire head_cdb1_hit = cdb1_valid && (cdb1_rob_idx == head);
    wire head1_cdb0_hit = cdb0_valid && (cdb0_rob_idx == head1);
    wire head1_cdb1_hit = cdb1_valid && (cdb1_rob_idx == head1);

    wire head_ready_now = r_ready[head] || head_cdb0_hit || head_cdb1_hit;
    wire head1_ready_now = r_ready[head1] || head1_cdb0_hit || head1_cdb1_hit;

    wire [63:0] head_result_now =
        head_cdb1_hit ? cdb1_result :
        head_cdb0_hit ? cdb0_result :
        r_result[head];
    wire [63:0] head1_result_now =
        head1_cdb1_hit ? cdb1_result :
        head1_cdb0_hit ? cdb0_result :
        r_result[head1];

    wire head_mis_pred_now =
        head_cdb1_hit ? cdb1_mis_pred :
        head_cdb0_hit ? cdb0_mis_pred :
        r_mis_pred[head];
    wire head1_mis_pred_now =
        head1_cdb1_hit ? cdb1_mis_pred :
        head1_cdb0_hit ? cdb0_mis_pred :
        r_mis_pred[head1];

    wire [63:0] head_actual_pc_now =
        head_cdb1_hit ? cdb1_actual_pc :
        head_cdb0_hit ? cdb0_actual_pc :
        r_actual_pc[head];
    wire [63:0] head1_actual_pc_now =
        head1_cdb1_hit ? cdb1_actual_pc :
        head1_cdb0_hit ? cdb0_actual_pc :
        r_actual_pc[head1];

    wire can_commit0 = r_valid[head] && head_ready_now;
    wire flush0 = can_commit0 && r_is_branch[head] && head_mis_pred_now;
    wire can_commit1 = can_commit0 && !r_is_halt[head] && !flush0 &&
                       r_valid[head1] && head1_ready_now && !r_is_halt[head1];
    wire flush1 = can_commit1 && r_is_branch[head1] && head1_mis_pred_now;
    wire [1:0] avail_commit_cnt =
        (flush0 || (can_commit0 && r_is_halt[head])) ? 2'd0 :
        flush1 ? 2'd1 :
        can_commit1 ? 2'd2 :
        can_commit0 ? 2'd1 : 2'd0;
    wire [4:0] eff_count = count - {3'b0, avail_commit_cnt};
    assign alloc0_idx = tail;
    assign alloc1_idx = tail + 1'b1;
    assign rob_full = (eff_count >= ROB_SIZE - 1);
    assign rob_one_avail = (eff_count < ROB_SIZE);
    assign rob_head_idx = head;

    integer i;

    always @(*) begin
        commit0_en = can_commit0;
        commit0_areg = r_dareg[head];
        commit0_preg = r_dpreg[head];
        commit0_old_preg = r_old_preg[head];
        commit0_result = head_result_now;
        commit0_reg_write = r_reg_write[head];
        commit0_is_store = r_is_store[head];

        commit1_en = can_commit1;
        commit1_areg = r_dareg[head1];
        commit1_preg = r_dpreg[head1];
        commit1_old_preg = r_old_preg[head1];
        commit1_result = head1_result_now;
        commit1_reg_write = r_reg_write[head1];
        commit1_is_store = r_is_store[head1];
    end

    always @(posedge clk) begin
        reg [1:0] commit_cnt;
        reg [1:0] alloc_cnt;
        reg [3:0] next_head;
        reg       do_flush;

        if (reset) begin
            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                r_valid[i] <= 0; r_ready[i] <= 0;
            end
            head <= 0; tail <= 0; count <= 0;
            flush <= 0; hlt <= 0;
            flush_pc <= 0;
            flush_rat_snap <= 0;
            flush_rob_idx <= 0;
        end else begin
            flush      <= 0;
            hlt        <= 0;
            commit_cnt  = 0;
            alloc_cnt   = 0;
            next_head   = head;
            do_flush    = 0;

            if (cdb0_valid) begin
                r_ready    [cdb0_rob_idx] <= 1;
                r_result   [cdb0_rob_idx] <= cdb0_result;
                r_mis_pred [cdb0_rob_idx] <= cdb0_mis_pred;
                r_actual_pc[cdb0_rob_idx] <= cdb0_actual_pc;
            end
            if (cdb1_valid) begin
                r_ready    [cdb1_rob_idx] <= 1;
                r_result   [cdb1_rob_idx] <= cdb1_result;
                r_mis_pred [cdb1_rob_idx] <= cdb1_mis_pred;
                r_actual_pc[cdb1_rob_idx] <= cdb1_actual_pc;
            end

            if (!r_valid[head] && count != 0) begin
                next_head = head + 1'b1;
            end else if (can_commit0) begin
                r_valid[head]    <= 0;
                commit_cnt        = 1;
                next_head         = head + 1'b1;

                if (r_is_halt[head]) begin
                    hlt <= 1;
                end else if (flush0) begin
                    flush          <= 1;
                    flush_pc       <= head_actual_pc_now;
                    flush_rat_snap <= r_rat_snap [head];
                    flush_rob_idx  <= head;
                    do_flush       = 1;
                end else begin
                    if (can_commit1) begin
                        r_valid[head1]  <= 0;
                        commit_cnt        = 2;
                        next_head         = head + 2'd2;

                        if (flush1) begin
                            flush          <= 1;
                            flush_pc       <= head1_actual_pc_now;
                            flush_rat_snap <= r_rat_snap [head1];
                            flush_rob_idx  <= head1;
                            do_flush       = 1;
                        end
                    end
                end
            end

            if (do_flush) begin
                for (i = 0; i < ROB_SIZE; i = i + 1) begin
                    r_valid[i] <= 0;
                    r_ready[i] <= 0;
                end
                head <= 0;
                tail <= 0;
                count <= 0;
            end else begin
                if (alloc0_en) begin
                    r_valid    [tail]   <= 1;
                    r_ready    [tail]   <= (alloc0_is_store && !alloc0_is_branch) || alloc0_is_halt;
                    r_fu_type  [tail]   <= alloc0_fu_type;
                    r_dareg    [tail]   <= alloc0_dest_areg;
                    r_dpreg    [tail]   <= alloc0_dest_preg;
                    r_old_preg [tail]   <= alloc0_old_preg;
                    r_reg_write[tail]   <= alloc0_reg_write;
                    r_is_store [tail]   <= alloc0_is_store;
                    r_is_branch[tail]   <= alloc0_is_branch;
                    r_is_halt  [tail]   <= alloc0_is_halt;
                    r_pred_pc  [tail]   <= alloc0_pred_pc;
                    r_mis_pred [tail]   <= 0;
                    r_rat_snap [tail]   <= alloc0_rat_snap;
                    alloc_cnt           = alloc_cnt + 1;
                end
                if (alloc1_en) begin
                    r_valid    [tail+1] <= 1;
                    r_ready    [tail+1] <= (alloc1_is_store && !alloc1_is_branch) || alloc1_is_halt;
                    r_fu_type  [tail+1] <= alloc1_fu_type;
                    r_dareg    [tail+1] <= alloc1_dest_areg;
                    r_dpreg    [tail+1] <= alloc1_dest_preg;
                    r_old_preg [tail+1] <= alloc1_old_preg;
                    r_reg_write[tail+1] <= alloc1_reg_write;
                    r_is_store [tail+1] <= alloc1_is_store;
                    r_is_branch[tail+1] <= alloc1_is_branch;
                    r_is_halt  [tail+1] <= alloc1_is_halt;
                    r_pred_pc  [tail+1] <= alloc1_pred_pc;
                    r_mis_pred [tail+1] <= 0;
                    r_rat_snap [tail+1] <= alloc1_rat_snap;
                    alloc_cnt           = alloc_cnt + 1;
                end
                head <= next_head;
                tail  <= tail + {2'b0, alloc_cnt};
                count <= count - {3'b0, commit_cnt} + {3'b0, alloc_cnt};
            end
        end
    end
endmodule
