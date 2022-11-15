`timescale 1 ps / 1 ps
`include "matrix_mul_ctrl.svh"

module matrix_mul_ctrl  #(
    parameter int MULER_WIDTH = 8,
    parameter int NUM_WIDTH = 8,
    parameter int OUTPUT_WIDTH = 32,
    parameter int MULER_DELAY = 1,
    parameter int ROW_SIZE = 8,
    parameter int COLUMN_SIZE = 8,

    parameter int BRAM_READ_LATENCY = 1 // BRAM Latency should be no less then 1, for at least one clk is needed for num_valid
)(
    input clk,
    input rst,
    output req_valid,
    input matrix_mul_ctrl_t ctrl_info,

    output feature_bram_addr_t feature_addr,
    input logic[COLUMN_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] feature_resp,
    output weight_bram_addr_t weight_addr,
    input logic[ROW_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] weight_resp,

    output output_bram_addr_t output_addr,
    output logic[ROW_SIZE - 1 : 0][OUTPUT_WIDTH - 1 : 0] output_data,
    output logic output_we
);

    // Matrix Muler core
    logic num_valid_r;
    logic [NUM_WIDTH - 1 : 0] num_r;
    logic [ROW_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] input_a;
    logic [COLUMN_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] input_b;
    logic [ROW_SIZE - 1 : 0][OUTPUT_WIDTH - 1 : 0] output_r;
    logic output_valid;
    logic output_valid_early;
    mac_array #(
        .MULER_WIDTH(MULER_WIDTH),
        .NUM_WIDTH(NUM_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .MULER_DELAY(MULER_DELAY),
        .ROW_SIZE(ROW_SIZE),
        .COLUMN_SIZE(COLUMN_SIZE)
    ) mac_array_core (
        .clk(clk),
        .rst(rst),
        .num_valid(num_valid_r),
        .num(num_r),
        .data_a(input_a),
        .data_b(input_b),
        .result_r(output_r),

        .result_valid_match(output_valid),
        .result_valid_r(output_valid_early)
    );

    // input_address controlling logic
    logic[14:0] feature_len_size;
    logic[16:0] weight_len_size;
    always_ff @(posedge clk) begin
        if(req_valid & ctrl_info.valid) begin
            feature_addr <= ctrl_info.input_a_addr_begin;
            weight_addr <= ctrl_info.input_b_addr_begin;
            feature_len_size <= ctrl_info.a_line_size;
            weight_len_size <= ctrl_info.b_line_size;
        end else begin
            feature_addr <= feature_addr + feature_len_size;
            weight_addr <= weight_addr + weight_len_size;
        end
    end

    // output_address controlling logic
    logic[14:0] output_len_size;
    logic[14:0] output_addr_last;
    logic[14:0] output_len_size_last;
    logic[2:0] output_cnt;
    logic output_cnt_is_zero;
    assign output_cnt_is_zero = output_cnt == '0;
    always_ff @(posedge clk) begin
        if(output_cnt_is_zero) begin
            output_addr <= output_addr_last;
            output_len_size <= output_len_size_last;
        end else begin
            output_addr <= output_addr + output_len_size;
        end
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            output_cnt <= '0;
        end else if(output_cnt_is_zero) begin
            if(output_valid_early) begin
                output_cnt <= 3'd7;
            end
        end else begin
            output_cnt <= output_cnt - 1;
        end
    end

    // output_we controlling logic
    assign output_we = output_valid;

    // output_address pipeline maintain logic
    always_ff @(posedge clk) begin
        if(req_valid & ctrl_info.valid) begin
            output_addr_last <= ctrl_info.output_c_addr_begin;
            output_len_size_last <= ctrl_info.c_line_size;
        end
    end

    // num_valid controlling logic
    logic[BRAM_READ_LATENCY - 1 : 0] num_valid_shift_register;
    logic[BRAM_READ_LATENCY - 1 : 0][11:0] num_shift_register;
    always_ff @(posedge clk) begin
        num_valid_shift_register <= {num_valid_shift_register[BRAM_READ_LATENCY - 2 : 0], req_valid};
        num_shift_register <= {num_shift_register[BRAM_READ_LATENCY - 2 : 0], ctrl_info.matrix_n};
    end
    assign num_valid_r = num_valid_shift_register[BRAM_READ_LATENCY - 1];
    assign num_r = num_shift_register[BRAM_READ_LATENCY - 1];

    // execution counting logic (for issue decision)
    logic[11:0] execution_cnt;
    always_ff @(posedge clk) begin
        if(rst) begin
            execution_cnt <= '0;
        end else if(req_valid) begin
            execution_cnt <= COLUMN_SIZE + num_r - 2; // Critical, adjusted by test&simulation but not calculation.
        end else begin
            if(execution_cnt != 0) begin
                execution_cnt <= execution_cnt - 1;
            end
        end
    end

    // req_valid controlling logic
    assign req_valid = ((COLUMN_SIZE - 1) > execution_cnt) & (ctrl_info.matrix_n > execution_cnt) & ctrl_info.valid;
    // Critical, adjusted by test&simulation but not calculation.

    // connect core and memory bus
    assign input_a = weight_resp;
    assign input_b = feature_resp;
    assign output_data = output_r;

endmodule