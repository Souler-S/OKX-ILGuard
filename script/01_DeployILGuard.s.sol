// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ILGuardHook} from "../src/ILGuardHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @notice Step 1: Deploy ILGuardHook to X Layer with CREATE2 address mining.
///         Reads .secrets/okx-hackathon.env for deployer key and RPC URL.
///         WARNING: Do NOT --broadcast without CEO approval.
contract DeployILGuard is Script {
    // X Layer mainnet PoolManager (verified)
    address constant POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    // Universal CREATE2 deployer
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Hook permission bits (must be EXACT match for low 14 bits)
    uint160 constant HOOK_PERMISSIONS = 0x0744;

    uint16 constant INSURANCE_BPS = 15;
    uint16 constant COMPENSATION_THRESHOLD_BPS = 500;

    function run() external {
        string memory rpcUrl = vm.envString("XLAYER_MAINNET_RPC_URL");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("=== ILGuardHook Deployment ===");
        console.log("RPC:", rpcUrl);
        console.log("PoolManager:", POOL_MANAGER);

        // Build creation bytecode
        bytes memory creationCode = type(ILGuardHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER), INSURANCE_BPS, COMPENSATION_THRESHOLD_BPS);
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);

        // Mine a salt that gives the correct permission bits
        bytes32 salt = _mineSalt(bytecodeHash);
        address hookAddr = _computeCreate2Address(salt, bytecodeHash);

        console.log("Mined salt:", vm.toString(salt));
        console.log("Hook address:", hookAddr);

        // Verify permission bits
        require(uint160(hookAddr) & 0x3FFF == HOOK_PERMISSIONS, "mined address has wrong permission bits");

        console.log("Hook address permissions verified (low 14 bits == 0x0744)");
        console.log("");

        // Deploy via CREATE2 (requires --broadcast)
        console.log("To deploy, run with --broadcast:");
        console.log("Data to send to CREATE2 deployer (0x4e59b...) = concat(salt, bytecode)");

        // Broadcast the deployment
        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerKey);

        // Send raw transaction to CREATE2 deployer
        (bool success,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, bytecode));
        require(success, "CREATE2 deployment failed");

        vm.stopBroadcast();

        // Verify the deployed contract
        ILGuardHook deployed = ILGuardHook(hookAddr);
        require(uint160(address(deployed)) & 0x3FFF == HOOK_PERMISSIONS, "deployed hook has wrong permission bits");

        console.log("=== Deployment Complete ===");
        console.log("ILGuardHook deployed at:", address(deployed));
        console.log("Insurance BPS:", deployed.insuranceBps());
        console.log("Compensation Threshold BPS:", deployed.compensationThresholdBps());
    }

    /// @notice Compute CREATE2 address for given salt and bytecode hash.
    function _computeCreate2Address(bytes32 salt, bytes32 bytecodeHash) internal pure returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, bytecodeHash)))));
    }

    /// @notice Iterate salt values until finding one whose CREATE2 address has exact permission bits.
    function _mineSalt(bytes32 bytecodeHash) internal pure returns (bytes32) {
        uint256 s = 0;
        while (s < 1_000_000) {
            address addr = _computeCreate2Address(bytes32(s), bytecodeHash);
            if (uint160(addr) & 0x3FFF == HOOK_PERMISSIONS) {
                // Verify isValidHookAddress would pass
                // (PoolManager checks: return delta flags must have corresponding action flags)
                // Our 0x0744: bits {10,9,8,6,2} — all checks pass since
                // afterSwapReturnDelta(bit2) has afterSwap(bit6) ✓
                return bytes32(s);
            }
            unchecked {
                s++;
            }
        }
        revert("Failed to mine salt in 1M attempts");
    }
}
