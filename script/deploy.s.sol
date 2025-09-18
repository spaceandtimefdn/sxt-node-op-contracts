    // SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/* solhint-disable no-console */
/* solhint-disable gas-small-strings */

import {Script, console} from "forge-std/Script.sol";
import {Staking} from "../src/Staking.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {SubstrateSignatureValidator} from "../src/SubstrateSignatureValidator.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SXTChainMessaging} from "../src/SXTChainMessaging.sol";
/// @title Deploy
/// @notice Deploy the Staking contract

contract Deploy is Script {
    using stdJson for string;

    struct Config {
        address[] attestors;
        uint16 threshold;
        address tokenAddress;
        address stakingPoolOwner;
        uint64 unbondingPeriod;
    }

    function run() public {
        // Read the JSON file
        string memory configJson = vm.readFile(string.concat(vm.projectRoot(), "/script/input/config.json"));

        // Parse individual fields
        Config memory config;
        config.attestors = configJson.readAddressArray(".attestors");
        config.threshold = uint16(configJson.readUint(".threshold"));
        config.tokenAddress = configJson.readAddress(".tokenAddress");

        // Parse stakingPoolOwner from config, default to msg.sender if not specified
        bytes memory stakingPoolOwnerData = vm.parseJson(configJson, ".stakingPoolOwner");
        if (stakingPoolOwnerData.length > 0) {
            config.stakingPoolOwner = configJson.readAddress(".stakingPoolOwner");
        } else {
            config.stakingPoolOwner = msg.sender;
        }

        config.unbondingPeriod = uint64(configJson.readUint(".unbondingPeriod"));

        vm.startBroadcast();

        SXTChainMessaging sxtChainMessaging = new SXTChainMessaging(config.tokenAddress);
        console.log("SXTChainMessaging deployed at:", address(sxtChainMessaging));

        // Deploy SubstrateSignatureValidator
        address signatureValidatorAddress = address(new SubstrateSignatureValidator(config.attestors, config.threshold));
        console.log("SubstrateSignatureValidator deployed at:", signatureValidatorAddress);

        // Deploy StakingPool with owner parameter from config
        address stakingPoolAddress = address(new StakingPool(config.tokenAddress, msg.sender));
        console.log("StakingPool deployed at:", stakingPoolAddress);
        console.log("StakingPool owner set to:", msg.sender);

        // Deploy Staking
        address stakingAddress = address(
            new Staking(config.tokenAddress, stakingPoolAddress, config.unbondingPeriod, signatureValidatorAddress)
        );
        console.log("Staking deployed at:", stakingAddress);

        // Add Staking contract to StakingPool
        StakingPool(stakingPoolAddress).addStakingContract(stakingAddress);
        console.log("Staking contract added to StakingPool");

        // Set staking pool owner
        StakingPool(stakingPoolAddress).transferOwnership(config.stakingPoolOwner);
        console.log("StakingPool owner set to:", config.stakingPoolOwner);

        vm.stopBroadcast();

        // Create output JSON with deployed contract addresses
        string memory outputJson = _createFormattedOutputJson(
            signatureValidatorAddress, stakingPoolAddress, stakingAddress, address(sxtChainMessaging), config
        );

        // Write output to file
        string memory outputPath = string.concat(vm.projectRoot(), "/script/output/output.json");
        vm.writeFile(outputPath, outputJson);
        console.log("Deployment information written to:", outputPath);
    }

    /// @notice Create a formatted JSON output with deployed contract addresses and configuration
    /// @param signatureValidatorAddress Address of the deployed SubstrateSignatureValidator contract
    /// @param stakingPoolAddress Address of the deployed StakingPool contract
    /// @param stakingAddress Address of the deployed Staking contract
    /// @param config The configuration used for deployment
    /// @return formattedJson The formatted JSON string containing deployment information
    function _createFormattedOutputJson(
        address signatureValidatorAddress,
        address stakingPoolAddress,
        address stakingAddress,
        address sxtChainMessagingAddress,
        Config memory config
    ) internal pure returns (string memory formattedJson) {
        // Create the deployedContracts section
        string memory deployedContracts = string.concat(
            "  \"deployedContracts\": {\n",
            "    \"SubstrateSignatureValidator\": \"",
            _addressToString(signatureValidatorAddress),
            "\",\n",
            "    \"StakingPool\": \"",
            _addressToString(stakingPoolAddress),
            "\",\n",
            "    \"Staking\": \"",
            _addressToString(stakingAddress),
            "\",\n",
            "    \"SXTChainMessaging\": \"",
            _addressToString(sxtChainMessagingAddress),
            "\"\n",
            "  }"
        );

        // Create the deploymentConfig section
        string memory deploymentConfig = string.concat(
            "  \"deploymentConfig\": {\n",
            "    \"tokenAddress\": \"",
            _addressToString(config.tokenAddress),
            "\",\n",
            "    \"stakingPoolOwner\": \"",
            _addressToString(config.stakingPoolOwner),
            "\",\n",
            "    \"unbondingPeriod\": ",
            _uint64ToString(config.unbondingPeriod),
            ",\n",
            "    \"threshold\": ",
            _uint16ToString(config.threshold),
            ",\n",
            "    \"attestorsCount\": ",
            _uintToString(config.attestors.length),
            "\n",
            "  }"
        );

        // Combine all sections into the final JSON
        formattedJson = string.concat("{\n", deployedContracts, ",\n", deploymentConfig, "\n", "}");

        return formattedJson;
    }

    /// @notice Convert an address to its string representation
    /// @param addr The address to convert
    /// @return addrString The string representation of the address
    function _addressToString(address addr) internal pure returns (string memory addrString) {
        bytes memory addressBytes = abi.encodePacked(addr);
        bytes memory stringBytes = new bytes(42);

        stringBytes[0] = "0";
        stringBytes[1] = "x";

        for (uint256 i = 0; i < 20; ++i) {
            uint8 byteValue = uint8(addressBytes[i]);
            stringBytes[2 + i * 2] = _byteToChar(byteValue / 16);
            stringBytes[3 + i * 2] = _byteToChar(byteValue % 16);
        }

        return string(stringBytes);
    }

    /// @notice Convert a byte value to its hexadecimal character representation
    /// @param b The byte value to convert (0-15)
    /// @return charByte The character representation of the byte
    function _byteToChar(uint8 b) internal pure returns (bytes1 charByte) {
        if (b < 10) {
            return bytes1(uint8(b) + 0x30);
        } else {
            return bytes1(uint8(b) + 0x57); // 0x57 = 'a' - 10
        }
    }

    /// @notice Convert a uint16 to its string representation
    /// @param value The uint16 to convert
    /// @return strValue The string representation of the uint16
    function _uint16ToString(uint16 value) internal pure returns (string memory strValue) {
        return _uintToString(uint256(value));
    }

    /// @notice Convert a uint64 to its string representation
    /// @param value The uint64 to convert
    /// @return strValue The string representation of the uint64
    function _uint64ToString(uint64 value) internal pure returns (string memory strValue) {
        return _uintToString(uint256(value));
    }

    /// @notice Convert a uint256 to its string representation
    /// @param value The uint256 to convert
    /// @return strValue The string representation of the uint256
    function _uintToString(uint256 value) internal pure returns (string memory strValue) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            ++digits;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
