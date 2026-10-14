---
name: skill-creator
description: Create a new skill from scratch, improve or rewrite an existing one, sharpen a skill's description so it triggers reliably, and test a skill against realistic prompts before trusting it. Make sure to use this skill whenever the user says "turn this into a skill", "write a skill for…", "my skill isn't triggering", "make this reusable", or wants to capture a workflow they just walked through so it works next time — even if they don't use the word "skill".
---

# Skill Creator

A skill for writing skills and iteratively making them better.

The shape of the work:

- Decide what the skill should do and roughly how.
- Write a draft.
- Try it on a few realistic prompts.
- Judge the results — with the user, not for them.
- Rewrite based on what you both saw.
- Repeat until it holds up, then widen the test set.

Your job is to work out **where in that loop the user actually is** and join them
there. "I want a skill for X" means start at the top. An existing draft means
jump straight to testing and iterating. And if they say "skip the evals, just
vibe with me" — do that instead. The loop is a default, not a ritual.

## Talking to the user

Skill authors range from career engineers to people who opened a terminal for
the first time last week. Read the context cues and match them.

As a rough calibration: "evaluation" and "benchmark" are usually fine. "JSON"
and "assertion" need real evidence the user knows those words before you use
them bare. When in doubt, a six-word gloss in parentheses costs nothing.

## Capture intent

If the conversation already contains the workflow — they just did the thing and
now want it captured — mine the history first: which tools got used, in what
order, what corrections the user made along the way, what the input and output
actually looked like. Come to them with gaps to fill, not a blank form.

Then settle four things:

1. What should this let Claude do?
2. **When should it trigger?** Which user phrasings, which contexts.
3. What's the expected output?
4. Are test cases worth it? Objectively checkable outputs (file transforms, data
   extraction, code generation, fixed workflows) benefit. Subjective ones
   (writing voice, visual design) usually don't — judge those by reading them.
   Recommend a default based on which kind it is, and let the user decide.

Ask about edge cases, formats, example files, success criteria and dependencies
*before* writing test prompts. Research in parallel where it helps.

## Write the SKILL.md

```
skill-name/
├── SKILL.md                 (required)
│   ├── YAML frontmatter     name + description required
│   └── markdown body        the instructions
└── optional bundled resources
    ├── scripts/             executable code for deterministic, repetitive work
    ├── references/          docs read into context on demand
    └── assets/              templates, icons, fonts used in the output
```

**Progressive disclosure** — three loading levels, and writing to them is most
of the craft:

1. `name` + `description` — always in context, every session. ~100 words.
2. The SKILL.md body — loaded when the skill triggers. Under ~500 lines.
3. Bundled resources — read or executed only as needed. Unbounded.

Approximate numbers, not limits. But if the body is pushing 500 lines, that's
the signal to add a layer: move detail into `references/` and leave clear
pointers about when to go read each one. Give reference files over ~300 lines a
table of contents. When a skill spans several variants, split by variant
(`references/aws.md`, `gcp.md`, `azure.md`) so only the relevant one gets read.

### The description is the whole triggering mechanism

It must carry both *what the skill does* and *when to use it*. All the "when"
information belongs here — not in the body, which nothing reads until after the
decision to trigger has already been made.

Claude currently **undertriggers** skills: it skips them in exactly the
situations they were written for. So make descriptions a little pushy. Instead
of:

> How to build a fast dashboard for internal data.

write:

> How to build a fast dashboard for internal data. Make sure to use this skill
> whenever the user mentions dashboards, data visualization, internal metrics,
> or wants to display any kind of company data — even if they don't explicitly
> ask for a "dashboard".

Name the phrasings and the near-misses. Add `compatibility` for required tools
or dependencies, though it's rarely needed.

### Writing style

Imperative form. Explain *why* something matters instead of stacking musty
MUSTs — a model that understands the reason generalizes to the case you didn't
think of; one following a bare directive doesn't.

Use theory of mind: write for someone who has the body in context and nothing
else. Keep it general rather than overfitted to your examples. Draft it, then
reread with fresh eyes and cut what isn't pulling its weight.

Pin down output formats with a literal template, and show examples:

```markdown
## Commit message format
**Example 1:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### Don't build surprising skills

A skill must do what its description says it does. No malware, no exploit code,
no content that quietly compromises the user's system or exfiltrates their data.
If asked for a deliberately misleading skill, decline that part and say why.
Roleplay and persona skills are entirely fine.

## Test it

Write 2–3 prompts a real user would actually type — not sanitized restatements
of the spec. Show them to the user: *"Here are the cases I'd like to try — do
these look right, or should I add more?"* Save them to `evals/evals.json` as
prompts only; assertions come later, drafted while the runs are in flight.

```json
{
  "skill_name": "example-skill",
  "evals": [
    { "id": 1, "prompt": "User's task prompt", "expected_output": "What should come back", "files": [] }
  ]
}
```

Then run the comparison. For each test case spawn **two** subagents in the same
turn — one with the skill, one without — so everything finishes together. The
baseline is "no skill at all" for a new skill, or a snapshot of the previous
version (`cp -r` it before editing) when improving an existing one. Keep results
in `<skill-name>-workspace/iteration-N/eval-<id>/{with_skill,without_skill}/`,
creating directories as you go rather than all upfront.

While the runs are going, draft the assertions and explain them to the user.
Good ones are objectively verifiable and named so that someone skimming the
results immediately sees what each checks. Don't force assertions onto things
that need human judgment.

When the runs land, grade each assertion against the outputs, then put the
results in front of the user — the actual outputs to read, and the pass rates
alongside. Where an assertion can be checked by a script, write the script: it's
faster, repeatable across iterations, and doesn't drift the way eyeballing does.

## Improve it

This is the heart of the loop, and the part most likely to go wrong.

**Generalize from the feedback.** You and the user are iterating on three
examples because that's fast and they know those examples cold. But the skill
will run on thousands of prompts neither of you has seen. A fix that satisfies
`eval-2` and nothing else is worse than no fix — it adds tokens and narrows the
skill. When an issue is stubborn, don't escalate to a louder MUST; try a
different metaphor or suggest a different working pattern. It's cheap to try and
occasionally you land on something much better.

**Keep it lean.** Cut what isn't earning its place. Read the *transcripts*, not
just the final outputs: if the skill is sending the model down unproductive
detours, find the instruction causing it and delete that instruction.

Rerun into a fresh `iteration-N/` directory and compare against the last one.
Stop when it holds up — then widen the test set and check it still does.

---

Derived from Anthropic's `skill-creator` skill
(<https://github.com/anthropics/skills/tree/main/skills/skill-creator>),
Apache-2.0, condensed for this environment. The upstream skill additionally
ships Python tooling for benchmark aggregation, an HTML eval viewer, grader and
analyzer subagents, and a description-optimization loop. For heavier work —
formal benchmarking with variance analysis, or automated description tuning —
fetch upstream and use it directly rather than reimplementing it here.
