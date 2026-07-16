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

## Status and caveats (please read before integrating)

- **Non-custodial:** Caffee never takes custody of user funds. Trading is peer-to-contract on each
  token's own bonding curve; graduation moves liquidity into a canonical Uniswap-V2 pair with the **LP
  burned** (liquidity is locked, not withdrawable by the team). The only protocol fee is the 1% trading
  fee routed to the treasury.
- **Audit status:** the contracts are **unaudited** — they have undergone internal review only, and a
  **formal third-party audit is planned but has not yet begun**. Do not treat launched tokens as vetted or endorsed.
- **Known issue — graduation griefability:** anyone can pre-seed a token's Uniswap pair with dust so the
  pristine-pair check defers migration. The curve stays live and holders can always sell back, but the
  DEX migration can be delayed. Treat `graduated()` / the `Graduated` event as the authoritative
  migration signal.
- **Verify before you trust:** all four contracts are source-verified (full match) on
  [Blockscout](https://robinhoodchain.blockscout.com); the source here is byte-for-byte the verified
  input. Reproduce the deployed bytecode yourself using the notes in [`README.md`](README.md).
