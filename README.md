# V4 Swap Router

A simple and optimized router for swapping on Uniswap V4. ABI inspired by [`UniswapV2Router02`](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol).

## Design

The Uniswap V4 Swap Router supports the following features:

- Exact input swaps
- Exact output swaps
- Multi-hop swaps
- Native token (ETH) swaps
- Hook interactions
- Custom swap curves

## Deployment

Every chain at [0x00000000000044AcF0C243EECB34c8C0069B2E4B](https://contractscan.xyz/contract/0x00000000000044AcF0C243EECB34c8C0069B2E4B)

# Usage

## Install

*requires [foundry](https://book.getfoundry.sh)*

```bash
forge install z0r0z/v4-router
```

## Exact Input

- For swaps, where users are specifying the input amount and want the maximum output possible

*Trade 1000 USDC into x Ether*

### Single Pool Swaps - Exact Input

For simple swaps on a singular pool

```solidity
IV4SwapRouter router = IV4SwapRouter(...);

uint256 amountIn = 1e18;                 // amount of input tokens
uint256 amountOutMin = 0.99e18;          // minimum amount of output tokens, otherwise revert
bool zeroForOne = true;                  // swap token0 for token1
PoolKey memory poolKey = PoolKey(...);   // the pool to swap on
bytes memory hookData;                   // optional arbitrary data to be provided to the hook
uint256 deadline = block.timestamp + 60; // deadline for the transaction to be mined
router.swapExactTokensForTokens(
    amountIn,
    amountOutMin,
    zeroForOne,
    poolKey,
    hookData,
    recipient,
    deadline
);
```

### Multihop Swaps - Exact Input

For swaps trading through multiple pools

```solidity
IV4SwapRouter router = IV4SwapRouter(...);

// Example swapPath: A --> B --> C
Currency startCurrency = currencyA;
PathKey[] memory path = new PathKey[](2);
path[0] = PathKey({
    intermediateCurrency: currencyB,
    fee: fee0,                           // fee tier of the (A, B) pool
    tickSpacing: tickSpacing0,           // tick spacing of the (A, B) pool
    hooks: IHooks(address(...)),         // hook address of the (A, B) pool
    hookData: hookData0                  // optional arbitrary bytes to passed to the (A, B) pool's beforeSwap/afterSwap functions
});
path[1] = PathKey({
    intermediateCurrency: currencyC,
    fee: fee1,                           // fee tier of the (B, C) pool
    tickSpacing: tickSpacing1,           // tick spacing of the (B, C) pool
    hooks: IHooks(address(...)),         // hook address of the (B, C) pool
    hookData: hookData1                  // optional arbitrary bytes to passed to the (B, C) pool's beforeSwap/afterSwap functions
});

uint256 amountIn = 1e18;                 // amount of input tokens
uint256 amountOutMin = 0.99e18;          // minimum amount of output tokens, otherwise revert
uint256 deadline = block.timestamp + 60; // deadline for the transaction to be mined
router.swapExactTokensForTokens(
    amountIn, amountOutMin, startCurrency, path, recipient, deadline
);
```


---

## Exact Output

- For swaps, where users are specifying the output amount and want the minimum input possible

*Trade x USDC into 1.0 Ether*

### Single Pool Swaps - Exact Output

For simple swaps on a singular pool

```solidity
IV4SwapRouter router = IV4SwapRouter(...);

uint256 amountOut = 1e18;                // amount of output tokens expected
uint256 amountInMax = 1.01e18;           // maximum amount of input tokens, otherwise revert
bool zeroForOne = true;                  // swap token0 for token1
PoolKey memory poolKey = PoolKey(...);   // the pool to swap on
bytes memory hookData;                   // optional arbitrary data to be provided to the hook
uint256 deadline = block.timestamp + 60; // deadline for the transaction to be mined
router.swapTokensForExactTokens(
    amountOut,
    amountInMax,
    zeroForOne,
    poolKey,
    ZERO_BYTES,
    recipient,
    deadline
);
```

### Multihop Swaps - Exact Output

For swaps trading through multiple pools

```solidity
IV4SwapRouter router = IV4SwapRouter(...);

// Example swapPath: A --> B --> C
Currency startCurrency = currencyA;
PathKey[] memory path = new PathKey[](2);
path[0] = PathKey({
    intermediateCurrency: currencyB,
    fee: fee0,                           // fee tier of the (A, B) pool
    tickSpacing: tickSpacing0,           // tick spacing of the (A, B) pool
    hooks: IHooks(address(...)),         // hook address of the (A, B) pool
    hookData: hookData0                  // optional arbitrary bytes to passed to the (A, B) pool's beforeSwap/afterSwap functions
});
path[1] = PathKey({
    intermediateCurrency: currencyC,
    fee: fee1,                           // fee tier of the (B, C) pool
    tickSpacing: tickSpacing1,           // tick spacing of the (B, C) pool
    hooks: IHooks(address(...)),         // hook address of the (B, C) pool
    hookData: hookData1                  // optional arbitrary bytes to passed to the (B, C) pool's beforeSwap/afterSwap functions
});

uint256 amountOut = 1e18;                // amount of output tokens expected
uint256 amountInMax = 1.01e18;           // maximum amount of input tokens, otherwise revert
uint256 deadline = block.timestamp + 60; // deadline for the transaction to be mined
router.swapTokensForExactTokens(
    amountOut, amountInMax, startCurrency, path, recipient, deadline
);
```

For additional usage examples, please see [test/V4SwapRouter.multihop.t.sol](/test/V4SwapRouter.multihop.t.sol)


## Architecture

The router is implemented in two main contracts:

1. `BaseSwapRouter`: Contains core swap logic and handles callbacks from the Pool Manager
2. `V4SwapRouter`: Inherits from BaseSwapRouter and implements the user-facing interface

## Optimizations

The implementation prioritizes gas efficiency through:

- Minimal state changes
- Optimized memory usage in multi-hop swaps
- Single-swap vs multi-swap specific codepaths
- Efficient native token handling
- Reuse of Pool Manager callbacks

## Interface

The router provides three categories of swap functions:

### Multi-pool Swaps
- `swapExactTokensForTokens`: Swap exact input amount through multiple pools
- `swapTokensForExactTokens`: Receive exact output amount through multiple pools
- `swap`: Generic multi-pool swap interface

### Single-pool Swaps
- `swapExactTokensForTokens`: Swap exact input in a single pool
- `swapTokensForExactTokens`: Receive exact output from a single pool
- `swap`: Generic single-pool swap interface

### Optimized Swaps
- `swap(bytes, uint256)`: Pre-encoded swap data for reduced gas costs

## Path Construction

Multi-hop swaps are defined using the `PathKey` struct:
```solidity
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

## Getting Started

Run: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`

Build the foundry project with `forge build`. Run tests with `forge test`. Measure gas with `forge snapshot`. Format with `forge fmt`.

## Community Router Code Disclaimer

This community router code provided herein is offered on an “as-is” basis and has not been audited for security, reliability, or compliance with any specific standards or regulations. It may contain bugs, errors, or vulnerabilities that could lead to unintended consequences.

By utilizing this community router, you acknowledge and agree that:

- Assumption of Risk: You assume all responsibility and risks associated with its use.
- No Warranty: The authors and distributors of this code, namely, z0r0z and the Uniswap Foundation, disclaim all warranties, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement.
- Limitation of Liability: In no event shall the authors or distributors be held liable for any damages or losses, including but not limited to direct, indirect, incidental, or consequential damages arising out of or in connection with the use or inability to use the code.
- Recommendation: Users are strongly encouraged to review, test, and, if necessary, audit the community router independently before deploying in any environment.

By proceeding to utilize this community router, you indicate your understanding and acceptance of this disclaimer.

## License

See [LICENSE](./LICENSE) for more details.
