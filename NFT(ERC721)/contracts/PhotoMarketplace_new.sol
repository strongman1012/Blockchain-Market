// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { NFTD } from "./NFTD.sol";

library ECRecovery {

  /**
   * @dev Recover signer address from a message by using his signature
   * @param hash bytes32 message, the hash is the signed message. What is recovered is the signer address.
   * @param sig bytes signature, the signature is generated using web3.eth.sign()
   */
  function recover(bytes32 hash, bytes memory sig) public pure returns (address) {
    bytes32 r;
    bytes32 s;
    uint8 v;

    //Check the signature length
    if (sig.length != 65) {
      return (address(0));
    }

    // Divide the signature in r, s and v variables
    assembly {
      r := mload(add(sig, 32))
      s := mload(add(sig, 64))
      v := byte(0, mload(add(sig, 96)))
    }

    // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
    if (v < 27) {
      v += 27;
    }

    // If the version is correct return the signer address
    if (v != 27 && v != 28) {
      return (address(0));
    } else {
      return ecrecover(hash, v, r, s);
    }
  }

}

contract Marketplaces {

    using SafeMath for uint256;

    string public constant salt = "NFTD MARKETPLACE";
    mapping(address => bool) public whitelist;
    mapping(address => uint) public nonces;

    NFTD public flexNFT;
    // IERC20 public WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); //mainnet weth
    IERC20 public WETH = IERC20(0xc778417E063141139Fce010982780140Aa0cD5Ab); //ropsten weth

    uint public fee = 250;  // 2.5%
    address public _market_owner;  //fee collector

    constructor(address _nftNFT, address market_owner_) {
        flexNFT = NFTD(_nftNFT);
        _market_owner = market_owner_;
    }

    modifier onlyOwner() {
        require(msg.sender == _market_owner, "account is not market owner");
        _;
    }

    function buy(uint tokenId, address from, uint price, bool is_premium, bytes memory signature) external payable {
        address to = msg.sender;
        require(msg.value >= price, "insufficient price");
        require(flexNFT.ownerOf(tokenId) == from, "wrong owner");
        bytes32 digest = keccak256(abi.encodePacked(salt, keccak256(abi.encodePacked(nonces[from] ++, from, tokenId, price, is_premium))));
        address recoveredAddress = ECRecovery.recover(digest, signature);
        require(recoveredAddress == from, "invalid signature");
        flexNFT.transferFrom(from, to, tokenId);
        uint feeValue;
        uint royaltyFee;
        NFTD.Royalty memory royalty = flexNFT.getRoyalty(tokenId);

        if(!whitelist[from]) {
          feeValue = msg.value.mul(fee).div(10000);
          if (royalty.fee > 0) royaltyFee = msg.value.mul(royalty.fee).div(10000);
        }
        if(feeValue > 0) payable(_market_owner).transfer(feeValue);
        if (royaltyFee > 0) payable(royalty.receiver).transfer(royaltyFee);
        payable(from).transfer(msg.value - feeValue - royaltyFee);
    }

    function sell(uint tokenId, address to, uint price, bytes memory signature) external {
        address from = msg.sender;
        require(WETH.balanceOf(to) >= price, "payer doen't have enough price");
        require(flexNFT.ownerOf(tokenId) == from, "wrong owner");
        bytes32 digest = keccak256(abi.encodePacked(salt, keccak256(abi.encodePacked(nonces[to] ++, to, tokenId, price))));
        address recoveredAddress = ECRecovery.recover(digest, signature);
        require(recoveredAddress == to, "invalid signature");
        flexNFT.transferFrom(from, to, tokenId);
        uint feeValue;
        uint royaltyFee;
        NFTD.Royalty memory royalty = flexNFT.getRoyalty(tokenId);

        if(!whitelist[from]) {
          feeValue = price.mul(fee).div(10000);
          if (royalty.fee > 0) royaltyFee = price.mul(royalty.fee).div(10000);
        }
        
        if(feeValue > 0) WETH.transferFrom(to, _market_owner, feeValue);
        if (royaltyFee > 0) WETH.transferFrom(to, royalty.receiver, royaltyFee);
        WETH.transferFrom(to, from, price - feeValue - royaltyFee);
    }

    function setWhitelist(address to, bool value) external onlyOwner{
        whitelist[to] = value;
    }

    function setFee(uint _fee) external onlyOwner{
        fee = _fee;
    }

    function setMarketOwner(address market_owner_) external onlyOwner{
        _market_owner = market_owner_;
    }
}