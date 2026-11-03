// 文件类型: .sv (SystemVerilog)
// 功能: Channel Shuffle - mkdc 中 k3+k5 后的通道重排
// 微架构: 纯组合逻辑，将 C 个通道按 [0,1,2,...,C/2-1,C/2,...,C-1] 重排为 [0,C/2,1,C/2+1,2,C/2+2,...]
//         等效于 PyTorch: x.reshape(2, C//2).transpose(0,1).reshape(C)

module channel_shuffle #(
    parameter int C = 16  // 通道数，必须是偶数
) (
    // 输入数据：C 个通道，每通道 8-bit signed INT8
    input  logic [C-1:0][7:0] data_i,
    // 输出数据：重排后的 C 个通道
    output logic [C-1:0][7:0] data_o
);

    // 编译时检查：通道数必须是偶数
    initial begin
        if (C % 2 != 0) begin
            $fatal(1, "Channel Shuffle: C=%0d must be even!", C);
        end
    end

    // 组合逻辑：通道重排
    // 前半部分 [0..C/2-1] 放到偶数位 [0,2,4,...]
    // 后半部分 [C/2..C-1] 放到奇数位 [1,3,5,...]
    always_comb begin
        for (int i = 0; i < C/2; i++) begin
            data_o[2*i]   = data_i[i];         // 前半部分 → 偶数位
            data_o[2*i+1] = data_i[i + C/2];   // 后半部分 → 奇数位
        end
    end

endmodule

// 设计说明:
// 1. 纯组合逻辑，无流水延迟 (Latency = 0 cycle)
// 2. 硬件资源: 0 LUT（纯布线，可能用少量 LUT 做 MUX）, 0 FF, 0 BRAM, 0 DSP
// 3. 时序: 关键路径为组合逻辑延迟，预估 < 1 ns @ UltraScale+
