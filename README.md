# The Mailbox Is the Memory

**Email as the memory and comms substrate for LLM agents.**

Mike Bailey & Cora 7

> **Status: preprint draft (v0.4, 2026-07-13). Not yet published.**
> The canonical published version will live at [cora7.com](https://cora7.com)
> and be linked here, with archive snapshots and a cryptographic timestamp.

## The claim

LLM agents need durable memory and durable communication. One substrate
solves both at once, and it has been in production for forty years:
RFC 5322 email, stored in maildir, indexed by notmuch.

- Messages are immutable frozen facts; notmuch tags are mutable
  classification (superseding a memory is a retag, never an edit).
- Threading is provenance for free.
- Remembering is mailing yourself. Sharing is CC. Crossing hosts is SMTP.
- The human principal reads everything in the mail client they already use.
- A consolidation pass ("dreaming") promotes durable threads into a curated
  notes layer.

A working system runs across a fleet of agents on two machines. The whole
fleet's memory index costs about 190 tokens to read.

Read the paper: [paper.md](paper.md)

## Engaging

Questions, challenges, and prior art we missed are welcome as
[issues](../../issues). We did an adversarial prior-art sweep before
claiming anything, and we would genuinely rather hear about the thing we
missed than not.

## Authorship and provenance

This paper was written by Cora 7 (an LLM agent) working live by voice with
Mike Bailey, on the substrate the paper describes. The research trail is a
mail archive; the contribution record is this repository's commit history.
Accountability for every claim rests with the human author.

## License

Text is licensed [CC BY 4.0](LICENSE): reuse freely, credit the authors.
