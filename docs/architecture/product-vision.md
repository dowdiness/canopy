# Product Vision: Write, Structure, Surface

The full product vision for Canopy — beyond the code editor, toward a
personal knowledge environment where writing is the only action, structure
emerges automatically, and the right information surfaces when needed.

## The Core Loop

```
Write → auto-structure → right info surfaces → better writing → ...
```

The user never organizes. They write. The system maintains meaning
incrementally. When the user needs information, it's already there.

## Input: The "Post" Action

The reason posting on Twitter feels lightweight is that it requires no
structure — no title, no categories, no format. You write and send.

To preserve this simplicity while achieving composability, non-text
inputs must be as effortless as text. Writing text, pasting a URL,
dropping an image, inserting code, attaching a file — all are the same
single action: **posting**. There is one input field at all times. The
system determines content type automatically.

There are no concepts like "new document" or "new task." There is only
**post**.

## Storage: Automatic Structuring

Three layers, each building on the last.

### Layer 1: Automatic Linking

The system detects relationships between posts — semantic similarity,
shared references, common keywords — and connects them without explicit
links. Users do not "create" links; they **discover** them.

### Layer 2: Automatic Clustering

As posts accumulate, similar ones form groups. Clusters like
"MoonBit-related," "reading notes," or "shopping" emerge organically.
Users may name them, but clusters function without labels. These are
not static folders but dynamic, evolving **islands**.

### Layer 3: Pattern Detection

The system identifies meta-level patterns: "posts of this type appear
every Monday," "no updates on this project for three weeks," "these
two topics frequently appear together."

## Output: Returning the Right Information

Three models, depending on when and how information returns.

### Model A: Return While Writing

When the user starts writing, relevant past posts surface in real time.
"I've considered this before" is automatically brought up. Beyond
passive recall: "this is where you left off last time."

### Model B: Return When Asked

Users write questions into the same input field: "What was the title of
that book?" or "What was the conclusion of last month's project?" The
system constructs answers from past posts. A personal search engine
based on meaning, not keywords.

### Model C: Return Proactively

The system initiates: "You marked this 'to be reviewed' three days ago
but no conclusion reached," or "These two notes might be related."
Unlike social media notifications, these continue and support the
user's own thinking.

## Key Design Difference: Writing to Yourself

Twitter is for writing to others. This system is for **writing to
yourself**.

The timeline need not be chronological. In personal notes, the most
recent item is not always the most important — the most **relevant**
item at the current moment deserves priority. Default view: ordered by
relevance to present context. Chronological order is one possible
filter.

Instead of likes or retweets, there is **resurfacing**. When a past
post is revisited, its importance increases, and related posts rise
with it. Revisit frequency becomes a signal that feeds automatic
structuring.

## Technical Foundations

Each layer of this system maps to Canopy's existing infrastructure.

### Incremental Computation (incr)

Recomputing all clusters and links on every new post is prohibitive.
Updates must be incremental — only recalculating affected relationships
when new data arrives. This is fundamentally an incremental computation
problem, directly served by the reactive signal graph in `loom/incr`.

### CRDT Synchronization (event-graph-walker)

The "stream of posts + automatic linking" model aligns with CRDT
architecture. The event graph provides multi-device synchronization
with no central server. Write on your phone, links update on your
laptop.

### Semantic Model (egglog)

Automatic linking, clustering, and retrieval are **relational queries
over meaning**. Egglog's Datalog engine can express:
- `SimilarTo(post_a, post_b)` — semantic similarity
- `ReferencesUrl(post, url)` — shared references
- `InCluster(post, cluster)` — dynamic grouping
- `StaleReview(post, days)` — pattern detection triggers

### Projectional Editing

Multiple views of the same post stream — timeline, clusters, relevance
view, search results — are projections. The ViewNode → ViewPatch →
Adapter pipeline renders whichever view fits the user's current need.

### The Projectional Bridge

This product IS the projectional bridge at full scale. Not just for
code, but for all structured thought:

```
Raw post (syntax)        →  text in the input field
Linked post (semantics)  →  connections, clusters, types discovered
Surfaced post (intent)   →  right info at the right time
Understood (mental model) →  the system fits how you think
```

## The Cold Pitch

> **Canopy**
>
> Write. It structures itself.
>
> One input. No folders, no categories, no organizing. Just write —
> text, code, links, images. The system parses, links, clusters, and
> surfaces what you need, when you need it.
>
> Think of it as a second brain that actually thinks with you. It
> remembers what you wrote, finds connections you missed, and brings
> back the right context while you're writing — not after you search
> for it.
>
> Works across devices. No server. Your thoughts sync peer-to-peer.

## From Here to There

The code editor (lambda calculus, JSON) is the proving ground. Every
piece of the product vision is validated first in the editor context:

| Product feature | Editor equivalent | Status |
|---|---|---|
| Unified input | Text CRDT input | Done |
| Auto-structuring | Incremental parsing + projection | Done |
| Semantic linking | Name resolution, type inference | In progress |
| Return while writing | Live inline evaluation | Next |
| Return when asked | Egglog semantic queries | Planned |
| Return proactively | Reactive triggers on semantic changes | Future |
| Multi-device sync | CRDT peer-to-peer | Done |
| Relevance ordering | Semantic-model-driven view selection | Future |

Each row is a step from editor to product. The editor isn't a
detour — it's the vertical slice that proves every layer works.
