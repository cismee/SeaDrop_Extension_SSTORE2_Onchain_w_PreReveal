// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {OnchainCollection} from "src/OnchainCollection.sol";

/// @notice Uploads the shared pre-reveal metadata and points the collection at it.
///         Every token serves this JSON until it is individually revealed via
///         UploadMetadata.s.sol (which sets a per-token pointer).
contract SetPrereveal is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address collectionAddress = vm.envAddress("CONTRACT_ADDRESS");

        // Path to the pre-reveal JSON; override with PREREVEAL_FILE if desired.
        string memory filename = "data/prereveal.json";
        try vm.envString("PREREVEAL_FILE") returns (string memory f) {
            filename = f;
        } catch {}

        vm.startBroadcast(deployer);

        OnchainCollection collection = OnchainCollection(collectionAddress);

        console.log("=== SET PRE-REVEAL METADATA ===");
        console.log("Contract:", collectionAddress);
        console.log("Pre-reveal file:", filename);

        string memory metadataJson = vm.readFile(filename);
        bytes memory metadataBytes = bytes(metadataJson);
        console.log("Size:", metadataBytes.length, "bytes");

        // Deploy the JSON to SSTORE2 and register it as the shared pre-reveal pointer.
        address pointer = SSTORE2.write(metadataBytes);
        console.log("SSTORE2 pointer:", pointer);

        collection.setPrerevealMetadata(pointer);

        console.log("Pre-reveal pointer set:", collection.prerevealMetadata());
        console.log("Done. All unrevealed tokens now serve this metadata.");

        vm.stopBroadcast();
    }
}
