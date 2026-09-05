# Loomark DocumentLead Stage 2 measurement gate

Status: **not accepted**. This is measurement evidence only: no optimization,
production behavior change, generated `.mbti` change, or browser work was
performed. Private production seams were extracted without changing behavior;
the harness checks recomposition parity with `extract`.

## Reproduction

Run from `apps/loomark`:

```sh
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
NEW_MOON_MOD=0 moon bench internal/document_lead --target js --release
```

The complete final output is in [`raw-moon-bench-js-release.log`](raw-moon-bench-js-release.log).
Only trailing whitespace was removed for repository whitespace checks; timing
values and diagnostic lines are unchanged.
The harness was formatted before this run. Its SHA-256 is
`2f5807324a4b043732ad8282f2959fea294d18aa4e551b953763413891a3df34`.

## Environment

| item | value |
|---|---|
| Canopy checkout | `04ae1d5da5d5b2f5f3977f5c996cb2fb1e37c168` |
| `deps/loom` submodule | `a74f56a41cedd272a5382b511a702e8e3d69b507` |
| `deps/rabbita` submodule | `6472dd339bc1cf93b04fcd3bae1fa8f9e775e9ed` |
| Moon | `0.1.20260819 (fc2a4ee)` |
| Moon compiler | `v0.10.9+6e6c44045` |
| Node.js | `v24.14.1` |
| npm | `11.11.0` |

| item | value |
|---|---|
| target | JS release |
| samples | 10 per benchmark |
| source reference | `04ae1d5d:apps/loomark/internal/document_lead/lead_wbtest.mbt` |
| reference SHA-256 | `56c47af786a5d32470009bae557ee5b39812bbe75fba3c14100fa7c45e86e4a7` |

The large-fixture recipes were compared directly with that reference using
`git show`; this records provenance and does not presume baseline timing parity.

## Fixtures and outputs

The two large recipes are shared by the original whole-extract tests and every
large decomposition case. Exact UTF-8 identities:

| fixture | bytes | Unicode chars | SHA-256 |
|---|---:|---:|---|
| mixed (20,000 alternating records) | 1,268,890 | 1,268,890 | `a946a9f61ab6cb775c699c4966913ccf49f4308b2c2d2ff855701ce7d84ad981` |
| distinct (`payload`.repeat(22,000)) | 1,056,000 | 1,056,000 | `a42e3581b66bc486bd4b3ce0b833513b6377c801fb18989f0cc7ef09ef52338d` |

With limits primary=80 and description=160, mixed outputs are 57/160 chars
(primary/description), flags false/true; distinct outputs are 80/0 chars,
flags true/false. The harness asserts these identities and recomposition parity
with `extract` for every small and large corpus member.

## Final large-fixture results

Each cell is an independent isolated timing, not additive and not a causal
attribution. CST is only the cheap `SyntaxNode::from_cst` wrapper conversion;
it is not deep conversion. `±` is standard deviation.

| phase | mixed | distinct |
|---|---:|---:|
| parse | 441.90 ms ± 27.01 ms | 58.29 ms ± 1.60 ms |
| CST wrapper | 18.20 ns ± 3.77 ns | 18.08 ns ± 3.54 ns |
| IR | 243.87 ms ± 22.66 ms | 144.94 ms ± 17.71 ms |
| primary selection | 130.07 µs ± 3.43 µs | 148.15 ns ± 12.19 ns |
| primary construction | 139.45 µs ± 12.35 µs | 2.91 ms ± 122.14 µs |
| description | 13.23 ms ± 401.99 µs | 42.40 ns ± 5.21 ns |
| bound | 2.95 ms ± 81.90 µs | 19.03 ns ± 3.14 ns |
| result | 20.80 ns ± 3.89 ns | 18.61 ns ± 3.24 ns |
| whole extract | 752.36 ms ± 39.09 ms | 184.10 ms ± 2.93 ms |

The original `lead_wbtest` whole cases measured 725.51 ± 26.80 ms and
174.92 ± 4.82 ms respectively. They remain separately named cases, not a sum
of phases.

## Equality results

Equality is split into independent cases. Two separately extracted outputs are
equal when differences occur beyond the retained maximum primary or description;
the harness asserts limits, retained sizes, truncation flags, and equality. A
separate final-field case asserts inequality when only the final truncation flag
differs. There is no mixed equal/early-unequal average.

| case | result | mean ± standard deviation |
|---|---|---:|
| equal after maximum primary | equal | 100.00 ns ± 17.15 ns |
| equal after maximum description | equal | 56.44 ns ± 6.10 ns |
| unequal final truncation flag | unequal | 13.66 ns ± 2.16 ns |

All timings are warmed `moon bench` measurements with setup outside the timed
span. They do not establish process-cold or browser first-input behavior.
Each parser operation starts a fresh full-source parse, not a cached parser
read. Downstream inputs are precomputed outside the timed span. These isolated
probes prioritize further investigation; they are not an additive attribution
of whole-pipeline cost.

## Remaining acceptance work

- Browser comparison must settle numeric budgets, grapheme-boundary expectations,
  visible omission, and accessible omission. The tested scalar limits are not
  accepted product defaults.
- Probe New with a Visible sidebar using the actual Rabbita runtime: entry
  creation must be immediate without extraction in the first text-input task.
  If propagation cannot guarantee this, defer structured LeadSource acceptance
  to existing quiet and use a generic accessible identity until then.
- Do not connect the extractor to input or advance Stage 3 while these gates are
  open. Hidden demand suppression remains the accepted mitigation; no new timer,
  manual cache, Preview parser, or async completion protocol is introduced.
- Large-source fresh extraction remains expensive. This evidence alone does not
  authorize off-thread or asynchronous redesign. Such a change requires its own
  ADR decision after browser evidence.
