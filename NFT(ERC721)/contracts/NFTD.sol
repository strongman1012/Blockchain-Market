// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

library Strings {
    
    function toString(uint256 value) internal pure returns (string memory) {

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
}

contract NFTD is ERC721Enumerable, ERC721URIStorage, Ownable {

    using Strings for uint256;

    struct ItemNFT {
        uint tokenID;
        string tokenURI;
        address owner;
        Royalty royalty;
    }
    
    struct Royalty {
        address receiver;
        uint fee;
    }

    mapping(uint256 => Royalty) private royalties;

    bool public openPublic;
    uint256 public lastID;

    event NFTMinted(uint tokenId);

    constructor() ERC721("NFT DEVELOPMENTS", "NFT DEVELOPMENTS") {}

    function bulkMint(string memory baseURI, address royaltyAddress, address to, uint256 count, uint fee) external {
        require(fee > 0 && fee <= 1000, "Royalty fee is 0 ~ 10%");
        require(openPublic, "No start sale yet");
        require(count <= 100, "You can mint 100 NFTs at a time at max");

        for (uint i = 0; i < count; i ++) {
            _mint(to, lastID);
            string memory _BaseURI = string(abi.encodePacked("https://ipfs.io/ipfs/", baseURI, "/", i.toString()));
            _setTokenURI(lastID, _BaseURI);
            royalties[lastID] = Royalty(royaltyAddress, fee);
            lastID ++;
        }
        emit NFTMinted(lastID);
    }

    function singleMint(string memory _tokenURI, address royaltyAddress, uint fee) external {
        require(fee > 0 && fee <= 1000, "Royalty fee is 0 ~ 10%");
        require(openPublic, "No start sale yet");

        _mint(msg.sender, lastID);
        _setTokenURI(lastID, _tokenURI);
        royalties[lastID] = Royalty(royaltyAddress, fee);
        lastID ++;
        
        emit NFTMinted(lastID);
    }

    function getItemNFT(uint tokenID) public view returns (ItemNFT memory _nft) {
        _nft = ItemNFT ({
            tokenID: tokenID,
            tokenURI : tokenURI (tokenID), 
            owner : ownerOf(tokenID),
            royalty: getRoyalty(tokenID)
        });
    }

    function getPersonalNFT(address owner_) external view returns (ItemNFT[] memory) {

        uint count = balanceOf(owner_);

        ItemNFT[] memory list = new ItemNFT[](count);

        for (uint i; i < count; i ++) {
            uint index = tokenOfOwnerByIndex(owner_, i);
            list[i] = getItemNFT(index);
        }
        return list;
    }

    function getRoyalty(uint tokenID) public view returns (Royalty memory) {
        return royalties[tokenID];
    }

    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function start() external onlyOwner {
        require(!openPublic, "already started");
        openPublic = true;
    }

}