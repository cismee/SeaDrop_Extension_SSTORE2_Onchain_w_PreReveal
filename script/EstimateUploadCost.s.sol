// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {OnchainCollection} from "src/OnchainCollection.sol";

contract EstimateUploadCost is Script {
    function run() external view {
        // Try to get contract address, but make it optional
        address collectionAddress = address(0);
        try vm.envAddress("CONTRACT_ADDRESS") returns (address addr) {
            collectionAddress = addr;
        } catch {
            // Contract not deployed yet, that's okay
        }
        
        console.log("=== GAS COST ESTIMATION ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block number:", block.number);
        console.log("");
        
        // Get current gas price
        uint256 gasPrice = tx.gasprice;
        console.log("Current gas price (wei):", gasPrice);
        console.log("Gas price (Gwei):", gasPrice / 1e9);
        console.log("");
        
        // Get ETH price in USD (you'll need to update this manually or use an oracle)
        uint256 ethPriceUsd = 2500;
        console.log("Assumed ETH price: $", ethPriceUsd);
        console.log("Update manually for accurate USD");
        console.log("");
        
        // Get current progress if contract is deployed
        uint256 currentCount = 0;
        uint256 maxSupply = 478;
        
        if (collectionAddress != address(0)) {
            console.log("Contract deployed at:", collectionAddress);
            OnchainCollection collection = OnchainCollection(collectionAddress);
            currentCount = collection.getMetadataCount();
            maxSupply = collection.MAX_SUPPLY();
            console.log("Current metadata count:", currentCount);
        } else {
            console.log("Contract not deployed yet");
            console.log("Estimating for full deployment");
        }
        console.log("Max supply:", maxSupply);
        console.log("");
        
        // Assume 20KB per JSON file as baseline
        uint256 assumedJsonSize = 20 * 1024; // 20KB in bytes
        console.log("Assumed JSON size:", assumedJsonSize);
        console.log("JSON size KB:", assumedJsonSize / 1024);
        console.log("(Direct storage - no encoding)");
        console.log("");
        
        // Optional: Try to sample actual files if they exist
        console.log("Checking actual files (optional validation):");
        uint256 sampledCount = 0;
        uint256 totalActualSize = 0;
        
        for (uint256 i = 1; i <= 5; i++) {
            string memory filename = string.concat(
                "data/nfts/",
                vm.toString(i),
                ".json"
            );
            
            try vm.readFile(filename) returns (string memory metadataJson) {
                bytes memory metadataBytes = bytes(metadataJson);
                
                totalActualSize += metadataBytes.length;
                sampledCount++;
                
                console.log("  Token", i);
                console.log("    Size:", metadataBytes.length);
            } catch {
                // File not found, that's okay - we're using assumed size
            }
        }
        
        uint256 avgSize = assumedJsonSize;
        if (sampledCount > 0) {
            uint256 actualAvgSize = totalActualSize / sampledCount;
            console.log("");
            console.log("Actual average:", actualAvgSize);
            console.log("Sample count:", sampledCount);
            console.log("Assumed size:", assumedJsonSize);
            avgSize = actualAvgSize;
        } else {
            console.log("  No files found");
            console.log("  Using assumed 20KB baseline");
        }
        console.log("");
        
        // Estimate gas costs for different operations
        console.log("=== GAS ESTIMATES ===");
        
        // SSTORE2.write() gas estimate: ~20,000 base + ~20 gas per byte
        uint256 sstore2Gas = 20000 + (avgSize * 20);
        console.log("SSTORE2.write():");
        console.log("  Estimated gas:", sstore2Gas);
        
        // setTokenMetadata() gas estimate: ~50,000 for the transaction
        uint256 setMetadataGas = 50000;
        console.log("setTokenMetadata():");
        console.log("  Estimated gas:", setMetadataGas);
        
        // Total per token
        uint256 gasPerToken = sstore2Gas + setMetadataGas;
        console.log("Total per token:", gasPerToken);
        console.log("");
        
        // Cost calculations
        uint256 weiPerToken = gasPerToken * gasPrice;
        uint256 ethPerToken = weiPerToken;
        
        console.log("=== COST PER TOKEN ===");
        console.log("Wei:", weiPerToken);
        console.log("ETH:", _formatEth(ethPerToken));
        console.log("USD:", _formatUsd(weiPerToken, ethPriceUsd));
        console.log("");
        
        // Get current progress
        uint256 remainingTokens = maxSupply - currentCount;
        
        console.log("=== TOTAL PROJECT COSTS ===");
        console.log("Current metadata uploaded:", currentCount);
        console.log("Remaining tokens:", remainingTokens);
        console.log("");
        
        if (remainingTokens > 0) {
            uint256 totalWeiRemaining = weiPerToken * remainingTokens;
            
            console.log("Remaining tokens:", remainingTokens);
            console.log("Cost:");
            console.log("  ETH:", _formatEth(totalWeiRemaining));
            console.log("  USD:", _formatUsd(totalWeiRemaining, ethPriceUsd));
            console.log("");
        }
        
        // Full collection cost (if starting from scratch)
        uint256 totalWeiFull = weiPerToken * maxSupply;
        console.log("All tokens:", maxSupply);
        console.log("  ETH:", _formatEth(totalWeiFull));
        console.log("  USD:", _formatUsd(totalWeiFull, ethPriceUsd));
        console.log("");

        // Add buffer recommendations
        uint256 recommendedBuffer = totalWeiFull * 120 / 100; // 20% buffer
        console.log("=== RECOMMENDED (20% buffer) ===");
        console.log("  ETH:", _formatEth(recommendedBuffer));
        console.log("  USD:", _formatUsd(recommendedBuffer, ethPriceUsd));
        console.log("");
        
        // Gas price scenarios
        console.log("=== DIFFERENT GAS PRICES ===");
        _printCostScenario("Low (0.001 Gwei)", 1e6, gasPerToken, ethPriceUsd, maxSupply);
        _printCostScenario("Current", gasPrice, gasPerToken, ethPriceUsd, maxSupply);
        _printCostScenario("High (0.1 Gwei)", 1e8, gasPerToken, ethPriceUsd, maxSupply);
        console.log("");
        
        console.log("=== NOTES ===");
        console.log("- These are ESTIMATES based on current conditions");
        console.log("- Actual costs may vary +-20% depending on:");
        console.log("  * Metadata size variations");
        console.log("  * Network congestion");
        console.log("  * Contract state changes");
        console.log("- L2 costs are typically very stable");
        console.log("- Direct JSON storage (no encoding)");
        console.log("- Run this script periodically to check rates");
    }
    
    function _formatEth(uint256 wei_) internal pure returns (string memory) {
        // Convert wei to ETH with 6 decimal places
        uint256 eth = wei_ / 1e12; // Get to 6 decimals
        uint256 whole = eth / 1e6;
        uint256 decimal = eth % 1e6;
        
        return string.concat(
            vm.toString(whole),
            ".",
            _padDecimals(decimal, 6),
            " ETH"
        );
    }
    
    function _formatUsd(uint256 wei_, uint256 ethPriceUsd) internal pure returns (string memory) {
        // Convert wei to USD
        uint256 usdCents = (wei_ * ethPriceUsd) / 1e16; // Get cents
        uint256 dollars = usdCents / 100;
        uint256 cents = usdCents % 100;
        
        return string.concat(
            "$",
            vm.toString(dollars),
            ".",
            _padDecimals(cents, 2)
        );
    }
    
    function _padDecimals(uint256 num, uint256 places) internal pure returns (string memory) {
        string memory numStr = vm.toString(num);
        bytes memory numBytes = bytes(numStr);
        
        if (numBytes.length >= places) {
            return numStr;
        }
        
        bytes memory padded = new bytes(places);
        uint256 zerosNeeded = places - numBytes.length;
        
        for (uint256 i = 0; i < zerosNeeded; i++) {
            padded[i] = "0";
        }
        for (uint256 i = 0; i < numBytes.length; i++) {
            padded[zerosNeeded + i] = numBytes[i];
        }
        
        return string(padded);
    }
    
    function _printCostScenario(
        string memory label,
        uint256 gasPrice_,
        uint256 gasPerToken,
        uint256 ethPriceUsd,
        uint256 supply
    ) internal pure {
        uint256 weiPerToken = gasPerToken * gasPrice_;
        uint256 totalWei = weiPerToken * supply;

        console.log(label);
        console.log("  Total:", _formatEth(totalWei));
        console.log("  USD:", _formatUsd(totalWei, ethPriceUsd));
    }
}