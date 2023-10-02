// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract EmpireToken is Context, IERC20, Ownable {
    using Address for address;

    address public bridge;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public automatedMarketMakerPairs;

    mapping(address => bool) private _isExcludedFromFee;

    mapping(address => bool) private _isExcluded;
    address[] private _excluded;

    struct BuyFee {
        uint256 autoLp;
        uint256 burn;
        uint256 marketing;
        uint256 tax;
        uint256 team;
    }

    struct SellFee {
        uint256 autoLp;
        uint256 burn;
        uint256 marketing;
        uint256 tax;
        uint256 team;
    }

    BuyFee public buyFee;
    SellFee public sellFee;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1000000000 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private constant _name = "EmpireToken";
    string private constant _symbol = "EMPIRE";
    uint8 private constant _decimals = 9;

    uint256 public _taxFee;
    uint256 public _liquidityFee;
    uint256 public _burnFee;
    uint256 public _marketingFee;
    uint256 public _teamFee;

    address payable public marketingWallet;
    address public burnWallet;
    address public liquidityWallet;
    address public teamWallet;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    bool public isTradingEnabled;

    uint256 private numTokensSellToAddToLiquidity = 8000 * 10**9;

    event LogSetAutomatedMarketMakerPair(
        address indexed setter,
        address pair,
        bool enabled
    );
    event LogSwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event LogSwapAndDistribute(
        uint256 forLiquidity,
        uint256 forBurn,
        uint256 forTeam
    );
    event LogSwapAndLiquifyEnabledUpdated(address indexed setter, bool enabled);
    event LogSetBridge(address indexed setter, address bridge);
    event LogSetSwapTokensAmount(address indexed setter, uint256 amount);
    event LogSetExcludeFromFee(
        address indexed setter,
        address account,
        bool enabled
    );
    event LogSetEnableTrading(bool enabled);
    event LogSetMarketingWallet(
        address indexed setter,
        address marketingWallet
    );
    event LogSetBurnWallet(address indexed setter, address burnWallet);
    event LogSetTeamWallet(address indexed setter, address teamWallet);
    event LogSetBuyFees(address indexed setter, BuyFee buyFee);
    event LogSetSellFees(address indexed setter, SellFee sellFee);
    event LogSetRouterAddress(address indexed setter, address router);
    event LogSetPairAddress(address indexed setter, address pair);
    event LogUpdateGasForProcessing(address indexed setter, uint256 value);
    event LogUpdateLiquidityWallet(
        address indexed setter,
        address liquidityWallet
    );
    event LogWithdrawalBNB(address indexed account, uint256 amount);
    event LogWithdrawToken(
        address indexed token,
        address indexed account,
        uint256 amount
    );
    event LogWithdrawal(address indexed account, uint256 tAmount);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(address payable _marketingWallet, address payable _teamWallet) {
        _rOwned[_msgSender()] = _rTotal;

        marketingWallet = _marketingWallet;
        burnWallet = address(0xdead);
        liquidityWallet = owner();
        teamWallet = _teamWallet;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            // Bsc Mainnet
            // 0x10ED43C718714eb63d5aA57B78B54704E256024E
            // Bsc Testnet
            // 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
            // Ethereum Mainnet
            // Ropsten
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[owner()] = true;

        _isExcludedFromFee[address(uniswapV2Router)] = true;
        buyFee.tax = 2;
        sellFee.tax = 6;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function setAutomatedMarketMakerPair(address pair, bool enabled)
        external
        onlyOwner
    {
        automatedMarketMakerPairs[pair] = enabled;

        emit LogSetAutomatedMarketMakerPair(msg.sender, pair, enabled);
    }

    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _tTotal;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative). Referenced from SafeMath library to preserve transaction integrity.
     */
    function balanceCheck(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            balanceCheck(
                _allowances[sender][_msgSender()],
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            balanceCheck(
                _allowances[_msgSender()][spender],
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcludedFromReward(address account)
        external
        view
        returns (bool)
    {
        return _isExcluded[account];
    }

    function totalFees() external view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) external {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _rTotal = _rTotal - rAmount;
        _tFeeTotal = _tFeeTotal + tAmount;
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        external
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    function excludeFromReward(address account) external onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    //to recieve ETH from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity,
            uint256 tMarketing,
            uint256 tBurn
        ) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            tLiquidity,
            tMarketing,
            tBurn,
            _getRate()
        );
        return (
            rAmount,
            rTransferAmount,
            rFee,
            tTransferAmount,
            tFee,
            tLiquidity
        );
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tMarketing = calculateMarketingFee(tAmount);
        uint256 tBurn = calculateBurnFee(tAmount);
        uint256 tTeam = calculateTeamFee(tAmount);
        uint256 tTransferAmount = tAmount - (tFee + tLiquidity);
        tTransferAmount = tTransferAmount - (tMarketing + tBurn + tTeam);
        return (tTransferAmount, tFee, tLiquidity, tMarketing, tBurn);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tLiquidity,
        uint256 tMarketing,
        uint256 tBurn,
        uint256 currentRate
    )
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount * currentRate;
        uint256 rFee = tFee * currentRate;
        uint256 rLiquidity = tLiquidity * currentRate;
        uint256 rMarketing = tMarketing * currentRate;
        uint256 rBurn = tBurn * currentRate;
        uint256 tTeam = calculateTeamFee(tAmount);
        uint256 rTeam = tTeam * currentRate;
        uint256 rTransferAmount = rAmount -
            (rFee + rLiquidity + rMarketing + rBurn + rTeam);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply - _rOwned[_excluded[i]];
            tSupply = tSupply - _tOwned[_excluded[i]];
        }
        if (rSupply < (_rTotal / _tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate = _getRate();
        uint256 rLiquidity = tLiquidity * currentRate;
        _rOwned[address(this)] = _rOwned[address(this)] + rLiquidity;
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)] + tLiquidity;
    }

    function _takeTeam(uint256 tTeam) private {
        uint256 currentRate = _getRate();
        uint256 rTeam = tTeam * currentRate;
        _rOwned[address(this)] = _rOwned[address(this)] + rTeam;
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)] + tTeam;
    }

    function _takeMarketingAndBurn(uint256 tMarketing, uint256 tBurn) private {
        uint256 currentRate = _getRate();
        uint256 rMarketing = tMarketing * currentRate;
        uint256 rBurn = tBurn * currentRate;
        _rOwned[address(this)] = _rOwned[address(this)] + (rBurn + rMarketing);
        if (_isExcluded[address(this)])
            _tOwned[address(this)] =
                _tOwned[address(this)] +
                (tMarketing + tBurn);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return (_amount * _taxFee) / 10**2;
    }

    function calculateLiquidityFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return (_amount * _liquidityFee) / 10**2;
    }

    function calculateBurnFee(uint256 _amount) private view returns (uint256) {
        return (_amount * _burnFee) / 10**2;
    }

    function calculateMarketingFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return (_amount * _marketingFee) / 10**2;
    }

    function calculateTeamFee(uint256 _amount) private view returns (uint256) {
        return (_amount * _teamFee) / 10**2;
    }

    function restoreAllFee() private {
        _taxFee = 0;
        _liquidityFee = 0;
        _marketingFee = 0;
        _burnFee = 0;
        _teamFee = 0;
    }

    function setBuyFee() private {
        _taxFee = buyFee.tax;
    }

    function setSellFee() private {
        _taxFee = sellFee.tax;
    }

    function setEnableTrading(bool enable) external onlyOwner {
        isTradingEnabled = enable;

        emit LogSetEnableTrading(isTradingEnabled);
    }

    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        uint256 contractTokenBalance = balanceOf(address(this));
        bool overMinTokenBalance = contractTokenBalance >=
            numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            !automatedMarketMakerPairs[from] &&
            swapAndLiquifyEnabled &&
            from != liquidityWallet &&
            to != liquidityWallet
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;

            swapAndDistribute(contractTokenBalance);
        }

        //transfer amount, it will take tax, Burn, liquidity fee
        _tokenTransfer(from, to, amount);
    }

    function swapAndDistribute(uint256 contractTokenBalance)
        private
        lockTheSwap
    {
        uint256 total = buyFee.tax + sellFee.tax;

        uint256 forLiquidity = contractTokenBalance  / total;
        swapAndLiquify(forLiquidity);

        uint256 forBurn = contractTokenBalance / total;
        sendToBurn(forBurn);

        uint256 forTeam = (contractTokenBalance *
            (buyFee.team + sellFee.team)) / total;
        sendToTeam(forTeam);

        emit LogSwapAndDistribute(forLiquidity, forBurn, forTeam);
    }

    function sendToBurn(uint256 tBurn) private {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn * currentRate;

        _rOwned[burnWallet] = _rOwned[burnWallet] + rBurn;
        _rOwned[address(this)] = _rOwned[address(this)] - rBurn;

        if (_isExcluded[burnWallet])
            _tOwned[burnWallet] = _tOwned[burnWallet] + tBurn;

        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)] - tBurn;

        emit Transfer(address(this), burnWallet, tBurn);
    }

    function sendToTeam(uint256 tTeam) private {
        uint256 currentRate = _getRate();
        uint256 rTeam = tTeam * currentRate;

        _rOwned[teamWallet] = _rOwned[teamWallet] + rTeam;
        _rOwned[address(this)] = _rOwned[address(this)] - rTeam;

        if (_isExcluded[teamWallet])
            _tOwned[teamWallet] = _tOwned[teamWallet] + tTeam;

        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)] - tTeam;

        emit Transfer(address(this), teamWallet, tTeam);
    }

    function sendToMarketing(uint256 tMarketing) private {
        uint256 currentRate = _getRate();
        uint256 rMarketing = tMarketing * currentRate;

        _rOwned[marketingWallet] = _rOwned[marketingWallet] + rMarketing;
        _rOwned[address(this)] = _rOwned[address(this)] - rMarketing;

        if (_isExcluded[marketingWallet])
            _tOwned[marketingWallet] = _tOwned[marketingWallet] + tMarketing;

        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)] - tMarketing;

        emit Transfer(address(this), marketingWallet, tMarketing);
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        uint256 initialBalance = address(this).balance;

        swapTokensForETH(half);

        uint256 newBalance = address(this).balance - initialBalance;

        addLiquidity(otherHalf, newBalance);

        emit LogSwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityWallet,
            block.timestamp
        );
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient]) {
            require(isTradingEnabled, "Trading is disabled");

            if (automatedMarketMakerPairs[sender] == true) {
                setBuyFee();
            } else if (automatedMarketMakerPairs[recipient] == true) {
                setSellFee();
            }
        }

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        restoreAllFee();
    }

    function _takeFee(
        address sender,
        uint256 tAmount,
        uint256 tLiquidity,
        uint256 tTransferAmount,
        uint256 tFee,
        uint256 rFee
    ) private {
        _takeLiquidity(tLiquidity);
        _takeMarketingAndBurn(
            calculateMarketingFee(tAmount),
            calculateBurnFee(tAmount)
        );
        _takeTeam(calculateTeamFee(tAmount));
        _reflectFee(rFee, tFee);

        emit Transfer(sender, address(this), tAmount - tTransferAmount - tFee);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        _takeLiquidity(tLiquidity);
        _takeMarketingAndBurn(
            calculateMarketingFee(tAmount),
            calculateBurnFee(tAmount)
        );
        _takeTeam(calculateTeamFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _tOwned[recipient] = _tOwned[recipient] + tTransferAmount;
        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        _takeLiquidity(tLiquidity);
        _takeMarketingAndBurn(
            calculateMarketingFee(tAmount),
            calculateBurnFee(tAmount)
        );
        _takeTeam(calculateTeamFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender] - tAmount;
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        _takeLiquidity(tLiquidity);
        _takeMarketingAndBurn(
            calculateMarketingFee(tAmount),
            calculateBurnFee(tAmount)
        );
        _takeTeam(calculateTeamFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender] - tAmount;
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _tOwned[recipient] = _tOwned[recipient] + tTransferAmount;
        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        _takeLiquidity(tLiquidity);
        _takeMarketingAndBurn(
            calculateMarketingFee(tAmount),
            calculateBurnFee(tAmount)
        );
        _takeTeam(calculateTeamFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function setExcludeFromFee(address account, bool enabled)
        external
        onlyOwner
    {
        _isExcludedFromFee[account] = enabled;
        emit LogSetExcludeFromFee(msg.sender, account, enabled);
    }

    function setMarketingWallet(address payable newWallet) external onlyOwner {
        marketingWallet = newWallet;
        emit LogSetMarketingWallet(msg.sender, marketingWallet);
    }

    function setBurnWallet(address payable newWallet) external onlyOwner {
        burnWallet = newWallet;
        emit LogSetBurnWallet(msg.sender, burnWallet);
    }

    function setTeamWallet(address payable newWallet) external onlyOwner {
        teamWallet = newWallet;
        emit LogSetTeamWallet(msg.sender, teamWallet);
    }

    function setBuyFees(
        uint256 _tax,
        uint256 _team
    ) external onlyOwner {
        buyFee.tax = _tax;
        buyFee.team = _team;

        emit LogSetBuyFees(msg.sender, buyFee);
    }

    function setSellFees(
        uint256 _tax,
        uint256 _team
    ) external onlyOwner {
        sellFee.tax = _tax;
        sellFee.team = _team;

        emit LogSetSellFees(msg.sender, sellFee);
    }

    function setRouterAddress(address newRouter) external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(newRouter);

        emit LogSetRouterAddress(msg.sender, newRouter);
    }

    function setPairAddress(address newPair) external onlyOwner {
        uniswapV2Pair = newPair;

        emit LogSetPairAddress(msg.sender, newPair);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;

        emit LogSwapAndLiquifyEnabledUpdated(msg.sender, _enabled);
    }

    function setSwapTokensAmount(uint256 amount) external onlyOwner {
        numTokensSellToAddToLiquidity = amount;

        emit LogSetSwapTokensAmount(msg.sender, amount);
    }

    function updateLiquidityWallet(address newLiquidityWallet)
        external
        onlyOwner
    {
        require(
            newLiquidityWallet != liquidityWallet,
            "The liquidity wallet is already this address"
        );
        liquidityWallet = newLiquidityWallet;

        emit LogUpdateLiquidityWallet(msg.sender, newLiquidityWallet);
    }

    function withdrawBNB(address payable account, uint256 amount)
        external
        onlyOwner
    {
        require(amount <= (address(this)).balance, "Incufficient funds");
        account.transfer(amount);
        emit LogWithdrawalBNB(account, amount);
    }

    /**
     * @notice Should not be withdrawn scam token.
     */
    function withdrawToken(
        IERC20 token,
        address account,
        uint256 amount
    ) external onlyOwner {
        require(amount <= token.balanceOf(address(this)), "Incufficient funds");
        require(token.transfer(account, amount), "Transfer Fail");

        emit LogWithdrawToken(address(token), account, amount);
    }

    //TODO why need this function? can need? missed transfer event. can use transfer with `swapAndLiquifyEnabled` instead withdraw
    function withdraw(address account, uint256 tAmount) external onlyOwner {
        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount * currentRate;
        require(rAmount <= _rOwned[address(this)], "Incufficient funds");
        _rOwned[account] = _rOwned[account] + rAmount;
        _rOwned[address(this)] = _rOwned[address(this)] - rAmount;
        if (_isExcluded[account]) _tOwned[account] = _tOwned[account] + tAmount;
        emit LogWithdrawal(account, tAmount);
    }

    modifier onlyBridge() {
        require(msg.sender == bridge, "Only bridge can perform this action");
        _;
    }

    function setBridge(address _bridge) external onlyOwner {
        require(bridge != _bridge, "Same Bridge!");
        bridge = _bridge;

        emit LogSetBridge(msg.sender, bridge);
    }

    //TODO why need this function? can need. but can update transferFrom and `swapAndLiquifyEnabled`
    // in this case, maybe solve transferfee issue if have transferFee
    function lock(
        address from,
        address to,
        uint256 tAmount
    ) external onlyBridge {
        require(from != address(0), "zero address");
        _approve(
            from,
            _msgSender(),
            balanceCheck(
                _allowances[from][_msgSender()],
                tAmount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount * currentRate;

        _rOwned[from] = _rOwned[from] - rAmount;
        _rOwned[to] = _rOwned[to] + rAmount;

        emit Transfer(from, to, tAmount);
    }
}
