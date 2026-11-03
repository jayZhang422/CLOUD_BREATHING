# Airway 训练最终报告

## 结果

- 实际完成：31 轮；用户停止要求：第 30 轮完成后停止。
- 停止原因：第 30 轮停止请求交接期间，第 31 轮已经完成并写入记录；未启动第 32 轮。
- best：第 27 轮。
- best 权重：`<server_root>/lung_training/airway_mkdc_v1/runs/resunet_mkdc_relu6_100e_v2/best_records/best_epoch_0027.pt`
- best 权重 SHA256：`f0141e0a3579d33b3d781abe10d3f403a22d8673c263e9aca78ff85854df75ce`
- 远端最终状态：`complete`；训练、终结和监督进程均已退出。

## 验证集

best=27 的完整验证集结果：

| 聚合 | Dice | Recall | Precision | 阳性层召回 |
|---|---:|---:|---:|---:|
| Global | 0.9012988735 | 0.9340946840 | 0.8707278551 | 0.9877074689 |
| Macro | 0.9000573486 | 0.9340879519 | 0.8726465646 | 0.9869230788 |

验证集每病例结果见 `reports/final_export/best_validation_cases.csv`，共42例。

## 测试集

测试仅在 best 选定后执行，未用于选 best；共42例、28610层完整推理：

| 聚合 | Dice | Recall | Precision | 阳性层召回 |
|---|---:|---:|---:|---:|
| Global | 0.9005237751 | 0.9295116821 | 0.8732892309 | 0.9886142006 |
| Macro | 0.8993106857 | 0.9306131222 | 0.8724394475 | 0.9881744656 |

测试集每病例结果见 `reports/final_export/test_cases.csv`。Dice 最低的测试病例为 ATM_046=0.8283995、ATM_108=0.8298532、ATM_065=0.8303804、ATM_051=0.8541402、ATM_030=0.8648795。

## 气道连续性诊断限制

固定病例 ATM_135、ATM_170、ATM_614 使用保留各向异性原始网格的 26 邻域连通性、Lee 3D GT 骨架、零容差覆盖和 EDT 半径不超过2 mm 的细中心线覆盖诊断。第27轮细中心线覆盖分别为 0.82197、0.87087、0.92496；这些是诊断指标，未宣称为官方树长或分支检出率。官方 `tree_length_detection_rate` 和 `branch_detection_rate` 没有可信评估器，均保持为空。

## 监督与异常

- 第1至31轮记录、监督报告、决定文件的 SHA256 链独立审计通过；总 optimizer updates=18225，AMP 跳步=3。
- 保留了原始不一致证据：`final_results_epoch30_original.json`、`final_check_failed_original.json`、`status_paused_original.json`。原失败只来自 `completed_epochs=30` 与监督核验到31轮不一致，未发现 OOM 导致训练失败。
- 20个 ATM22 病例标签存在但 CT 缺失（ATM_242–250、ATM_501–511），按预检记录隔离，未混入监督训练。
- 训练前 smoke 的优化器恢复问题已在独立 v2 修复；修复只比较 CPU 上的恢复状态，不改变损失、指标、架构或输入契约。

## 交付文件

- `final_results.json`：实际31轮、best27轮的修正版最终结果。
- `final_check.json`：独立修复后一致性核验 PASS，并指向原始 FAIL 证据。
- `reports/final_export/epoch_metrics.csv`：31轮训练/验证轨迹。
- `reports/final_export/best_validation_cases.csv`、`test_cases.csv`：完整每病例指标。
- `reports/final_export/summary.json`、`manifest.json`：汇总和导出文件哈希。

该模型可以进入独立 INT8/部署接口和三维气道连续性验证；仅凭体素 Dice 不应直接宣称部署完成。
