# Evaluation scenarios

`evals.json` contains three design-review prompts and expected outcomes. These
are authoring/evaluation assets, not instructions to load on ordinary reviews.

## Initial qualitative evaluation

Evaluated the three domain-neutral prompts with the skill and independently
without it. Reviewed responses for the following acceptance criteria:

| Scenario | Acceptance criteria | With-skill result |
| --- | --- | --- |
| Daily snapshots | Detect execution/resource churn; distinguish batch cap from retained series; qualify counts; address sparse recovery and latest-state/freshness queries | Met |
| Concurrent workers | Reject identity collapse; preserve independent writers or define real aggregation; account for resets, utilization weighting, and overlap | Met |
| Readable checks | Honor scoped unique names; retain workspace separation; preserve internal ID selection; cover rename/migration, latest state, and identity tests | Met |

The generic baseline also identified the central defects. The skill-assisted
responses made label contracts, assumptions, authoritative writers, lifecycle
tradeoffs, and verification more explicit. This small qualitative comparison
does not establish a general performance improvement or test auto-discovery.

One actionable gap was found: explicitly require an expected-entity inventory
for partial disappearance, since queries over existing series cannot detect
entities with no remaining samples. That guidance was added to the skill and
reference after review. The resulting text was structurally validated; that
small refinement has not had a separate agent evaluation.

Earlier domain-specific evaluation attempts had blocked skill-file reads and
are excluded from these results. Raw agent responses are not runtime assets.

For future changes, rerun these scenarios with fresh contexts and inspect the
actual answers against the criteria above; add representative cases for any new
backend or instrumentation architecture. Keep cases independent of a specific
application domain.
