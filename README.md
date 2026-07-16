# Caffee — smart contracts

**Caffee** ([caffee.fun](https://caffee.fun)) is a pump.fun-style token launchpad and bonding-curve DEX on
**Robinhood Chain** (EVM L2, **chain id 4663 / `0x1237`**, native coin ETH). Anyone can launch a fixed-supply
ERC-20 whose entire supply seeds a virtual-reserve constant-product bonding curve; the token trades on that
curve (buy/sell anytime) until it "graduates" to a canonical Uniswap-V2 WETH pair with the LP burned
(liquidity locked, not rug-able). This repository contains the **complete, unmodified Solidity source** for the
four on-chain contracts that power that flow. Every source file here is the exact input that was used to
**source-verify** the deployed bytecode on Blockscout, so you can read, audit, and reproduce it yourself — there
is no hidden logic and no honeypot.

## Deployed contracts (Robinhood Chain, chain id 4663)

All four are **source-verified on Blockscout with a full match** (exact source + compiler settings ↔ deployed
bytecode). Explorer: <https://robinhoodchain.blockscout.com>.

| Contract | Address | Blockscout |
|---|---|---|
| **CaffeeLaunchV2** — factory (launches tokens + curves) | `0xdeDc13eAA14462644dD99087eB408515D7D2aD56` | [view](https://robinhoodchain.blockscout.com/address/0xdeDc13eAA14462644dD99087eB408515D7D2aD56) |
| **TokenMetadata** — on-chain image/description/socials registry | `0xe82bd8EEBe34df851a6Bc33629BE6Ed23601c81D` | [view](https://robinhoodchain.blockscout.com/address/0xe82bd8EEBe34df851a6Bc33629BE6Ed23601c81D) |
| **CaffeeCurveV2** — a bonding curve (one per token) | `0x065f1f16d52ee85b1ba4a0fed319b4d63bc37e60` | [view](https://robinhoodchain.blockscout.com/address/0x065f1f16d52ee85b1ba4a0fed319b4d63bc37e60) |
| **LaunchToken** — a launched ERC-20 (one per token) | `0x32e5dcffe3098a4f1d01a460a3df8b47eecaffee` | [view](https://robinhoodchain.blockscout.com/address/0x32e5dcffe3098a4f1d01a460a3df8b47eecaffee) |

> **On the curve/token addresses:** the **factory** and **registry** are singletons at the fixed addresses above.
> Each launch, however, deploys a **new** `CaffeeCurveV2` **and** a **new** `LaunchToken` via CREATE2, so there
> are many live instances — they all share the same verified source/bytecode as the two example instances shown
> above (Blockscout auto-matches every sibling by bytecode). Discover the current instances on-chain with
> `curvesLength()` / `curves(i)` / `token()` on the factory. The example curve `0x065f…7e60` and token
> `0x32e5…caffee` (CLAYNO) are the specific instances that were manually verified on Blockscout.

**Verification status: full match on Blockscout (all four).**

## Contract → source map

| Contract | Deployed address | Source path | Solidity contract |
|---|---|---|---|
| CaffeeLaunchV2 | `0xdeDc13eAA14462644dD99087eB408515D7D2aD56` | [`contracts/src/CaffeeTradingV2.sol`](contracts/src/CaffeeTradingV2.sol) | `CaffeeLaunchV2` |
| CaffeeCurveV2 | `0x065f1f16d52ee85b1ba4a0fed319b4d63bc37e60` (example instance) | [`contracts/src/CaffeeTradingV2.sol`](contracts/src/CaffeeTradingV2.sol) | `CaffeeCurveV2` |
| LaunchToken | `0x32e5dcffe3098a4f1d01a460a3df8b47eecaffee` (example instance) | [`contracts/src/CaffeeTrading.sol`](contracts/src/CaffeeTrading.sol) | `LaunchToken` |
| TokenMetadata | `0xe82bd8EEBe34df851a6Bc33629BE6Ed23601c81D` | [`contracts/src/TokenMetadata.sol`](contracts/src/TokenMetadata.sol) | `TokenMetadata` |

**Repository layout**

```
contracts/
  src/
    CaffeeTradingV2.sol      # CaffeeLaunchV2 (live factory) + CaffeeCurveV2; imports LaunchToken from CaffeeTrading.sol
    CaffeeTrading.sol        # LaunchToken (the deployed ERC-20) + the deprecated V1 CaffeeCurve/CaffeeLaunch (see note)
    TokenMetadata.sol        # TokenMetadata registry
  standard-json-input/       # the exact solc Standard-JSON-Input used to verify on Blockscout (for reproducible builds)
    CaffeeLaunchV2.standard-input.json
    TokenMetadata.standard-input.json
README.md  LICENSE  SECURITY.md  PUSH.md
```

> **Note on `CaffeeTrading.sol`:** the live V2 factory (`CaffeeLaunchV2`) and curve (`CaffeeCurveV2`) live in
> `CaffeeTradingV2.sol`. `CaffeeTrading.sol` is required because it defines **`LaunchToken`** (the deployed
> ERC-20, reused unchanged by V2) and the shared interfaces (`IERC20`, `IWETH`, `IUniV2Factory`). It **also**
> still contains the earlier **V1** `CaffeeCurve` / `CaffeeLaunch` contracts, which are **deprecated and not the
> live factory** — the V2 factory (`0xdeDc…aD56`) is the one in use. The V1 contracts are included verbatim only
> because they are part of the file that was compiled and verified.

## Design in one line

`CaffeeLaunchV2` (factory) deploys a `LaunchToken` (fixed 1,000,000,000 × 1e18 supply) and a `CaffeeCurveV2`
(virtual-reserve constant-product curve, 1% fee) per launch. Trades happen on the curve until it sells out and
**graduates** to a canonical Uniswap-V2 WETH pair with LP burned. `TokenMetadata` is an additive, fully on-chain
registry (image/description/socials as a JSON blob), writable only by a token's original creator. There is no
backend, no IPFS, no off-chain storage. For the full read/integration reference see
[`ops/INTEGRATION.md`](../INTEGRATION.md) in the app repo.

## Build & verify

**Compiler:** solc **`v0.8.26+commit.8a97fa7a`** (i.e. `0.8.26`).

**Exact settings** (identical for all four contracts; taken from the verified Standard-JSON metadata):

| Setting | Value |
|---|---|
| Optimizer | **enabled**, **200** runs |
| EVM version | **paris** |
| Metadata bytecode hash | **ipfs** (`appendCBOR: true`) |
| Remappings | none |
| Language | Solidity |

**Reproduce the verified bytecode** — the canonical inputs are the two Standard-JSON files under
`contracts/standard-json-input/` (they embed the sources + the exact settings above). With `solc` 0.8.26:

```bash
# factory + curve + token (CaffeeLaunchV2.sol / CaffeeTrading.sol are both inside the JSON)
solc --standard-json contracts/standard-json-input/CaffeeLaunchV2.standard-input.json > out-launch.json

# metadata registry
solc --standard-json contracts/standard-json-input/TokenMetadata.standard-input.json > out-metadata.json
```

The resulting `evm.deployedBytecode` for each contract matches the on-chain code at the addresses above.
Alternatively, re-run verification straight against the explorer (no key, no transaction) with
`forge verify-contract … --verifier blockscout --verifier-url https://robinhoodchain.blockscout.com/api/
--compiler-version 0.8.26 --num-of-optimizations 200 --evm-version paris`.

**Factory constructor arguments** (`CaffeeLaunchV2`, ABI-encoded, confirmed against the deploy tx
`0xe5e037dbefcfd2cac0bd8124e50e9e22f44f403c9ab783c2a1da19c992c88443`):
`constructor(address treasury, uint16 feeBps, address weth, address dexFactory)` =
`treasury 0xd06bf16e78d15a511d7a8555bfb066a101df2246`, `feeBps 100` (1%),
`weth 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`, `dexFactory 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f`.

### Related on-chain addresses (external — not part of this repo)

These are pre-existing, canonical Robinhood Chain infrastructure that the contracts reference; they are **not**
Caffee contracts and their source is not in this repo:

```
Uniswap-V2 Factory (graduation target)  0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f
WETH                                    0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
CREATE2 deployer proxy                  0x4e59b44847b379578588920ca78fbf26c0b4956c
Treasury (fee recipient)                0xd06bf16e78d15a511d7a8555bfb066a101df2246
```

## Security

Contracts are **unaudited** (internal review only; a formal audit is in progress). See
[`SECURITY.md`](SECURITY.md) for responsible disclosure and known caveats.

## License

[MIT](LICENSE) — matching the `// SPDX-License-Identifier: MIT` header declared in every source file.
