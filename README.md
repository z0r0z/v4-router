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
