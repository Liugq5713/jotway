# Proposal

## Why

当前 AI Services 要用户自行判断接口协议、查找地址并填写模型 ID，DeepSeek 等常见服务也缺少直接入口。需要把已有个人模型能力整理成可理解的配置流程，减少手工填写，同时保持凭据与实际调用服务一致。

## What Changes

- 增加 DeepSeek、Kimi、OpenAI、Claude 与自定义服务入口，预填协议和地址并提供官方 Key 获取链接。
- 显式加载模型列表，保留手填模型 ID；失败或刷新不替换已有选择。
- 将地址和协议放进高级设置，分别展示模型发现与固定样例生成测试的结果及实际目标。
- 保留单个人配置、托管优先与隐藏界面恢复开关；不增加本地模型、多账号或自动服务切换。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `model-capabilities`：服务商预设、模型发现、凭据限定与设置交互。

## Impact

涉及 AI 设置、个人模型配置、模型目录请求和相关说明。新增只读模型目录网络请求，不增加依赖，不改变已有模型生成协议或凭据存储结构。
