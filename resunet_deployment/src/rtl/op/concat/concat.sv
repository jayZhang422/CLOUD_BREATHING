// 文件类型：.sv。P=16、INT8 Concat：两路缓存地址调度，无数值转换。
// 缓存顺序：[通道组][行][列][16 通道]，低 8 bit 为组内第 0 通道。
// 先输出 source=0 的全部组，再输出 source=1 的全部组；地址单位为 128-bit 字。
module concat (
    input  logic         clk_i,             // 全局时钟
    input  logic         rst_n_i,           // 异步低有效控制复位
    input  logic         cfg_valid_i,       // 配置有效，仅空闲时接收
    output logic         cfg_ready_o,       // 配置接收许可
    output logic         busy_o,            // 正在处理一次拼接
    output logic         done_o,            // 最后一个输出握手后的单拍脉冲
    output logic         rd_valid_o,        // 缓存读请求有效
    input  logic         rd_ready_i,        // 缓存接受读请求
    input  logic         rsp_valid_i,       // 缓存返回有效，等待时须保持数据
    output logic         rsp_ready_o,       // 缓存返回接收许可
    output logic         valid_o,           // 输出有效
    input  logic         ready_i,           // 下游接收许可
    output logic         last_o,            // 本次拼接的最后一个字
    input  logic [31:0]  cfg_base1_i,       // 第一路起始字地址
    input  logic [31:0]  cfg_base2_i,       // 第二路起始字地址
    input  logic [31:0]  cfg_words1_i,      // 第一路字数：W*H*(C1/16)，必须非零
    input  logic [31:0]  cfg_words2_i,      // 第二路字数：W*H*(C2/16)，必须非零
    output logic         rd_source_o,       // 0：第一路；1：第二路
    output logic [31:0]  rd_addr_o,         // 所选缓存的字地址
    input  logic [127:0] rsp_data_i,        // 缓存返回的 16 个 INT8
    output logic [127:0] data_o             // 拼接后的 16 个 INT8
);
    typedef enum logic [1:0] {IDLE, REQUEST, RESPONSE} state_t;
    state_t state_r, state_nxt;
    logic source_r;
    logic [31:0] addr_r, remaining_r, base2_r, words2_r;
    logic cfg_fire_w, rd_fire_w, out_fire_w, source_last_w;

    // 三段式状态机：现态寄存器。
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) state_r <= IDLE;
        else          state_r <= state_nxt;
    end

    // 次态判断：只允许一个在途请求，返回握手后才推进地址。
    always_comb begin
        state_nxt = state_r;
        case (state_r)
            IDLE:     if (cfg_fire_w) state_nxt = REQUEST;
            REQUEST:  if (rd_fire_w)  state_nxt = RESPONSE;
            RESPONSE: if (out_fire_w) begin
                if (source_last_w && source_r) state_nxt = IDLE;
                else                           state_nxt = REQUEST;
            end
            default: state_nxt = IDLE;
        endcase
    end

    // 组合输出：请求反压时地址不变；返回反压直接传递给缓存接口。
    always_comb begin
        source_last_w = remaining_r == 32'd1;
        cfg_ready_o = rst_n_i && state_r == IDLE;
        busy_o      = state_r != IDLE;
        rd_valid_o  = rst_n_i && state_r == REQUEST;
        rd_source_o = source_r;
        rd_addr_o   = addr_r;
        rsp_ready_o = rst_n_i && state_r == RESPONSE && ready_i;
        valid_o     = rst_n_i && state_r == RESPONSE && rsp_valid_i;
        last_o      = source_r && source_last_w;
        data_o      = rsp_data_i;
        cfg_fire_w  = cfg_valid_i && cfg_ready_o;
        rd_fire_w   = rd_valid_o && rd_ready_i;
        out_fire_w  = valid_o && ready_i;
    end

    // 地址、剩余字数与配置快照：运行期间外部配置变化不影响当前任务。
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            source_r    <= 1'b0;
            addr_r      <= 32'd0;
            remaining_r <= 32'd0;
            base2_r     <= 32'd0;
            words2_r    <= 32'd0;
            done_o      <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_r)
                IDLE: if (cfg_fire_w) begin
                    source_r    <= 1'b0;
                    addr_r      <= cfg_base1_i;
                    remaining_r <= cfg_words1_i;
                    base2_r     <= cfg_base2_i;
                    words2_r    <= cfg_words2_i;
                end
                RESPONSE: if (out_fire_w) begin
                    if (source_last_w) begin
                        if (!source_r) begin
                            source_r    <= 1'b1;
                            addr_r      <= base2_r;
                            remaining_r <= words2_r;
                        end else done_o <= 1'b1;
                    end else begin
                        addr_r      <= addr_r + 32'd1;
                        remaining_r <= remaining_r - 32'd1;
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule
