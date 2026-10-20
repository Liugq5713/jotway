# personal-context-retrieval Specification

## Purpose

定义已移除的个人问答与历史检索入口的边界，确保旧个人来源与向量配置不再触发自动索引或模型请求，也不控制存入或笔记回顾；原始笔记继续保留，笔记回顾遵循 `notes-review` 的独立开关及显式请求规则。

## Requirements

### Requirement: Retired personal retrieval remains inactive

系统 SHALL NOT 注册 Personal Agent 问答、个人来源设置、日期规划、分批摘要或回答证据处理。Related History 与 embedding 配置 SHALL 移除，不再自动索引 Notes 或发送向量请求。旧个人来源偏好 SHALL NOT 控制存入或笔记回顾；回顾只迁移原 Notes 文件夹范围，并遵循独立开关及显式请求规则。

#### Scenario: Existing retrieval settings remain dormant
- **WHEN** 旧版本已保存向量凭据、索引开关或 Personal Agent 来源配置
- **THEN** 启动、返回应用或普通输入均不触发历史索引、向量调用或个人问答

#### Scenario: Keep original notes and provenance
- **WHEN** 打开旧的本地检索数据库
- **THEN** 迁移只移除派生检索缓存并保留原文边界记录，不改写或删除 Apple Notes 原始笔记
