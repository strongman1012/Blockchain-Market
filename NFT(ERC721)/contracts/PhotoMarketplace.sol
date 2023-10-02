// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { NFTD } from "./NFTD.sol";

contract Marketplace is Ownable {

    using SafeMath for uint256;

    struct Profit {
        bool status;
        uint256 index;
    }

    string public constant salt = "NFTD MARKETPLACE";
    mapping (uint => uint) public nonces;
    mapping (address => bool) public whitelist;
    mapping (uint256 => Profit) public profitSet;
    uint256[] public profits;

    NFTD public flexNFT;
    IERC20 public WBNB = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    uint public fee = 250;  // 2.5%
    uint public premium_fee = 300;  // 3%
    address public treasurer;  //fee collector
    address public devWallet; // dev fee collector

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable BUY_SALT;
    bytes32 public immutable SELL_SALT;

    bool private profitable;
    constructor(address _nftNFT) {
        flexNFT = NFTD(_nftNFT);
        treasurer = msg.sender;
        
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")),
            keccak256("NFT Developments Marketplace"),
            keccak256("1"),
            97,
            address(this)
        ));
        BUY_SALT = keccak256(bytes("List(uint256 nonce,address from,uint256 tokenID,uint256 price,bool isPremium)"));
        SELL_SALT = keccak256(bytes("Offer(uint256 nonce,address from,uint256 tokenID,uint256 price)"));
    }

    function buy(uint tokenId, address from, uint price, bool is_premium, bytes memory signature) external payable {
        address to = msg.sender;
        require(msg.value >= price, "insufficient price");
        require(flexNFT.ownerOf(tokenId) == from, "wrong owner");
        bytes32 digest = keccak256(abi.encodePacked(uint8(0x19), uint8(0x01), DOMAIN_SEPARATOR, keccak256(abi.encode(BUY_SALT, nonces[tokenId] ++, from, tokenId, price, uint256(is_premium ? 1: 0)))));
        address recoveredAddress = ECDSA.recover(digest, signature);
        require(recoveredAddress == from, "invalid signature");
        
        flexNFT.transferFrom(from, to, tokenId);
        uint feeValue;
        uint royaltyFee;
        
        if(is_premium) {
            feeValue = msg.value.mul(premium_fee).div(10000);
        } else {
            feeValue = msg.value.mul(fee).div(10000);
        }
        
        NFTD.Royalty memory royalty = flexNFT.getRoyalty(tokenId);
        if (royalty.fee > 0) royaltyFee = msg.value.mul(royalty.fee).div(10000);

        if (!profitable) {
            
            
            if(feeValue > 0) {
                address receiver = treasurer;
                if (whitelist[msg.sender]) receiver = msg.sender;
                payable(receiver).transfer(feeValue);
            }

        }

        else {
            uint256 toDev = feeValue * 600 / 1000;
            uint256 toProfit = feeValue - toDev;
            
            payable(devWallet).transfer(toDev);
            for (uint i; i < profits.length; i ++) {
                payable(flexNFT.ownerOf(profits[i])).transfer(toProfit/profits.length);
            }
        }

        if(royaltyFee > 0) payable(royalty.receiver).transfer(royaltyFee);

        payable(from).transfer(msg.value - feeValue - royaltyFee);
        
    }

    function sell(uint tokenId, address to, uint price, bool is_premium, bytes memory signature) external {
        address from = msg.sender;
        require(WBNB.balanceOf(to) >= price, "payer doesn't have enough price");
        require(flexNFT.ownerOf(tokenId) == from, "wrong owner");

        bytes32 digest = keccak256(abi.encodePacked(uint8(0x19), uint8(0x01), DOMAIN_SEPARATOR, keccak256(abi.encode(SELL_SALT, nonces[tokenId] ++, to, tokenId, price))));
        address recoveredAddress = ECDSA.recover(digest, signature);
        require(recoveredAddress == to, "invalid signature");
        flexNFT.transferFrom(from, to, tokenId);
        uint feeValue;
        uint royaltyFee;

        if(is_premium) {
            feeValue = price.mul(premium_fee).div(10000);
        } else {
            feeValue = price.mul(fee).div(10000);
        }
        
        NFTD.Royalty memory royalty = flexNFT.getRoyalty(tokenId);
        if (royalty.fee > 0) royaltyFee = price.mul(royalty.fee).div(10000);

        if (!profitable) {
            
            
            if(feeValue > 0) {
                address receiver = treasurer;
                if (whitelist[msg.sender]) receiver = msg.sender;
                WBNB.transferFrom(to, receiver, feeValue);
            }

        }

        else {
            uint256 toDev = feeValue * 600 / 1000;
            uint256 toProfit = feeValue - toDev;

            WBNB.transferFrom(to, devWallet, toDev);
            for (uint i; i < profits.length; i ++) {
                WBNB.transferFrom(to, flexNFT.ownerOf(profits[i]), toProfit/profits.length);

            }
        }

        if(royaltyFee > 0) WBNB.transferFrom(to, royalty.receiver, royaltyFee);

        WBNB.transferFrom(to, from, price - feeValue - royaltyFee);

    }

    function setFee(uint _fee, uint _premium_fee) external onlyOwner{
        fee = _fee;
        premium_fee = _premium_fee;
    }

    function setTresurer(address _treasurer) external onlyOwner{
        treasurer = _treasurer;
    }

    function addWhitelist(address[] memory account) external onlyOwner {
        require(account.length > 0, "empty list");
        for (uint256 i; i < account.length; i ++) {
            if (account[i] != address(0)) whitelist[account[i]] = true;
        }
    }

    function removeWhitelist(address[] memory account) external onlyOwner {
        require(account.length > 0, "empty list");
        for (uint256 i; i < account.length; i ++) {
            if (account[i] != address(0)) whitelist[account[i]] = false;
        }
    }

    function updateProfits(uint256[] calldata tokenIDs) external onlyOwner {
        require(tokenIDs.length > 0, "empty list");
        require(tokenIDs.length + profits.length <= 100, "exceed maximum");
        for (uint256 i = 0; i < tokenIDs.length; i ++) {
            require(flexNFT.ownerOf(tokenIDs[i]) != address(0), "no nft created");
            profitSet[tokenIDs[i]] = Profit(true, i);
        }
        profits = tokenIDs;
    }
        
    function updateDevWallet(address account) external onlyOwner {
        require(account != address(0), "invalid address");
        require(account != devWallet, "same address");
        devWallet = account;
    }

    function manageProfitable(bool status) external onlyOwner {
        profitable = status;
    }

    function getProfitable() external view onlyOwner returns(bool) {
        return profitable;
    }
}