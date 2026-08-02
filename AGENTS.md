# AGENTS.md - 无畏契约灵敏度测试升级版

## 项目概览

- **引擎**: Godot 4.7 (Forward+ 渲染器, GDScript)
- **类型**: 2D 项目 (canvas_items 拉伸模式)
- **平台**: Windows (D3D12 渲染驱动)
- **物理引擎**: Jolt Physics (3D)

## 项目结构

本项目是 Godot 4 项目，所有资源路径 (`res://`) 均相对于项目根目录。
- `project.godot` — 项目配置入口（启动场景为 `res://main.tscn`）
- `main.tscn` / `test_select.tscn` / `test_config.tscn` / `test_shoot.tscn` / `test_result.tscn` / `history.tscn` / `settings.tscn` / `about.tscn` — 场景文件（测试流程：选择 → 配置 → 射击 → 结果；test_shoot 为 3D 射击场场景）
- `target.tscn` — 3D 目标预制体（程序生成靶子纹理，Area3D 命中检测，`scripts/target.gd`）
- `scripts/` — 场景脚本（`main_menu.gd` 导航、`back_button.gd` 返回主菜单、`nav_button.gd` 通用跳转按钮 `@export target_scene`、`esc_nav.gd` 通用 ESC 返回按钮 `@export esc_scene`、`scene_nav.gd` 场景切换封装（含错误检查 + 切换后淡入过渡，各脚本用 `const SceneNav := preload(...)` 引用）、`top_bar.gd` 共享标题栏、`settings_menu.gd` 配置读写、`test_select.gd` / `test_config.gd` 测试流程逻辑、`test_shoot.gd` 射击主控（热身/轮次/数据收集/灵敏度映射/暂停/轨迹微调/跟枪检测/目标对象池）、`target.gd` 目标逻辑（程序纹理静态缓存 + 对象池复用）、`crosshair.gd` 准星绘制（标准/紧凑/圆点三样式）、`sfx.gd` 程序合成音效、`chart.gd` 自绘折线图（CI 带/图例）、`advice.gd` 问题识别与建议、`test_metrics.gd` 指标聚合、`history_store.gd` 历史 JSON 存储、`test_plan.gd` 灵敏度策略、`test_objective.gd` 目标函数、`bayes_opt.gd` 贝叶斯优化）
- `tests/run_tests.gd` — 常驻回归测试（61 项：目标函数/BO 收敛/GP 方差/指标聚合/历史存储/图表几何/微调检测/场景实例化/平坦检测/高原修正/异常耗时剔除/命中耗时真实性/稳定性阈值），运行 `--headless --script res://tests/run_tests.gd`
- `scripts/test_session.gd` — autoload 单例 `TestConfig`（注册于 project.godot `[autoload]`），保存当前测试参数（测试类型/灵敏度范围/轮数/目标类型/大小/模式）、测试执行状态（`current_round`/`current_sens`/`round_results`）、`reset()` 重置方法、设置读取（`get_dpi()`/`get_fov()`），跨场景传递数据用
- `ui/theme_valorant.tres` — 全局 UI 主题（无畏契约红黑配色，挂在各场景根节点）
- `ui/top_bar.tscn` — 共享顶部标题栏子场景（`@export title_text`），各场景 instance 引用
- `settings.tscn` 配置保存至 `user://settings.cfg`（ConfigFile 格式）
- `.godot/` — 自动生成目录（已在 `.gitignore` 中忽略），包含导入缓存、着色器缓存、编辑器布局等
- `*.import` — 资产导入伴生文件（由 Godot 编辑器自动管理）
- `无畏契约灵敏度测试工具 - 开发计划-wz优化0731.md` — 开发计划文档，按 Phase 勾选进度

## 开发命令

- **打开项目**: 使用 Godot 编辑器直接打开 `project.godot`，或运行 `godot -e`
- **运行项目**: `godot --path "."` 或编辑器中按 F5
- **命令行运行**: `godot --headless`（无窗口运行模式）
- **回归测试**: `D:\godotstudy\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe --headless --path "." --script res://tests/run_tests.gd`（61 项常驻用例）

## 注意事项

- GDScript 脚本会自动被 Godot 识别，无需手动编译
- 导入的资产会生成对应的 `.import` 文件，两者需要一起提交到 Git
- 项目名称含中文字符，路径中也含中文，命令行操作时需注意编码和引号
- **不要依赖 `class_name` 全局注册**：headless `--script` 验证模式下全局类缓存可能未更新，跨脚本引用统一用 `const Xxx := preload("res://scripts/xxx.gd")`；`--script` 验证脚本需先 `await process_frame` 再实例化场景（autoload 注入时序）

## 工作流程（必须遵守）

- **每次代码改动完成后**（验证通过后），自动执行 `git add -A` + `git commit`，提交信息用中文简述本次改动
- **同步更新 AGENTS.md**：每次改动后检查本节「项目结构」「开发命令」等内容是否过时，如有变化立即更新
- 改完代码后先用 `D:\godotstudy\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe --headless --path "." --quit` 验证无脚本错误，再提交

## 约定

- **你没有识图能力**, 禁止沟通中出现截图发我等幻觉。