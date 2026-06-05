// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {OnchainCollection} from "src/OnchainCollection.sol";

/// @notice Fills in gaps: uploads metadata only for tokens that do NOT yet have a
///         custom pointer set on-chain. Idempotent — re-run until "Still missing: 0".
///
/// Tokens already revealed (tokenMetadata != 0) are skipped, so this is safe and cheap
/// to re-run after a partial/failed UploadMetadata run.
///
/// Env:
///   DEPLOYER          deployer address (must control PRIVATE_KEY)
///   CONTRACT_ADDRESS  the deployed collection
///   UPLOADS_PER_RUN   max tokens to upload this run (optional, default 25)
contract UploadMissing is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address collectionAddress = vm.envAddress("CONTRACT_ADDRESS");

        uint256 uploadsPerRun = 25;
        try vm.envUint("UPLOADS_PER_RUN") returns (uint256 n) {
            uploadsPerRun = n;
        } catch {}

        OnchainCollection collection = OnchainCollection(collectionAddress);
        uint256 maxSupply = collection.MAX_SUPPLY();

        console.log("=== FILL MISSING METADATA ===");
        console.log("Contract:", collectionAddress);
        console.log("Currently set:", collection.getMetadataCount());
        console.log("Max supply:", maxSupply);
        console.log("Uploads this run (cap):", uploadsPerRun);
        console.log("");

        vm.startBroadcast(deployer);

        uint256 uploaded = 0;
        for (uint256 tokenId = 1; tokenId <= maxSupply && uploaded < uploadsPerRun; tokenId++) {
            // Skip tokens that already have a custom pointer.
            if (collection.hasMetadata(tokenId)) {
                continue;
            }

            string memory filename = string.concat(
                "data/nfts/",
                vm.toString(tokenId),
                ".json"
            );

            try vm.readFile(filename) returns (string memory metadataJson) {
                address pointer = SSTORE2.write(bytes(metadataJson));

                try collection.setTokenMetadata(tokenId, pointer) {
                    uploaded++;
                    console.log("Uploaded token:", tokenId);
                } catch Error(string memory reason) {
                    console.log("FAILED to set token:", tokenId);
                    console.log("  reason:", reason);
                } catch {
                    console.log("FAILED to set token (empty revert):", tokenId);
                }
            } catch {
                console.log("ERROR reading file for token:", tokenId);
            }
        }

        vm.stopBroadcast();

        uint256 nowSet = collection.getMetadataCount();
        console.log("");
        console.log("=== RUN SUMMARY ===");
        console.log("Uploaded this run:", uploaded);
        console.log("Total set now:", nowSet);
        console.log("Still missing:", maxSupply - nowSet);
        if (nowSet < maxSupply) {
            console.log("Re-run this script to continue filling gaps.");
        } else {
            console.log("All tokens have metadata. Done.");
        }
    }
}
