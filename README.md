# Pirex-GMX

### Setup

IDE: VSCode 1.73.0 (Universal)

Forge: 0.2.0

From inside the project directory:
1. Install contract dependencies `forge i`
2. Compile contracts `forge build`
3. Set up and run tests
   - Create the test variables helper script `cp scripts/loadEnv.example.sh scripts/loadEnv.sh`
   - Define the values within the newly-created file
   - Run the test helper script `scripts/forgeTest.sh` (along with any `forge test` arguments, flags, options, etc.)

### Overview

Pirex provides GMX token holders with a streamlined and convenient solution for maximizing the productivity of their GMX and (fs)GLP tokens. As a user of Pirex, you can benefit in the following ways:
- Boosted yield as a result of frequent and continuous multiplier point compounding
- Efficient, autonomous compounding of rewards into pxGMX or pxGLP (if using "Easy Mode")
- Mint tokens backed by your future GMX rewards and sell them on our decentralized futures marketplace (if using "Hard Mode" - coming soon)

And more. We're continuously improving our products and adding value to our users (if you are one of them, thank you ❤️).

### How Does It Work?

Standard Mode: Deposit GMX, fsGLP, or a GLP-approved asset (i.e. assets which can be used to mint and stake fsGLP, such as USDC, WBTC, WETH, WAVAX, etc.) and receive a Pirex version of that token in return. For example, when depositing GMX, you will receive pxGMX, which is the equivalent of staked GMX that is handled in a way to maximize yield (i.e. automatic, socialized multiplier point compounding). You will be able to claim rewards and vote in GMX governance proposals (pxGMX only - coming soon), just as you would with the original staked GMX assets. pxGMX can be sold for GMX, via a liquidity pool which we will seed liquidity for, but _cannot_ be redeemed for GMX or esGMX. pxGLP can be redeemed for any GLP constituent asset ([check the GMX app for a complete list](https://app.gmx.io/#/buy_glp#redeem)).

Easy Mode: Deposit the same assets that are accepted in Standard Mode (e.g. GMX, fsGLP, etc.), pxGMX, or pxGLP, and we will automatically compound the rewards earned by those tokens into more pxGMX or pxGLP for you.

Hard Mode (Coming Soon): Stake your pxGMX or pxGLP and mint tokens representing their future rewards (e.g. you can stake pxGMX for 1 year and receive the equivalent of 1 year's worth of rewards - after 1 year, you can unstake your pxGMX), and sell it on our decentralized futures marketplace.

### Core Contract Overview

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

### Contract Diagram: Deposit GMX, Receive pxGMX

![Contract Diagram: Deposit GMX, Receive pxGMX](https://i.imgur.com/5qEKj8q.png)

### Contract Diagram: Claim pxGMX/pxGLP Rewards

![Contract Diagram: Claim pxGMX/pxGLP Rewards](https://i.imgur.com/NqaxI2P.png)
