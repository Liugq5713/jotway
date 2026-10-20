# Spec Delta

## ADDED Requirements

### Requirement: Drag guides identify the default panel position

快捷输入或临时便签发生真实窗口移动时，系统 SHALL 在当前拖动屏幕显示默认水平中心的垂直线和默认顶边的水平线。目标 SHALL 根据当前受约束的窗口尺寸，复用无保存位置时的默认放置：在可用区域水平居中、距可用顶边 18% 高度，并限制在可用屏幕内。两个轴 SHALL 相互独立。

#### Scenario: Return after an earlier move
- **WHEN** 用户拖动已有自定义保存位置的面板
- **THEN** 引导线指向默认位置，不指向保存位置或本次拖动起点；移动期间两条线均在面板外可见

#### Scenario: A lower card or manual size is present
- **WHEN** 用户拖动手动调整尺寸或带有下方内容卡的面板
- **THEN** 垂直目标对应窗口水平中心，水平目标对应顶边而非垂直中心；屏幕约束包含当前完整窗口，引导线符合可到达的默认位置

#### Scenario: Sticky mode uses the same alignment reference
- **WHEN** 用户拖动临时便签
- **THEN** 引导线按其当前尺寸使用相同默认放置公式；首次进入仍用既有左上锚点，重开仍恢复进程内几何

### Requirement: Releasing near a guide aligns only that axis

拖动期间面板 SHALL 自由跟随指针。窗口某一轴与目标距离不超过 8 pt（含边界）时，该引导线 SHALL 显示激活状态。发生移动后正常松手时，系统 SHALL 无动画地将每个激活轴精确对齐，其他轴保留自由位置但遵循既有屏幕约束，并移除引导线。无移动的点击及中断拖动 SHALL 不对齐。

#### Scenario: Align both axes
- **WHEN** 松手时水平中心距垂直线 6 pt，顶边距水平线 8 pt
- **THEN** 松手前两条线均激活，最终窗口两个轴距离目标坐标均不超过 1 pt

#### Scenario: Align only one axis
- **WHEN** 松手时水平中心距垂直线 8 pt，顶边距水平线超过 8 pt
- **THEN** 仅垂直线激活，仅水平位置吸附；垂直位置保持自由且遵循既有屏幕约束

#### Scenario: Leave the alignment range
- **WHEN** 用户先接近引导线，松手前又移到超过 8 pt 的位置
- **THEN** 该线恢复非激活状态，该轴不吸附；移动途中指针不受磁性阻力

#### Scenario: Click or resize instead of moving
- **WHEN** 用户只点击可拖动留白而不移动，或拖动缩放边缘
- **THEN** 不出现对齐引导线或位置吸附，原有点击和缩放行为仍可用

### Requirement: Drag guides follow the window across screens

当前拖动屏幕 SHALL 按未对齐窗口与屏幕完整区域的最大交集选择。平局时保留仍符合条件的上一屏，否则按稳定屏幕顺序选择。引导线 SHALL 仅显示在该屏可用区域内；换屏立即替换旧线和目标。无屏幕相交时隐藏且不吸附；显示配置变化 SHALL 取消当前手势的对齐。

#### Scenario: Drag between displays
- **WHEN** 面板从一个屏幕移向尺寸、比例或坐标原点不同的另一屏幕
- **THEN** 最大交集变化时切换引导线，目标采用新屏幕以 pt 表示的可用区域；松手不能吸附旧屏幕，唤起屏幕偏好不能覆盖拖动选屏

#### Scenario: Lose the active display
- **WHEN** 拖动期间显示器断开或可用区域变化
- **THEN** 清除引导线和待执行对齐，由正常屏幕恢复逻辑保持窗口可达；旧手势后续不能吸附或保存过期对齐位置

### Requirement: Guide feedback preserves input and cleans up with the drag

引导线 SHALL 不可交互、不激活，不进入键盘导航或辅助功能焦点；位于面板可见卡片外，保留文字、选区、Undo 与组词。浅色、深色及增强对比度下 SHALL 保持可读，不使用持续动画或截屏。结束、隐藏、关闭、切换模式、失去拖动或开始提交过渡 SHALL 立即移除引导线。

#### Scenario: Move through either supported drag path
- **WHEN** 用户通过原生背景拖动或自定义拖动区移动面板
- **THEN** 两条路径显示相同目标、激活状态、松手结果与清理效果，不激活其他窗口或夺取编辑器焦点

#### Scenario: Interrupt or hide during a drag
- **WHEN** 隐藏、关闭、切换模式、失去拖动或提交过渡中断了拖动
- **THEN** 不残留引导线，不执行待定吸附，且该中断手势不保存新位置

#### Scenario: Programmatic movement and accessible appearance
- **WHEN** 面板打开、随文字增长、恢复几何或播放过渡，或者用户启用减少动态效果／增强对比度
- **THEN** 程序移动不启动引导线或吸附；有效拖动的线保持静态可读，激活与非激活状态同时用线型和颜色区分

### Requirement: Alignment preserves mode-specific position storage

快捷输入完成拖动后 SHALL 通过已有位置偏好保存目标屏幕上最终受约束、对齐的实际窗口偏移。便签完成拖动后 SHALL 仅更新进程内几何。仅显示引导线、点击、缩放、取消或程序移动 SHALL NOT 写入拖动位置偏好；对齐不得重置其他屏幕位置或新增草稿／便签持久化数据。

#### Scenario: Reopen aligned quick input
- **WHEN** 用户将快捷输入两个轴对齐后隐藏，再以相同可用区域及窗口尺寸在同屏重开
- **THEN** 恢复最终对齐位置，而非松手前的原始位置；其他显示器的保存偏移不变

#### Scenario: Move a sticky note independently
- **WHEN** 临时便签吸附引导线后，用户切回快捷输入或重启应用
- **THEN** 快捷输入位置偏好不变；模式切换遵循各自既有几何规则，重启不恢复便签模式或其草稿
