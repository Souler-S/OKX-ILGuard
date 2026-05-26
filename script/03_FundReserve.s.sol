// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ILGuardHook} from "../src/ILGuardHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

/// @notice Step 3: Fund the ILGuardHook insurance reserve with token0.
///         Prerequisites: 01 and 02 must have been run.
contract FundReserve is Script {
    // Pool params (must match what was created in step 2)
    // These are overridden by env vars; see .secrets/okx-hackathon.env
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        string memory rpcUrl = vm.envString("XLAYER_MAINNET_RPC_URL");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address hookAddr = vm.envAddress("ILGUARD_HOOK_ADDRESS");
        address token0Addr = vm.envAddress("MOCK_TOKEN0_ADDRESS");
        address token1Addr = vm.envAddress("MOCK_TOKEN1_ADDRESS");
        uint256 fundAmount = vm.envOr("RESERVE_FUND_AMOUNT", uint256(10 ether));

        console.log("=== Fund Insurance Reserve ===");
        console.log("Hook:", hookAddr);
        console.log("Token0:", token0Addr);
        console.log("Fund amount:", fundAmount);

        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerKey);

        // Build pool key (currency order must match step 2)
        require(token0Addr < token1Addr, "tokens must be sorted (token0 < token1)");
        PoolKey memory key =
            PoolKey(Currency.wrap(token0Addr), Currency.wrap(token1Addr), POOL_FEE, TICK_SPACING, IHooks(hookAddr));

        ILGuardHook hook = ILGuardHook(hookAddr);

        // Approve hook to spend token0
        IERC20Minimal(token0Addr).approve(hookAddr, fundAmount);

        // Fund the reserve
        hook.fundReserve(key, fundAmount);

        vm.stopBroadcast();

        // Verify
        (uint256 balance,) = hook.reserves(key.toId());
        console.log("Reserve balance after funding:", balance);
        require(balance == fundAmount, "reserve funding verification failed");

        console.log("=== Reserve Funded Successfully ===");
    }
}
