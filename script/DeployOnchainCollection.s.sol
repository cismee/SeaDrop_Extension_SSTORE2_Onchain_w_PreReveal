// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {OnchainCollection} from "src/OnchainCollection.sol";

contract DeployOnchainCollection is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        uint256 expectedChainId = vm.envUint("CHAIN_ID");

        // SAFETY CHECK: Ensure we're on the expected network
        require(block.chainid == expectedChainId, "ERROR: Wrong network! Chain ID does not match CHAIN_ID");

        // SAFETY CHECK: Ensure deployer has sufficient ETH
        require(deployer.balance >= 0.01 ether, "ERROR: Insufficient ETH balance for deployment");

        console.log("=== DEPLOYMENT STARTING ===");
        console.log("WARNING: This deployment spends REAL funds!");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        // Ready to deploy
        console.log("Ready to deploy...");

        vm.startBroadcast(deployer);

        // Deploy the collection with the canonical SeaDrop address.
        // Replace the name and symbol below with your collection's values.
        OnchainCollection collection = new OnchainCollection(
            "Pattern Retrieval",
            "PTTRNRTVL",
            0x00005EA00Ac477B1030CE78506496e8C2dE24bf5  // canonical SeaDrop address
        );

        // Sync the SeaDrop mint cap with the contract's MAX_SUPPLY constant.
        // Without this the SeaDrop cap defaults to 0 and minting would revert.
        collection.setMaxSupply(collection.MAX_SUPPLY());

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("Collection contract deployed to:", address(collection));
        console.log("Contract owner:", collection.owner());
        console.log("Max supply (MAX_SUPPLY constant):", collection.MAX_SUPPLY());
        console.log("SeaDrop mint cap (maxSupply):", collection.maxSupply());
        console.log("Starting token ID: 1");
        console.log("Metadata: Direct JSON (no encoding)");
        console.log("SeaDrop integration: ACTIVE");
        console.log("");

        console.log("=== IMPORTANT: SAVE THIS INFO ===");
        console.log("Contract Address:", address(collection));
        console.log("");

        console.log("=== NEXT STEPS ===");
        console.log("1. Set environment variable:");
        console.log("   export CONTRACT_ADDRESS=", address(collection));
        console.log("");
        console.log("2. Update your .env file:");
        console.log("   CONTRACT_ADDRESS=", address(collection));
        console.log("");
        console.log("3. Verify contract:");
        console.log("   forge verify-contract --chain-id $CHAIN_ID \\");
        console.log("     --rpc-url $RPC_URL \\");
        console.log("     --etherscan-api-key $ETHERSCAN_API_KEY \\");
        console.log("     ", address(collection), " \\");
        console.log("     src/OnchainCollection.sol:OnchainCollection \\");
        console.log("     --constructor-args $(cast abi-encode \"constructor(string,string,address)\" \"Onchain Collection\" \"ONCHAIN\" \"0x00005EA00Ac477B1030CE78506496e8C2dE24bf5\")");
        console.log("");
        console.log("4. Upload metadata (AFTER verification):");
        console.log("   forge script script/UploadMetadata.s.sol:UploadMetadata \\");
        console.log("     --broadcast --rpc-url $RPC_URL \\");
        console.log("     --private-key $PRIVATE_KEY --chain $CHAIN_ID");
        console.log("");
        console.log("5. Check deployment:");
        console.log("   cast call", address(collection), "name()(string) --rpc-url $RPC_URL");
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
    }
}
