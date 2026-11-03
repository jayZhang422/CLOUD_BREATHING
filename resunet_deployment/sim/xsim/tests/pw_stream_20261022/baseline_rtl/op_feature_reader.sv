`timescale 1ns/1ps
// 【文件类型：.sv】P16相邻半拍复用；64B参数两笔连续提交，响应保序收集。
// 在线三切片保留独立32B缓存；clear同时失效缓存，禁止跨写回复用旧数据。
module op_feature_reader_wstream_before (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic clear_i, // 任务配置或协议控制字段
    input logic req_valid_i, // 握手有效，阻塞期间保持载荷
    output logic req_ready_o, // 握手接收许可
    output logic rsp_valid_o, // 握手有效，阻塞期间保持载荷
    input logic rsp_ready_i, // 握手接收许可
    output logic rsp_error_o, // 本次操作错误状态
    output logic mem_valid_o, // 握手有效，阻塞期间保持载荷
    input logic mem_ready_i, // 握手接收许可
    input logic mem_rsp_valid_i, // 握手有效，阻塞期间保持载荷
    output logic mem_rsp_ready_o, // 握手接收许可
    input logic mem_rsp_error_i, // 本次操作错误状态
    input logic [1:0] req_mode_i, // 任务配置或协议控制字段
    input logic [30:0] req_addr_i, // 地址字段，单位按模块接口约定
    input logic [31:0] req_pixel_i, // mode2为切片内像素地址；其它模式为字节偏移
    input logic [31:0] slices_i, // 任务配置或协议控制字段
    input logic [31:0] center_i, // 任务配置或协议控制字段
    output logic [511:0] rsp_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [30:0] mem_addr_o, // 地址字段，单位按模块接口约定
    input logic [255:0] mem_rsp_data_i // 数据载荷，低位承载首字节或首 lane
);
    typedef enum logic [2:0] {IDLE, SLICE, SLICE_BASE, ADDRESS,
        LOOKUP, REQUEST, RETURN, FINISH} state_t;
    state_t state_r, state_nxt;
    logic [1:0] mode_r, part_r;
    logic [30:0] base_r, slice_base_r, address_r;
    logic [31:0] pixel_r, z_w, z_r;
    logic [255:0] cache_r[0:2];
    logic [30:0] cache_addr_r[0:2];
    logic [2:0] cache_valid_r;
    logic hit_w, last_w, error_r;
    logic [511:0] result_r;
    logic [1:0] issued_r, received_r;
    logic [1:0] cache_slot_w;
    assign cache_slot_w = mode_r == 2'd2 ? part_r : 2'd0;
    always_comb begin
        z_w = center_i;
        case (part_r)
            2'd0: z_w = center_i == 32'd0 ? 32'd0 : center_i - 32'd1;
            2'd2: z_w = center_i + 32'd1 >= slices_i ? slices_i - 32'd1 : center_i + 32'd1;
            default: ;
        endcase
        hit_w = mode_r != 2'd1 && !clear_i && cache_valid_r[cache_slot_w] &&
                cache_addr_r[cache_slot_w] == {address_r[30:5],5'd0};
        last_w = mode_r == 2'd0 || (mode_r == 2'd1 && part_r == 2'd1) ||
                 (mode_r == 2'd2 && part_r == 2'd2);
        req_ready_o = state_r == IDLE;
        rsp_valid_o = state_r == FINISH;
        rsp_data_o = result_r; rsp_error_o = error_r;
        mem_valid_o = state_r == REQUEST && issued_r < (mode_r == 2'd1 ? 2'd2 : 2'd1);
        mem_addr_o = {address_r[30:5],5'd0} + (mode_r == 2'd1 ? {24'd0,issued_r,5'd0} : 31'd0);
        mem_rsp_ready_o = state_r == REQUEST || state_r == RETURN;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i) state_nxt = req_mode_i == 2'd2 ? SLICE : ADDRESS;
            SLICE: state_nxt = SLICE_BASE;
            SLICE_BASE: state_nxt = ADDRESS;
            ADDRESS: state_nxt = LOOKUP;
            LOOKUP: if (hit_w) state_nxt = last_w ? FINISH : SLICE;
                    else state_nxt = REQUEST;
            REQUEST: if (mem_ready_i && issued_r == (mode_r == 2'd1 ? 2'd1 : 2'd0)) state_nxt = RETURN;
            RETURN: ;
            FINISH: if (rsp_ready_i) state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
        if ((state_r == REQUEST || state_r == RETURN) && mem_rsp_valid_i &&
            received_r == (mode_r == 2'd1 ? 2'd1 : 2'd0))
            state_nxt = last_w || mode_r == 2'd1 ? FINISH : SLICE;
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; mode_r <= 2'd0; part_r <= 2'd0;
            base_r <= 31'd0; pixel_r <= 32'd0; error_r <= 1'b0;
            cache_valid_r <= 3'd0;
            issued_r <= 2'd0; received_r <= 2'd0;
        end else begin
            state_r <= state_nxt;
            if (state_r == IDLE && req_valid_i) begin
                mode_r <= req_mode_i; base_r <= req_addr_i;
                pixel_r <= req_pixel_i; part_r <= 2'd0; error_r <= 1'b0;
                issued_r <= 2'd0; received_r <= 2'd0;
            end
            if (state_r == SLICE) begin issued_r <= 2'd0; received_r <= 2'd0; end
            if (mem_valid_o && mem_ready_i) issued_r <= issued_r + 2'd1;
            if ((state_r == LOOKUP && hit_w) || (mem_rsp_valid_i && mem_rsp_ready_o))
                part_r <= part_r + 2'd1;
            if (mem_rsp_valid_i && mem_rsp_ready_o) begin
                received_r <= received_r + 2'd1;
                error_r <= error_r || mem_rsp_error_i;
                if (mode_r != 2'd1 && !mem_rsp_error_i) cache_valid_r[cache_slot_w] <= 1'b1;
            end
            if (clear_i) cache_valid_r <= 3'd0;
        end
    end
    always_ff @(posedge clk_i) begin
        // 切片钳位、切片基址、像素加法和cache比较分拍，等待DDR期间地址保持。
        if (state_r == SLICE) z_r <= z_w;
        if (state_r == SLICE_BASE) begin
            case (mode_r)
                2'd1: slice_base_r <= base_r + (part_r == 2'd0 ? 31'd0 : 31'd32);
                2'd2: slice_base_r <= base_r + {z_r[12:0],18'd0};
                default: slice_base_r <= base_r;
            endcase
        end
        // 上游先选择基址和偏移，本拍独立相加，切断算子选择到地址的级联路径。
        if (state_r == ADDRESS)
            address_r <= (mode_r == 2'd2 ? slice_base_r : base_r) + pixel_r[30:0];
        // 空闲拍即可清空结果，不让上游请求仲裁驱动512位同步清零端。
        if (state_r == IDLE) result_r <= 512'd0;
        if (state_r == LOOKUP && hit_w) begin
            if (mode_r == 2'd0)
                result_r[127:0] <= address_r[4] ? cache_r[0][255:128] : cache_r[0][127:0];
            else result_r[part_r*8 +: 8] <= cache_r[part_r][address_r[4:0]*8 +: 8];
        end
        if (mem_rsp_valid_i && mem_rsp_ready_o) begin
            case (mode_r)
                2'd0: begin
                    result_r[127:0] <= address_r[4] ? mem_rsp_data_i[255:128] : mem_rsp_data_i[127:0];
                    cache_r[0] <= mem_rsp_data_i;
                    cache_addr_r[0] <= {address_r[30:5],5'd0};
                end
                2'd1: result_r[received_r[0]*256 +: 256] <= mem_rsp_data_i;
                2'd2: begin
                    result_r[part_r*8 +: 8] <= mem_rsp_data_i[address_r[4:0]*8 +: 8];
                    cache_r[part_r] <= mem_rsp_data_i;
                    cache_addr_r[part_r] <= {address_r[30:5],5'd0};
                end
                default: ;
            endcase
        end
    end
endmodule
