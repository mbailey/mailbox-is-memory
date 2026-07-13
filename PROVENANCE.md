# Provenance

> A live URL is a mutable memory; a commit hash is a frozen fact.

Every external source cited in [paper.md](paper.md), pinned to the moment
it was verified. Unless noted, all data was measured **2026-07-13 (AEST)**
against raw sources: the GitHub API, raw file contents at a pinned commit,
the dev.to API, and the Internet Archive. Model-written page summaries
were not accepted as evidence for any quotation — a lesson the paper
itself reports (§5, §7).

## Repositories — pinned commits and vitals

Citation form: `github.com/<repo>/tree/<sha>`, accessed 2026-07-13.

| project | pinned HEAD | ★ | created | last push | license |
|---|---|---|---|---|---|
| [3DRaven/threlium](https://github.com/3DRaven/threlium/tree/a047ff825077) | `a047ff825077` | 1 | 2026-05-28 | 2026-06-19 | AGPL-3.0 |
| [Dicklesworthstone/mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail/tree/35e774fa9ae6) | `35e774fa9ae6` | 2,022 | 2025-10-23 | 2026-06-27 | (none) |
| [Dicklesworthstone/cass_memory_system](https://github.com/Dicklesworthstone/cass_memory_system/tree/7fece3170015) | `7fece3170015` | 395 | 2025-12-07 | 2026-07-10 | (none) |
| [alookai/alook](https://github.com/alookai/alook/tree/a227bcf7c67b) | `a227bcf7c67b` | 898–900\* | 2026-04-03 | 2026-07-13 | Apache-2.0 |
| [mxaiorg/kikubot](https://github.com/mxaiorg/kikubot/tree/693c30d11beb) | `693c30d11beb` | 7 | 2026-04-29 | 2026-07-01 | MIT |
| [joryeugene/notmuch-ai](https://github.com/joryeugene/notmuch-ai/tree/84a874321412) | `84a874321412` | 1 | 2026-03-04 | 2026-03-15 | MIT |
| [jstxn/agentdir](https://github.com/jstxn/agentdir/tree/b3ef55f6c03c) | `b3ef55f6c03c` | 17 | 2026-05-08 | 2026-07-06 | MIT |
| [hj2314/ai-context-protocol](https://github.com/hj2314/ai-context-protocol/tree/c76f479edf0f) | `c76f479edf0f` | 0 | 2026-06-11 | 2026-06-11 | MIT |
| [gusitllc/dual-plane-inbound-email-delivery](https://github.com/gusitllc/dual-plane-inbound-email-delivery/tree/ba9653d94581) | `ba9653d94581` | 0 | 2026-07-04 | 2026-07-04 | AGPL-3.0 |

\* Star counts on actively-pushed repos moved during the day of
measurement: alook read 898 (19:40), 899 (20:00, the paper's "as of 13
July 2026"), 900 (21:31); mcp_agent_mail read 2,022 → 2,023 over the same
window. The paper pins the values as of its own claims audit.

**What the vitals say, plainly:** the mid-2026 convergence §5 concedes is
real, independent — and thin. The closest existing system (threlium) is a
one-star, six-week-old, single-developer project whose memory
documentation is in Russian; three of the nine cited repos have zero or
one star. Only mcp_agent_mail and alook are genuinely adopted, and both
pair an email-shaped coordination layer with a separate memory store —
the split the paper collapses.

## Verified quotations — exact locations

Every string the paper places in quotation marks was matched
byte-for-byte in raw source (or is explicitly declared a translation).

| quotation (as cited in the paper) | source of truth |
|---|---|
| "each event is an RFC 5322 message; each stage is `stages/<stage>/Maildir/`" | [threlium README.md L10 @ `a047ff8`](https://github.com/3DRaven/threlium/blob/a047ff825077/README.md#L10) — English, verbatim |
| threlium `thread_memory` / `global_memory` as FSM stages emitting durable messages | [docs/MEMORY_TABLE.md @ `a047ff8`](https://github.com/3DRaven/threlium/blob/a047ff825077/docs/MEMORY_TABLE.md) — **in Russian**; the paper's characterisation is our translation, declared as such in §5 |
| "Hybrid is fine. Use the inbox for durable, addressable, audit-able memory. Use a vector store for similarity search over summaries." | [Lumbox, "Email as Memory for AI Agents" (D. Kumar, 2026-05-22)](https://lumbox.co/blog/email-as-memory-ai-agents-lumbox) · [archived 2026-07-13](https://web.archive.org/web/20260713095038/https://lumbox.co/blog/email-as-memory-ai-agents-lumbox/) |
| "that context layer **is** email" (alook, marketing) | alook homepage / marketing copy (asset `email-memory.svg`), 2026-07-13 |
| "All the state must be in DB or local" (alook, implementation) | alook `AGENTS.md` @ `a227bcf` ("service must be STATELESS! All the state must be in DB or local, never put important states in memory"); recall implemented against a separate timeline DB (`src/daemon/src/timeline/types.ts`) |
| "the most underrated memory substrate available" | [Muhammad, "From Chatbot to Mailbox: Persistent Agent Memory in Threads" (2026-06-16)](https://dev.to/qasim157/from-chatbot-to-mailbox-persistent-agent-memory-in-threads-4ce0) — verified via the dev.to API · [archived 2026-07-13](https://web.archive.org/web/20260713094052/https://dev.to/qasim157/from-chatbot-to-mailbox-persistent-agent-memory-in-threads-4ce0) |
| "TL;DR: Email is persistent, searchable memory for AI agents." | [Nylas (Hazik), "Email as Memory for AI Agents"](https://cli.nylas.com/guides/email-as-memory-for-ai-agents) — opening body sentence, not the title; published 2026-03-12, modified 2026-05-16 · [archived 2026-05-16](https://web.archive.org/web/20260516103848/https://cli.nylas.com/) |
| "should not be listed as an author" | arXiv submission policies (exact for arXiv; bioRxiv/medRxiv use the plural "authors") — re-verified July 2026, policy-check report in the research archive |
| `Reviewed-by:` / `Acked-by:` / `Tested-by:` trailers; patchwork states (New, Under Review, Accepted, Superseded) | [kernel.org submitting-patches](https://www.kernel.org/doc/html/latest/process/submitting-patches.html) · [patchwork.kernel.org](https://patchwork.kernel.org) |

## Web sources — Internet Archive snapshots

| source | archived |
|---|---|
| lumbox.co (home) | [2026-07-13 09:40 UTC](https://web.archive.org/web/20260713094034/https://lumbox.co/) — no snapshot existed before 2026-07-13; we created the first |
| lumbox.co memory post | [2026-07-13 09:50 UTC](https://web.archive.org/web/20260713095038/https://lumbox.co/blog/email-as-memory-ai-agents-lumbox/) |
| Muhammad essay (dev.to) | [2026-07-13 09:40 UTC](https://web.archive.org/web/20260713094052/https://dev.to/qasim157/from-chatbot-to-mailbox-persistent-agent-memory-in-threads-4ce0) — first snapshot; ours |
| Nylas guide | [2026-05-16](https://web.archive.org/web/20260516103848/https://cli.nylas.com/) (pre-existing) |
| agentmail.to | [2026-07-09](https://web.archive.org/web/20260709200940/https://agentmail.to/) (pre-existing) |
| codeberg.org/ctietze/agent-mail | [2026-07-13 09:41 UTC](https://web.archive.org/web/20260713094112/https://codeberg.org/ctietze/agent-mail) — first snapshot; ours |

## Papers

arXiv identifiers are immutable by design:
[2304.03442](https://arxiv.org/abs/2304.03442) (Generative Agents) ·
[2310.08560](https://arxiv.org/abs/2310.08560) (MemGPT) ·
[2603.17244](https://arxiv.org/abs/2603.17244) (Kumiho) ·
[2606.12329](https://arxiv.org/abs/2606.12329) (PROJECTMEM) ·
[2605.21997](https://arxiv.org/abs/2605.21997) (The Log is the Agent).

DOIs: [10.1145/45941.45943](https://doi.org/10.1145/45941.45943)
(The Coordinator, *ACM TOIS*, 1988) ·
[10.1016/j.websem.2004.09.001](https://doi.org/10.1016/j.websem.2004.09.001)
(Semantic email — the *Journal of Web Semantics* version; a WWW 2004
conference paper by the same authors also exists) ·
[10.1145/176789.176797](https://doi.org/10.1145/176789.176797)
(softbots, *CACM*, 1994) ·
[10.1145/238386.238530](https://doi.org/10.1145/238386.238530)
(email overload, CHI 1996) ·
[CVE-2025-32711](https://nvd.nist.gov/vuln/detail/CVE-2025-32711)
(EchoLeak).

## Method and audit trail

Three verification passes were run on 2026-07-13, each over the text as
it existed at the time (a verification pass is only valid for the text
that existed when it ran — the paper reports what happened when we
forgot that):

1. a claims inventory over v0.4 (arXiv trio + CVE verified at source);
2. a source-level citation audit (19:30–19:45 AEST) that produced the
   pinned SHAs above and found the two §5 source-integrity defects the
   paper now discloses;
3. an independent claims re-audit over v0.8.1 (21:31 AEST) — every
   quotation matched in raw source; every number traced or flagged.

The audit reports, and the research trail behind them, are stored as
threaded mail in the substrate the paper describes, with working copies
in the project task archive. The local measurements (token counts,
timing figures, message counts) trace to that archive; they are
observations of a private fleet and are offered as reported, not
independently reproducible.
