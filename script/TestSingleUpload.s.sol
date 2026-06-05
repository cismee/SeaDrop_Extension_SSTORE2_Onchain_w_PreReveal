// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {OnchainCollection} from "src/OnchainCollection.sol";

contract TestSingleUpload is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address collectionAddress = vm.envAddress("CONTRACT_ADDRESS");
        
        vm.startBroadcast(deployer);
        
        OnchainCollection collection = OnchainCollection(collectionAddress);
        
        console.log("=== SINGLE UPLOAD TEST ===");
        console.log("Contract:", collectionAddress);
        console.log("Deployer:", deployer);
        console.log("Contract owner:", collection.owner());
        console.log("Metadata finalized:", collection.metadataFinalized());
        console.log("Current metadata count:", collection.getMetadataCount());
        
        // Try to upload metadata for token 1
        uint256 testTokenId = 1;
        
        // Check if it already has metadata
        bool hasMetadata = collection.hasMetadata(testTokenId);
        console.log("Token", testTokenId, "has metadata:", hasMetadata);
        
        if (!hasMetadata) {
            console.log("Attempting to upload metadata for token", testTokenId);
            
            // Try to read the file
            string memory filename = "data/nfts/1.json";
            
            try vm.readFile(filename) returns (string memory metadataJson) {
                console.log("File read successfully");
                bytes memory metadataBytes = bytes(metadataJson);
                console.log("Size:", metadataBytes.length, "bytes");
                
                // Deploy to SSTORE2
                address metadataPointer = SSTORE2.write(metadataBytes);
                console.log("SSTORE2 pointer created:", metadataPointer);
                
                // Try to set metadata
                try collection.setTokenMetadata(testTokenId, metadataPointer) {
                    console.log("SUCCESS: Metadata set for token", testTokenId);
                    
                    // Verify it was set
                    bool nowHasMetadata = collection.hasMetadata(testTokenId);
                    console.log("Verification - Token now has metadata:", nowHasMetadata);
                    
                    if (nowHasMetadata) {
                        console.log("Final metadata count:", collection.getMetadataCount());
                    }
                } catch Error(string memory reason) {
                    console.log("FAILED: setTokenMetadata failed with reason:", reason);
                } catch {
                    console.log("FAILED: setTokenMetadata failed with empty revert");
                }
                
            } catch {
                console.log("ERROR: Could not read file:", filename);
            }
        } else {
            console.log("Token already has metadata");
        }
        
        vm.stopBroadcast();
    }
}