# Security Policy

## Reporting a vulnerability

If you discover a security issue in any Caffee contract, please report it **privately** and give us a
reasonable window to remediate before any public disclosure.

- **Contact:** [@caffeefun](https://x.com/caffeefun) on X (the only official Caffee account) — DM us to
  open a private disclosure channel.

Please include a clear description, the affected contract/address, and reproduction steps or a PoC. We
aim to acknowledge reports promptly and will credit good-faith researchers.

## Scope

The contracts in this repository, as deployed on **Robinhood Chain (chain id 4663)**:

- `CaffeeLaunchV2` — factory — `0xdeDc13eAA14462644dD99087eB408515D7D2aD56`
- `TokenMetadata` — metadata registry — `0xe82bd8EEBe34df851a6Bc33629BE6Ed23601c81D`
- `CaffeeCurveV2` — bonding curve (one per launched token)
- `LaunchToken` — launched ERC-20 (one per launched token)

## Bug bounty

We pay for good-faith reports of security bugs in the in-scope contracts above. Rewards are in **ETH**, paid
from the treasury after we reproduce and triage a finding; the amount within a band reflects impact,
exploitability and report quality. Critical payouts are **capped at ~10% of the funds actually at risk**.

| Severity | What it covers | Reward (ETH) |
|---|---|---:|
| **Critical** | Direct, unauthorized theft or permanent loss of user funds; unauthorized mint / seize / freeze; pulling graduated LP. | **2 – 10** (≤ ~10% of at-risk funds) |
| **High** | Bounded fund loss, or a griefing / lock that risks user funds beyond the known issue below. | **0.5 – 2** |
| **Medium** | Incorrect accounting or a broken guarantee with no direct theft path. | **0.1 – 0.5** |
| **Low / Info** | Non-exploitable correctness or hardening finding. | credit + up to **0.1** |

The high-value target is a bonding curve **before graduation**, when it custodies real ETH. A clear PoC (a
Foundry test against a Robinhood-Chain fork is ideal) earns the top of the band, and we publicly credit every
valid reporter who wants it.

**Out of scope (not eligible):** the known graduation-griefability issue described below; anything outside the
contract set in [Scope](#scope) (frontend, RPC proxy, Blockscout, wallets, the chain itself, third-party
contracts); self-inflicted loss (approving a scam token, signing a malicious tx, losing keys); ordinary
market / price behavior (slippage, MEV, a coin going to zero); spam / gas-griefing / L2 liveness; social
engineering or phishing; best-practice-only static-analysis output with no exploit; and already-reported
issues (first credible report wins).

**Safe harbor.** Good-faith research under this policy is authorized — we won't pursue legal action for testing
that follows the rules. Report privately first (see [Reporting a vulnerability](#reporting-a-vulnerability))
and give us a reasonable window to fix before public disclosure. **Only ever test against your own funds** — a
fork, a test coin you launch yourself, or your own wallet — never another user's live position or a real curve,
and never degrade the service.

## Status and caveats (please read before integrating)

- **Non-custodial:** Caffee never takes custody of user funds. Trading is peer-to-contract on each
  token's own bonding curve; graduation moves liquidity into a canonical Uniswap-V2 pair with the **LP
  burned** (liquidity is locked, not withdrawable by the team). The only protocol fee is the 1% trading
  fee routed to the treasury.
- **Verify before you trust:** all four contracts are source-verified (full match) on
  [Blockscout](https://robinhoodchain.blockscout.com); the source here is byte-for-byte the verified
  input. Reproduce the deployed bytecode yourself using the notes in [`README.md`](README.md). The
  bonding curve has no owner, withdraw, pause or mint, so its core protections are immutable in code —
  not dependent on trust in the team. Human-readable security model: <https://caffee.fun/trust>.
- **Audit status:** the contracts have completed internal review; an independent third-party audit is
  **planned but has not yet begun**. They are therefore **unaudited** — do not treat launched tokens as
  vetted or endorsed.
- **Known issue — graduation griefability:** anyone can pre-seed a token's Uniswap pair with dust so the
  pristine-pair check defers migration. The curve stays live and holders can always sell back, but the
  DEX migration can be delayed. Treat `graduated()` / the `Graduated` event as the authoritative
  migration signal.
