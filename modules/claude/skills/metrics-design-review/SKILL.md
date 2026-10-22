---
name: metrics-design-review
description: Design and review operational metrics and monitoring for useful labels, bounded cardinality, collision-free series identity, and correct alert semantics. Use whenever creating, modifying, or reviewing Prometheus/OpenTelemetry metrics, exporters, collectors, dashboards, or alert rules—even when the user only asks to add a metric, improve monitoring, or fix a Grafana query. Proactively challenge execution-specific labels, resource attributes, missing identity, sparse recovery, and freshness. Do not use for statistical/model metrics stored only in tables or standalone incident investigation unless telemetry design is being changed.
---

# Metrics Design Review

Treat telemetry as a data model with operational consumers. Help developers find
causes and SREs detect actionable conditions, while keeping series identities
stable, sufficiently distinct, and affordable. Challenge the design during the
requested work; a review is not an extra approval gate.

## 1. Establish the actual telemetry contract

Inspect repository instructions and existing conventions. Trace relevant metrics
from source calculation through exporter/collector transformations to queries
and alerts. Distinguish implemented behavior from drafts and external systems
you cannot inspect. Scale the review to the request; inspect all producers and
shared resources when asked for a full audit.

For each metric, identify:

- Operational question, consumers, unit, instrument type, and value meaning.
- Full name, point labels, resource attributes, and backend-added dimensions.
- Producer count, entity population, publication cadence, and retention window.
- Existing queries, alert grouping/routing, and source-data/log/trace correlation.

Do not treat an arbitrary variable called `metrics`, training-quality statistics
in a table, or run IDs in audit records as exported metric labels. Preserve
source filtering and audit correlation when changing exported identity.

Read [references/design-checks.md](references/design-checks.md) when estimating
cardinality, choosing identity, or reviewing query/alert behavior.

## 2. Challenge every dimension

For every proposed label, resource attribute, and dynamic name component, ask:

1. Which concrete query, grouping, drill-down, or notification needs it?
2. Is it a stable entity/category, a measurement, or an individual event/run?
3. How many distinct values occur per deployment and over retention? Does the
   value grow without bound or change on each execution/restart?
4. Could this detail live more usefully in logs, traces, supported exemplars,
   source records, or a metric value instead?
5. Does an exporter promote it into series labels or a changing `target_info`
   series? Verify the actual mapping; moving a label into a resource does not
   automatically remove its cardinality cost.

Flag run/request/trace IDs, UUIDs, timestamps, ephemeral cluster/application IDs,
IPs, raw URLs, free-form errors, and generated model instances. Also inspect
metric names: putting an ID in a name hides rather than fixes cardinality.

Estimate plausible active and retention-window series counts. Use observed
combinations when possible; a Cartesian product is an upper bound, not a fact.
Include replicas/targets and histogram bucket expansion. State assumptions and
compare with repository/platform budgets; do not invent a universal safe limit.
Separate per-batch caps, active series, and historical churn. A top-20 affected
entity list can still introduce thousands of historical series as membership changes.

Keep justified entity dimensions. A new service or monitored resource may
legitimately create a series; a new execution of the same entity normally should
not. Version identifiers may be bounded configurations or generated per-execution
artifacts—inspect which.

## 3. Prove identity remains collision-free

Before deleting a dimension, write down the final identity: metric name plus
all exported labels, including applicable resource/target dimensions.

Check both directions:

- **Continuity:** same logical entity, different run/retry/restart → same series
  when the metric is intended to describe logical state.
- **Separation:** different entities or simultaneous producers → distinct series,
  or explicitly aggregated measurements with defined semantics and ownership.

Consider workspace, environment, tenant, service, node, region, and overlapping
executions as appropriate. Do not remove all producer identity from independent
writers or silently use last-writer-wins for conflicting observations.

For infrastructure counters and per-node data, ephemeral identity can be
necessary for correctness. Do not blindly strip it to meet a cardinality target.
Choose a real aggregation architecture or a justified per-instance budget; define
counter resets, node lifecycles, and concurrent writers. A bounded slot label
is only valid if the system actually assigns and coordinates those slots.

Prefer readable stable dimensions where useful. Names are acceptable if unique
in their scope and rename churn is acceptable. Use IDs when uniqueness requires
them; do not add both ID and name automatically. If using an info mapping for
readability, include its cardinality and join uniqueness in the review. Keep
bounded routing labels such as `team` or `alert` only when consumers need them.

## 4. Check measurement and alert semantics

- Use gauges for snapshots, counters for cumulative events, and appropriate
  histograms for distributions. Follow local naming/unit conventions and flag
  misleading `_total` gauges; avoid gratuitous renames during label-only fixes.
- Specify zero, missing/no-data, failure, and not-applicable independently.
  Sparse problem-only emission does not report recovery. Capped-out entities
  are not healthy by implication. Do not add persistent reset state casually.
- Compare publication cadence with backend lookback and alert evaluation.
  Stable labels do not keep daily pushes visible to ordinary instant queries.
- Use latest-value range queries for latest snapshots. A historical maximum can
  preserve an old failure or hide a new failure in a success gauge. Define the
  window from cadence/latency and monitor freshness separately.
- Define how expected entities are enumerated when detecting partial or total
  disappearance. A query over existing series alone cannot identify an entity
  that no longer has any samples; scope against configuration/inventory and
  handle retired entities explicitly.
- Use rate/increase only with suitable counter/reset semantics. For ephemeral
  sources, account for resets and aggregate in the correct order.
- Examine retry/duplicate ingestion, timestamps, out-of-order samples, overlapping
  runs, and authoritative writers where relevant. A duration is a value/unit,
  not a label; completion timestamps can be gauge values for freshness.
- Ensure alert identity and routing stay meaningful; explain migrations of label
  selectors, recordings, joins, and dashboards affected by a contract change.

## 5. Implement and verify proportionately

Follow the user's requested scope. For an implementation request, make the
changes and verify them rather than stopping at advice. Raise only decisions
that materially affect correctness or operational tradeoffs.

Prefer a documented label contract with validation at an appropriate boundary
when it fits the existing architecture. Validate missing and unexpected labels
without silently dropping identity. Keep intentional metric extensibility.

Use focused checks that can fail for real design defects:

- Compare exported series keys across different executions of the same entity.
- Emit two distinct/concurrent entities and verify separation or correct
  aggregation. Exercise duplicate/ambiguous identities explicitly.
- Inspect serialized resource and point attributes; test source filtering still
  works after removing execution correlation from labels.
- Check recovery/no-data and representative alert transitions when those
  semantics change. Review actual scrape output if available.

Do not infer backend behavior from a unit test alone. State what was verified
locally and what requires deployed telemetry. Avoid tests that merely copy the
implementation's allowlist without independently checking identity semantics.

## Review output

Lead with the concrete findings or completed change. For a broad review or label
migration, provide this table (use full metric names; group only identical
contracts and keep the covered names discoverable):

| Metric | Purpose / type | Current labels and resources | Cardinality / collision finding | Proposed labels and resources |
| --- | --- | --- | --- | --- |

Then summarize:

1. Cardinality estimate and assumptions, including intentional entity growth.
2. Continuity/separation reasoning and relevant lifecycle tradeoffs.
3. Query, alert, recovery, and freshness impacts.
4. Changes, focused verification, and any remaining material decision.

For a small change, give only the applicable findings and checks. Never claim
zero cardinality risk or guaranteed collision freedom without evidence.
