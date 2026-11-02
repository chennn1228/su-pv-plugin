# 离线校核

所有检查均使用模拟模型对象或纯数值数据；不启动、控制或保存 SketchUp。测试文件按当前功能划分，`test.skp` 与 `test.skb` 是人工模型样例，不由脚本改写。

## Ruby 与测试样例

使用 SketchUp 2022 自带 Ruby DLL运行纯 Ruby 检查：

```powershell
python tests/run_ruby_checks.py tests/check_plugin.rb
python tests/run_ruby_checks.py tests/verify_release.rb
python tests/run_ruby_checks.py tests/check_access_layout.rb
python tests/run_ruby_checks.py tests/check_access_planner.rb
python tests/run_ruby_checks.py tests/check_electrical_mounting.rb
python tests/run_ruby_checks.py tests/check_prediction.rb
python tests/run_ruby_checks.py tests/check_roof_angles.rb
```

样例和测试结果统一写入 `output/checks/`。该目录可删除；按上面命令重新生成后，再运行对应 JavaScript 检查。预测、屋面与通道样例仍支持脚本中的环境变量覆盖输出位置。

## 功能分组

| 范围 | 脚本 |
| --- | --- |
| 模型与布局 | `check_plugin`、`check_layout`、`check_roof_*`、`check_layout_search` |
| 约束与检修通道 | `check_access_*`、`check_constraints_tool` |
| 支架与配置建议 | `check_mounting_*`、`check_design_advice` |
| 电气 | `check_electrical_*`、`check_characteristics` |
| 预测与遮挡 | `check_prediction`、`check_shading*`、`check_scene_*`、`benchmark_shading` |
| 导出与界面 | `check_generation_export`、`check_export_selection`、`check_header_layout`、`verify_ui` |
| 数据一致性 | `audit_csv.py` |

JavaScript 的 `.cjs` 检查由 Node.js 执行；涉及界面的脚本还需要 Playwright 和本地 Edge，仅渲染插件 HTML。
