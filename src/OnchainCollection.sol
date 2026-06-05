// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/ERC721SeaDrop.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

contract OnchainCollection is ERC721SeaDrop {
    // O(1) mapping: tokenId => SSTORE2 address containing JSON metadata.
    // A non-zero entry means the token is revealed (serves its own metadata);
    // a zero entry means the token is still pre-reveal (serves prerevealMetadata).
    mapping(uint256 => address) public tokenMetadata;

    // Shared SSTORE2 pointer served for every token that has not been revealed yet.
    address public prerevealMetadata;

    uint256 public constant MAX_SUPPLY = 478;  // Collection size
    bool public metadataFinalized;

    constructor(
        string memory name,
        string memory symbol,
        address allowedSeaDrop
    ) ERC721SeaDrop(name, symbol, _toDynamic(allowedSeaDrop)) {}

    /// @notice Set the shared pre-reveal metadata served for all unrevealed tokens
    /// @param metadataPointer SSTORE2 address containing the pre-reveal JSON metadata
    function setPrerevealMetadata(address metadataPointer) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        prerevealMetadata = metadataPointer;

        // Changing the pre-reveal pointer affects every unrevealed token (ERC-4906).
        emit BatchMetadataUpdate(_startTokenId(), MAX_SUPPLY);
    }

    /// @notice Reveal a specific token ID by setting its own metadata
    /// @dev Setting a non-zero pointer reveals the token; until then it serves the
    ///      shared pre-reveal metadata. Pass address(0) to revert a token to pre-reveal.
    /// @param tokenId The token ID (1-999)
    /// @param metadataPointer SSTORE2 address containing JSON metadata
    function setTokenMetadata(uint256 tokenId, address metadataPointer) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "Invalid token ID");
        tokenMetadata[tokenId] = metadataPointer;

        // Notify marketplaces to refresh this token's metadata (ERC-4906).
        emit BatchMetadataUpdate(tokenId, tokenId);
    }

    /// @notice Batch set metadata for multiple tokens (gas optimization)
    /// @param tokenIds Array of token IDs
    /// @param metadataPointers Array of SSTORE2 addresses
    function batchSetTokenMetadata(
        uint256[] calldata tokenIds,
        address[] calldata metadataPointers
    ) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(tokenIds.length == metadataPointers.length, "Array length mismatch");
        require(tokenIds.length <= 3, "Batch too large");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(tokenIds[i] >= 1 && tokenIds[i] <= MAX_SUPPLY, "Invalid token ID");
            tokenMetadata[tokenIds[i]] = metadataPointers[i];

            // Notify marketplaces to refresh each token's metadata (ERC-4906).
            emit BatchMetadataUpdate(tokenIds[i], tokenIds[i]);
        }
    }

    /// @notice Reveal a token by uploading its JSON directly. Writes the data to a
    ///         new SSTORE2 pointer on-chain in the same transaction, so a client only
    ///         needs to send the bytes (one tx per token instead of two).
    /// @param tokenId The token ID (1..MAX_SUPPLY)
    /// @param data Raw JSON metadata bytes
    function setTokenMetadataRaw(uint256 tokenId, bytes calldata data) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "Invalid token ID");
        tokenMetadata[tokenId] = SSTORE2.write(data);
        emit BatchMetadataUpdate(tokenId, tokenId);
    }

    /// @notice Batch version of setTokenMetadataRaw: reveal many tokens in one tx,
    ///         each written to its own SSTORE2 pointer. Keep the batch small enough to
    ///         fit under the block gas limit (the caller is responsible for chunking).
    /// @param tokenIds Array of token IDs
    /// @param datas Array of raw JSON metadata bytes, aligned with tokenIds
    function setTokenMetadataRawBatch(
        uint256[] calldata tokenIds,
        bytes[] calldata datas
    ) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(tokenIds.length == datas.length, "Array length mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "Invalid token ID");
            tokenMetadata[tokenId] = SSTORE2.write(datas[i]);
            emit BatchMetadataUpdate(tokenId, tokenId);
        }
    }

    /// @notice Set the shared pre-reveal metadata by uploading its JSON directly.
    /// @param data Raw pre-reveal JSON metadata bytes
    function setPrerevealMetadataRaw(bytes calldata data) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        prerevealMetadata = SSTORE2.write(data);
        emit BatchMetadataUpdate(_startTokenId(), MAX_SUPPLY);
    }

    /// @notice Check if a token has its own metadata set (i.e. has been revealed)
    function hasMetadata(uint256 tokenId) external view returns (bool) {
        return tokenMetadata[tokenId] != address(0);
    }

    /// @notice Whether a token is revealed (serves its own metadata vs. pre-reveal)
    function isRevealed(uint256 tokenId) external view returns (bool) {
        return tokenMetadata[tokenId] != address(0);
    }

    /// @notice Get count of tokens with metadata set
    function getMetadataCount() external view returns (uint256 count) {
        for (uint256 i = 1; i <= MAX_SUPPLY; i++) {
            if (tokenMetadata[i] != address(0)) {
                count++;
            }
        }
    }

    /// @notice Get all tokens that have metadata set
    function getTokensWithMetadata() external view returns (uint256[] memory tokens) {
        uint256 count = this.getMetadataCount();
        tokens = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= MAX_SUPPLY; i++) {
            if (tokenMetadata[i] != address(0)) {
                tokens[index] = i;
                index++;
            }
        }
    }

    function finalizeMetadata() external onlyOwner {
        metadataFinalized = true;
    }

    function _toDynamic(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @notice Returns raw JSON metadata stored on-chain via SSTORE2
    /// @dev Revealed tokens (with their own pointer) serve their own JSON; every other
    ///      existing token serves the shared pre-reveal JSON. Returned as a raw string.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");

        // Revealed tokens serve their own metadata; otherwise fall back to pre-reveal.
        address metadataPointer = tokenMetadata[tokenId];
        if (metadataPointer == address(0)) {
            metadataPointer = prerevealMetadata;
        }
        require(metadataPointer != address(0), "Metadata not set");

        // Read and return raw JSON from SSTORE2
        bytes memory jsonData = SSTORE2.read(metadataPointer);
        return string(jsonData);
    }

    /// @notice Get max supply for external queries
    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }
}
