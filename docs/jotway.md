# Jotway documentation

This page is the documentation entry point. A document's role determines whether it is authoritative.

- **Current**: product and architecture pages explain shipped behavior and link to detailed behavior contracts in `openspec/specs/`. Both describe the current source build.
- **Work**: a temporary proposal or implementation brief; it is not current behavior.
- **Reference**: reusable external, protocol, or operational facts.
- **Decision**: the durable reason behind a hard-to-reverse choice.

Terminology lives only in [CONTEXT.md](../CONTEXT.md). When a spec and code disagree, reconcile them in the same change rather than adding another explanation.

## Current product

| Document | Scope |
|---|---|
| [Product overview](product/overview.md) | Positioning, main flow, and product boundaries |
| [First use](product/first-use.md) | Entry points, shortcut setup, and the first successful action |
| [Settings](product/settings.md) | Current settings navigation and persistence boundaries |
| [Architecture](development/architecture.md) | Runtime modules and the routing/execution flow |
| [Data model](development/data-model.md) | Launcher datasets and independent database initialization |
| [Environment](development/environment.md) | Build, package, application identity, and storage |
| [Runtime logs](development/runtime-logs-research.md) | Privacy boundary, retention, export, and clearing |
| [AI capability](plugins/ai.md) | Optional text processing and configuration |
| [Plugin distribution](plugins/README.md) | Source and package boundaries for optional capability |
| [App updates](product/updates.md) | Sparkle configuration and user-visible update behavior |
| [Website and usage images](development/website.md) | English static site, interactive demo, verified download metadata, and README captures |

## Actions and routing

| Document | Scope |
|---|---|
| [Apple Notes](integrations/apple-notes.md) | Default action, destination, and text writing |
| [Clipboard](integrations/clipboard.md) | Local clipboard history, image text search, and exact copy |
| [Codex](integrations/codex.md) | Background app-server tasks and conversation links without choosing a project |

## Work documents

These describe active or candidate changes. Their contents do not override specs.

| Document | State |
|---|---|
| [Input responsiveness](development/launcher-ui.md) | Draft: stable target and preview layout, availability caching, and typing performance validation |
| [Submission receipt](product/submission-receipt.md) | P1 implementation brief: immediate non-activating completion feedback and grouped results |
| [Editor cursor alignment](development/editor-cursor-alignment.md) | Pending follow-up: native empty-line caret geometry and input-method positioning |
| [Personal routing memory](development/personal-routing-memory.md) | Paused candidate; automatic learning and its previous storage assumptions require reassessment |

Delete a Work document after its resulting behavior has been synced into the relevant spec.

## Decisions and references

| Document | Role |
|---|---|
| [Launcher pivot](development/launcher-refactor.md) | Decision: transient launcher instead of local inbox |
| [Connector to action](development/launcher-connector-to-action.md) | Decision: one action abstraction |
| [Jev API](integrations/jev-api-research.md) | Reference: retired Jev protocol and historical diagnostics only |
| [Cloudflare Workers AI proxy](integrations/cloudflare-workers-ai-research.md) | Reference: proxy integration, mainland China latency, and measurement boundaries |
| [Launcher competitor research](development/launcher-competitor-research.md) | Reference: Raycast, Alfred, and LaunchBar capabilities and Jotway comparison boundaries |
| [ASCII shark background](development/ascii-shark-background-research.md) | Reference: upstream rendering and licensing, native editor fit, and typing-aware motion feasibility |
| [ASCII cat motion](development/ascii-cat-motion-research.md) | Reference: disappearance and return discontinuities, offscreen evidence, and character-motion options |
| [Application matching research](development/application-matching-research.md) | Reference: Raycast search behavior, Tinycast matching and ranking, and Jotway application-search gaps |
| [AI development plans](development/ai-development-plans-research.md) | Reference: readable plan templates, acceptance criteria, and agent handoffs |
| [Codex sidebar visibility](development/codex-sidebar-research.md) | Reference: background-session discovery, community workarounds, and app-server integration options |
| [Apple Notes native tags](development/apple-notes-tags-research.md) | Reference: native tag actions, community integrations, and verification boundaries |
| [Apple Notes formatting](development/apple-notes-formatting-research.md) | Reference: rich text, HTML import boundaries, and source links |
| [AI and personal notes community practices](development/ai-notes-community-research.md) | Reference: first-person workflows, product patterns, evidence limits, and implications for Jotway |
| [Capture and thinking mechanisms](development/capture-and-thinking-mechanisms-research.md) | Reference: primary evidence, product mechanisms, work/life reflection, and candidate validation |
| [Personal Agent context strategies](development/personal-agent-context-research.md) | Reference: full context, targeted retrieval, and global summaries for personal questions |
| [AI provider onboarding](development/ai-provider-onboarding.md) | Reference: adding an AI source |
| [BYOK 接入参考](development/byok-provider-onboarding-research.md) | Reference: 开源项目的服务商配置方式、Jotway 当前差异与交互初稿 |
| [AI provider implementation](plugins/ai-provider-implementation.md) | Reference: provider request path |
| [Third-party notices](../THIRD_PARTY_NOTICES.md) | Reference: dependency sources and licenses |

## Maintenance rules

1. Choose the lightweight or full workflow using [AGENTS.md — Change Workflow](../AGENTS.md#change-workflow). Small changes need no Work document; when one is needed, keep only the scope and acceptance information needed to carry out the change.
2. Keep Current docs and their detailed specs timeless. Do not append delivery dates, build durations, PIDs, local installation receipts, or chronological implementation logs.
3. After implementation, update the affected main spec directly for lightweight changes, or sync delta specs for OpenSpec changes. Update Current docs only where behavior or structure changed; link to detailed specs instead of repeating their scenarios. Delete completed Work briefs. Git is the archive.
4. Keep research only when its sources or uncertainty boundaries will be reused.
5. Create a decision record only when the choice is hard to reverse, surprising without context, and the result of a real trade-off.
