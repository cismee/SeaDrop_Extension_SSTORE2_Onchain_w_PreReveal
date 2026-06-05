// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {OnchainCollection} from "../src/OnchainCollection.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

contract OnchainCollectionTest is Test {
    // ERC-4906 event (declared here so vm.expectEmit can match it).
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    OnchainCollection public collection;
    address public seadropAddress = 0x8FFf93E810af25A6d5EDa6E6f2d14bD1138484f5;

    function setUp() public {
        // Deploy with current 3-argument constructor
        collection = new OnchainCollection("Onchain Collection", "ONCHAIN", seadropAddress);
    }

    /// @dev Mint `quantity` tokens via the allowed SeaDrop so they exist for tokenURI.
    function _mint(address to, uint256 quantity) internal {
        collection.setMaxSupply(collection.MAX_SUPPLY());
        vm.prank(seadropAddress);
        collection.mintSeaDrop(to, quantity);
    }

    function testContractSetup() public {
        assertEq(collection.name(), "Onchain Collection");
        assertEq(collection.symbol(), "ONCHAIN");
        assertEq(collection.MAX_SUPPLY(), 478);
        assertEq(collection.getMetadataCount(), 0);
        assertFalse(collection.metadataFinalized());
    }

    function testSetTokenMetadata() public {
        // Create test metadata (raw JSON, no encoding)
        string memory testJson = '{"name":"Test NFT","description":"A test NFT"}';
        bytes memory jsonBytes = bytes(testJson);

        // Store directly in SSTORE2 (no base64 encoding)
        address metadataPointer = SSTORE2.write(jsonBytes);

        // Set metadata for token 1
        collection.setTokenMetadata(1, metadataPointer);

        // Verify metadata was set
        assertTrue(collection.hasMetadata(1));
        assertEq(collection.getMetadataCount(), 1);
        assertEq(collection.tokenMetadata(1), metadataPointer);
    }

    function testBatchSetTokenMetadata() public {
        // Create test metadata for tokens 1-3
        uint256[] memory tokenIds = new uint256[](3);
        address[] memory pointers = new address[](3);

        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;

            string memory testJson = string.concat('{"name":"Test NFT #', vm.toString(i + 1), '"}');
            bytes memory jsonBytes = bytes(testJson);

            // Store directly (no encoding)
            pointers[i] = SSTORE2.write(jsonBytes);
        }

        // Batch set metadata
        collection.batchSetTokenMetadata(tokenIds, pointers);

        // Verify all metadata was set
        assertEq(collection.getMetadataCount(), 3);
        for (uint256 i = 1; i <= 3; i++) {
            assertTrue(collection.hasMetadata(i));
        }
    }

    function testMetadataStorageAndRetrieval() public {
        // Test that we can store and retrieve metadata correctly
        string memory testJson = '{"name":"Test NFT","description":"A test NFT"}';
        bytes memory jsonBytes = bytes(testJson);
        address metadataPointer = SSTORE2.write(jsonBytes);

        collection.setTokenMetadata(1, metadataPointer);

        // Read directly from SSTORE2 to verify storage
        bytes memory storedData = SSTORE2.read(metadataPointer);
        assertEq(string(storedData), testJson);
    }

    function testComplexJSONStorage() public {
        // Test with more complex JSON
        string memory complexJson = '{"name":"Complex NFT","description":"A complex test","attributes":[{"trait_type":"Color","value":"Blue"}]}';
        bytes memory jsonBytes = bytes(complexJson);
        address metadataPointer = SSTORE2.write(jsonBytes);

        collection.setTokenMetadata(5, metadataPointer);

        // Verify storage
        bytes memory storedData = SSTORE2.read(metadataPointer);
        assertEq(string(storedData), complexJson);
    }

    function testFinalizeMetadata() public {
        assertFalse(collection.metadataFinalized());

        collection.finalizeMetadata();

        assertTrue(collection.metadataFinalized());
    }

    function testCannotSetMetadataAfterFinalized() public {
        // Finalize metadata
        collection.finalizeMetadata();

        // Try to set metadata - should revert
        address dummyPointer = address(0x123);

        vm.expectRevert("Metadata is finalized");
        collection.setTokenMetadata(1, dummyPointer);
    }

    function testInvalidTokenId() public {
        address dummyPointer = address(0x123);

        // Token ID 0 should revert
        vm.expectRevert("Invalid token ID");
        collection.setTokenMetadata(0, dummyPointer);

        // Token ID > MAX_SUPPLY should revert
        vm.expectRevert("Invalid token ID");
        collection.setTokenMetadata(1000, dummyPointer);
    }

    function testGetTokensWithMetadata() public {
        // Set metadata for tokens 1, 3, and 5
        string memory testJson = '{"name":"Test"}';
        bytes memory jsonBytes = bytes(testJson);
        address metadataPointer = SSTORE2.write(jsonBytes);

        collection.setTokenMetadata(1, metadataPointer);
        collection.setTokenMetadata(3, metadataPointer);
        collection.setTokenMetadata(5, metadataPointer);

        // Get tokens with metadata
        uint256[] memory tokensWithMetadata = collection.getTokensWithMetadata();

        assertEq(tokensWithMetadata.length, 3);
        assertEq(tokensWithMetadata[0], 1);
        assertEq(tokensWithMetadata[1], 3);
        assertEq(tokensWithMetadata[2], 5);
    }

    function testTokenURIRevertsForNonexistentToken() public {
        // Set metadata but don't mint
        string memory testJson = '{"name":"Test"}';
        bytes memory jsonBytes = bytes(testJson);
        address metadataPointer = SSTORE2.write(jsonBytes);
        collection.setTokenMetadata(1, metadataPointer);

        // Token doesn't exist yet (not minted) - should revert
        vm.expectRevert("Token does not exist");
        collection.tokenURI(1);
    }

    // --- Pre-reveal / reveal ---

    function testSetPrerevealMetadata() public {
        string memory prerevealJson = '{"name":"Hidden","description":"Not revealed yet"}';
        address prerevealPointer = SSTORE2.write(bytes(prerevealJson));

        collection.setPrerevealMetadata(prerevealPointer);

        assertEq(collection.prerevealMetadata(), prerevealPointer);
    }

    function testCannotSetPrerevealAfterFinalized() public {
        collection.finalizeMetadata();

        vm.expectRevert("Metadata is finalized");
        collection.setPrerevealMetadata(address(0x123));
    }

    function testTokenURIServesPrerevealWhenUnrevealed() public {
        string memory prerevealJson = '{"name":"Hidden","description":"Not revealed yet"}';
        address prerevealPointer = SSTORE2.write(bytes(prerevealJson));
        collection.setPrerevealMetadata(prerevealPointer);

        // Mint token 1 but do NOT set its own metadata
        _mint(address(0xBEEF), 1);

        assertFalse(collection.isRevealed(1));
        assertEq(collection.tokenURI(1), prerevealJson);
    }

    function testTokenURIServesTokenMetadataAfterReveal() public {
        // Pre-reveal pointer set for everyone
        string memory prerevealJson = '{"name":"Hidden"}';
        address prerevealPointer = SSTORE2.write(bytes(prerevealJson));
        collection.setPrerevealMetadata(prerevealPointer);

        _mint(address(0xBEEF), 1);

        // Before reveal: shows pre-reveal
        assertEq(collection.tokenURI(1), prerevealJson);

        // Reveal token 1 by setting its own metadata
        string memory revealedJson = '{"name":"Revealed #1","attributes":[]}';
        address revealedPointer = SSTORE2.write(bytes(revealedJson));
        collection.setTokenMetadata(1, revealedPointer);

        // After reveal: shows its own metadata
        assertTrue(collection.isRevealed(1));
        assertEq(collection.tokenURI(1), revealedJson);
    }

    function testRevealIsPerToken() public {
        string memory prerevealJson = '{"name":"Hidden"}';
        collection.setPrerevealMetadata(SSTORE2.write(bytes(prerevealJson)));

        _mint(address(0xBEEF), 3); // tokens 1, 2, 3

        // Reveal only token 2
        string memory revealedJson = '{"name":"Revealed #2"}';
        collection.setTokenMetadata(2, SSTORE2.write(bytes(revealedJson)));

        assertEq(collection.tokenURI(1), prerevealJson);   // still hidden
        assertEq(collection.tokenURI(2), revealedJson);    // revealed
        assertEq(collection.tokenURI(3), prerevealJson);   // still hidden
    }

    function testTokenURIRevertsWhenNoMetadataAtAll() public {
        // Minted, but neither pre-reveal nor per-token metadata is set
        _mint(address(0xBEEF), 1);

        vm.expectRevert("Metadata not set");
        collection.tokenURI(1);
    }

    function testRehideTokenRevertsToPrereveal() public {
        string memory prerevealJson = '{"name":"Hidden"}';
        collection.setPrerevealMetadata(SSTORE2.write(bytes(prerevealJson)));
        _mint(address(0xBEEF), 1);

        // Reveal, then re-hide by clearing the per-token pointer
        string memory revealedJson = '{"name":"Revealed #1"}';
        collection.setTokenMetadata(1, SSTORE2.write(bytes(revealedJson)));
        assertEq(collection.tokenURI(1), revealedJson);

        collection.setTokenMetadata(1, address(0));
        assertFalse(collection.isRevealed(1));
        assertEq(collection.tokenURI(1), prerevealJson);
    }

    function testUpdatePrerevealPointer() public {
        _mint(address(0xBEEF), 1);

        string memory firstJson = '{"name":"Hidden v1"}';
        collection.setPrerevealMetadata(SSTORE2.write(bytes(firstJson)));
        assertEq(collection.tokenURI(1), firstJson);

        string memory secondJson = '{"name":"Hidden v2"}';
        collection.setPrerevealMetadata(SSTORE2.write(bytes(secondJson)));
        assertEq(collection.tokenURI(1), secondJson);
    }

    function testBatchRevealServesPerTokenMetadata() public {
        collection.setPrerevealMetadata(SSTORE2.write(bytes('{"name":"Hidden"}')));
        _mint(address(0xBEEF), 3); // tokens 1, 2, 3

        uint256[] memory tokenIds = new uint256[](3);
        address[] memory pointers = new address[](3);
        string[3] memory jsons = [
            '{"name":"Revealed #1"}',
            '{"name":"Revealed #2"}',
            '{"name":"Revealed #3"}'
        ];
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;
            pointers[i] = SSTORE2.write(bytes(jsons[i]));
        }

        collection.batchSetTokenMetadata(tokenIds, pointers);

        for (uint256 i = 1; i <= 3; i++) {
            assertTrue(collection.isRevealed(i));
            assertEq(collection.tokenURI(i), jsons[i - 1]);
        }
        assertEq(collection.getMetadataCount(), 3);
    }

    function testGetMetadataCountReflectsReveals() public {
        collection.setPrerevealMetadata(SSTORE2.write(bytes('{"name":"Hidden"}')));
        assertEq(collection.getMetadataCount(), 0); // pre-reveal does not count

        collection.setTokenMetadata(1, SSTORE2.write(bytes('{"name":"R1"}')));
        collection.setTokenMetadata(7, SSTORE2.write(bytes('{"name":"R7"}')));
        assertEq(collection.getMetadataCount(), 2);
    }

    // --- Raw upload helpers (single-tx reveal) ---

    function testSetTokenMetadataRaw() public {
        string memory json = '{"name":"Raw #1","description":"uploaded directly"}';
        collection.setTokenMetadataRaw(1, bytes(json));

        assertTrue(collection.isRevealed(1));
        _mint(address(0xBEEF), 1);
        assertEq(collection.tokenURI(1), json);
    }

    function testSetTokenMetadataRawEmitsUpdate() public {
        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(7, 7);
        collection.setTokenMetadataRaw(7, bytes('{"name":"#7"}'));
    }

    function testSetTokenMetadataRawBatch() public {
        uint256[] memory ids = new uint256[](3);
        bytes[] memory datas = new bytes[](3);
        ids[0] = 1; ids[1] = 50; ids[2] = 478;
        datas[0] = bytes('{"name":"#1"}');
        datas[1] = bytes('{"name":"#50"}');
        datas[2] = bytes('{"name":"#478"}');

        collection.setTokenMetadataRawBatch(ids, datas);

        _mint(address(0xBEEF), 478);
        assertEq(collection.tokenURI(1), '{"name":"#1"}');
        assertEq(collection.tokenURI(50), '{"name":"#50"}');
        assertEq(collection.tokenURI(478), '{"name":"#478"}');
        assertEq(collection.getMetadataCount(), 3);
    }

    function testSetTokenMetadataRawBatchLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        bytes[] memory datas = new bytes[](1);
        ids[0] = 1; ids[1] = 2;
        datas[0] = bytes('{"name":"#1"}');

        vm.expectRevert("Array length mismatch");
        collection.setTokenMetadataRawBatch(ids, datas);
    }

    function testSetPrerevealMetadataRaw() public {
        string memory json = '{"name":"Hidden","description":"prereveal raw"}';
        collection.setPrerevealMetadataRaw(bytes(json));

        _mint(address(0xBEEF), 1);
        assertEq(collection.tokenURI(1), json); // unrevealed -> serves prereveal
    }

    function testRawHelpersRespectFinalized() public {
        collection.finalizeMetadata();

        vm.expectRevert("Metadata is finalized");
        collection.setTokenMetadataRaw(1, bytes('{"name":"x"}'));

        vm.expectRevert("Metadata is finalized");
        collection.setPrerevealMetadataRaw(bytes('{"name":"x"}'));
    }

    function testRawHelpersOnlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("OnlyOwner()"));
        collection.setTokenMetadataRaw(1, bytes('{"name":"x"}'));
    }

    function testSetTokenMetadataRawInvalidId() public {
        vm.expectRevert("Invalid token ID");
        collection.setTokenMetadataRaw(479, bytes('{"name":"x"}'));
    }

    // --- ERC-4906 metadata-update events ---

    function testSetTokenMetadataEmitsMetadataUpdate() public {
        address pointer = SSTORE2.write(bytes('{"name":"Revealed #1"}'));

        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(1, 1);
        collection.setTokenMetadata(1, pointer);
    }

    function testBatchSetTokenMetadataEmitsPerToken() public {
        uint256[] memory tokenIds = new uint256[](2);
        address[] memory pointers = new address[](2);
        tokenIds[0] = 4;
        tokenIds[1] = 9;
        pointers[0] = SSTORE2.write(bytes('{"name":"#4"}'));
        pointers[1] = SSTORE2.write(bytes('{"name":"#9"}'));

        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(4, 4);
        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(9, 9);
        collection.batchSetTokenMetadata(tokenIds, pointers);
    }

    function testSetPrerevealEmitsFullRangeUpdate() public {
        address pointer = SSTORE2.write(bytes('{"name":"Hidden"}'));

        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(1, collection.MAX_SUPPLY());
        collection.setPrerevealMetadata(pointer);
    }

    function testSupportsERC4906() public {
        // 0x49064906 is the ERC-4906 interface id.
        assertTrue(collection.supportsInterface(0x49064906));
    }

    function testSeaDropMintCapMatchesMaxSupply() public {
        // Mirror the deploy script: sync the SeaDrop cap to MAX_SUPPLY.
        uint256 cap = collection.MAX_SUPPLY();
        collection.setMaxSupply(cap);
        assertEq(collection.maxSupply(), cap);

        // Minting up to the cap succeeds; one over reverts.
        vm.prank(seadropAddress);
        collection.mintSeaDrop(address(0xBEEF), cap);

        vm.prank(seadropAddress);
        vm.expectRevert();
        collection.mintSeaDrop(address(0xBEEF), 1);
    }

    function testNonOwnerCannotSetPrereveal() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("OnlyOwner()"));
        collection.setPrerevealMetadata(address(0x123));
    }

    function testNonOwnerCannotReveal() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("OnlyOwner()"));
        collection.setTokenMetadata(1, address(0x123));
    }

    function testCannotRevealAfterFinalized() public {
        collection.finalizeMetadata();

        vm.expectRevert("Metadata is finalized");
        collection.setTokenMetadata(1, address(0x123));
    }
}
