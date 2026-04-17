// fpu.sv - 4-stage pipelined FPU execution unit
// Handles: ADDF, SUBF, MULF, DIVF (IEEE 754 double-precision)
// Stage 1: Compute result (combinational), register into pipeline
// Stages 2-4: Pipeline delay (result passes through)
// Fully pipelined: can accept one new instruction every cycle.
// FP logic adapted from prog09/hdl/alu.sv (proven correct by test cases).
`include "hdl/cpu_pkg.sv"
module fpu (
    input clk,
    input reset,
    input flush,

    // Issue from reservation station
    input wire        issue_valid,
    input wire [4:0]  issue_opcode,
    input wire [63:0] issue_Vj,       // rs value
    input wire [63:0] issue_Vk,       // rt value
    input wire [4:0]  issue_rob_tag,
    input wire [5:0]  issue_phys_dest,

    // CDB output
    output reg        cdb_valid,
    output reg [4:0]  cdb_tag,
    output reg [63:0] cdb_value,
    output reg [5:0]  cdb_phys_dest,

    // EU busy (fully pipelined = never busy)
    output wire       eu_busy
);

    assign eu_busy = 1'b0;

    integer i;
    integer found;

    // Working registers for FP computation (combinational)
    reg [105:0] multf_reg;
    reg [108:0] divf_reg;
    reg [53:0]  addf_reg;
    reg [12:0]  float_exponent_1;
    reg [12:0]  float_exponent_2;
    reg [12:0]  final_exponent;
    reg [52:0]  float_value_1;
    reg [52:0]  float_value_2;
    reg [12:0]  amount_shifted_1;
    reg [12:0]  amount_shifted_2;
    reg [52:0]  mantissa_result;
    reg [2:0]   grs_rounding;
    reg         carry_1;
    reg         carry_2;
    reg         sign_1;
    reg         sign_2;

    // Stage 1: combinational FP compute
    reg [63:0] fp_result;

    always @(*) begin
        multf_reg = 106'b0;
        divf_reg = 109'b0;
        addf_reg = 54'b0;
        float_exponent_1 = 13'b0;
        float_exponent_2 = 13'b0;
        final_exponent = 13'b0;
        float_value_1 = 53'b0;
        float_value_2 = 53'b0;
        amount_shifted_1 = 13'b0;
        amount_shifted_2 = 13'b0;
        mantissa_result = 53'b0;
        grs_rounding = 3'b0;
        carry_1 = 1'b0;
        carry_2 = 1'b0;
        sign_1 = 1'b0;
        sign_2 = 1'b0;
        found = 0;
        fp_result = 64'd0;

        case (issue_opcode)
            // =================================================================
            // ADDF: rd = rs +f rt
            // =================================================================
            OP_ADDF: begin
                fp_result[63] = 0;
                if (issue_Vj[62:0] == 0) fp_result = issue_Vk;
                else if (issue_Vk[62:0] == 0) fp_result = issue_Vj;
                else if (issue_Vk[62:52] == 11'h7FF || issue_Vj[62:52] == 11'h7FF) begin
                    if (issue_Vj[62:52] == 11'h7FF && issue_Vj[51:0] != 0) fp_result = issue_Vj;
                    else if (issue_Vk[62:52] == 11'h7FF && issue_Vk[51:0] != 0) fp_result = issue_Vk;
                    else if (issue_Vk[62:52] == 11'h7FF && issue_Vj[62:52] == 11'h7FF) begin
                        if (issue_Vj[63] == issue_Vk[63]) fp_result = {issue_Vj[63], 11'h7FF, 52'b0};
                        else begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 1;
                        end
                    end else if (issue_Vk[62:52] == 11'h7FF) begin
                        fp_result = {issue_Vk[63:52], 52'b0};
                    end else if (issue_Vj[62:52] == 11'h7FF) begin
                        fp_result = {issue_Vj[63:52], 52'b0};
                    end
                end else begin
                    if (issue_Vj[62:52] == 0) begin
                        float_exponent_1 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vj[i] && !found) begin
                                amount_shifted_1 = 52 - i;
                                float_value_1 = issue_Vj[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_1 = issue_Vj[62:52];
                        float_value_1 = {1'b1, issue_Vj[51:0]};
                        amount_shifted_1 = 0;
                    end
                    found = 0;
                    if (issue_Vk[62:52] == 0) begin
                        float_exponent_2 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vk[i] && !found) begin
                                amount_shifted_2 = 52 - i;
                                float_value_2 = issue_Vk[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_2 = issue_Vk[62:52];
                        float_value_2 = {1'b1, issue_Vk[51:0]};
                        amount_shifted_2 = 0;
                    end
                    found = 0;
                    sign_1 = issue_Vj[63];
                    sign_2 = issue_Vk[63];
                    if (float_exponent_1 + amount_shifted_2 < float_exponent_2 + amount_shifted_1) begin
                        float_exponent_1 = float_exponent_1 ^ float_exponent_2;
                        float_exponent_2 = float_exponent_1 ^ float_exponent_2;
                        float_exponent_1 = float_exponent_1 ^ float_exponent_2;
                        amount_shifted_1 = amount_shifted_1 ^ amount_shifted_2;
                        amount_shifted_2 = amount_shifted_1 ^ amount_shifted_2;
                        amount_shifted_1 = amount_shifted_1 ^ amount_shifted_2;
                        float_value_1 = float_value_1 ^ float_value_2;
                        float_value_2 = float_value_1 ^ float_value_2;
                        float_value_1 = float_value_1 ^ float_value_2;
                        sign_1 = issue_Vk[63];
                        sign_2 = issue_Vj[63];
                    end
                    if (float_exponent_1 + amount_shifted_2 == float_exponent_2 + amount_shifted_1) begin
                        if (sign_1 == sign_2) begin
                            fp_result[63] = sign_1;
                            addf_reg = float_value_1 + float_value_2;
                        end else begin
                            if (float_value_1 >= float_value_2) begin
                                fp_result[63] = sign_1;
                                addf_reg = float_value_1 - float_value_2;
                            end else begin
                                fp_result[63] = sign_2;
                                addf_reg = float_value_2 - float_value_1;
                            end
                        end
                        final_exponent = float_exponent_1;
                        if (addf_reg[53]) begin
                            final_exponent = final_exponent + 1;
                            mantissa_result[51:0] = addf_reg[52:1];
                        end else if (addf_reg[52]) begin
                            mantissa_result[51:0] = addf_reg[51:0];
                        end else begin
                            for (i = 51; i >= 0; i = i - 1) begin
                                if (addf_reg[i] && !found) begin
                                    addf_reg = addf_reg << (53-i);
                                    mantissa_result[51:0] = addf_reg[52:1];
                                    amount_shifted_1 = amount_shifted_1 + (52 - i);
                                    found = 1;
                                end
                            end
                            found = 0;
                        end
                        if (!addf_reg[53] && !addf_reg[52] && mantissa_result == 0) begin
                            fp_result[62:0] = 0;
                        end else if (final_exponent > amount_shifted_1 + 13'd2046) begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 52'b0;
                        end else if (final_exponent > amount_shifted_1) begin
                            final_exponent = final_exponent - amount_shifted_1;
                            fp_result[62:52] = final_exponent;
                            fp_result[51:0] = mantissa_result[51:0];
                        end else if (final_exponent + 52 > amount_shifted_1) begin
                            mantissa_result[52] = 1'b1;
                            amount_shifted_1 = amount_shifted_1 - final_exponent;
                            mantissa_result = mantissa_result >> amount_shifted_1;
                            fp_result[62:52] = 0;
                            fp_result[51:0] = mantissa_result[52:1];
                        end else begin
                            fp_result[62:0] = 0;
                        end
                    end else begin
                        float_value_2 = float_value_2 >> (float_exponent_1 + amount_shifted_2 - float_exponent_2 - amount_shifted_1);
                        fp_result[63] = sign_1;
                        if (sign_1 == sign_2) begin
                            addf_reg = float_value_1 + float_value_2;
                        end else begin
                            addf_reg = float_value_1 - float_value_2;
                        end
                        final_exponent = float_exponent_1;
                        if (addf_reg[53]) begin
                            final_exponent = final_exponent + 1;
                            mantissa_result[51:0] = addf_reg[52:1];
                        end else if (addf_reg[52]) begin
                            mantissa_result[51:0] = addf_reg[51:0];
                        end else begin
                            for (i = 51; i >= 0; i = i - 1) begin
                                if (addf_reg[i] && !found) begin
                                    addf_reg = addf_reg << (53-i);
                                    mantissa_result[51:0] = addf_reg[52:1];
                                    amount_shifted_1 = amount_shifted_1 + (52 - i);
                                    found = 1;
                                end
                            end
                            found = 0;
                        end
                        if (!addf_reg[53] && !addf_reg[52] && mantissa_result == 0) begin
                            fp_result[62:0] = 0;
                        end else if (final_exponent > amount_shifted_1 + 13'd2046) begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 52'b0;
                        end else if (final_exponent > amount_shifted_1) begin
                            final_exponent = final_exponent - amount_shifted_1;
                            fp_result[62:52] = final_exponent;
                            fp_result[51:0] = mantissa_result[51:0];
                        end else if (final_exponent + 52 > amount_shifted_1) begin
                            mantissa_result[52] = 1'b1;
                            amount_shifted_1 = amount_shifted_1 - final_exponent;
                            mantissa_result = mantissa_result >> amount_shifted_1;
                            fp_result[62:52] = 0;
                            fp_result[51:0] = mantissa_result[52:1];
                        end else begin
                            fp_result[62:0] = 0;
                        end
                    end
                end
            end

            // =================================================================
            // SUBF: rd = rs -f rt (same as ADDF but negate rt sign)
            // =================================================================
            OP_SUBF: begin
                fp_result[63] = 0;
                if (issue_Vj[62:0] == 0 && issue_Vk[62:0] == 0) begin
                    if (issue_Vj[63] == 0 || (issue_Vj[63] == 1 && issue_Vk[63] == 1)) begin
                        fp_result = 0;
                    end else fp_result = {1'b1, 63'b0};
                end
                else if (issue_Vj[62:0] == 0) fp_result = {~issue_Vk[63], issue_Vk[62:0]};
                else if (issue_Vk[62:0] == 0) fp_result = issue_Vj;
                else if (issue_Vk[62:52] == 11'h7FF || issue_Vj[62:52] == 11'h7FF) begin
                    if (issue_Vj[62:52] == 11'h7FF && issue_Vj[51:0] != 0) fp_result = issue_Vj;
                    else if (issue_Vk[62:52] == 11'h7FF && issue_Vk[51:0] != 0) fp_result = issue_Vk;
                    else if (issue_Vk[62:52] == 11'h7FF && issue_Vj[62:52] == 11'h7FF) begin
                        if (issue_Vj[63] != issue_Vk[63]) fp_result = {issue_Vj[63], 11'h7FF, 52'b0};
                        else begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 1;
                        end
                    end else if (issue_Vk[62:52] == 11'h7FF) begin
                        fp_result = {~issue_Vk[63], issue_Vk[62:52], 52'b0};
                    end else if (issue_Vj[62:52] == 11'h7FF) begin
                        fp_result = {issue_Vj[63:52], 52'b0};
                    end
                end else begin
                    if (issue_Vj[62:52] == 0) begin
                        float_exponent_1 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vj[i] && !found) begin
                                amount_shifted_1 = 52 - i;
                                float_value_1 = issue_Vj[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_1 = issue_Vj[62:52];
                        float_value_1 = {1'b1, issue_Vj[51:0]};
                        amount_shifted_1 = 0;
                    end
                    found = 0;
                    if (issue_Vk[62:52] == 0) begin
                        float_exponent_2 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vk[i] && !found) begin
                                amount_shifted_2 = 52 - i;
                                float_value_2 = issue_Vk[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_2 = issue_Vk[62:52];
                        float_value_2 = {1'b1, issue_Vk[51:0]};
                        amount_shifted_2 = 0;
                    end
                    found = 0;
                    sign_1 = issue_Vj[63];
                    sign_2 = ~issue_Vk[63]; // negate rt sign for subtraction
                    if (float_exponent_1 + amount_shifted_2 < float_exponent_2 + amount_shifted_1) begin
                        float_exponent_1 = float_exponent_1 ^ float_exponent_2;
                        float_exponent_2 = float_exponent_1 ^ float_exponent_2;
                        float_exponent_1 = float_exponent_1 ^ float_exponent_2;
                        amount_shifted_1 = amount_shifted_1 ^ amount_shifted_2;
                        amount_shifted_2 = amount_shifted_1 ^ amount_shifted_2;
                        amount_shifted_1 = amount_shifted_1 ^ amount_shifted_2;
                        float_value_1 = float_value_1 ^ float_value_2;
                        float_value_2 = float_value_1 ^ float_value_2;
                        float_value_1 = float_value_1 ^ float_value_2;
                        sign_1 = ~issue_Vk[63];
                        sign_2 = issue_Vj[63];
                    end
                    if (float_exponent_1 + amount_shifted_2 == float_exponent_2 + amount_shifted_1) begin
                        if (sign_1 == sign_2) begin
                            fp_result[63] = sign_1;
                            addf_reg = float_value_1 + float_value_2;
                        end else begin
                            if (float_value_1 >= float_value_2) begin
                                fp_result[63] = sign_1;
                                addf_reg = float_value_1 - float_value_2;
                            end else begin
                                fp_result[63] = sign_2;
                                addf_reg = float_value_2 - float_value_1;
                            end
                        end
                        final_exponent = float_exponent_1;
                        if (addf_reg[53]) begin
                            final_exponent = final_exponent + 1;
                            mantissa_result[51:0] = addf_reg[52:1];
                        end else if (addf_reg[52]) begin
                            mantissa_result[51:0] = addf_reg[51:0];
                        end else begin
                            for (i = 51; i >= 0; i = i - 1) begin
                                if (addf_reg[i] && !found) begin
                                    addf_reg = addf_reg << (53-i);
                                    mantissa_result[51:0] = addf_reg[52:1];
                                    amount_shifted_1 = amount_shifted_1 + (52 - i);
                                    found = 1;
                                end
                            end
                            found = 0;
                        end
                        if (!addf_reg[53] && !addf_reg[52] && mantissa_result == 0) begin
                            fp_result[62:0] = 0;
                        end else if (final_exponent > amount_shifted_1 + 13'd2046) begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 52'b0;
                        end else if (final_exponent > amount_shifted_1) begin
                            final_exponent = final_exponent - amount_shifted_1;
                            fp_result[62:52] = final_exponent;
                            fp_result[51:0] = mantissa_result[51:0];
                        end else if (final_exponent + 52 > amount_shifted_1) begin
                            mantissa_result[52] = 1'b1;
                            amount_shifted_1 = amount_shifted_1 - final_exponent;
                            mantissa_result = mantissa_result >> amount_shifted_1;
                            fp_result[62:52] = 0;
                            fp_result[51:0] = mantissa_result[52:1];
                        end else begin
                            fp_result[62:0] = 0;
                        end
                    end else begin
                        float_value_2 = float_value_2 >> (float_exponent_1 + amount_shifted_2 - float_exponent_2 - amount_shifted_1);
                        fp_result[63] = sign_1;
                        if (sign_1 == sign_2) begin
                            addf_reg = float_value_1 + float_value_2;
                        end else begin
                            addf_reg = float_value_1 - float_value_2;
                        end
                        final_exponent = float_exponent_1;
                        if (addf_reg[53]) begin
                            final_exponent = final_exponent + 1;
                            mantissa_result[51:0] = addf_reg[52:1];
                        end else if (addf_reg[52]) begin
                            mantissa_result[51:0] = addf_reg[51:0];
                        end else begin
                            for (i = 51; i >= 0; i = i - 1) begin
                                if (addf_reg[i] && !found) begin
                                    addf_reg = addf_reg << (53-i);
                                    mantissa_result[51:0] = addf_reg[52:1];
                                    amount_shifted_1 = amount_shifted_1 + (52 - i);
                                    found = 1;
                                end
                            end
                            found = 0;
                        end
                        if (!addf_reg[53] && !addf_reg[52] && mantissa_result == 0) begin
                            fp_result[62:0] = 0;
                        end else if (final_exponent > amount_shifted_1 + 13'd2046) begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 52'b0;
                        end else if (final_exponent > amount_shifted_1) begin
                            final_exponent = final_exponent - amount_shifted_1;
                            fp_result[62:52] = final_exponent;
                            fp_result[51:0] = mantissa_result[51:0];
                        end else if (final_exponent + 52 > amount_shifted_1) begin
                            mantissa_result[52] = 1'b1;
                            amount_shifted_1 = amount_shifted_1 - final_exponent;
                            mantissa_result = mantissa_result >> amount_shifted_1;
                            fp_result[62:52] = 0;
                            fp_result[51:0] = mantissa_result[52:1];
                        end else begin
                            fp_result[62:0] = 0;
                        end
                    end
                end
            end

            // =================================================================
            // MULF: rd = rs *f rt
            // =================================================================
            OP_MULF: begin
                fp_result[63] = issue_Vj[63] ^ issue_Vk[63];
                if (issue_Vj[62:52] == 11'h7FF || issue_Vk[62:52] == 11'h7FF) begin
                    if (issue_Vj[62:52] == 11'h7FF && issue_Vj[51:0] != 0) fp_result = issue_Vj;
                    else if (issue_Vk[62:52] == 11'h7FF && issue_Vk[51:0] != 0) fp_result = issue_Vk;
                    else if (issue_Vj[62:0] == 0 || issue_Vk[62:0] == 0) begin
                        fp_result[62:52] = 11'h7FF;
                        fp_result[51:0] = 1;
                    end else fp_result[62:52] = 11'h7FF;
                end else if (issue_Vj[62:0] == 0 || issue_Vk[62:0] == 0) fp_result[62:0] = 63'b0;
                else begin
                    if (issue_Vj[62:52] == 0) begin
                        float_exponent_1 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vj[i] && !found) begin
                                amount_shifted_1 = 52 - i;
                                float_value_1 = issue_Vj[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_1 = issue_Vj[62:52];
                        float_value_1 = {1'b1, issue_Vj[51:0]};
                        amount_shifted_1 = 0;
                    end
                    found = 0;
                    if (issue_Vk[62:52] == 0) begin
                        float_exponent_2 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vk[i] && !found) begin
                                amount_shifted_2 = 52 - i;
                                float_value_2 = issue_Vk[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                        found = 0;
                    end else begin
                        float_exponent_2 = issue_Vk[62:52];
                        float_value_2 = {1'b1, issue_Vk[51:0]};
                        amount_shifted_2 = 0;
                    end
                    multf_reg = float_value_1 * float_value_2;
                    if (multf_reg[105]) begin
                        carry_1 = 1;
                        mantissa_result[51:0] = multf_reg[104:53];
                        grs_rounding[2:0] = multf_reg[52:50];
                    end else begin
                        carry_1 = 0;
                        mantissa_result[51:0] = multf_reg[103:52];
                        grs_rounding[2:0] = multf_reg[51:49];
                    end
                    if ((grs_rounding > 4) || (mantissa_result[0] && grs_rounding[2])) begin
                        mantissa_result = mantissa_result + 53'b1;
                    end
                    if (mantissa_result[52]) carry_2 = 1;
                    else carry_2 = 0;
                    final_exponent = float_exponent_1 + float_exponent_2 + carry_1 + carry_2;
                    if (final_exponent > 13'd1023 + amount_shifted_1 + amount_shifted_2) begin
                        final_exponent = final_exponent - (13'd1023 + amount_shifted_1 + amount_shifted_2);
                        if (final_exponent > 13'd2046) begin
                            fp_result[62:52] = 11'h7ff;
                            fp_result[51:0] = 52'b0;
                        end else begin
                            fp_result[62:52] = final_exponent[10:0];
                            if (carry_2) fp_result[51:0] = {1'b0, mantissa_result[51:1]};
                            else fp_result[51:0] = mantissa_result[51:0];
                        end
                    end else if (final_exponent + 52 > amount_shifted_1 + amount_shifted_2) begin
                        mantissa_result[52] = 1'b1;
                        amount_shifted_1 = 1023 + amount_shifted_1 + amount_shifted_2 - final_exponent;
                        mantissa_result = mantissa_result >> amount_shifted_1;
                        fp_result[62:52] = 0;
                        fp_result[51:0] = mantissa_result[52:1];
                    end else begin
                        fp_result[62:0] = 0;
                    end
                end
            end

            // =================================================================
            // DIVF: rd = rs /f rt
            // =================================================================
            OP_DIVF: begin
                fp_result[63] = issue_Vj[63] ^ issue_Vk[63];
                if (issue_Vj[62:0] == 0 || issue_Vk[62:0] == 0) begin
                    if (issue_Vj[62:0] == 0 && issue_Vk[62:0] == 0) begin
                        fp_result[62:52] = 11'h7FF;
                        fp_result[51:0] = 1;
                    end else if (issue_Vj[62:0] == 0) begin
                        fp_result[62:0] = 0;
                    end else begin
                        fp_result[62:52] = 11'h7FF;
                        fp_result[51:0] = 0;
                    end
                end else if (issue_Vj[62:52] == 11'h7FF || issue_Vk[62:52] == 11'h7FF) begin
                    if (issue_Vj[62:52] == 11'h7FF && issue_Vj[51:0] != 0) fp_result = issue_Vj;
                    else if (issue_Vk[62:52] == 11'h7FF && issue_Vk[51:0] != 0) fp_result = issue_Vk;
                    else if (issue_Vj[62:52] == 11'h7FF && issue_Vk[62:52] == 11'h7FF) begin
                        fp_result[62:52] = 11'h7ff;
                        fp_result[51:0] = 52'h1;
                    end else if (issue_Vk[62:52] == 11'h7FF) begin
                        fp_result[62:0] = 0;
                    end else if (issue_Vj[62:52] == 11'h7FF) begin
                        fp_result[62:52] = 11'h7FF;
                        fp_result[51:0] = 0;
                    end
                end else begin
                    if (issue_Vj[62:52] == 0) begin
                        float_exponent_1 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vj[i] && !found) begin
                                amount_shifted_1 = 52 - i;
                                float_value_1 = issue_Vj[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_1 = issue_Vj[62:52];
                        float_value_1 = {1'b1, issue_Vj[51:0]};
                        amount_shifted_1 = 0;
                    end
                    found = 0;
                    if (issue_Vk[62:52] == 0) begin
                        float_exponent_2 = 1;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (issue_Vk[i] && !found) begin
                                amount_shifted_2 = 52 - i;
                                float_value_2 = issue_Vk[52:0] << (52 - i);
                                found = 1;
                            end
                        end
                    end else begin
                        float_exponent_2 = issue_Vk[62:52];
                        float_value_2 = {1'b1, issue_Vk[51:0]};
                        amount_shifted_2 = 0;
                    end
                    found = 0;
                    divf_reg = {float_value_1, 56'b0};
                    divf_reg = divf_reg / float_value_2;
                    if (divf_reg[56]) begin
                        carry_1 = 0;
                        mantissa_result[51:0] = divf_reg[55:4];
                        grs_rounding[2:0] = divf_reg[3:1];
                    end else begin
                        carry_1 = 1;
                        mantissa_result[51:0] = divf_reg[54:3];
                        grs_rounding[2:0] = divf_reg[2:0];
                    end
                    if ((grs_rounding > 4) || (mantissa_result[0] && grs_rounding[2])) begin
                        mantissa_result = mantissa_result + 53'b1;
                    end
                    if (mantissa_result[52]) carry_2 = 1;
                    else carry_2 = 0;
                    final_exponent = 13'd1023 + float_exponent_1 + carry_2 + amount_shifted_2;
                    if (final_exponent > float_exponent_2 + carry_1 + amount_shifted_1) begin
                        final_exponent = final_exponent - (float_exponent_2 + carry_1 + amount_shifted_1);
                        if (final_exponent > 13'd2046) begin
                            fp_result[62:52] = 11'h7FF;
                            fp_result[51:0] = 52'b0;
                        end else begin
                            fp_result[62:52] = final_exponent[10:0];
                            if (carry_2) fp_result[51:0] = {1'b0, mantissa_result[51:1]};
                            else fp_result[51:0] = mantissa_result[51:0];
                        end
                    end else if (final_exponent + 1075 > float_exponent_2 + carry_1 + amount_shifted_1) begin
                        mantissa_result[52] = 1'b1;
                        amount_shifted_1 = 2 + float_exponent_2 + carry_1 + amount_shifted_1 - final_exponent;
                        mantissa_result = mantissa_result >> amount_shifted_1;
                        fp_result[62:52] = 0;
                        fp_result[51:0] = mantissa_result[52:1];
                    end else begin
                        fp_result[62:0] = 0;
                    end
                end
            end

            default: fp_result = 64'd0;
        endcase
    end

    // Pipeline registers: stage 1 -> stage 2 -> stage 3 -> stage 4
    reg        s2_valid, s3_valid, s4_valid;
    reg [4:0]  s2_tag,   s3_tag,   s4_tag;
    reg [5:0]  s2_phys,  s3_phys,  s4_phys;
    reg [63:0] s2_value, s3_value, s4_value;

    always @(posedge clk) begin
        if (reset || flush) begin
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;
            s4_valid <= 1'b0;
        end else begin
            // Stage 1 -> 2
            s2_valid <= issue_valid;
            s2_tag   <= issue_rob_tag;
            s2_phys  <= issue_phys_dest;
            s2_value <= fp_result;
            // Stage 2 -> 3
            s3_valid <= s2_valid;
            s3_tag   <= s2_tag;
            s3_phys  <= s2_phys;
            s3_value <= s2_value;
            // Stage 3 -> 4
            s4_valid <= s3_valid;
            s4_tag   <= s3_tag;
            s4_phys  <= s3_phys;
            s4_value <= s3_value;
        end
    end

    // Stage 4: output to CDB
    always @(*) begin
        cdb_valid     = s4_valid;
        cdb_tag       = s4_tag;
        cdb_value     = s4_value;
        cdb_phys_dest = s4_phys;
    end

endmodule
