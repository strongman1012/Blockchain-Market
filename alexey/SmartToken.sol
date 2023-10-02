// SPDX-License-Identifier: MIT

/**
 * Smart Token
 * @author Liu
 */

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './libs/IBEP20.sol';
import './libs/TransferHelper.sol';
import './interfaces/IWETH.sol';
import './interfaces/IUniswapRouter.sol';
import './interfaces/IUniswapFactory.sol';
import './interfaces/IUniswapPair.sol';
import './interfaces/IGoldenTreePool.sol';
import './interfaces/ISmartArmy.sol';
import './interfaces/ISmartLadder.sol';
import './interfaces/ISmartFarm.sol';
import './interfaces/ISmartComp.sol';
import './interfaces/ISmartAchievement.sol';
import 'hardhat/console.sol';

contract SmartToken is Context, IBEP20, Ownable {
    using SafeMath for uint256;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    address public busdContract;
    address public _uniswapV2ETHPair;
    address public _uniswapV2BUSDPair;
    IUniswapV2Router02 public _uniswapV2Router;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public _operator; 
    address public _smartArmy;
    
    // tax addresses
    address public _referralAddress;
    address public _goldenTreePoolAddress;
    address public _devAddress;
    address public _achievementSystemAddress;
    address public _farmingRewardAddress;
    address public _intermediaryAddress;

    // Buy Tax information
    uint256 public _buyTaxFeeForUser = 15; // the % amount of buying amount when buying SMT token

    uint256 public _buyReferralFee = 50;
    uint256 public _buyGoldenPoolFee = 30;
    uint256 public _buyDevFee = 10;
    uint256 public _buyAchievementFee = 10;

    // Sell Tax information
    uint256 public _sellTaxFee = 15; // the % amount of selling amount when selling SMT token

    uint256 public _sellDevFee = 10;
    uint256 public _sellGoldenPoolFee = 30;
    uint256 public _sellFarmingFee = 20;
    uint256 public _sellBurnFee = 30;
    uint256 public _sellAchievementFee = 10;

    // Transfer Tax information
    uint256 public _transferTaxFee = 15; // the % amount of transfering amount when transfering SMT token

    uint256 public _transferDevFee = 10;
    uint256 public _transferAchievementFee = 10;
    uint256 public _transferGoldenFee = 50;
    uint256 public _transferFarmingFee = 30;

    uint256[] public _sellTaxTierDays = [10, 10, 10, 10];
    uint256[] public _sellTaxTiers    = [30, 25, 20, 15];
    uint256 private _start_timestamp = block.timestamp;

    uint256 public constant MAX_TOTAL_SUPPLY = 15000000 * 1e18;

    uint256 public _liquidityDist; // SMT-BNB liquidity distribution (locked)
    uint256 public _farmingRewardDist; // farming rewards distribution (locked)
    uint256 public _presaleDist; // presale distribution
    uint256 public _airdropDist; // airdrop distribution
    uint256 public _suprizeRewardsDist; // surprize rewards distribution (locked)
    uint256 public _chestRewardsDist; // chest rewards distribution (locked)
    uint256 public _devDist; // marketing & development distribution (unlocked)

    address[] public _whitelist;
    mapping(address => bool) mapEnabledWhitelist;

    bool _initialLiquidityLocked;
    bool _farmingRewardsLocked;
    bool _surprizeRewardsLocked;
    bool _chestRewardsLocked;

    uint256 public _tokenPriceByBusd = 15;
    uint256 public _busdDec = 10;

    uint256 public _tokenPriceByBNB = 25;
    uint256 public _bnbDec = 1000;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public _excludedFromFee;

    ISmartComp comptroller;

    bool _isSwap = false;

    event TaxAddressesUpdated(
        address indexed referral, 
        address indexed goldenTree, 
        address indexed dev, 
        address achievement, 
        address farming
    );

    event ExcludeFromFee(address indexed account, bool excluded);

    event UpdatedBuyFee(uint256 buyTaxFee);
    event UpdatedSellFee(uint256 sellTaxFee);
    event UpdatedTransferFee(uint256 transferTaxFee);

    event UpdatedBuyTaxFees(
        uint256 referralFee,
        uint256 goldenPoolFee,
        uint256 devFee,
        uint256 achievementFee        
    );
    event UpdatedSellTaxFees(
        uint256 devFee,
        uint256 goldenPoolFee,
        uint256 farmingFee,
        uint256 burnFee,
        uint256 achievementFee
    );
    event UpdatedTransferTaxFees(
        uint256 devFee,
        uint256 achievementFee,
        uint256 goldenPoolFee,
        uint256 farmingFee
    );

    event ResetedTimestamp(uint256 start_timestamp);

    event UpdatedGoldenTree(address indexed _address);
    event UpdatedSmartArmy(address indexed _address);

    event UpdatedLiquidityLocked(bool _enable);
    event UpdatedFarmingLocked(bool _enable);
    event UpdatedSurprizeLocked(bool _enable);
    event UpdatedChestLocked(bool _enable);

    event AddedWhitelist(uint256 lengthOfWhitelist);
    event UpdatedWhitelistAccount(address account, bool enable);

    modifier onlyOperator() {
        require(_operator == msg.sender || msg.sender == owner(), "SMT: caller is not the operator");
        _;
    }
    modifier liquidityLocked(uint256 amount) {
        require(
            _initialLiquidityLocked == false && _liquidityDist-amount > 0, 
            "Locked the amount for initial SMT-BNB liquidity."
        );
        _;
    }
    modifier farmingRewardsLocked(uint256 amount) {
        require(
            _farmingRewardsLocked == false && _farmingRewardDist-amount > 0, 
            "Locked the amount for farming rewards."
        );
        _;
    }
    modifier surprizeRewardsLocked(uint256 amount) {
        require(
            _surprizeRewardsLocked == false && _suprizeRewardsDist-amount > 0, 
            "Locked the amount for surprize rewards."
        );
        _;
    }
    modifier chestRewardsLocked(uint256 amount) {
        require(
            _chestRewardsLocked == false && _chestRewardsDist-amount > 0, 
            "Locked the amount for chest rewards."
        );
        _;
    }
    /**
     * @dev Sets the values for busdContract, {totalSupply} and tax addresses
     *
     */
    constructor(
        address referral,
        address goldenTree,
        address dev,
        address achievement, // passive global share
        address farming,
        address intermediary,
        address smartArmy,
        address smartComp,
        address airdrop
    ) {
        _name = "Smart Token";
        _symbol = "SMT";
        _decimals = 18;

        require(
            referral != address(0x0) 
            && goldenTree != address(0x0) 
            && dev != address(0x0) 
            && achievement != address(0x0) 
            && farming != address(0x0) 
            && intermediary != address(0x0) 
            && smartArmy != address(0x0)
            && smartComp != address(0x0) 
            && airdrop != address(0x0) , 
            "invalid address"
        );

        _operator = msg.sender;
        _referralAddress = referral;
        _goldenTreePoolAddress = goldenTree;
        _devAddress = dev;
        _achievementSystemAddress = achievement;
        _farmingRewardAddress = farming;
        _intermediaryAddress = intermediary;

        _smartArmy = smartArmy;

        comptroller = ISmartComp(smartComp);
        busdContract = address(comptroller.getBUSD());

        // 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3 // bsctestnet
        // Pancake V2 router
        _uniswapV2Router = ISmartComp(smartComp).getUniswapV2Router();

        // Create a pair with ETH
        _uniswapV2ETHPair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // Create a pair with BUSD
        _uniswapV2BUSDPair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), busdContract);

        _excludedFromFee[msg.sender] = true;
        _excludedFromFee[address(this)] = true;
        _excludedFromFee[BURN_ADDRESS] = true;
        _excludedFromFee[_referralAddress] = true;
        _excludedFromFee[_goldenTreePoolAddress] = true;
        _excludedFromFee[_devAddress] = true;
        _excludedFromFee[_achievementSystemAddress] = true;
        _excludedFromFee[_farmingRewardAddress] = true;
        _excludedFromFee[_smartArmy] = true;

        _liquidityDist = MAX_TOTAL_SUPPLY.div(10);
        _farmingRewardDist = MAX_TOTAL_SUPPLY.div(1000).mul(383);
        _presaleDist = MAX_TOTAL_SUPPLY.div(10).mul(3);
        _airdropDist = MAX_TOTAL_SUPPLY.div(1000).mul(5);
        _suprizeRewardsDist = MAX_TOTAL_SUPPLY.div(100).mul(9);
        _chestRewardsDist = MAX_TOTAL_SUPPLY.div(1000).mul(121);
        _devDist = MAX_TOTAL_SUPPLY.div(1000);

        _mint(airdrop, _airdropDist);
        _mint(dev, _devDist);
    }

    function getOwner() external override view returns (address) {
        return owner();
    }

    function getETHPair() external view returns (address) {
        return _uniswapV2ETHPair;
    }

    function getBUSDPair() external view returns (address) {
        return _uniswapV2BUSDPair;
    }

    function name() external override view returns (string memory) {
        return _name;
    }

    function symbol() external override view returns (string memory) {
        return _symbol;
    }

    function decimals() external override view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external override view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external override view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transferFrom(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender, 
        address recipient, 
        uint256 amount
    ) public virtual override returns (bool) {
        _transferFrom(sender, recipient, amount);
        if(recipient != _msgSender() && sender != _msgSender()){
            _approve(
                sender,
                _msgSender(),
                _allowances[sender][_msgSender()].sub(amount, 'SMT: transfer amount exceeds allowance')
            );
        }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, 'SMT: decreased allowance below zero'));
        return true;
    }

    function _transferFrom(
        address sender, 
        address recipient, 
        uint256 amount
    ) internal virtual {
        require(sender != address(0), 'SMT: transfer from the zero address');
        require(recipient != address(0), 'SMT: transfer to the zero address');
        require(_balances[sender] >= amount, "SMT: balance of sender is too small.");

        // _transfer(sender, recipient, amount);
        if (_isSwap || _excludedFromFee[sender] || _excludedFromFee[recipient]) {
            // console.log("<<<<<<<<< main transfer <<<<<<<<<<");
            _transfer(sender, recipient, amount);
        } else {
            bool toPair = recipient == _uniswapV2ETHPair || recipient == _uniswapV2BUSDPair;
            bool fromPair = sender == _uniswapV2ETHPair || sender == _uniswapV2BUSDPair;
            if(sender == _intermediaryAddress && toPair) {
                // Intermediary => Pair: No Fee
                // console.log("<<<<<<<<< intermediary sell transfer <<<<<<<<<<");
                uint256 taxAmount = amount.mul(10).div(100);
                uint256 recvAmount = amount.sub(taxAmount);                
                distributeSellTax(sender, taxAmount);
                _transfer(sender, recipient, recvAmount);
            } else if(fromPair && recipient == _intermediaryAddress) {
                // Pair => Intermediary: No Fee
                // console.log("<<<<<<<<< intermediary buy transfer <<<<<<<<<<");
                uint256 taxAmount = amount.mul(10).div(100);
                uint256 recvAmount = amount.sub(taxAmount);                
                distributeBuyTax(sender, recipient, taxAmount);
                _transfer(sender, recipient, recvAmount);
            } else if(sender == _intermediaryAddress || recipient == _intermediaryAddress) {
                // console.log("<<<<<<<<< intermediary normal transfer <<<<<<<<<<");
                if (recipient == _intermediaryAddress) {
                    require(enabledIntermediary(sender), "SMT: no smart army account");
                    // sell transfer via intermediary: sell tax reduce 30%
                    uint256 taxAmount = _getCurrentSellTax().mul(700).div(1000).div(100);
                    uint256 recvAmount = amount.sub(taxAmount);
                    distributeSellTax(sender, taxAmount);
                    _transfer(sender, recipient, recvAmount);
                } else {
                    require(enabledIntermediary(recipient), "SMT: no smart army account");
                    // buy transfer via intermediary: buy tax reduce 30%
                    uint256 taxAmount = amount.mul(_buyTaxFeeForUser.mul(700).div(1000)).div(100);
                    uint256 recvAmount = amount.sub(taxAmount);                    
                    distributeBuyTax(sender, recipient, taxAmount);
                    _transfer(sender, recipient, recvAmount);
                }
            } else if (fromPair) {
                // buy transfer
                // console.log("<<<<<<<<< buy transfer <<<<<<<<<<");
                uint256 taxAmount = amount.mul(15).div(100);
                uint256 recvAmount = amount.sub(taxAmount);
                distributeBuyTax(sender, recipient, taxAmount);
                _transfer(sender, recipient, recvAmount);
            } else if (toPair) {
                // sell transfer 
                // console.log("<<<<<<<<< sell transfer <<<<<<<<<<");
                uint256 taxAmount = amount.mul(15).div(100);
                uint256 recvAmount = amount.sub(taxAmount);
                distributeSellTax(sender, taxAmount);
                _transfer(sender, recipient, recvAmount);
            } else {
                // normal transfer
                // console.log("<<<<<<<<< normal transfer <<<<<<<<<<");
                uint256 taxAmount = amount.mul(15).div(100);
                uint256 recvAmount = amount.sub(taxAmount);  
                distributeTransferTax(sender, taxAmount);
                _transfer(sender, recipient, recvAmount);
            }
        }
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        require(_balances[_from] - _amount >= 0, "amount exceeds current balance");
        _balances[_to] += _amount;
        _balances[_from] -= _amount;
        emit Transfer(_from, _to, _amount);
    }

    function _transferToGoldenTreePool(address _sender, uint256 amount) internal {
        IERC20 busd = comptroller.getBUSD();
        _transfer(_sender, address(this), amount);
        _swapTokenForBUSD(amount);
        uint256 _amount = busd.balanceOf(address(this));
        if(_amount > 0)
            busd.transfer(_goldenTreePoolAddress, _amount);
    }

    function _transferToAchievement(address _sender, uint256 amount) internal {        
        _transfer(_sender, address(this), amount);
        _swapTokenForBNB(amount);
        uint256 _amount = payable(address(this)).balance;
        if(_amount > 0) {
            payable(_achievementSystemAddress).send(_amount);
        }
    }

    function distributeSellTax (
        address sender,
        uint256 amount
    ) internal {

        uint256 devAmount = amount.mul(_sellDevFee).div(100);
        uint256 goldenTreeAmount = amount.mul(_sellGoldenPoolFee).div(100);
        uint256 farmingAmount = amount.mul(_sellFarmingFee).div(100);
        uint256 burnAmount = amount.mul(_sellBurnFee).div(100);
        uint256 achievementAmount = amount.mul(_sellAchievementFee).div(100);

        _transfer(sender, _devAddress, devAmount);
        _transfer(sender, _farmingRewardAddress, farmingAmount);
        _transfer(sender, BURN_ADDRESS, burnAmount);
        // _transferToGoldenTreePool(sender, goldenTreeAmount);
        // _transferToAchievement(sender, achievementAmount);

        _transfer(sender, _achievementSystemAddress, achievementAmount);
        _transfer(sender, _goldenTreePoolAddress, goldenTreeAmount);

        // distributeTaxToGoldenTreePool(sender, goldenTreeAmount);

        // if(farmingAmount > 0) {
        //     distributeSellTaxToFarming(farmingAmount);
        // }
    }

    /**
     * @dev Distributes buy tax tokens to tax addresses
    */

    function distributeBuyTax(
        address sender,
        address recipient,
        uint256 amount
    ) internal {

        uint256 referralAmount = amount.mul(_buyReferralFee).div(100);
        uint256 goldenTreeAmount = amount.mul(_buyGoldenPoolFee).div(100);
        uint256 devAmount = amount.mul(_buyDevFee).div(100);
        uint256 achievementAmount = amount.mul(_buyAchievementFee).div(100);

        _transfer(sender, _devAddress, devAmount);
        _transfer(sender, _referralAddress, referralAmount);
        _transfer(sender, _achievementSystemAddress, achievementAmount);
        _transfer(sender, _goldenTreePoolAddress, goldenTreeAmount);

        // _transferToGoldenTreePool(sender, goldenTreeAmount);
        // _transferToAchievement(sender, achievementAmount);

        // distributeBuyTaxToLadder(recipient);
        // distributeTaxToGoldenTreePool(recipient, goldenTreeAmount);
    }

    /**
     * @dev Distributes transfer tax tokens to tax addresses
     */

    function distributeTransferTax(
        address sender,
        uint256 amount
    ) internal {
        uint256 devAmount = amount.mul(_transferDevFee).div(100);
        uint256 farmingAmount = amount.mul(_transferFarmingFee).div(100);
        uint256 goldenTreeAmount = amount.mul(_transferGoldenFee).div(100);
        uint256 achievementAmount = amount.mul(_transferAchievementFee).div(100);

        _transfer(sender, _devAddress, devAmount);
        _transfer(sender, _farmingRewardAddress, farmingAmount);
        _transfer(sender, _goldenTreePoolAddress, goldenTreeAmount);
        _transfer(sender, _achievementSystemAddress, achievementAmount);

        // _transferToGoldenTreePool(sender, goldenTreeAmount);
        // _transferToAchievement(sender, achievementAmount);

        // distributeTaxToGoldenTreePool(sender, goldenTreeAmount);
    } 

    /**
     * @dev Distributes buy tax tokens to smart ladder system
     */
    function distributeBuyTaxToLadder (address from) internal {
        ISmartLadder(_referralAddress).distributeBuyTax(from);
    } 

    /**
     * @dev Distributes sell tax tokens to farmming passive rewards pool
     */
    function distributeSellTaxToFarming (uint256 amount) internal {
        ISmartFarm(_farmingRewardAddress).notifyRewardAmount(amount);
    } 

    /**
     * @dev Distribute tax to golden Tree pool as SMT and notify
     */
    function distributeTaxToGoldenTreePool (address account, uint256 amount) internal {
        IGoldenTreePool(_goldenTreePoolAddress).notifyReward(amount, account);
    }

    function _mint(address account, uint256 amount) private {
        require(account != address(0), 'SMT: mint to the zero address');
        require(_totalSupply + amount <= MAX_TOTAL_SUPPLY, "exceeds maximum total supply");
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _mintForLiquidity(address account, uint256 amount) 
        external onlyOperator liquidityLocked(amount)
    {
        _mint(account, amount);
        _liquidityDist = _liquidityDist.sub(amount);
    }

    function _mintForFarmingPool(address account, uint256 amount)
        external onlyOperator farmingRewardsLocked(amount)
    {
        _mint(account, amount);
        _farmingRewardDist = _farmingRewardDist.sub(amount);
    }

    function _mintForPresale(address account, uint256 amount)
        internal
    {
        require(_presaleDist.sub(amount) >= 0, "the amount to be minted exceeds maximum presale amount");
        _mint(account, amount);
        _presaleDist = _presaleDist.sub(amount);
    }

    function _mintForAirdrop(address account, uint256 amount)
        external onlyOperator
    {
        require(_presaleDist.sub(amount) >= 0, "the amount to be minted exceeds maximum presale amount");
        _mint(account, amount);
        _airdropDist = _airdropDist.sub(amount);
    }

    function _mintForSurprizeReward(address account, uint256 amount)
        external onlyOperator surprizeRewardsLocked(amount)
    {
        _mint(account, amount);
        _suprizeRewardsDist = _suprizeRewardsDist.sub(amount);
    }

    function _mintForChestReward(address account, uint256 amount)
        external onlyOperator chestRewardsLocked(amount)
    {
        _mint(account, amount);
        _chestRewardsDist = _chestRewardsDist.sub(amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), 'SMT: approve from the zero address');
        require(spender != address(0), 'SMT: approve to the zero address');

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Returns the address is excluded from burn fee or not.
     */
    function isExcludedFromFee (address account) external view returns (bool) {
        return _excludedFromFee[account];
    }

    /**
     * @dev Exclude the address from fee.
     */
    function excludeFromFee (address account, bool excluded) external onlyOperator {
        require(_excludedFromFee[account] != excluded, "SMT: already excluded or included");
        _excludedFromFee[account] = excluded;

        emit ExcludeFromFee(account, excluded);
    }    

    /**
     * @dev Sets value for _sellTaxFee with {sellTaxFee} in emergency status.
     */
    function setSellFee (uint256 sellTaxFee) external onlyOperator {
        require(sellTaxFee < 100, 'SMT: sellTaxFee exceeds maximum value');
        _sellTaxFee = sellTaxFee;

        emit UpdatedSellFee(sellTaxFee);
    }    

    /**
     * @dev Sets value for _buyTaxFeeForUser with {buyTaxFee} in emergency status.
     */
    function setBuyFee(uint256 buyTaxFee) external onlyOperator {
        require(buyTaxFee < 100, 'SMT: buyTaxFee exceeds maximum value');
        _buyTaxFeeForUser = buyTaxFee;

        emit UpdatedBuyFee(buyTaxFee);
    }    

    /**
     * @dev Sets value for _transferTaxFee with {transferTaxFee} in emergency status.
     */
    function setTransferFee (uint256 transferTaxFee) external onlyOperator {
        require(transferTaxFee < 100, 'SMT: transferTaxFee exceeds maximum value');
        _transferTaxFee = transferTaxFee;

        emit UpdatedTransferFee(transferTaxFee);
    }  

    function getEventFees() external view returns(
        uint256 buyFee, 
        uint256 sellFee, 
        uint256 transferFee
    ){
        return (_buyTaxFeeForUser, _sellTaxFee, _transferTaxFee);
    }

    function getBuyTaxFees() external view returns(
        uint256 referralFee, 
        uint256 goldenPoolFee, 
        uint256 devFee,
        uint256 achievementFee
    ){
        return (
            _buyReferralFee, 
            _buyGoldenPoolFee, 
            _buyDevFee, 
            _buyAchievementFee
        );
    }

    function getSellTaxFees() external view returns(
        uint256 devFee, 
        uint256 goldenPoolFee, 
        uint256 farmingFee,
        uint256 burnFee,
        uint256 achievementFee
    ){
        return (
            _sellDevFee, 
            _sellGoldenPoolFee, 
            _sellFarmingFee, 
            _sellBurnFee, 
            _sellAchievementFee
        );
    }

    function getTransferTaxFees() external view returns(
        uint256 devFee, 
        uint256 achievementFee,
        uint256 goldenPoolFee, 
        uint256 farmingFee
    ){
        return (
            _transferDevFee,
            _transferAchievementFee,
            _transferGoldenFee,
            _transferFarmingFee
        );
    }

    /**
     * @dev start Sell Tax tier system again 
     */
    function resetStartTimestamp() external onlyOperator {
        _start_timestamp = block.timestamp;

        emit ResetedTimestamp(_start_timestamp);
    }   

    /**
     * @dev get current sellTax percent through sell tax tier system
     */
    function _getCurrentSellTax() public view returns (uint256) {
        uint256 time_since_start = block.timestamp - _start_timestamp;
        for(uint i = 0; i < _sellTaxTierDays.length; i++) {
            if(time_since_start < _sellTaxTierDays[i] * 24 * 3600) {
                return _sellTaxTiers[i];
            }
        }
        return _sellTaxFee;
    }   

    /**
     *  @dev Sets buying tax fees
    */
    function setBuyTaxFees(
        uint256 referralFee,
        uint256 goldenPoolFee,
        uint256 devFee,
        uint256 achievementFee
    ) external onlyOperator {
        _buyReferralFee = referralFee;
        _buyGoldenPoolFee = goldenPoolFee;
        _buyDevFee = devFee;
        _buyAchievementFee = achievementFee;
        emit UpdatedBuyTaxFees(referralFee, goldenPoolFee, devFee, achievementFee);
    }

    /**
     *  @dev Sets selling tax fees
    */
    function setSellTaxFees(
        uint256 devFee,
        uint256 goldenPoolFee,
        uint256 farmingFee,
        uint256 burnFee,
        uint256 achievementFee
    ) external onlyOperator {
        _sellDevFee = devFee;
        _sellGoldenPoolFee = goldenPoolFee;
        _sellFarmingFee = farmingFee;
        _sellBurnFee = burnFee;
        _sellAchievementFee = achievementFee;
        emit UpdatedSellTaxFees(devFee, goldenPoolFee, farmingFee, burnFee, achievementFee);
    }

    /**
     *  @dev Sets buying tax fees
    */
    function setTransferTaxFees(
        uint256 devFee,
        uint256 achievementFee,
        uint256 goldenPoolFee,
        uint256 farmingFee
    ) external onlyOperator {
        _transferDevFee = devFee;
        _transferAchievementFee = achievementFee;
        _transferGoldenFee = goldenPoolFee;
        _transferFarmingFee = farmingFee;
        emit UpdatedTransferTaxFees(devFee, achievementFee, goldenPoolFee, farmingFee);
    }

    /**
     *  @dev Sets values for tax addresses 
     */
    function setTaxAddresses (
        address referral, 
        address goldenTree, 
        address dev, 
        address achievement, 
        address farming, 
        address intermediary
    ) external onlyOperator {

        if (_referralAddress != referral && referral != address(0x0)) {
            _excludedFromFee[_referralAddress] = false;
            _referralAddress = referral;
            _excludedFromFee[referral] = true;
        }
        if (_goldenTreePoolAddress != goldenTree && goldenTree != address(0x0)) {
            _excludedFromFee[_goldenTreePoolAddress] = false;
            _goldenTreePoolAddress = goldenTree;
            _excludedFromFee[goldenTree] = true;
        }
        if (_devAddress != dev && dev != address(0x0)) {
            _excludedFromFee[_devAddress] = false;
            _devAddress = dev;
            _excludedFromFee[dev] = true;
        }
        if (_achievementSystemAddress != achievement && achievement != address(0x0)) {
            _excludedFromFee[_achievementSystemAddress] = false;
            _achievementSystemAddress = achievement;
            _excludedFromFee[achievement] = true;
        }
        if (_farmingRewardAddress != farming && farming != address(0x0)) {
            _excludedFromFee[_farmingRewardAddress] = false;
            _farmingRewardAddress = farming;
            _excludedFromFee[farming] = true;
        }
        if (_intermediaryAddress != intermediary && intermediary != address(0x0)) {
            _intermediaryAddress = intermediary;
        }
        emit TaxAddressesUpdated(referral, goldenTree, dev, achievement, farming);
    }

    /**
     * @dev Sets value for _goldenTreePoolAddress
     */
    function setGoldenTreeAddress (address _address) external onlyOperator {
        require(_address!= address(0x0), 'SMT: not allowed zero address');
        _goldenTreePoolAddress = _address;

        emit UpdatedGoldenTree(_address);
    }

    /**
     * @dev Sets value for _smartArmy
     */
    function setSmartArmyAddress (address _address) external onlyOperator {
        require(_address!= address(0x0), 'SMT: not allowed zero address');
        _smartArmy = _address;

        emit UpdatedSmartArmy(_address);
    }
    
    function setInitialLiquidity(bool lockStatus) external onlyOperator {
        _initialLiquidityLocked = lockStatus;
        emit UpdatedLiquidityLocked(lockStatus);
    }

    function setFarmingRewards(bool lockStatus) external onlyOperator {
        _farmingRewardsLocked = lockStatus;
        emit UpdatedFarmingLocked(lockStatus);
    }

    function setSurprizeRewards(bool lockStatus) external onlyOperator {
        _surprizeRewardsLocked = lockStatus;
        emit UpdatedSurprizeLocked(lockStatus);
    }

    function setChestRewards(bool lockStatus) external onlyOperator {
        _chestRewardsLocked = lockStatus;
        emit UpdatedChestLocked(lockStatus);
    }    

    function enabledIntermediary (address account) public view returns(bool){
        if(_smartArmy == address(0x0)) {
            return false;
        }
        return ISmartArmy(_smartArmy).isEnabledIntermediary(account);
    }

    function getAmountFromBUSD(uint256 amount) public view returns(uint256){
        return amount.div(_tokenPriceByBusd).mul(_busdDec);
    }

    function getAmountFromBNB(uint256 amount) public view returns(uint256){
        return amount.div(_tokenPriceByBNB).mul(_bnbDec);
    }

    function buyTokenWithBNB() external payable {
        address payable sender = payable(msg.sender);
        uint256 _amount = getAmountFromBNB(msg.value);
        require(
            sender.balance >= msg.value, 
            "balance is too small, you can't pay for minting."
        );
        _mintForPresale(msg.sender, _amount);
        payable(_operator).transfer(msg.value);
    }

    function buyTokenWithBUSD(uint256 amount) external {
        // require(existInWhitelist(to), "this address have to become whitelist");
        IERC20 busd = IERC20(busdContract);        
        uint256 amountIn = amount.mul(1e18);
        uint256 allow = busd.allowance(msg.sender, address(this));
        uint256 _amount = getAmountFromBUSD(amountIn);
        require(allow >= amountIn, "cost is the smaller than allowed amount");
        require(busd.balanceOf(msg.sender) >= amountIn, "balance is too small, you can't pay for minting.");
        _mintForPresale(msg.sender, _amount);
        busd.transferFrom(msg.sender, _operator, amountIn);
    }

    function buyTokenWithHelper(uint256 amount) external {
        IERC20 busd = IERC20(busdContract);
        uint256 amountIn = amount.mul(1e18);
        uint256 _amount = getAmountFromBUSD(amountIn);
        require(busd.balanceOf(msg.sender) >= amount, "balance is too small, you can't pay for minting.");        
        _mintForPresale(msg.sender, _amount);
        TransferHelper.safeTransfer(address(busd), _operator, amountIn);
    }

    function addAccountToWhitelist(address[] memory accounts) 
        external onlyOperator 
    {
        uint256 counter = 0;
        for(uint256 i=0; i<accounts.length; i++){
            if(accounts[i] != address(0x0)){
                _whitelist.push(accounts[i]); counter++;
            }
        }
        emit AddedWhitelist(accounts.length);
    }

    function enableWhitelistAccount(address account, bool _enable) 
        external onlyOperator 
    {
        mapEnabledWhitelist[account] = _enable;
        emit UpdatedWhitelistAccount(account, _enable);
    }

    function getEnabledAccounts() public view returns(address[] memory) {
        address[] memory availables;
        uint256 cn = 0;
        for(uint256 i=0; i<_whitelist.length; i++){
            if(_whitelist[i] != address(0x0) 
                && !mapEnabledWhitelist[_whitelist[i]]) {
                    availables[cn++] = _whitelist[i];
            }
        }
        return availables;
    }

    function existInWhitelist(address account) public view returns(bool) {
        bool exist = false;
        for(uint256 i=0; i<_whitelist.length; i++){
            if(_whitelist[i] != address(0x0) 
                && !mapEnabledWhitelist[_whitelist[i]]) {
                if(_whitelist[i] == account){
                    exist == true;
                    break;
                }
            }
        }
        return exist;
    }

    function _swapTokenForBUSD(uint256 tokenAmount) private {
        _isSwap = true;
        IERC20 busdToken = comptroller.getBUSD();
        IUniswapV2Router02 uniswapV2Router = comptroller.getUniswapV2Router();

        // generate the uniswap pair path of token -> busd
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(busdToken);

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        _isSwap = false;
    }

    function _swapTokenForBNB(uint256 tokenAmount) private {
        _isSwap = true;
        IUniswapV2Router02 uniswapV2Router = comptroller.getUniswapV2Router();

        // generate the uniswap pair path of token -> busd
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(uniswapV2Router.WETH());

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        _isSwap = false;
    }

     //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}
}

