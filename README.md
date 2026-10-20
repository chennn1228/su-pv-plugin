# 变电站光伏

## Load

在 SketchUp 2022 Ruby 控制台加载统一入口：

```ruby
load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/pv_toolbar.rb'
```

统一入口同时显示两套工具栏：

| 工具栏 | 按钮 |
| --- | --- |
| toolbar1 | 标准变电站、光伏板放置＋出力、阵列放置＋出力、平铺排布 |
| toolbar2 | 标准变电站、光伏板放置、阵列放置、预测出力、平铺排布 |

toolbar1在放置窗口中查询和导出；toolbar2选中已放置的单板或阵列后预测。两套窗口与参数独立，模型属性和内置数据兼容。

两套工具栏的平铺排布选择安装面，用SU原生参数框设置板型、排布方向、净距和离屋面高度。

旧会话已有错误工具栏注册时，重启SU后加载入口一次。重复加载不会追加按钮。

## Files

| Path | Content |
| --- | --- |
| `data/model.skp` / `data/model.skb` | 标准模型及备份 |
| `scripts/pv_toolbar.rb` | 同时加载两套工具栏 |
| `scripts/pv_toolbar1.rb` / `scripts/pv_toolbar2.rb` | 各版本入口，可单独加载 |
| `scripts/toolbar1/` | 放置与出力集成的版本 |
| `scripts/toolbar2/` | 独立预测版本及共用几何计算 |
| `scripts/inspect_model.rb` | 第一层组件信息表 |
| `scripts/insert_model_faces.rb` | 面数据记录和逐面插入 |
| `scripts/pv_csv.rb` | 参数CSV读取小实验 |
| `scripts/merge_pv_generation.py` | 出力时序合并 |
| `data/` | 组件参数、面数据、原始仿真结果 |
| `data/pv_generation/` | 插件内置查表数据及型号索引 |
| `output/` | CSV读取小实验的导出结果 |
| `ui/` | 两个交互窗口及共用控件 |
| `icons/` | 工具栏本地PNG |
| `tests/` | 可复用的离线校核脚本 |
| `references/gb50797_2024/` | 间距参考资料、原图及来源 |

内部路径相对脚本定位。移动整个project后，只需更改首次load路径。

修改标准模型后：先保存 `data/model.skp`，加载 `scripts/insert_model_faces.rb` 并执行 `SuPvFaces.capture` 更新面数据，再到目标模型使用按钮1插入。`insert` 只重建已提取的数据，不负责更新标准模型，也不会刷新已经插入的实例。

## Conventions

世界+Y为北、+X为东、+Z为上；方位角顺时针，倾角相对世界水平面。
组件在 `PV_panel` Tag；阵列为独立Group，内含板型Component实例，支持撤销。
阵列净距界面单位cm，滑条5cm、手输1cm。上限随板投影和安装面尺寸计算。
当前仅处理内置数据索引中的5种板型（140、480、505、560、630 W）。参数原表保留其他记录，工具和转换脚本不读取这些型号。出力数据按型号严格匹配。

两个阵列窗口的“预测出力”共用单板查询图表。“原始预测”按实际保留的板数逐时累加；“互遮挡实验”按扬州太阳变化 → 板面阴影 → 出力修正三步展示。位置固定为32.4°N、119.4°E，北京时间UTC+8，参考年2025；进入互遮挡分支后自动计算8760小时，保留原始分支。修改排布后自动更新，同型号阵列采用固定计算流程，关闭窗口后实验结果不保留。假设与计算函数见 `docs/methods.md`。
