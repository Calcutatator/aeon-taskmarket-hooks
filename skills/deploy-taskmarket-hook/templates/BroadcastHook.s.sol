// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ITMPHook} from "@taskmarket/contracts/src/interfaces/ITMPHook.sol";
import {Hook} from "../src/Hook.sol";

/// @notice Armed deterministic deployment through Foundry's canonical CREATE2 factory.
/// @dev Authorization and key loading live here so the private key is never a CLI argument.
contract BroadcastHook is Script {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes4 internal constant EXPECTED_ITMP_HOOK_INTERFACE_ID = 0x2187b4de;

    function run() external returns (Hook hook) {
        string memory rawInput = vm.envString("SKILL_VAR");
        require(_startsWithArm(rawInput), "raw SKILL_VAR is not armed");

        uint256 expectedChainId = vm.envUint("TASKMARKET_CHAIN_ID");
        require(block.chainid == expectedChainId, "unexpected broadcast chain");
        if (block.chainid == 8453) {
            require(_containsToken(rawInput, "chain:base"), "raw input lacks chain:base");
            require(vm.envOr("HOOK_MAINNET_OK", uint256(0)) == 1, "HOOK_MAINNET_OK is not 1");
        }

        address diamond = vm.envAddress("TASKMARKET_DIAMOND");
        require(diamond != address(0) && diamond.code.length != 0, "invalid TaskMarket Diamond");
        require(CREATE2_DEPLOYER.code.length != 0, "CREATE2 factory is unavailable");

        bytes memory initCode = abi.encodePacked(type(Hook).creationCode, abi.encode(diamond));
        bytes32 defaultSalt =
            keccak256(abi.encode("aeon.deploy-taskmarket-hook.v1", diamond, keccak256(type(Hook).creationCode)));
        bytes32 salt = vm.envOr("TASKMARKET_HOOK_SALT", defaultSalt);
        address expected = vm.computeCreate2Address(salt, keccak256(initCode), CREATE2_DEPLOYER);
        Hook runtimeProbe = new Hook(diamond);
        bytes32 expectedRuntimeCodehash = address(runtimeProbe).codehash;

        uint256 deployerKey = vm.envUint("HOOK_DEPLOYER_PRIVATE_KEY");
        require(deployerKey != 0, "empty deployer key");
        console2.log("deployer", vm.addr(deployerKey));

        if (expected.code.length != 0) {
            hook = Hook(expected);
            require(expected.codehash == expectedRuntimeCodehash, "CREATE2 address collision");
            require(hook.diamond() == diamond, "existing hook bound to wrong diamond");
            require(hook.supportsInterface(EXPECTED_ITMP_HOOK_INTERFACE_ID), "existing hook has wrong interface");
            console2.log("ALREADY_DEPLOYED", expected);
            console2.logBytes32(expected.codehash);
            return hook;
        }

        vm.startBroadcast(deployerKey);
        (bool deployed,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, initCode));
        vm.stopBroadcast();
        require(deployed, "CREATE2 factory call failed");
        require(expected.code.length != 0, "CREATE2 deployment missing code");
        require(expected.codehash == expectedRuntimeCodehash, "deployed runtime mismatch");
        hook = Hook(expected);

        require(hook.diamond() == diamond, "hook bound to wrong diamond");
        require(hook.supportsInterface(type(ITMPHook).interfaceId), "ITMPHook ERC165 mismatch");
        require(type(ITMPHook).interfaceId == EXPECTED_ITMP_HOOK_INTERFACE_ID, "unexpected ITMPHook interface");

        console2.log("hook", address(hook));
        console2.log("diamond", diamond);
        console2.logBytes32(salt);
        console2.logBytes32(address(hook).codehash);
    }

    function _startsWithArm(string memory value) private pure returns (bool) {
        bytes memory data = bytes(value);
        return data.length >= 4 && data[0] == "a" && data[1] == "r" && data[2] == "m" && data[3] == ":";
    }

    function _containsToken(string memory value, string memory token) private pure returns (bool) {
        bytes memory data = bytes(value);
        bytes memory needle = bytes(token);
        if (needle.length == 0 || data.length < needle.length) return false;

        for (uint256 i; i + needle.length <= data.length; ++i) {
            if (i != 0 && !_isSpace(data[i - 1])) continue;
            if (i + needle.length != data.length && !_isSpace(data[i + needle.length])) continue;

            bool same = true;
            for (uint256 j; j < needle.length; ++j) {
                if (data[i + j] != needle[j]) {
                    same = false;
                    break;
                }
            }
            if (same) return true;
        }
        return false;
    }

    function _isSpace(bytes1 value) private pure returns (bool) {
        return value == 0x20 || value == 0x09 || value == 0x0a || value == 0x0d;
    }
}
