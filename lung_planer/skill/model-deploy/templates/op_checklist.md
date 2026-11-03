# <OP> 校验清单

## 来源

- [ ] 源实现：`src/scala/<op>/<op>.scala` 或 `src/rtl/<op>.sv`
- [ ] 生成入口：`src/scala/<op>/<op>gen.scala`（手写 RTL 删掉此行）
- [ ] 冻结契约：`<path>/contract.json`，SHA256 `<...>`，相关字段（如 `shift=<n>`）
- [ ] 冻结输入/权重/Golden SHA256：见 `vectors/vector_manifest.txt`
- [ ] 打包约定：<lanes> lane × <bits> bit，lane 0 位于 <LSB/MSB>

## 覆盖

- [ ] 数值边界：.5 舍入点、饱和上下界、溢出上界附近
- [ ] 形状：最小、非整 lane、奇数宽高、最大至少一例
- [ ] 握手：输入间隙、输出反压、payload/标签保持
- [ ] 控制：中途复位 <n> 个相位、`last`/边界信号
- [ ] 配置：全部 <k> 种任务配置
- [ ] 真实数据：来自冻结网络节点 `<node>`

## 结果

- [ ] `run.log` PASS，比对计数 <N>（`sim_check.py --expect-count <N>` 返回 0）
- [ ] `result.json` 状态 PASS，含源文件 SHA256
- [ ] lint：<工具与版本> `<参数>`，必须清零的类别为 0，见 `lint.log`
- [ ] Latency：<n> 拍，已写入接口文档
- [ ] 仿真缓存已清理，只保留源码、生成 RTL、最小向量与记录

仿真 PASS 只证明功能与整数 Golden 一致；<频率> 时序需后续 STA 报告确认。本阶段未进行综合、实现、bitstream 或上板。
