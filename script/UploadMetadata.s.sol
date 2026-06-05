// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {OnchainCollection} from "src/OnchainCollection.sol";

contract UploadMetadata is Script {
    // MEMORY FIX: Process only this many tokens per run to avoid memory issues
    uint256 constant TOKENS_PER_RUN = 10;
    
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address collectionAddress = vm.envAddress("CONTRACT_ADDRESS");

        vm.startBroadcast(deployer);

        OnchainCollection collection = OnchainCollection(collectionAddress);

        console.log("=== METADATA UPLOAD STARTING ===");
        console.log("Contract:", collectionAddress);
        console.log("Current metadata count:", collection.getMetadataCount());
        console.log("Max supply:", collection.MAX_SUPPLY());
        console.log("Tokens per run:", TOKENS_PER_RUN);
        console.log("Mode: OVERWRITE MODE - Fixing all metadata");
        
        // Upload in batches to manage gas limits
        uint256 batchSize = 1;  // Process one token at a time
        uint256 maxSupply = collection.MAX_SUPPLY();
        
        // OVERWRITE MODE: Use START_TOKEN env variable to track progress
        // If not set, default to 1
        uint256 startingToken = 1;
        try vm.envUint("START_TOKEN") returns (uint256 startToken) {
            startingToken = startToken;
            console.log("Using START_TOKEN from environment:", startingToken);
        } catch {
            console.log("START_TOKEN not set, starting from token 1");
        }
        
        console.log("Starting from token:", startingToken);
        console.log("*** OVERWRITE MODE ENABLED ***");
        
        // Calculate end token for this run
        uint256 endTokenForRun = startingToken + TOKENS_PER_RUN - 1;
        if (endTokenForRun > maxSupply) {
            endTokenForRun = maxSupply;
        }
        console.log("Will process up to token:", endTokenForRun);
        console.log("");
        
        uint256 tokensProcessedThisRun = 0;
        
        for (uint256 startToken = startingToken; startToken <= maxSupply && tokensProcessedThisRun < TOKENS_PER_RUN; startToken += batchSize) {
            uint256 endToken = startToken + batchSize - 1;
            if (endToken > maxSupply) {
                endToken = maxSupply;
            }
            
            console.log("");
            console.log("=== BATCH:", startToken);
            console.log("    to:", endToken, "===");
            uploadBatch(collection, startToken, endToken, deployer);
            
            tokensProcessedThisRun++;
            
            // Show progress
            uint256 newCount = collection.getMetadataCount();
            console.log("Progress:", newCount);
            console.log("Total:", maxSupply);
            console.log("Processed this run:", tokensProcessedThisRun, "/", TOKENS_PER_RUN);
            
            // Stop after processing TOKENS_PER_RUN tokens
            if (tokensProcessedThisRun >= TOKENS_PER_RUN) {
                console.log("");
                console.log("=== CHUNK COMPLETE ===");
                console.log("Processed", TOKENS_PER_RUN, "tokens this run");
                
                uint256 nextStartToken = startToken + 1;
                if (nextStartToken <= maxSupply) {
                    console.log("");
                    console.log("Run the script again with START_TOKEN to continue:");
                    console.log("START_TOKEN=", nextStartToken, "forge script script/UploadMetadata.s.sol:UploadMetadata \\");
                    console.log("  --broadcast --rpc-url $RPC_URL \\");
                    console.log("  --private-key $PRIVATE_KEY --chain $CHAIN_ID --legacy");
                }
                break;
            }
        }
        
        uint256 finalCount = collection.getMetadataCount();
        console.log("");
        console.log("=== RUN SUMMARY ===");
        console.log("Tokens uploaded this run:", tokensProcessedThisRun);
        console.log("Total metadata count:", finalCount);
        console.log("Out of total:", maxSupply);
        
        if (startingToken + TOKENS_PER_RUN > maxSupply) {
            console.log("");
            console.log("SUCCESS: All metadata uploaded!");
            console.log("");
            console.log("Optional: Finalize metadata to prevent further changes:");
            console.log("cast send", collectionAddress, "finalizeMetadata()");
            console.log("Add: --rpc-url $RPC_URL");
            console.log("Add: --private-key $PRIVATE_KEY");
        }
        
        vm.stopBroadcast();
    }
    
    /// @notice Upload a batch of tokens efficiently
    function uploadBatch(OnchainCollection collection, uint256 startToken, uint256 endToken, address deployer) internal {
        uint256 batchSize = endToken - startToken + 1;
        uint256[] memory tokenIds = new uint256[](batchSize);
        address[] memory metadataPointers = new address[](batchSize);
        
        uint256 successCount = 0;
        
        // Deploy SSTORE2 contracts for each token in batch
        for (uint256 tokenId = startToken; tokenId <= endToken; tokenId++) {
            // OVERWRITE MODE: Allow re-uploading existing metadata
            if (collection.hasMetadata(tokenId)) {
                console.log("OVERWRITING token:", tokenId);
            }
            
            // Try to read metadata file (data/nfts/1.json, 2.json, ...)
            string memory filename = string.concat(
                "data/nfts/",
                vm.toString(tokenId),
                ".json"
            );
            
            try vm.readFile(filename) returns (string memory metadataJson) {
                bytes memory metadataBytes = bytes(metadataJson);
                
                // Deploy JSON directly to SSTORE2
                // The --gas-limit flag in the forge script command will apply here
                address metadataPointer = SSTORE2.write(metadataBytes);
                
                tokenIds[successCount] = tokenId;
                metadataPointers[successCount] = metadataPointer;
                successCount++;
                
                console.log("Token uploaded:", vm.toString(tokenId));
                console.log("Pointer:", metadataPointer);
                console.log("Size:", vm.toString(metadataBytes.length), "bytes");
                           
            } catch {
                console.log("ERROR reading file for token:", vm.toString(tokenId));
            }
        }
        
        // Process individual uploads instead of batch to avoid failures
        console.log("Processing", vm.toString(successCount), "tokens individually");
        
        // Check ETH balance before individual uploads
        uint256 currentBalance = deployer.balance;
        console.log("Current balance:", vm.toString(currentBalance));
        
        if (currentBalance < 0.001 ether) {
            console.log("WARNING: Very low balance");
            console.log("Balance in ETH:", vm.toString(currentBalance / 1e18));
        }
        
        for (uint256 i = 0; i < successCount; i++) {
            uint256 tokenId = tokenIds[i];
            address pointer = metadataPointers[i];
            
            // Upload individually with error handling (will overwrite if exists)
            console.log("Uploading token:", vm.toString(tokenId));
            console.log("Using pointer:", pointer);
            
            try collection.setTokenMetadata(tokenId, pointer) {
                console.log("SUCCESS: Token", vm.toString(tokenId));
            } catch Error(string memory reason) {
                console.log("FAILED:", reason);
            } catch {
                console.log("FAILED: Empty revert");
                
                // Diagnose the issue
                console.log("  Pointer:", pointer);
                console.log("  Token valid:", tokenId >= 1 && tokenId <= collection.MAX_SUPPLY());
                console.log("  Owner:", collection.owner());
                console.log("  Finalized:", collection.metadataFinalized());
            }
        }
        
        console.log("Batch complete");
        console.log("New count:", collection.getMetadataCount());
    }
}