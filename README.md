# 变电站光伏

## Load

在 SketchUp 2022 Ruby 控制台加载统一入口：

```ruby
load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/pv_toolbar.rb'
```

统一工具栏含八个按钮：标准变电站、光伏板与出力、阵列与出力、边界约束、电气配置、预测出力、导出CSV、导出SVG / DXF。

三个工具均从空选择开始，支持单板、阵列或包含光伏板的群组；点击累计选择，Ctrl点选嵌套单板。Enter后，预测工具打开查询窗口，CSV与图纸工具直接弹出保存窗口。查询窗口中的CSV、SVG按钮也进入同一套重新选取流程。CSV汇总所选PV的原始出力，图纸导出所选PV的水平俯视图，一次保存同时生成同名SVG与DXF；DXF保留真实水平投影毫米尺寸、图层和可编辑文字。电气配置中的电路导出采用相同的成对输出方式。

旧会话已有错误工具栏注册时，重启SU后加载入口一次。重复加载不会追加按钮。

## 出力数据

仓库保存1°数据索引，不包含完整逐时与月汇总CSV。完整数据目前保存在本地；克隆或下载仓库后，需从已有数据目录复制五个型号的CSV，保持以下目录结构：

```text
data/pv_generation/stride_1-1/
  index.json
  <型号目录>/
    hourly.csv
    monthly_hourly.csv
    row_index.json
```

索引已随代码提供，CSV原始数值和格式保持不变。数据未放齐时，出力查询及依赖真实出力的测试无法完整运行；生成模型与插件代码仍保留在仓库中。插件运行读取本地文件，不依赖网络。

## Files

| Path | Content |
| --- | --- |
| `data/model.skp` / `data/model.skb` | 标准模型及备份 |
| `scripts/pv_toolbar.rb` | 统一工具栏入口 |
| `scripts/tools/` | 八个按钮的实现 |
| `scripts/support/` | 排布、选取、场景读取与导出 |
| `scripts/inspect_model.rb` | 第一层组件信息表 |
| `scripts/insert_model_faces.rb` | 面数据记录和逐面插入 |
| `scripts/merge_pv_generation.py` | 出力时序合并 |
| `data/` | 组件参数、面数据与合并出力数据 |
| `data/pv_generation/stride_1-1/` | 1°数据目录；Git保存索引，完整CSV单独提供 |
| `output/checks/` | 可重新生成的测试样例与校核产物 |
| `ui/` | 单板、阵列、预测与电气等工作区及共用控件 |
| `icons/` | 工具栏本地PNG |
| `tests/` | 当前功能的离线校核脚本，运行方式见[测试说明](tests/README.md) |
| `references/gb50797_2024/` | 间距参考资料、原图及来源 |

内部路径相对脚本定位。移动整个project后，只需更改首次load路径。仿真源文件可放在项目之外；转换后插件只读取合并数据，不依赖源盘在线。

合并脚本接受`--source`源目录，每个`<功率>_excel_files`目录须唯一对应参数表中的型号。每型号生成`hourly.csv`、`monthly_hourly.csv`和`row_index.json`，型号信息与校验结果统一保存于根目录`index.json`；逐时数值与月年汇总核对后进行保存回读，保留双精度数值。`--model`可指定单一型号，配合`--workers 4 --shards 4`按方位角区间并行处理；分段逐值校验后拼回同一份表。每个型号完成后自动更新索引，`--finalize`可重新核验全部已索引型号。

修改标准模型后：先保存 `data/model.skp`，加载 `scripts/insert_model_faces.rb` 并执行 `SuPvFaces.capture` 更新面数据，再到目标模型使用按钮1插入。`insert` 只重建已提取的数据，不负责更新标准模型，也不会刷新已经插入的实例。

## Conventions

世界+Y为北、+X为东、+Z为上；方位角顺时针，倾角相对世界水平面。
组件在 `PV_panel` Tag；阵列为独立Group，内含板型Component实例，支持撤销。
阵列净距界面单位cm，滑条5cm、手输1cm。上限随板投影和安装面尺寸计算。
当前仅处理内置数据索引中的5种板型（140、480、505、560、630 W）。参数原表保留其他记录，工具和转换脚本不读取这些型号。出力数据按型号严格匹配。当前方位角0°—359°、倾角0°—90°，步长均为1°；360°与0°为同一方向。非整数角度保持实际几何，缺少精确查表值时不插值或借用邻近角度。

阵列窗口集成原始预测与阴影修正；分别查看周边遮挡（黄）、自遮挡（深蓝）及并集（绿）。场景读取当前可见面，计算考虑嵌套变换和孔洞。扬州太阳位置固定32.4°N、119.4°E、UTC+8、2025年，逐时自动计算；混合选取按各板数据加权。

wall、fence Tag强制贴合安装面；fence板长超过面高时允许从上边界伸出。所有平面图均沿世界Z轴俯视。CSV与SVG为独立导出按钮：CSV导出全年出力，图纸按钮同步导出SVG与DXF矢量俯视图。核心公式见 `docs/methods.md`。
