# AGENTS.md - 无畏契约灵敏度测试升级版

## 项目概览

- **引擎**: Godot 4.7 (Forward+ 渲染器, GDScript)
- **类型**: 2D 项目 (canvas_items 拉伸模式)
- **平台**: Windows (D3D12 渲染驱动)
- **物理引擎**: Jolt Physics (3D)

## 项目结构

本项目是 Godot 4 项目，所有资源路径 (`res://`) 均相对于项目根目录。
- `project.godot` — 项目配置入口（启动场景为 `res://main.tscn`）
- `main.tscn` / `test_select.tscn` / `history.tscn` / `settings.tscn` / `about.tscn` — 场景文件（开发计划 Phase 1）
- `scripts/` — 场景脚本（`main_menu.gd` 导航、`back_button.gd` 返回、`settings_menu.gd` 配置读写）
- `ui/theme_valorant.tres` — 全局 UI 主题（无畏契约红黑配色，挂在各场景根节点）
- `settings.tscn` 配置保存至 `user://settings.cfg`（ConfigFile 格式）
- `.godot/` — 自动生成目录（已在 `.gitignore` 中忽略），包含导入缓存、着色器缓存、编辑器布局等
- `*.import` — 资产导入伴生文件（由 Godot 编辑器自动管理）
- `无畏契约灵敏度测试工具 - 开发计划-wz优化0731.md` — 开发计划文档，按 Phase 勾选进度

## 开发命令

- **打开项目**: 使用 Godot 编辑器直接打开 `project.godot`，或运行 `godot -e`
- **运行项目**: `godot --path "."` 或编辑器中按 F5
- **命令行运行**: `godot --headless`（无窗口运行模式）

## 注意事项

- GDScript 脚本会自动被 Godot 识别，无需手动编译
- 导入的资产会生成对应的 `.import` 文件，两者需要一起提交到 Git
- 项目名称含中文字符，路径中也含中文，命令行操作时需注意编码和引号
