# Product vision: write, negotiate structure, surface context

The full product vision for Canopy — beyond the code editor, toward a
personal thinking workbench where writing is the primary action, provisional
structure emerges as revisable hypotheses, and relevant context is offered
with reasons and under the person's control.

See [Human-centered product principles](human-centered-product-principles.md)
for the behavior invariants this vision is designed around. The
[Personal Knowledge Environment direction](personal-knowledge-environment-direction.md)
records the current product priority: use histories already produced in
everyday tools, beginning with agent histories, so past activity can
participate in present thinking.

## The core loop

```
Write → provisional structure → relevant context with reasons → better thinking → ...
```

The person is not required to organize before writing. They may organize
explicitly whenever that helps. Structure also emerges as provisional,
navigable hypotheses that the person can inspect, correct, pin, suppress, or
replace. When context is needed, the system offers relevant context with reasons
— one candidate view the person can accept or decline.

## Input: the 'post' action

The reason posting on Twitter feels lightweight is that it requires no
structure — no title, no categories, no format. You write and send.

To preserve this simplicity while achieving composability, non-text
inputs must be as effortless as text. Writing text, pasting a URL,
dropping an image, inserting code, attaching a file — all are the same
single action: **posting**.

The default capture surface is one input field. The system proposes a content
type and the person can correct it.

Named documents, tasks, and collections may be created or emerge later, but
none is required before capture. The lightweight default action is **post**.

## Storage: provisional structuring

Three layers, each building on the last.

### Layer 1: proposed linking

The system detects relationships between posts — semantic similarity,
shared references, common keywords — and proposes links. The person
can accept, name, correct, or suppress each one. Explicit
user-authored links remain first-class and are never replaced by
inferred ones.

### Layer 2: proposed clustering

As posts accumulate, similar ones form groups. Clusters like
"MoonBit-related," "reading notes," or "shopping" emerge as proposals.
The person can name them, pin them, merge them, or dismiss them.
Clusters function without labels but remain negotiable. These are not
static folders but dynamic, revisable **islands**.

### Layer 3: pattern detection

The system identifies meta-level patterns: "posts of this type appear
every Monday," "no updates on this project for three weeks," "these
two topics frequently appear together." Patterns are surfaced with
reasons and remain one view among many — they do not replace
chronological or user-defined ordering.

## Output: offering relevant context

Three models, depending on when and how context returns. All are
opt-in and quiet by default.

### Model A: context while writing

Only after the person opts in may relevant past posts surface with
reasons. "I've considered this before" is offered, not imposed. Beyond
passive recall: "this is where you left off last time." The person
controls whether and when this appears.

### Model B: context when asked

People write questions into the same input field: "What was the title of
that book?" or "What was the conclusion of last month's project?" The
system constructs answers from past posts — a search interface that
ranks by meaning rather than keywords, with sources shown.

### Model C: context offered proactively

The system can offer: "You marked this 'to be reviewed' three days ago
but no conclusion reached," or "These two notes might be related."
Unlike engagement-optimized notifications, these are opt-in, quiet by
default, and support the person's own thinking rather than competing
for attention. Revisit frequency may influence ordering, while the
person remains the authority on importance.

## Key design difference: writing to yourself

Twitter is for writing to others. This system is for **writing to
yourself**.

The timeline need not be chronological. In personal notes, the most
recent item is not always the most useful — a relevant item at the
current moment may deserve priority. But relevance is one inspectable
projection among chronological, pinned, and user-defined views. The
person chooses.

Instead of likes or retweets, there is **resurfacing**. When a past
post is revisited, its visibility in relevant-context views can
increase. The person can inspect, reset, or suppress that signal.

## The cold pitch

> **Canopy**
>
> Write. It structures itself.
>
> Structure emerges visibly and reversibly; you remain the author.
>
> One input. No mandatory folders, no required categories. Just write —
> text, code, links, images. The system proposes links, clusters, and
> relevant context with reasons — all inspectable, correctable, and
> under your control.
>
> Think of it as a thinking workbench that remembers context without
> speaking for you. It shows connections you can accept or dismiss,
> offers relevant context while you're writing, and keeps your data
> on your devices.
>
> Works across devices with no server — your thoughts sync peer-to-peer.

## From here to there

The code editor (lambda calculus, JSON) remains one proving ground for the
product vision, but it is no longer a mandatory sequence for every product
feature. Near-term Personal Knowledge Environment work validates continuous
movement from activity shape to exact source and back into present thinking,
then reuses editor infrastructure only when it improves that experience.

| Product capability | Existing proving-ground evidence |
|---|---|
| Unified input | Text CRDT input and the local-first Posts prototype |
| Provisional structuring | Incremental parsing and projection |
| Semantic linking | Name resolution, type inference, and explained lexical retrieval |
| Context while writing | Live inline evaluation and related-post retrieval |
| Context when asked | Source-post retrieval |
| Multi-device sync | CRDT peer-to-peer collaboration |
| Multiple representations | Text, structure, timeline, and related-context views |

These mappings are reusable evidence, not a product-development checklist. The
[Personal Knowledge Environment direction](personal-knowledge-environment-direction.md)
owns the current priority and its review gates.

## Appendix: Technical foundations

How each product layer maps to Canopy's existing infrastructure.

**Incremental computation (incr)** — Recomputing all clusters and links
on every new post is prohibitive. Updates must be incremental — only
recalculating affected relationships when new data arrives. Directly
served by the reactive signal graph in `loom/incr`.

**CRDT synchronization (event-graph-walker)** — The "stream of posts +
proposed linking" model aligns with CRDT architecture. The event graph
provides multi-device sync with no central server. Write on your phone,
links update on your laptop.

**Semantic model (egglog)** — Proposed linking, clustering, and
retrieval are relational queries over meaning. Egglog's Datalog engine
can express: `SimilarTo(post_a, post_b)`, `ReferencesUrl(post, url)`,
`InCluster(post, cluster)`, `StaleReview(post, days)`.

**Projectional editing** — Multiple views of the same post stream
(timeline, clusters, relevance, search) are projections. The ViewNode →
ViewPatch → Adapter pipeline renders whichever view fits the current
need.

**The projectional bridge at full scale** — not just for code, but for
all structured thought:

```
Raw post (syntax)        →  text in the input field
Linked post (semantics)  →  connections, clusters, types proposed
Offered post (intent)    →  relevant context with reasons, under user control
Understood (orientation) →  the person chooses representations;
                             the system does not claim their mental model
```
