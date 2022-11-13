module mac_array #(
    parameter int MULER_WIDTH = 8,
    parameter int NUM_WIDTH = 8,
    parameter int OUTPUT_WIDTH = 32,
    parameter int MULER_DELAY = 1,
    parameter int ROW_SIZE = 8,
    parameter int COLUMN_SIZE = 8,
    parameter int MUL_DELAY = ROW_SIZE + COLUMN_SIZE + MULER_DELAY - 2 // Automatic calculation, DO NOT Modify !
)(
    input clk,
    input rst,

    input num_valid,
    input [NUM_WIDTH - 1 : 0]num,

    input logic[ROW_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] data_a,
    input logic[COLUMN_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] data_b,

    output logic[ROW_SIZE - 1 : 0][OUTPUT_WIDTH - 1 : 0] result_r
);
    
    // input data aligning fifo
    logic[ROW_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] data_a_r;
    logic[COLUMN_SIZE - 1 : 0][MULER_WIDTH - 1 : 0] data_b_r;
    generate
        assign data_a_r[0] = data_a[0];
        for(genvar row_id = 1 ; row_id < ROW_SIZE; row_id += 1) begin : data_a_register_handling
            logic[row_id - 1 : 0][MULER_WIDTH - 1 : 0] data_a_tmp_r;
            always_ff @(posedge clk) begin
                data_a_tmp_r[0] <= data_a[row_id];
            end
            for(genvar register_id = 1; register_id < row_id; register_id += 1) begin
                always_ff @(posedge clk) begin
                    data_a_tmp_r[register_id] <= data_a_tmp_r[register_id - 1];
                end
            end
            assign data_a_r[row_id] = data_a_tmp_r[row_id - 1];
        end
        assign data_b_r[0] = data_b[0];
        for(genvar column_id = 1 ; column_id < COLUMN_SIZE; column_id += 1) begin : data_b_register_handling
            logic[column_id - 1 : 0][MULER_WIDTH - 1 : 0] data_b_tmp_r;
            always_ff @(posedge clk) begin
                data_b_tmp_r[0] <= data_b[column_id];
            end
            for(genvar register_id = 1; register_id < column_id; register_id += 1) begin
                always_ff @(posedge clk) begin
                    data_b_tmp_r[register_id] <= data_b_tmp_r[register_id - 1];
                end
            end
            assign data_b_r[column_id] = data_b_tmp_r[column_id - 1];
        end
    endgenerate

    // output data aligning 
    logic[ROW_SIZE - 1 : 0][OUTPUT_WIDTH - 1 : 0] result;
    generate
        assign result_r[ROW_SIZE - 1] = result[ROW_SIZE - 1];
        for(genvar row_id = 0 ; row_id < ROW_SIZE - 1; row_id += 1) begin : result_register_handling
            logic[ROW_SIZE - row_id - 2: 0][MULER_WIDTH - 1 : 0] result_tmp_r;
            always_ff @(posedge clk) begin
                result_tmp_r[0] <= result[row_id];
            end
            for(genvar register_id = 1; register_id < (ROW_SIZE - row_id - 1); register_id += 1) begin
                always_ff @(posedge clk) begin
                    result_tmp_r[register_id] <= result_tmp_r[register_id - 1];
                end
            end
            assign result_r[row_id] = result_tmp_r[ROW_SIZE - row_id - 2];
        end
    endgenerate

    // MAC unit generation
    typedef struct packed {
        logic[1:0][MULER_WIDTH - 1 : 0] data;
        logic[OUTPUT_WIDTH - 1 : 0] result;
        logic num_valid;
        logic [NUM_WIDTH - 1 : 0] num;
    } mac_io;
    mac_io [ROW_SIZE - 1 : 0][COLUMN_SIZE - 1 : 0] mac_inputs;
    mac_io [ROW_SIZE - 1 : 0][COLUMN_SIZE - 1 : 0] mac_outputs;
    generate
        for(genvar row_id = 0; row_id < ROW_SIZE ; row_id += 1) begin
            for(genvar column_id = 0; column_id < COLUMN_SIZE ; column_id += 1) begin
                mac_unit #(
                    .MULER_WIDTH(MULER_WIDTH),
                    .NUM_WIDTH(NUM_WIDTH),
                    .OUTPUT_WIDTH(OUTPUT_WIDTH),
                    .MULER_DELAY(MULER_DELAY)
                ) mac_unit_i (
                    .clk(clk),
                    .rst(rst),
                    .num_valid  (mac_inputs[row_id][column_id].num_valid),
                    .num        (mac_inputs[row_id][column_id].num),
                    .data       (mac_inputs[row_id][column_id].data),
                    .result     (mac_inputs[row_id][column_id].result),
                    
                    .num_valid_r(mac_outputs[row_id][column_id].num_valid),
                    .num_r      (mac_outputs[row_id][column_id].num),
                    .data_r     (mac_outputs[row_id][column_id].data),
                    .result_r   (mac_outputs[row_id][column_id].result)
                );
            end
        end
    endgenerate

    // MAC unit interconnection
    generate
        for(genvar row_id = 0; row_id < ROW_SIZE ; row_id += 1) begin
            for(genvar column_id = 0; column_id < COLUMN_SIZE ; column_id += 1) begin
                if (row_id == 0 && column_id == 0)begin
                    assign mac_inputs[row_id][column_id].num_valid = num_valid;
                    assign mac_inputs[row_id][column_id].num       = num;
                end else if(row_id != 0 && column_id % 2 == 0) begin
                    assign mac_inputs[row_id][column_id].num_valid = mac_outputs[row_id - 1][column_id].num_valid;
                    assign mac_inputs[row_id][column_id].num       = mac_outputs[row_id - 1][column_id].num;
                end else begin
                    assign mac_inputs[row_id][column_id].num_valid = mac_outputs[row_id][column_id - 1].num_valid;
                    assign mac_inputs[row_id][column_id].num       = mac_outputs[row_id][column_id - 1].num;
                end
                if(row_id == 0) begin
                    assign mac_inputs[row_id][column_id].data[0]   = data_b[column_id]; // row data 
                end else begin
                    assign mac_inputs[row_id][column_id].data[0]   = mac_outputs[row_id - 1][column_id].data[0]; // row data 
                end
                if(column_id == 0) begin
                    assign mac_inputs[row_id][column_id].data[1]   = data_a[row_id]; // column data
                end else begin
                    assign mac_inputs[row_id][column_id].data[1]   = mac_outputs[row_id][column_id - 1].data[1]; // column data
                end
                if(column_id == COLUMN_SIZE - 1) begin
                    assign mac_inputs[row_id][column_id].result = '0;
                end else begin
                    assign mac_inputs[row_id][column_id].result = mac_outputs[row_id][column_id + 1].result;
                end
            end
            assign result[row_id] = mac_outputs[row_id][0].result;
        end
    endgenerate

endmodule