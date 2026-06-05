# Fully On-Chain SeaDrop NFT Collection

A Foundry project for a fully on-chain ERC-721 NFT collection, with metadata
(including artwork) stored permanently on-chain via SSTORE2 and marketplace minting
provided by OpenSea's SeaDrop. It works on any EVM network where SeaDrop is deployed.

It's deliberately **simple and easy**: a single contract, a handful of scripts, and your
JSON files on disk. Deploy, point the contract at your metadata, and you have a permanent,
fully on-chain collection — no IPFS, no servers, no off-chain dependencies.

> **A note on artwork size.** Each token's **entire metadata JSON** — name, description,
> attributes/traits, *and* the base64-encoded image embedded in it — is stored in a single
> SSTORE2 blob, and SSTORE2 inherits the EVM's **~24 KB per-contract bytecode limit**. The
> 24 KB cap applies to the whole JSON file, **not** just the image, so the image must come
> in comfortably **under** 24 KB to leave room for the JSON wrapper and trait data. Keep in
> mind base64 encoding inflates the raw image by ~33%, so a 24 KB budget means an even
> smaller source image. That makes this approach **perfect for on-chain pixel art** — small,
> tightly-encoded sprites and palette-based PNGs — and **equally well suited to SVGs**, whose
> compact, text-based vector markup usually fits comfortably under 24 KB (and can be embedded
> directly without base64). It is **not optimal for byte-heavy
> artwork** (high-resolution photos, complex illustrations, large PNG/JPEG files), which
> won't fit alongside the JSON in a single blob. If your art is byte-heavy, shrink it
> (reduce resolution/palette, optimize the PNG, or use SVG) until the **complete JSON** fits
> within the ~24 KB limit.
>
> **Too big to fit? You still keep the JSON on-chain.** If the image can't be squeezed under
> the limit, point the `image` field at an **IPFS URI or external URL** instead of embedding
> it. The full metadata JSON — name, description, traits, and the image reference — still
> lives on Ethereum via SSTORE2, stays **updateable** (until you finalize), and has **no
> hosting dependency for your JSON**. You only delegate the image bytes; everything that
> describes the token remains on-chain. This is the practical middle ground for byte-heavy
> collections that still want their metadata permanent and self-hosted on Ethereum.

## Overview

This project deploys an `ERC721SeaDrop` token whose per-token metadata is written
directly to the blockchain. Each token's JSON — name, description, attributes, and a
base64-encoded image embedded in the `image` field — is stored as contract bytecode
using SSTORE2 and referenced by a pointer address in the main contract. Nothing is
hosted off-chain (no IPFS, no centralized server).

### Key features

- **Simple & easy** — one contract plus a few scripts; no IPFS, servers, or off-chain pieces
- **Fully on-chain** — all metadata and artwork live permanently on-chain
- **Best for pixel art & SVGs** — SSTORE2's ~24 KB per-blob limit fits compact pixel art and
  text-based SVG vector art ideally, but is not optimal for byte-heavy artwork (high-res
  photos, large illustrations)
- **Pre-reveal → reveal** — one shared pre-reveal pointer covers every token; each token
  reveals individually the moment you set its own pointer (lazy, per-token reveal)
- **Gas-efficient storage** — uses the SSTORE2 pattern (deploy data as bytecode, read by address)
- **SeaDrop integration** — built-in support for OpenSea's SeaDrop minting protocol; as an
  `ERC721SeaDrop` extension it's **OpenSea Studio–compatible** and mints on OpenSea, with
  allowlists, drop stages, pricing, and timing all editable in Studio after deploy
- **Immutable option** — metadata can be permanently locked once finalized
- **Adjustable supply** — defaults to `MAX_SUPPLY = 478` (token IDs `1`–`478`); set it to
  whatever size suits your collection (see the cost note below — large supplies get pricey)

### Reveal model

There is one shared pre-reveal pointer (`prerevealMetadata`) plus an optional per-token
pointer (`tokenMetadata[tokenId]`). `tokenURI(tokenId)` resolves as:

```
tokenURI(id):
  if tokenMetadata[id] != 0  → return that token's own JSON   (revealed)
  else                       → return prerevealMetadata        (still hidden)
```

A token is revealed the instant you set its own pointer, so you can reveal the whole
collection at once or gradually, token by token. Setting a token's pointer back to
`address(0)` returns it to the pre-reveal state.

### Storage pattern

```
JSON metadata (with base64 image) → SSTORE2.write → pointer address → stored in contract
```

Each token's metadata is:
1. Read from a local JSON file
2. Written to the chain as bytecode via SSTORE2
3. Referenced by its pointer address in the contract's `tokenMetadata` mapping
4. Returned by `tokenURI()` as the raw JSON string

> Note: `tokenURI()` returns the stored JSON directly (not wrapped in a
> `data:application/json` URI). To embed the image fully on-chain, place a base64 data
> URI (e.g. `data:image/png;base64,...`) in the `image` field. SSTORE2's ~24 KB per-pointer
> limit applies to the **entire JSON file** — image plus name, description, and traits — so
> the base64 image must stay well under 24 KB to leave room for the rest of the JSON.

### Contract components

- **Main contract** (`src/`) — `ERC721SeaDrop` subclass that manages on-chain metadata
- **SSTORE2** (Solmate) — gas-efficient on-chain storage library
- **ERC721SeaDrop** (seadrop lib) — base ERC-721 implementation with SeaDrop minting

### On-chain interface (owner-only)

- `setPrerevealMetadata(pointer)` — set the shared SSTORE2 pointer served by all unrevealed tokens
- `setTokenMetadata(tokenId, pointer)` — reveal one token by setting its own pointer
- `batchSetTokenMetadata(tokenIds[], pointers[])` — reveal up to 3 tokens at once
- `finalizeMetadata()` — permanently lock all metadata, pre-reveal and per-token (irreversible)
- `isRevealed(tokenId)` / `hasMetadata(tokenId)`, `getMetadataCount()`, `getTokensWithMetadata()` — read helpers

Reveal and pre-reveal changes emit ERC-4906 `BatchMetadataUpdate` events (the contract
also reports ERC-4906 support via `supportsInterface`), so marketplaces like OpenSea
refresh the affected tokens automatically: `setTokenMetadata`/`batchSetTokenMetadata`
emit per-token updates, and `setPrerevealMetadata` emits a full-range update covering
every unrevealed token.

## End-to-end walkthrough (0 → 100)

Every command in order, from a fresh machine to a finalized collection. Each step is
explained in detail in the sections further below.

```bash
# 0. Install Foundry (skip if already installed)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 1. Clone the repo and install dependencies
git clone <your-repo-url>
cd <project-dir>
forge install

# 2. Create your .env and fill in the values
cp .env.example .env
$EDITOR .env                 # set PRIVATE_KEY, DEPLOYER, RPC_URL, CHAIN_ID, ETHERSCAN_API_KEY
                             # DEPLOYER must be the address that PRIVATE_KEY controls
source .env                  # load the vars into your shell for the commands below

# 3. Build and test
forge build
forge test -vv

# 4. Deploy the contract
forge script script/DeployOnchainCollection.s.sol:DeployOnchainCollection \
  --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --chain $CHAIN_ID

# 5. Save the deployed address (printed by step 4) into your env + .env
export CONTRACT_ADDRESS=<deployed_contract_address>
echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS" >> .env

# 6. Verify the contract on the block explorer
forge verify-contract --chain-id $CHAIN_ID --rpc-url $RPC_URL \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  $CONTRACT_ADDRESS src/OnchainCollection.sol:OnchainCollection \
  --constructor-args $(cast abi-encode "constructor(string,string,address)" \
    "Onchain Collection" "ONCHAIN" "0x00005EA00Ac477B1030CE78506496e8C2dE24bf5")

# 7. Prepare metadata files (do this on disk, no command):
#      data/prereveal.json          — shared "hidden" art
#      data/nfts/1.json ... data/nfts/478.json — per-token art (named by token ID)

# 8. (Optional) Pre-flight checks — no --broadcast, so nothing is written on-chain.
#    EstimateUploadCost is read-only; TestSingleUpload simulates uploading token 1.
forge script script/EstimateUploadCost.s.sol --rpc-url $RPC_URL
forge script script/TestSingleUpload.s.sol --rpc-url $RPC_URL

# 9. Set the shared pre-reveal metadata (all tokens now show this until revealed)
forge script script/SetPrereveal.s.sol:SetPrereveal \
  --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --chain $CHAIN_ID

# 10. Reveal all tokens, 10 per run, by uploading each token's own metadata
#     (add --legacy if your RPC rejects EIP-1559 transactions)
for start in $(seq 1 10 478); do
  START_TOKEN=$start forge script script/UploadMetadata.s.sol:UploadMetadata \
    --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --chain $CHAIN_ID --slow
done

( run `forge clean` and `forge cache clean` then add `--skip-simulation` to avoid collisions on reset )

# 11. (Optional) Spot-check a token's metadata
cast call $CONTRACT_ADDRESS "tokenURI(uint256)(string)" 1 --rpc-url $RPC_URL

# 12. (Optional, IRREVERSIBLE) Lock all metadata once everything is revealed
cast send $CONTRACT_ADDRESS "finalizeMetadata()" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

> To reveal gradually instead of all at once, skip the loop in step 10 and run individual
> chunks (`START_TOKEN=1`, `START_TOKEN=11`, …) whenever you want. Only run step 12 after
> every token you intend to reveal has been revealed — finalizing cannot be undone.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- An RPC endpoint for your target network
- A funded deployer private key (≥ 0.01 ETH recommended)
- A block-explorer (Etherscan-compatible) API key for contract verification

## Installation

```bash
git clone <your-repo-url>
cd <project-dir>
forge install
cp .env.example .env   # then fill in the values below
```

### Environment variables (`.env`)

See [`.env.example`](.env.example) for the full template. The variables are:

```
PRIVATE_KEY=         # deployer private key (NEVER commit the real value)
DEPLOYER=            # deployer address — MUST be the address PRIVATE_KEY controls
RPC_URL=             # RPC endpoint for your target network
CHAIN_ID=            # chain ID of your target network (deploy-time safety check)
ETHERSCAN_API_KEY=   # block-explorer API key for verification
ETHERSCAN_API_URL=   # optional explicit verifier URL (see verify step below)
CONTRACT_ADDRESS=    # set after deployment (used by the upload script)
```

## Deployment guide

### Step 1 — Run tests

```bash
forge test -vv
```

### Step 2 — Deploy the contract

```bash
forge script script/DeployOnchainCollection.s.sol:DeployOnchainCollection \
  --broadcast \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --chain $CHAIN_ID
```

The deploy script enforces safety checks:
- Confirms the connected chain ID matches `CHAIN_ID`
- Confirms the deployer has sufficient ETH
- Sets the SeaDrop mint cap to the contract's `MAX_SUPPLY` constant, so minting is capped
  immediately (without this the cap defaults to `0` and mints revert)
- Prints deployment info and next steps — **save the contract address**

> **Collection size lives in two places.** `MAX_SUPPLY` is a compile-time `constant` in
> `src/OnchainCollection.sol` — edit it there to change the size (it bounds the metadata
> functions). The SeaDrop mint cap (`maxSupply()`) is separate storage set via
> `setMaxSupply`; the deploy script syncs it to `MAX_SUPPLY` for you. If you change
> `MAX_SUPPLY` after deploying, also call `setMaxSupply(<new>)` to re-sync.
>
> **Cost scales with supply — you pay it.** Supply can be set to any size, but writing each
> token's artwork on-chain is a transaction you fund yourself. Every token is its own SSTORE2
> write, so total cost grows roughly linearly with supply (and with how large each JSON blob
> is). A small collection is cheap; a **10,000-supply collection can get rather expensive**,
> especially on Ethereum mainnet at high gas. Estimate before committing with the cost-helper
> scripts (see [Cost estimation](#cost-estimation)), and consider a cheaper L2 for large
> collections.

### Step 3 — Record the contract address

```bash
export CONTRACT_ADDRESS=<deployed_contract_address>
# and add CONTRACT_ADDRESS=<...> to your .env
```

### Step 4 — Verify the contract

```bash
forge verify-contract \
  --chain-id $CHAIN_ID \
  --rpc-url $RPC_URL \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <contract_address> \
  src/OnchainCollection.sol:OnchainCollection \
  --constructor-args $(cast abi-encode "constructor(string,string,address)" \
    "Onchain Collection" "ONCHAIN" "0x00005EA00Ac477B1030CE78506496e8C2dE24bf5")
```

`0x00005EA00Ac477B1030CE78506496e8C2dE24bf5` is the canonical SeaDrop address.

On modern Foundry the verifier endpoint is resolved automatically from `--chain-id`
(Etherscan v2). If you are on an older Foundry or a non-Etherscan explorer, set
`ETHERSCAN_API_URL` in your `.env` and add `--verifier-url $ETHERSCAN_API_URL` to the
command above.

## On-chain metadata

The flow has two phases: set one shared **pre-reveal** pointer, then **reveal** tokens
by uploading their individual metadata.

### Step 1 — Prepare metadata files

Create the shared pre-reveal JSON and one JSON file per token, named by token ID:

```
data/prereveal.json          # shown for every token until it is revealed
data/nfts/1.json
data/nfts/2.json
...
data/nfts/478.json
```

To make a token 100% on-chain, embed the artwork as a base64 data URI in the `image`
field. The SSTORE2 ~24 KB limit is measured against the **whole JSON file**, not just the
image, so the base64 image needs to be well under 24 KB to leave headroom for the name,
description, and trait data. (Base64 also adds ~33% over the raw image bytes.)

If the image is too large to embed, set `image` to an **IPFS URI** (e.g.
`ipfs://<cid>`) or an external URL instead. The JSON itself still lives on-chain via
SSTORE2 — so your metadata stays permanent, updateable (until finalized), and free of any
hosting dependency for the JSON — while only the image bytes are served from elsewhere.

### Step 2 — Set the pre-reveal metadata

Upload the shared pre-reveal JSON and point the collection at it. Every token now serves
this metadata until it is individually revealed.

```bash
forge script script/SetPrereveal.s.sol:SetPrereveal \
  --broadcast --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY --chain $CHAIN_ID
```

The file defaults to `data/prereveal.json`; override it with `PREREVEAL_FILE=<path>`.

### Step 3 — Reveal tokens (upload per-token metadata)

Setting a token's own pointer reveals it. The upload script processes tokens in chunks
(10 per run) to manage gas and memory; use the `START_TOKEN` environment variable to
advance through the collection:

```bash
START_TOKEN=1 forge script script/UploadMetadata.s.sol:UploadMetadata \
  --broadcast --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY --chain $CHAIN_ID

START_TOKEN=11 forge script script/UploadMetadata.s.sol:UploadMetadata \
  --broadcast --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY --chain $CHAIN_ID

# ...continue (21, 31, ...) until all 478 tokens are revealed
```

Each run writes each token's JSON to SSTORE2 and registers its per-token pointer (which
reveals it). The script reads the target contract address from the `CONTRACT_ADDRESS`
environment variable. Reveal everything at once, or run only the chunks you want to
reveal gradually.

### Filling gaps after a partial run

If a run drops transactions (public RPCs sometimes do), some tokens can be left without a
pointer — `UploadMetadata` logs per-token failures and keeps going, so a run can "finish"
with silent gaps. First, check how many tokens are actually set:

```bash
cast call $CONTRACT_ADDRESS "getMetadataCount()(uint256)" --rpc-url $RPC_URL
```

If that's below your supply, use `UploadMissing.s.sol`. It checks `hasMetadata(id)` on-chain
and uploads **only the tokens that are still missing**, so it's much cheaper than re-running
`UploadMetadata` (which would overwrite the tokens that are already fine). It's idempotent —
re-run until it reports `Still missing: 0`:

```bash
UPLOADS_PER_RUN=25 forge script script/UploadMissing.s.sol:UploadMissing \
  --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --chain $CHAIN_ID --slow
```

`UPLOADS_PER_RUN` caps how many tokens it uploads per run (default `25`). Raise it if the
network is reliable, lower it if you keep hitting failures. Each run prints how many it
uploaded and how many remain. **Don't `finalizeMetadata()` until the count reaches your
full supply** — finalizing locks any remaining gaps onto the pre-reveal art permanently.

### Tuning the chunk size (`TOKENS_PER_RUN`)

How many tokens each run uploads is controlled by one constant at the top of
`script/UploadMetadata.s.sol`:

```solidity
uint256 constant TOKENS_PER_RUN = 10;
```

Edit that number to taste, then re-run the script (advancing `START_TOKEN` by the same
amount each time — e.g. with `TOKENS_PER_RUN = 25`, use `START_TOKEN=1, 26, 51, …`). Note
each token is still its own transaction; this only changes how many transactions a single
run broadcasts.

**Raise it (e.g. 25–50)** when you want fewer commands and faster end-to-end uploading,
and the network is cheap and reliable. The trade-offs:
- A single run broadcasts more transactions at once — bigger broadcast, longer to confirm.
- If one token fails mid-run (RPC hiccup, gas spike, rate limit), more work is in flight
  and you have a larger chunk to recover/re-run.
- More memory/compute per run (each ~15 KB JSON is read and held during the run).

**Lower it (e.g. 5 or fewer)** when files are large, the network is congested or
rate-limited, or you want tight control. The trade-offs:
- Safer and easier to recover — a failure only affects a small chunk.
- Lighter on memory and the RPC endpoint.
- But it takes more runs (more commands) to get through the whole collection.

Because this collection embeds full base64 images (~15 KB each), the default of `10` is a
conservative balance. If your metadata is small (text-only, no on-chain image) you can
safely raise it; if you hit RPC errors or timeouts, lower it.

## Updating metadata

As long as the collection is **not finalized**, every pointer can be changed. Because
SSTORE2 data is immutable once written, "updating" means writing a new JSON blob to a
fresh pointer and repointing the contract at it — the old blob simply stops being
referenced. There is no on-chain edit-in-place.

- **Update one token** — edit its `data/nfts/<id>.json` and re-run the upload script
  for that range. `UploadMetadata.s.sol` runs in overwrite mode, so it writes a new
  pointer and overwrites the existing `tokenMetadata[tokenId]`:

  ```bash
  START_TOKEN=42 forge script script/UploadMetadata.s.sol:UploadMetadata \
    --broadcast --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY --chain $CHAIN_ID
  ```

- **Update the pre-reveal art** — edit `data/prereveal.json` and re-run `SetPrereveal`.
  This instantly changes what every *unrevealed* token shows (revealed tokens are
  unaffected).

- **Re-hide a token** — set its pointer back to `address(0)` to drop it from revealed
  state so it serves the pre-reveal metadata again:

  ```bash
  cast send <contract_address> \
    "setTokenMetadata(uint256,address)" 42 0x0000000000000000000000000000000000000000 \
    --rpc-url $RPC_URL --private-key $PRIVATE_KEY
  ```

All of the above revert with `"Metadata is finalized"` after finalizing (see below).

## Finalizing (locking metadata permanently)

`finalizeMetadata()` flips a one-way switch (`metadataFinalized = true`) that
**permanently** blocks every metadata-mutating function: `setPrerevealMetadata`,
`setTokenMetadata`, and `batchSetTokenMetadata`. There is no un-finalize.

After finalizing:

- Existing metadata is frozen exactly as-is — pre-reveal pointer and each token's pointer
  can never be changed, replaced, or re-hidden again.
- `tokenURI()` keeps working normally; reads are unaffected.
- Any token still on the pre-reveal pointer stays that way forever, so **only finalize
  once every token you intend to reveal has been revealed.**

This is the trust guarantee for holders: it proves the art can no longer be altered.
Finalizing is optional — skip it if you want to keep the ability to update metadata.

```bash
cast send <contract_address> "finalizeMetadata()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## Enabling minting (SeaDrop)

This token is an **`ERC721SeaDrop` extension**, which makes it fully **compatible with
OpenSea Studio** — once deployed, the collection shows up in Studio and **mints on OpenSea**.
Its **allowlists, drop stages, pricing, mint windows, creator payout, and fee recipient are
all editable directly in OpenSea Studio** (no code, no redeploy) after the contract is live.

Deploying this contract does **not** open minting. It wires the token to SeaDrop (the
`allowedSeaDrop` address passed in the constructor) and sets the mint cap, but the actual
sale — public mint stage, price, start/end time, allowlists, creator payout, and fee
recipient — is configured through **SeaDrop itself**, not through this contract.

Two ways to do that, both using this token as the target NFT contract:

- **OpenSea Studio (recommended)** — because this is a Studio-compatible SeaDrop extension,
  this is the no-code path: connect the deployed collection in Studio and edit allowlists,
  drop stages, price, and timing there. Mints happen on OpenSea.
- **Directly on the SeaDrop contract** — call its config functions (e.g.
  `updatePublicDrop`, `updateCreatorPayoutAddress`, `updateAllowedFeeRecipient`,
  `updateAllowList`) as the token owner.

Metadata setup (pre-reveal + reveal) and mint configuration are independent — you can do
them in either order, though revealing after mint is the usual pattern.

## Cost estimation

Helper scripts estimate upload costs and simulate a single upload before committing to the
full collection. Neither uses `--broadcast`, so nothing is written on-chain;
`TestSingleUpload` requires `CONTRACT_ADDRESS` to be set (i.e. run after deploying):

```bash
forge script script/EstimateUploadCost.s.sol --rpc-url $RPC_URL
forge script script/TestSingleUpload.s.sol   --rpc-url $RPC_URL
```

## Project layout

```
src/                 Main ERC721SeaDrop contract (OnchainCollection.sol)
script/              Deploy, pre-reveal, upload, gap-fill, and cost-estimation scripts
test/                Foundry unit tests
data/prereveal.json  Shared pre-reveal metadata (served until a token is revealed)
data/nfts/           Per-token JSON metadata files (1.json ... 478.json)
lib/                 Dependencies (seadrop, solmate, openzeppelin, forge-std)
```
