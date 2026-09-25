# Jev API reference

> Role: **Reference**

This document records the external contract Jotway relies on. Current product behavior lives in [Jev intent recognition](jev-intent-research.md); source code defines the exact active rule.

## Provider

Jev is provided by TypeSafe and models classification questions with typed primitives such as Noul and Choice. Jotway consumes structured answers rather than asking for free-form text. Useful upstream references:

- [TypeSafe Jev quick start](https://docs.typesafe.ai/jev/quickstart)
- [Noul primitive](https://docs.typesafe.ai/primitives/noul)
- [Choice primitive](https://docs.typesafe.ai/primitives/choice)

## Jotway contract

- Input is the current draft text within the configured byte limit.
- Available action criteria are constructed from the action registry.
- The response may suggest one semantic action; Jotway maps it to a concrete enabled action locally.
- Scores and returned shapes are validated before a suggestion is shown.
- Explicit user selection and local keyword routes remain authoritative.
- Application launch is local and absent from the model's action set.

The active rule version is `Jev.ruleVersion` in source. Historical JSON snapshots do not live in `docs/`; runtime log export includes the exact current definition.

## Interpretation limits

- Provider confidence is not measured end-to-end routing accuracy.
- A syntactically valid response can still be semantically wrong.
- Mentioning an action name does not prove the user wants that action; quoted, negated, historical, or subject/object mentions require role-aware classification.
- Several internal steps inside one delegated task still map to one Jotway action. Several explicit Jotway destinations cannot be compressed into one.
- An unavailable target is rejected locally rather than silently replaced by another action.

## Privacy and reliability

The draft text is sent only when recognition is configured and eligible. Keys, clipboard history, local intent corrections, and unrelated application data are excluded. Network failure, timeout, invalid shape, or low-confidence output must leave the default local path usable.

Do not infer latency, accuracy, supported languages, pricing, or retention promises from this repository. Recheck the provider's current documentation before changing those claims.
