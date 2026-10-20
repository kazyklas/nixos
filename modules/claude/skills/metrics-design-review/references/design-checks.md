# Practical metric-design checks

## Cardinality accounting

A series is a metric name plus its complete backend label set. OTLP point and
resource fields may be transformed during ingestion. Inspect collector
processors, target labels, backend promotion, and info-series generation.

Example: a snapshot has 3 environments, 200 affected resources per environment,
and 4 configured policies per resource. If all combinations exist, that is
2,400 series for one metric. Adding a unique daily execution label creates up
to 72,000 distinct series over 30 days for unchanged resources/policies.
Actual counts depend on combinations and retention; active-series billing
windows are not necessarily the same as storage retention.

For classic Prometheus histograms with B finite configured buckets, account for
B + 1 bucket series (including +Inf), plus sum and count, per label combination;
some exporters also emit a created series. Check whether B already includes
+Inf. Native histograms use different storage/accounting; inspect the backend
rather than multiplying by classic buckets. Summary quantiles also expand series.

Avoid double counting dimensions already represented by a product. Correlated
labels are not independent: a resource ID/name mapping does not multiply by
every possible pairing, although renames introduce churn. Dropping redundant
labels may improve clarity without reducing the number of current series.

## Label decision examples

| Candidate | Question / likely action |
| --- | --- |
| `env`, bounded region | Keep when consumers separate deployments. |
| execution/request ID | Keep in logs/traces/source records, not ordinary metric identity. |
| readable resource name | Keep if unique in its scope; acknowledge rename churn. |
| stable resource ID | Use when needed for uniqueness; recreation may change it. |
| customer/tenant ID | Quantify intentional entity population, churn, access patterns, and budget. |
| version/artifact ID | Check configured version versus generated per-execution artifact identity. |
| `http.route` | Prefer bounded template `/orders/{id}`, not raw URL `/orders/9817?token=...`. |
| `error` | Prefer bounded error class/code if useful; raw messages belong in logs. |
| duration / timestamp | Usually a numeric observation; timestamp-as-value can support freshness. |
| cluster ID / pod UID / IP | Lifecycle identity may prevent collisions; aggregate deliberately or budget churn. |
| `team`, `alert` | Static routing can justify them; ownership changes can still create new series. |

Do not encode dynamic values in metric names, comma-separated label values, or
resource fields to bypass an attribute review.

## Collision scenarios

### Readable scheduled-check snapshots

```text
check_last_success{env="prd",workspace="west",check_name="Database backup"} 1
check_last_success{env="prd",workspace="west",check_name="Certificate expiry"} 0
```

Different executions reuse these series. Two checks named `Database backup`
in the same scope would collide; verify uniqueness, use a stable logical key,
or retain necessary ID identity. A rename creates series churn. Selecting a
resource internally by ID does not require exporting that ID.

### Multiple independent workers

Deleting `{deployment_id, worker_ip}` from 8 concurrent worker exporters does
not magically create a valid service-level CPU metric. Define a central owner
and aggregation: sum appropriate usage/capacity measurements and compute a
weighted utilization, rather than summing percentages or combining raw counters
from independent writers. For counter rates, handle each source's reset before
aggregation. If no aggregation exists, preserve sufficient identity and explain
the budget instead of falsely claiming stable collision-free service series.

### Overlapping snapshot publishers

Two executions writing the same logical snapshot can race or arrive out of
order. Define whether the metric means last completed observation, latest
scheduled observation, or current aggregate state; choose authoritative
ordering/ownership. Moving execution IDs to logs alone does not resolve this
value-selection problem.

## Snapshot queries and recovery

For a daily always-emitted gauge, a cadence-aware example is:

```promql
last_over_time(check_last_success{env="prd"}[2d]) == 0
```

Choose the window for real cadence, jitter, and ingestion delay. This is a
latest sample in the range, not a guarantee of fresh publication. Monitor stale
or absent data separately, possibly with a completion-time gauge value. Do not
convert missing samples to zero indiscriminately.

Use an expected-entity inventory or equivalent configuration for partial
disappearance: per-series freshness queries cannot identify an entity with no
remaining series. Define how new and retired entities enter/leave that inventory.

`max_over_time(success[2d])` can hide a recent failure behind yesterday's success.
`max_over_time(failure_count[2d])` can retain yesterday's failure after today's
explicit recovery zero. Both may be valid historical questions, but do not
substitute them for latest-state questions.

A sparse `resource_failure = 1` stream has no recovery observation. Switching
from `max_over_time` to `last_over_time` cannot fix that. Possible explicit
designs include always-emitted bounded entity state, coordinated reset
observations, or an authoritative snapshot/incident model. Evaluate lifecycle,
state, and cardinality costs before choosing one. Capping and missing publication
make absence ambiguous; a fleet rollup zero alone does not reset individual series.

## Label-contract migrations

Removing a label introduces a new identity; historical labeled series remain
until retention expires. For range queries spanning the migration, consider
both schemas explicitly and avoid summing duplicate logical entities. Review
dashboard selectors, alert grouping, recording rules, and label joins. Do not
silently delete historical data or modify production rules without authorization.

## Review exit checks

- Every retained dimension has a consumer, bounded category, or justified entity role.
- Estimates include lifecycle churn and all relevant exporter-added dimensions.
- Successive executions preserve intended identity; simultaneous entities remain distinct.
- Aggregations preserve units, reset semantics, and producer ownership.
- Missing, recovery, stale, zero, and historical-window behavior are explicit.
- Developers can correlate aggregate symptoms with detailed records without
  putting per-event identifiers into ordinary time-series labels.
