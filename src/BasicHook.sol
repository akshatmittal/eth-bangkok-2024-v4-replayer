// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IPoolManager } from "@uniswap/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import { BaseHook } from "@uniswap/v4-periphery/src/base/hooks/BaseHook.sol";
import { PoolKey } from "@uniswap/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { BeforeSwapDelta } from "@uniswap/v4-periphery/lib/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency } from "@uniswap/v4-periphery/lib/v4-core/src/types/Currency.sol";

contract BasicHook is BaseHook {
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }
}
