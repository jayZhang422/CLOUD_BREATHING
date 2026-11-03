// 文件类型: .sv (SystemVerilog)
// 历史实现：仅供同尺度 INT8 饱和加法测试，不能用于冻结模型的分支/残差合并。
// 部署核心：src/scala/element_add/elementadd.scala；生成 RTL：本目录 elementadd_p16.v。
// 微架构: 组合逻辑，逐通道 INT8 加法，带饱和保护到 [-128, 127]

module element_add #(
    parameter int C = 16  // 通道数
) (
    // 输入数据1：C 个通道，每通道 8-bit signed INT8
    input  logic [C-1:0][7:0] data1_i,
    // 输入数据2：C 个通道，每通道 8-bit signed INT8
    input  logic [C-1:0][7:0] data2_i,
    // 输出数据：C 个通道，带饱和的和
    output logic [C-1:0][7:0] data_o
);

    // 组合逻辑：逐通道加法 + 饱和
    always_comb begin
        for (int i = 0; i < C; i++) begin
            // 扩展到 9-bit 防止溢出
            logic signed [8:0] sum;

            // INT8 + INT8 → INT9
            sum = $signed(data1_i[i]) + $signed(data2_i[i]);

            // 饱和到 INT8 范围 [-128, 127]
            if (sum > 127)
                data_o[i] = 8'd127;
            else if (sum < -128)
                data_o[i] = -8'd128;
            else
                data_o[i] = sum[7:0];
        end
    end

endmodule

// 设计说明:
// 1. 纯组合逻辑，无流水延迟 (Latency = 0 cycle)
// 2. 硬件资源估算 (C=16):
//    - LUTs: ~50 (16通道 × 加法器 + 饱和比较器)
//    - FFs:  0 (组合逻辑)
//    - BRAM: 0
//    - DSP:  0 (8-bit 加法不使用 DSP)
// 3. 时序: 关键路径为 9-bit 加法 + 比较器 + MUX，预估 < 2 ns @ UltraScale+
