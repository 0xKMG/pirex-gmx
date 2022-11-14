# Pirex-GMX

### Setup

IDE: VSCode 1.73.0 (Universal)

Forge: 0.2.0

From inside the project directory:
1. Install contract dependencies `forge i`
2. Compile contracts `forge build`
3. Set up and run tests
    3a. Create the test variables helper script `cp scripts/loadEnv.example.sh scripts/loadEnv.sh`
    3b. Define the values within the newly-created file in 3a
    3c. Run the test helper script `scripts/forgeTest.sh` (along with any `forge test` arguments, flags, options, etc.)

### Core Contracts

**PirexGmx.sol**
- Intakes GMX-based tokens (GMX and fsGLP) and mints their synthetic counterparts in return (pxGMX and pxGLP)
- Allows users to redeem their pxGLP for GLP constituent assets (same assets which GMX allows GLP to be traded for, e.g. USDC, WBTC, etc.)
- Interacts with the GMX contracts to stake and mint assets, claim rewards, perform asset migrations (only if necessary, as a result of a contract upgrade), and more
- Custodies GMX rewards until they are claimed and distributed via a call from the

**PirexRewards.sol**
- Tracks perpetually accrued/continuously streamed GMX rewards across multiple scopes: global, different reward tokens, and individual users
- Has permission to call various reward-related methods on the PirexGmx contract for claiming and distributing rewards to users
- Enables reward forwarding, and can also set a reward recipient on behalf of contract accounts (permissioned, used to direct rewards accrued from tokens in LP contracts - those rewards would otherwise be wasted)

**PirexFees.sol**
- Custodies protocol fees and distributes them to the Redacted treasury and Pirex contributor multisig
- Allows its owner, a Redacted multisig, to modify various contract state variables (i.e. fee percent and fee recipient addresses)

**PxERC20.sol**
- Modifies standard ERC20 methods with calls to PirexRewards's reward accrual methods to ensure that asset ownership and reward distribution can be properly accounted for

**PxGmx.sol**
- Is a derivative of the PxERC20 contract
- Represents GMX and esGMX tokens (calls the PxERC20 constructor, which it is derived from, with fixed values that is consistent with this goal)
- Overwrites the `burn` method of PxERC20 (pxGMX cannot be redeemed for GMX or esGMX)
