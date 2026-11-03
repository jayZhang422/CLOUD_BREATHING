`timescale 1ns/1ps
// 【文件类型：.sv】四个官方BRAM IP实现双1KiB写合并、双路1KiB读缓存。
// write=1且mask=0为排空屏障：收齐B响应后返回，并报告此前延迟写错误。
module op_ddr_port (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic cache_clear_i, // 释放DDR所有权时失效读缓存，不丢弃脏数据
    input logic req_valid_i, // 握手有效，阻塞期间保持载荷
    output logic req_ready_o, // 握手接收许可
    input logic req_write_i, // 任务配置或协议控制字段
    output logic rsp_valid_o, // 握手有效，阻塞期间保持载荷
    input logic rsp_ready_i, // 握手接收许可
    output logic rsp_error_o, // 本次操作错误状态
    output logic active_o, // 任务配置或协议控制字段
    output logic wr_start_o, // 任务配置或协议控制字段
    input logic wr_ready_i, // 握手接收许可
    input logic wr_done_i, // 完成通知，须遵守排空条件
    input logic wr_error_i, // 本次操作错误状态
    input logic wr_fifo_re_i, // 任务配置或协议控制字段
    output logic wr_fifo_empty_o, // 任务配置或协议控制字段
    output logic rd_start_o, // 任务配置或协议控制字段
    input logic rd_ready_i, // 握手接收许可
    input logic rd_done_i, // 完成通知，须遵守排空条件
    input logic rd_error_i, // 本次操作错误状态
    input logic rd_fifo_we_i, // 任务配置或协议控制字段
    output logic rd_fifo_full_o, // 任务配置或协议控制字段
    input logic [30:0] req_addr_i, // 地址字段，单位按模块接口约定
    input logic [255:0] req_data_i, // 数据载荷，低位承载首字节或首 lane
    input logic [31:0] req_mask_i, // 任务配置或协议控制字段
    output logic [255:0] rsp_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [30:0] wr_addr_o, // 地址字段，单位按模块接口约定
    output logic [31:0] wr_len_o, // 有效字节数或接口长度
    output logic [255:0] wr_fifo_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [30:0] rd_addr_o, // 地址字段，单位按模块接口约定
    output logic [31:0] rd_len_o, // 有效字节数或接口长度
    input logic [255:0] rd_fifo_data_i // 数据载荷，低位承载首字节或首 lane
);
    // 1KiB自然对齐，任何突发均在同一个4KiB页内。缓存只覆盖DDR地址。
    typedef enum logic [2:0] {IDLE, MATCH, LOOKUP, STORE, READ_REQUEST, READ_WAIT, FENCE, RESPONSE} state_t;
    typedef enum logic [3:0] {W_IDLE, W_CHECK, W_READ_REQUEST, W_READ_WAIT,
        W_START, W_FETCH, W_DATA, W_WAIT, W_FINISH} write_state_t;
    typedef enum logic [1:0] {R_IDLE, R_START, R_DATA, R_FINISH} read_state_t;
    typedef enum logic [1:0] {RESPONSE_ZERO, RESPONSE_READ, RESPONSE_WRITE} response_source_t;
    state_t state_r, state_nxt;
    write_state_t write_r, write_nxt;
    read_state_t read_r, read_nxt;
    response_source_t response_source_r;
    logic response_bank_r;
    logic request_write_r, response_error_r, sticky_error_r;
    logic [30:0] address_r;
    logic [255:0] request_data_r;
    logic [31:0] request_mask_r;
    logic [1:0] dirty_r, read_valid_r;
    logic [3:0] read_segments_r[0:1];
    logic [20:0] write_tag_r[0:1], read_tag_r[0:1];
    logic [31:0] byte_valid_r[0:1][0:31];
    logic [31:0] word_valid_r[0:1];
    logic [5:0] full_words_r[0:1];
    logic [4:0] first_word_r[0:1], last_word_r[0:1];
    logic write_bank_r, read_bank_r, replace_r, read_owner_r;
    logic [4:0] write_word_r, read_word_r;
    logic [20:0] read_tag_active_r;
    logic [4:0] read_first_r;
    logic [5:0] read_count_r;
    logic read_error_r;
    logic write_hit_w, write_slot_w, write_available_w;
    logic read_hit_w, read_slot_w, overlap_w, overlap_bank_w;
    logic read_lookup_hit_w, fence_done_w;
    logic drain_w, drain_bank_w, store_w;
    logic read_after_write_w;
    logic [5:0] write_count_w;
    logic [1:0] write_match_r, read_match_r;
    logic store_bank_r, store_was_full_r, store_becomes_full_r;
    logic [31:0] word_full_w[0:1], word_completes_w[0:1];
    logic [1:0] selected_full_r, selected_completes_r;
    logic prefetch_pending_r,prefetch_active_r,prefetch_bank_r;
    logic [20:0] prefetch_tag_r, prefetch_next_tag_r;
    logic prefetch_next_valid_r, prefetch_target_valid_w, prefetch_cached_w;
    logic prefetch_start_w,prefetch_request_w;

    // 数据由Block Memory Generator托管；此处仅连接IP输出，不再推断二维RAM。
    logic [255:0] write_ram_data_w[0:1], read_ram_data_w[0:1];
    logic [31:0] perf_r [0:7];
    logic [255:0] perf_snapshot_r;
    logic [7:0] perf_event_w, perf_event_r;
    logic perf_clear_r;
    logic [10:0] perf_read_len_r, perf_write_len_r;

    always_comb begin
        write_hit_w = 1'b0; write_slot_w = 1'b0; write_available_w = 1'b0;
        read_hit_w = 1'b0; read_slot_w = 1'b0;
        prefetch_target_valid_w = 1'b0; prefetch_cached_w = 1'b0;
        prefetch_start_w = 1'b0; prefetch_request_w = 1'b0;
        overlap_w = 1'b0; overlap_bank_w = 1'b0;
        case (1'b1)
            (dirty_r[0] && write_match_r[0]): begin
                write_hit_w = 1'b1; write_slot_w = 1'b0;
            end
            (dirty_r[1] && write_match_r[1]): begin
                write_hit_w = 1'b1; write_slot_w = 1'b1;
            end
            (!dirty_r[0]): write_slot_w = 1'b0;
            (!dirty_r[1]): write_slot_w = 1'b1;
            default: ;
        endcase
        write_available_w = (write_hit_w || !(&dirty_r)) &&
            (write_r == W_IDLE || write_slot_w != write_bank_r);
        case (1'b1)
            (read_valid_r[0] && read_match_r[0] && read_segments_r[0][address_r[9:8]]): begin
                read_hit_w = 1'b1; read_slot_w = 1'b0;
            end
            (read_valid_r[1] && read_match_r[1] && read_segments_r[1][address_r[9:8]]): begin
                read_hit_w = 1'b1; read_slot_w = 1'b1;
            end
            default: begin
                read_slot_w = replace_r;
                // 同一行的不同256B段保留在原bank，避免部分填充相互驱逐。
                case (1'b1)
                    (read_valid_r[0] && read_match_r[0]): read_slot_w = 1'b0;
                    (read_valid_r[1] && read_match_r[1]): read_slot_w = 1'b1;
                    default: ;
                endcase
            end
        endcase
        overlap_w = write_hit_w;
        overlap_bank_w = write_slot_w;
        write_count_w = {1'b0,last_word_r[write_bank_r]} - {1'b0,first_word_r[write_bank_r]} + 6'd1;
        prefetch_target_valid_w = prefetch_next_valid_r &&
            ((read_valid_r[0] && read_tag_r[0] == prefetch_next_tag_r) ||
             (read_valid_r[1] && read_tag_r[1] == prefetch_next_tag_r) ||
             (dirty_r[0] && write_tag_r[0] == prefetch_next_tag_r) ||
             (dirty_r[1] && write_tag_r[1] == prefetch_next_tag_r));
        prefetch_cached_w =
            (read_valid_r[0] && read_tag_r[0] == prefetch_tag_r) ||
            (read_valid_r[1] && read_tag_r[1] == prefetch_tag_r) ||
            (dirty_r[0] && write_tag_r[0] == prefetch_tag_r) ||
            (dirty_r[1] && write_tag_r[1] == prefetch_tag_r);
        // 请求mask[2]是下一1KiB行预取提示，mask[1]标记op11连续读，mask[0]保留PW 256B提示。
        prefetch_request_w = state_r == LOOKUP && !request_write_r && !overlap_w && read_hit_w &&
            request_mask_r[2] && request_mask_r[1] && !request_mask_r[0] && read_r == R_IDLE &&
            prefetch_next_valid_r && !prefetch_pending_r && !prefetch_active_r && !prefetch_target_valid_w;
        prefetch_start_w = prefetch_pending_r && !prefetch_cached_w &&
            read_r == R_IDLE && write_r != W_READ_REQUEST &&
            (state_r == IDLE || state_r == RESPONSE) && !cache_clear_i &&
            !(req_valid_i && req_ready_o && !req_write_i && req_addr_i[30:10] == prefetch_tag_r);
        read_after_write_w = overlap_w && write_r == W_FINISH && write_slot_w == write_bank_r &&
            address_r[9:5] >= first_word_r[write_bank_r] && address_r[9:5] <= last_word_r[write_bank_r];
        drain_w = 1'b0; drain_bank_w = 1'b0;
        // 满行后台写回；换行、写后读相关、屏障和所有权释放均可触发排空。
        case (1'b1)
            (state_r == LOOKUP && !request_write_r && overlap_w): begin
                drain_w = 1'b1; drain_bank_w = overlap_bank_w;
            end
            (dirty_r[0] && (full_words_r[0] == 6'd32 || state_r == FENCE || cache_clear_i ||
                (state_r == LOOKUP && request_write_r && !write_hit_w && (&dirty_r)))): begin
                drain_w = 1'b1; drain_bank_w = 1'b0;
            end
            (dirty_r[1] && (full_words_r[1] == 6'd32 || state_r == FENCE || cache_clear_i ||
                (state_r == LOOKUP && request_write_r && !write_hit_w && (&dirty_r)))): begin
                drain_w = 1'b1; drain_bank_w = 1'b1;
            end
            default: ;
        endcase
        // LOOKUP锁定写bank后，下拍提交前不启动新的后台排空，避免抢占同一bank。
        if (state_r == STORE || (state_r == LOOKUP && request_write_r && write_available_w))
            drain_w = 1'b0;
        store_w = state_r == STORE;
        read_lookup_hit_w = state_r == LOOKUP && !request_write_r &&
            (read_after_write_w || (!overlap_w && read_hit_w));
        fence_done_w = state_r == FENCE && dirty_r == 2'b00 && write_r == W_IDLE && read_r == R_IDLE &&
            !prefetch_pending_r && !prefetch_active_r;
    end

    always_comb begin
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i) state_nxt = req_write_i && req_mask_i == 32'd0 ? FENCE : MATCH;
            MATCH: state_nxt = LOOKUP;
            LOOKUP: begin
                if (request_write_r) begin
                    if (write_available_w) state_nxt = STORE;
                end else if (read_after_write_w) state_nxt = RESPONSE;
                else if (!overlap_w) state_nxt = read_hit_w ? RESPONSE : READ_REQUEST;
            end
            STORE: state_nxt = RESPONSE;
            READ_REQUEST: if (read_r == R_IDLE && write_r != W_READ_REQUEST)
                state_nxt = read_hit_w ? LOOKUP : READ_WAIT;
            READ_WAIT: if (read_r == R_FINISH && !read_owner_r) state_nxt = RESPONSE;
            FENCE: if (fence_done_w) state_nxt = RESPONSE;
            RESPONSE: if (rsp_ready_i)
                state_nxt = req_valid_i ? (req_write_i && req_mask_i == 32'd0 ? FENCE : MATCH) : IDLE;
            default: state_nxt = IDLE;
        endcase
        write_nxt = write_r;
        case (write_r)
            W_IDLE: if (drain_w) write_nxt = W_CHECK;
            // 只回写实际修改的连续区间；例如PW的256B完整tile无需读取其余768B。
            W_CHECK: write_nxt = full_words_r[write_bank_r] == write_count_w ? W_START : W_READ_REQUEST;
            W_READ_REQUEST: if (read_r == R_IDLE) write_nxt = W_READ_WAIT;
            W_READ_WAIT: if (read_r == R_FINISH && read_owner_r)
                write_nxt = read_error_r ? W_FINISH : W_START;
            W_START: if (wr_ready_i) write_nxt = W_FETCH;
            W_FETCH: write_nxt = W_DATA;
            W_DATA: if (wr_fifo_re_i && write_word_r == last_word_r[write_bank_r]) write_nxt = wr_done_i ? W_FINISH : W_WAIT;
            W_WAIT: if (wr_done_i) write_nxt = W_FINISH;
            W_FINISH: write_nxt = W_IDLE;
            default: write_nxt = W_IDLE;
        endcase
        read_nxt = read_r;
        case (read_r)
            R_IDLE: if (write_r == W_READ_REQUEST || (state_r == READ_REQUEST && !read_hit_w) || prefetch_start_w)
                read_nxt = R_START;
            R_START: if (rd_ready_i) read_nxt = R_DATA;
            R_DATA: if (rd_done_i) read_nxt = R_FINISH;
            R_FINISH: read_nxt = R_IDLE;
            default: read_nxt = R_IDLE;
        endcase
        req_ready_o = state_r == IDLE || (state_r == RESPONSE && rsp_ready_i);
        rsp_valid_o = state_r == RESPONSE;
        rsp_data_o = request_write_r && request_mask_r == 32'd0 ? perf_snapshot_r : 256'd0;
        case (response_source_r)
            RESPONSE_READ: rsp_data_o = read_ram_data_w[response_bank_r];
            RESPONSE_WRITE: rsp_data_o = write_ram_data_w[response_bank_r];
            default: ;
        endcase
        rsp_error_o = response_error_r;
        active_o = state_r != IDLE || write_r != W_IDLE || read_r != R_IDLE || (|dirty_r) ||
            prefetch_pending_r || prefetch_active_r;
        wr_start_o = write_r == W_START && wr_ready_i;
        wr_addr_o = {write_tag_r[write_bank_r],10'd0} + {21'd0,first_word_r[write_bank_r],5'd0};
        wr_len_o = {21'd0,write_count_w,5'd0};
        wr_fifo_empty_o = write_r != W_DATA;
        wr_fifo_data_o = write_ram_data_w[write_bank_r];
        rd_start_o = read_r == R_START && rd_ready_i;
        rd_addr_o = {read_tag_active_r,10'd0} + {21'd0,read_first_r,5'd0};
        rd_len_o = {21'd0,read_count_r,5'd0};
        rd_fifo_full_o = read_r != R_DATA;
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; write_r <= W_IDLE; read_r <= R_IDLE;
            dirty_r <= 2'b00; read_valid_r <= 2'b00; replace_r <= 1'b0;
            write_bank_r <= 1'b0; read_bank_r <= 1'b0; read_owner_r <= 1'b0;
            write_word_r <= 5'd0; read_word_r <= 5'd0; read_error_r <= 1'b0;
            read_first_r <= 5'd0; read_count_r <= 6'd32;
            request_write_r <= 1'b0; address_r <= 31'd0; request_mask_r <= 32'd0;
            response_source_r <= RESPONSE_ZERO; response_bank_r <= 1'b0;
            response_error_r <= 1'b0; sticky_error_r <= 1'b0;
            prefetch_pending_r <= 1'b0; prefetch_active_r <= 1'b0;
            prefetch_bank_r <= 1'b0; prefetch_tag_r <= 21'd0;
            prefetch_next_tag_r <= 21'd0; prefetch_next_valid_r <= 1'b0;
            store_bank_r <= 1'b0;
            for (int bank=0; bank<2; bank++) begin
                write_tag_r[bank] <= 21'd0; read_tag_r[bank] <= 21'd0;
                full_words_r[bank] <= 6'd0;
                first_word_r[bank] <= 5'd31; last_word_r[bank] <= 5'd0;
                word_valid_r[bank] <= 32'd0;
                read_segments_r[bank] <= 4'd0;
            end
        end else begin
            state_r <= state_nxt; write_r <= write_nxt; read_r <= read_nxt;
            if (req_valid_i && req_ready_o) begin
                request_write_r <= req_write_i; address_r <= {req_addr_i[30:5],5'd0};
                request_mask_r <= req_mask_i; response_error_r <= 1'b0;
                response_source_r <= RESPONSE_ZERO;
            end
            if (state_r == MATCH) begin
                prefetch_next_tag_r <= address_r[30:10] + 21'd1;
                prefetch_next_valid_r <= address_r[30:10] != 21'h1fffff;
            end
            if (cache_clear_i || state_r == FENCE ||
                (prefetch_pending_r && prefetch_cached_w) ||
                (prefetch_pending_r && req_valid_i && req_ready_o && !req_write_i &&
                 req_addr_i[30:10] == prefetch_tag_r))
                prefetch_pending_r <= 1'b0;
            if (prefetch_request_w) begin
                prefetch_pending_r <= 1'b1; prefetch_tag_r <= prefetch_next_tag_r;
                prefetch_bank_r <= !read_slot_w;
            end
            if (prefetch_start_w) begin
                prefetch_pending_r <= 1'b0; prefetch_active_r <= 1'b1;
                read_valid_r[prefetch_bank_r] <= 1'b0;
            end
            if (state_r == LOOKUP && request_write_r && write_available_w)
                store_bank_r <= write_slot_w;
            // 同一拍发起同步RAM读并锁存来源，下一拍RESPONSE期间IP输出保持。
            if (state_r == LOOKUP && !request_write_r) begin
                case (1'b1)
                    read_after_write_w: begin
                        response_source_r <= RESPONSE_WRITE; response_bank_r <= write_bank_r;
                    end
                    (!overlap_w && read_hit_w): begin
                        response_source_r <= RESPONSE_READ; response_bank_r <= read_slot_w;
                    end
                    default: ;
                endcase
            end
            if (state_r == READ_WAIT && read_r == R_FINISH && !read_owner_r) begin
                response_source_r <= RESPONSE_READ; response_bank_r <= read_bank_r;
            end
            if (state_r == STORE || read_lookup_hit_w)
                response_error_r <= sticky_error_r;
            if (cache_clear_i || state_r == FENCE) read_valid_r <= 2'b00;
            if (store_w) begin
                for (int bank=0; bank<2; bank++)
                    if (read_tag_r[bank] == address_r[30:10]) read_valid_r[bank] <= 1'b0;
                dirty_r[store_bank_r] <= 1'b1;
                write_tag_r[store_bank_r] <= address_r[30:10];
                if (address_r[9:5] < first_word_r[store_bank_r]) first_word_r[store_bank_r] <= address_r[9:5];
                if (address_r[9:5] > last_word_r[store_bank_r]) last_word_r[store_bank_r] <= address_r[9:5];
                word_valid_r[store_bank_r][address_r[9:5]] <= 1'b1;
                if (!store_was_full_r && store_becomes_full_r)
                    full_words_r[store_bank_r] <= full_words_r[store_bank_r] + 6'd1;
            end
            if (write_r == W_IDLE && drain_w) write_bank_r <= drain_bank_w;
            if (write_r == W_START) write_word_r <= first_word_r[write_bank_r];
            if (write_r == W_DATA && wr_fifo_re_i) write_word_r <= write_word_r + 5'd1;
            if (write_r == W_FINISH) begin
                dirty_r[write_bank_r] <= 1'b0; full_words_r[write_bank_r] <= 6'd0;
                first_word_r[write_bank_r] <= 5'd31; last_word_r[write_bank_r] <= 5'd0;
                word_valid_r[write_bank_r] <= 32'd0;
            end
            if (read_r == R_IDLE && read_nxt == R_START) begin
                read_owner_r <= write_r == W_READ_REQUEST;
                read_tag_active_r <= write_r == W_READ_REQUEST ? write_tag_r[write_bank_r] :
                    prefetch_start_w ? prefetch_tag_r : address_r[30:10];
                read_bank_r <= write_r == W_READ_REQUEST ? write_bank_r :
                    prefetch_start_w ? prefetch_bank_r : read_slot_w;
                read_error_r <= 1'b0;
                // 读请求mask[0]是内部256B提示；写mask和外部协议保持原义。
                read_first_r <= write_r == W_READ_REQUEST ? first_word_r[write_bank_r] :
                    (prefetch_start_w ? 5'd0 : request_mask_r[0] ? {address_r[9:8],3'd0} : 5'd0);
                read_count_r <= write_r == W_READ_REQUEST ? write_count_w :
                    prefetch_start_w ? 6'd32 : request_mask_r[0] ? 6'd8 : 6'd32;
                read_word_r <= write_r == W_READ_REQUEST ? first_word_r[write_bank_r] :
                    (prefetch_start_w ? 5'd0 : request_mask_r[0] ? {address_r[9:8],3'd0} : 5'd0);
                if (write_r != W_READ_REQUEST && !prefetch_start_w) begin
                    read_segments_r[read_slot_w] <= request_mask_r[0] ?
                        ((read_valid_r[read_slot_w] && read_match_r[read_slot_w] ?
                          read_segments_r[read_slot_w] : 4'd0) | (4'b0001 << address_r[9:8])) : 4'b1111;
                end
            end
            if (read_r == R_DATA) begin
                if (rd_fifo_we_i) read_word_r <= read_word_r + 5'd1;
                if (rd_error_i) read_error_r <= 1'b1;
            end
            if (read_r == R_FINISH && !read_owner_r) begin
                read_valid_r[read_bank_r] <= !read_error_r && !cache_clear_i &&
                    !(prefetch_active_r && ((dirty_r[0] && write_tag_r[0] == read_tag_active_r) ||
                    (dirty_r[1] && write_tag_r[1] == read_tag_active_r) ||
                    (store_w && address_r[30:10] == read_tag_active_r)));
                read_tag_r[read_bank_r] <= read_tag_active_r; replace_r <= !read_bank_r;
                if (prefetch_active_r) begin
                    read_segments_r[read_bank_r] <= read_error_r ? 4'd0 : 4'b1111;
                    prefetch_active_r <= 1'b0;
                end
            end
            if (state_r == READ_WAIT && read_r == R_FINISH && !read_owner_r)
                response_error_r <= read_error_r || sticky_error_r;
            if (fence_done_w) begin
                response_error_r <= sticky_error_r; sticky_error_r <= 1'b0;
            end
            if ((read_r == R_FINISH && read_error_r) ||
                (wr_done_i && (write_r == W_DATA || write_r == W_WAIT) && wr_error_i))
                sticky_error_r <= 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (req_valid_i && req_ready_o) request_data_r <= req_data_i;
        // MATCH保证请求地址已锁存；比较结果与有效位分离，等待排空时仍使用当前dirty。
        for (int bank=0; bank<2; bank++) begin
            write_match_r[bank] <= write_tag_r[bank] == address_r[30:10];
            if (read_r == R_FINISH && !read_owner_r && read_bank_r == 1'(bank))
                read_match_r[bank] <= read_tag_active_r == address_r[30:10];
            else read_match_r[bank] <= read_tag_r[bank] == address_r[30:10];
        end
        for (int bank=0; bank<2; bank++) begin
            // W_FINISH clears this bank in the same clock edge.  Do not carry
            // the pre-clear full flag into the next STORE, or W_CHECK will
            // incorrectly enter the read-modify-write path.
            if (write_r == W_FINISH && write_bank_r == 1'(bank)) begin
                selected_full_r[bank] <= 1'b0;
                selected_completes_r[bank] <= &request_mask_r;
            end else begin
                selected_full_r[bank] <= word_full_w[bank][address_r[9:5]];
                selected_completes_r[bank] <= word_completes_w[bank][address_r[9:5]];
            end
        end
        // MATCH已按地址预取两bank标志，LOOKUP只选两个单比特。
        if (state_r == LOOKUP && request_write_r && write_available_w) begin
            store_was_full_r <= selected_full_r[write_slot_w];
            store_becomes_full_r <= selected_completes_r[write_slot_w];
        end
    end
    for (genvar bank=0; bank<2; bank++) begin : g_memory
        localparam logic BANK_ID = (bank == 0) ? 1'b0 : 1'b1;
        logic [31:0] write_enable_w;
        logic [4:0] write_address_w, write_read_address_w;
        logic [255:0] write_data_w;
        logic [31:0] write_enable_r;
        logic [4:0] write_address_r;
        logic [255:0] write_data_r;
        logic write_port_enable_r;
        logic write_port_enable_w, write_read_enable_w, read_fill_w, read_enable_w;
        for (genvar word_id=0; word_id<32; word_id++) begin : g_word_flags
            // 只复位每字一个有效位，2048位字节掩码无复位；无效字的掩码恒视为零。
            assign word_full_w[bank][word_id] = word_valid_r[bank][word_id] && (&byte_valid_r[bank][word_id]);
            assign word_completes_w[bank][word_id] = &((word_valid_r[bank][word_id] ?
                byte_valid_r[bank][word_id] : 32'd0) | request_mask_r);
            always_ff @(posedge clk_i)
                if (store_w && store_bank_r == BANK_ID && address_r[9:5] == word_id[4:0])
                    byte_valid_r[bank][word_id] <= (word_valid_r[bank][word_id] ?
                        byte_valid_r[bank][word_id] : 32'd0) | request_mask_r;
        end
        always_comb begin
            write_enable_w = 32'd0; write_address_w = 5'd0; write_data_w = 256'd0;
            write_port_enable_w = 1'b0;
            // 每个bank只有一个物理写端口，前台收集与RMW补字节先复用再进入IP。
            case (1'b1)
                (store_w && store_bank_r == BANK_ID): begin
                    write_port_enable_w = 1'b1;
                    write_enable_w = request_mask_r; write_address_w = address_r[9:5];
                    write_data_w = request_data_r;
                end
                (read_r == R_DATA && rd_fifo_we_i && read_owner_r && write_bank_r == BANK_ID): begin
                    write_port_enable_w = 1'b1;
                    write_enable_w = word_valid_r[bank][read_word_r] ? ~byte_valid_r[bank][read_word_r] : 32'hffffffff;
                    write_address_w = read_word_r;
                    write_data_w = rd_fifo_data_i;
                end
                default: ;
            endcase
            write_read_enable_w = 1'b0; write_read_address_w = 5'd0;
            case (1'b1)
                (state_r == LOOKUP && !request_write_r && read_after_write_w && write_bank_r == BANK_ID): begin
                    write_read_enable_w = 1'b1; write_read_address_w = address_r[9:5];
                end
                (write_r == W_FETCH && write_bank_r == BANK_ID): begin
                    write_read_enable_w = 1'b1; write_read_address_w = first_word_r[bank];
                end
                (write_r == W_DATA && wr_fifo_re_i && write_word_r != last_word_r[bank] && write_bank_r == BANK_ID): begin
                    write_read_enable_w = 1'b1; write_read_address_w = write_word_r + 5'd1;
                end
                default: ;
            endcase
            read_fill_w = read_r == R_DATA && rd_fifo_we_i && !read_owner_r && read_bank_r == BANK_ID;
            read_enable_w = (state_r == LOOKUP && !request_write_r && !overlap_w && read_hit_w && read_slot_w == BANK_ID) ||
                (state_r == READ_WAIT && read_r == R_FINISH && !read_owner_r && read_bank_r == BANK_ID);
        end
        // 字节掩码选择先寄存，RMW最后一笔在W_START前已提交；前台读仍经过MATCH/LOOKUP。
        always_ff @(posedge clk_i or negedge rst_n_i) begin
            if (!rst_n_i) write_port_enable_r <= 1'b0;
            else write_port_enable_r <= write_port_enable_w;
        end
        always_ff @(posedge clk_i) begin
            write_enable_r <= write_enable_w;
            write_address_r <= write_address_w;
            write_data_r <= write_data_w;
        end
        // 256bit×32深度，32路8bit写使能，UI同钟，B口同步读延迟1拍，无RAM复位。
        op_ddr_cache_bram u_write_cache (
            .clka(clk_i), .ena(write_port_enable_r), .wea(write_enable_r),
            .addra(write_address_r), .dina(write_data_r),
            .clkb(clk_i), .enb(write_read_enable_w), .addrb(write_read_address_w),
            .doutb(write_ram_data_w[bank])
        );
        op_ddr_cache_bram u_read_cache (
            .clka(clk_i), .ena(read_fill_w), .wea({32{read_fill_w}}),
            .addra(read_word_r), .dina(rd_fifo_data_i),
            .clkb(clk_i), .enb(read_enable_w), .addrb(address_r[9:5]),
            .doutb(read_ram_data_w[bank])
        );
    end
    // UI域统计随FENCE响应跨域，避免直接跨域采样多位计数器。
    // 次序：读/写突发数、读/写字节数、读/写等待拍、缓存命中/未命中。
    always_comb begin
        perf_event_w = 8'd0;
        perf_event_w[0] = rd_start_o;
        perf_event_w[1] = wr_start_o;
        perf_event_w[2] = rd_start_o;
        perf_event_w[3] = wr_start_o;
        perf_event_w[4] = (read_r == R_START && !rd_ready_i) || (read_r == R_DATA && !rd_fifo_we_i);
        perf_event_w[5] = (write_r == W_START && !wr_ready_i) || (write_r == W_DATA && !wr_fifo_re_i) || write_r == W_WAIT;
        perf_event_w[6] = read_lookup_hit_w;
        perf_event_w[7] = state_r == READ_REQUEST && read_r == R_IDLE && write_r != W_READ_REQUEST;
    end
    always_ff @(posedge clk_i) begin
        // 统计清零和事件均就地打拍，UI复位不再穿过统计解码驱动256个CE。
        perf_clear_r <= !rst_n_i || cache_clear_i;
        perf_event_r <= (!rst_n_i || cache_clear_i) ? 8'd0 : perf_event_w;
        perf_read_len_r <= rd_len_o[10:0]; perf_write_len_r <= wr_len_o[10:0];
        if (perf_clear_r) begin
            for (int p=0; p<8; p++) perf_r[p] <= 32'd0;
        end else begin
            if (perf_event_r[0]) begin perf_r[0] <= perf_r[0]+32'd1; perf_r[2] <= perf_r[2]+{21'd0,perf_read_len_r}; end
            if (perf_event_r[1]) begin perf_r[1] <= perf_r[1]+32'd1; perf_r[3] <= perf_r[3]+{21'd0,perf_write_len_r}; end
            if (perf_event_r[4])
                perf_r[4] <= perf_r[4]+32'd1;
            if (perf_event_r[5])
                perf_r[5] <= perf_r[5]+32'd1;
            if (perf_event_r[6])
                perf_r[6] <= perf_r[6]+32'd1;
            if (perf_event_r[7])
                perf_r[7] <= perf_r[7]+32'd1;
        end
        // FENCE期间持续复制，去掉state_nxt复用链到256位快照CE的长路径。
        // 最后一拍FENCE时突发已排空，前一拍登记的统计事件也已累加完成。
        if (state_r == FENCE)
            for (int p=0; p<8; p++) perf_snapshot_r[p*32 +: 32] <= perf_r[p];
    end
endmodule
