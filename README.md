# Aeon TaskMarket Hooks

Two opt-in Aeon skills for the TaskMarket V1 hook lifecycle:

| Skill | What it does | Default |
|---|---|---|
| `taskmarket-hook-idea` | Uses the xAI Responses API to produce exactly five buildable briefs, deduplicated against local attempts, the official submitted-hook registry, open listings, and observed public hooks. | Disabled; manual run |
| `deploy-taskmarket-hook` | Generates a direct immutable hook, performs automated source review, behavioral and gas tests, a local Diamond lifecycle, a live-chain fork rehearsal, and a deterministic deployment simulation. A leading `arm:` can authorize the final hook deployment only. | Disabled; dry-run |

Install from an Aeon checkout:

```bash
bin/install-skill-pack Calcutatator/aeon-taskmarket-hooks
```

Then enable only the skill you intend to use in `aeon.yml`. Both skills are installed disabled and run on demand.

## Inputs

`taskmarket-hook-idea` accepts an optional theme, such as `worker reputation`. Add `dry-run` to preserve its artifacts without sending a notification. It requires `XAI_API_KEY`.

`deploy-taskmarket-hook` accepts:

```text
[arm:] [template:tag|allowlist|receipt|freeform] [chain:base-sepolia|base] <brief>
```

Without `arm:`, it never broadcasts. Base Sepolia is the default. Base mainnet additionally requires explicit `chain:base` and `HOOK_MAINNET_OK=1`. Optional secrets are `HOOK_DEPLOYER_PRIVATE_KEY` for a dedicated gas-only deployer, `ALCHEMY_API_KEY` for RPC, and `ETHERSCAN_API_KEY` for best-effort source verification.

The deploy skill provisions Foundry v1.7.1 from checksum-pinned official binaries and uses the exact dependency revisions from `create-taskmarket-hook@0.1.0`. Its runner independently checks canonical Diamond identity, immutable fixtures, the official `BaseTMPHook`, and the complete dependency-tree digest before any key-bearing path.

## Deliberate limits

The generic deployer is for direct policy and observation hooks. It refuses token transfers, external escrow, callbacks into the TaskMarket Diamond, arbitrary low-level calls, proxies, and child deployments. It does not attach a hook to a task, fund a task, change protocol defaults, or submit registry metadata.

The [Affiliate Sidecar Escrow hook](https://github.com/Calcutatator/taskmarket-hooklist/tree/main/affiliate-sidecar-hook) demonstrates a more complex, separately reviewed asset-moving design. Its Base Sepolia listing is already prepared in [TaskMarket PR #647](https://github.com/daydreamsai/taskmarket/pull/647), with the corresponding [listing request #646](https://github.com/daydreamsai/taskmarket/issues/646). That implementation is a case study, not a template the generic deploy skill will silently approximate.

Automated review and passing tests are evidence, not an independent security audit or TaskMarket endorsement. Registry publication remains a separate maintainer-reviewed action.

## License

MIT
