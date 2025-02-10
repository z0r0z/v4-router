# SwapFlags
[Git Source](https://github.com/z0r0z/v4-router/blob/3ca8e002a9f3fc72b979853144fa3c49aa37eb54/src/libraries/SwapFlags.sol)

Library for managing swap configuration flags using bitwise operations

*Provides constants and utilities for working with swap flags encoded as uint8*


## State Variables
### SINGLE_SWAP
Flag indicating a single pool swap vs multi-hop swap

*Bit position 0 (0b00001)*


```solidity
uint8 constant SINGLE_SWAP = 1 << 0;
```


### EXACT_OUTPUT
Flag indicating exact output swap vs exact input swap

*Bit position 1 (0b00010)*


```solidity
uint8 constant EXACT_OUTPUT = 1 << 1;
```


### INPUT_6909
Flag indicating input token is ERC6909

*Bit position 2 (0b00100)*


```solidity
uint8 constant INPUT_6909 = 1 << 2;
```


### OUTPUT_6909
Flag indicating output token is ERC6909

*Bit position 3 (0b01000)*


```solidity
uint8 constant OUTPUT_6909 = 1 << 3;
```


### PERMIT2
Flag indicating swap uses Permit2 for token approvals

*Bit position 4 (0b10000)*


```solidity
uint8 constant PERMIT2 = 1 << 4;
```


## Functions
### unpackFlags

Unpacks individual boolean flags from packed uint8


```solidity
function unpackFlags(uint8 flags)
    internal
    pure
    returns (bool singleSwap, bool exactOutput, bool input6909, bool output6909, bool permit2);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`flags`|`uint8`|The packed uint8 containing all flag bits|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`singleSwap`|`bool`|True if single pool swap|
|`exactOutput`|`bool`|True if exact output swap|
|`input6909`|`bool`|True if input token is ERC6909|
|`output6909`|`bool`|True if output token is ERC6909|
|`permit2`|`bool`|True if using Permit2|


