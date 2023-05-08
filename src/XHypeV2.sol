// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "./AbstractDividends.sol";

contract XhypeV2 is ERC20, AbstractDividends, Ownable {
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludedFromMaxTransactionLimit(
        address indexed account,
        bool isExcluded
    );
    event ExcludedFromMaxWalletLimit(address indexed account, bool isExcluded);
    event UpdateBuyFees(
        uint liquidityFeeOnBuy,
        uint rewardFeeOnBuy
    );
    event UpdateSellFees(
        uint liquidityFeeOnSell,
        uint rewardFeeOnSell
    );
    event MarketingWalletChanged(address marketingWallet);
    event BuybackWalletChanged(address buybackWallet);
    event SalaryWalletChanged(address salaryWallet);
    event StakingWalletChanged(address stakingWallet);
    event MaxWalletLimitRateChanged(uint maxWalletLimitRate);
    event MaxWalletLimitStateChanged(bool maxWalletLimit);
    event MaxTransactionLimitRatesChanged(
        uint maxTransferRateBuy,
        uint maxTransferRateSell
    );
    event MaxTransactionLimitStateChanged(bool maxTransactionLimit);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint tokensSwapped,
        uint bnbReceived,
        uint tokensIntoLiqudity
    );
    event SendMarketing(uint bnbSend);
    event SendBuyback(uint bnbSend);
    event SendSalary(uint bnbSend);
    event SendStaking(uint tokenSend);
    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );
    event SendDividends(uint amount);

    using Address for address;
    using Address for address payable;

    struct Fees {
        uint liquidity;
        uint reward;                
        uint total;
    }

    Fees public buyFees = Fees(1, 1, 2);
    Fees public sellFees = Fees(1, 1, 2);
    
    struct Config {
        address treasuryWallet;
        uint totalSupply;
    }

    Config public config =
        Config(
            address(0xBbb422b9464DDa298E87eDf776Ea2D974C3a84bA),            
            1000000000 ether
        );

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    address private DEAD = 0x000000000000000000000000000000000000dEaD;

    uint public swapTokensAtAmount;
    bool public swapEnabled;    
    bool private swapping;

    mapping(address => bool) private _isExcludedFromDividends;
    address[] private _excludedFromDividends;
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public automatedMarketMakerPairs;

    address public immutable rewardToken;

    uint private constant MAX_TOTAL_FEE = 10; //25%
    
    constructor(
        address _rewardToken,
        address router
    )
        payable
        ERC20("XHype", "XHP")
        AbstractDividends(getSharesOf, totalShareableSupply)
    {
        rewardToken = _rewardToken;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        // _approve(address(this), address(uniswapV2Router), type(uint).max);

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        _isExcludedFromDividends[owner()]; //Verificar si quieren excluir al owner/wallet de treasury
        _isExcludedFromDividends[address(this)];
        _isExcludedFromDividends[DEAD];
        _isExcludedFromDividends[config.treasuryWallet];
        _isExcludedFromDividends[address(_uniswapV2Router)];

        _isExcludedFromMaxTxLimit[owner()] = true;
        _isExcludedFromMaxTxLimit[address(0)] = true;
        _isExcludedFromMaxTxLimit[address(this)] = true;
        _isExcludedFromMaxTxLimit[DEAD] = true;
        _isExcludedFromMaxTxLimit[config.treasuryWallet] = true;

        _isExcludedFromMaxWalletLimit[owner()] = true;
        _isExcludedFromMaxWalletLimit[address(0)] = true;
        _isExcludedFromMaxWalletLimit[address(this)] = true;
        _isExcludedFromMaxWalletLimit[DEAD] = true;
        _isExcludedFromMaxWalletLimit[config.treasuryWallet] = true;

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD] = true;
        _isExcludedFromFees[config.treasuryWallet] = true;

        swapEnabled = true;
        swapTokensAtAmount = (config.totalSupply * (10 ** 18)) / 5000;
        _mint(owner(), config.totalSupply * (10 ** 18));
    }

    function getSharesOf(address _user) public view returns (uint) {
        if (_isExcludedFromDividends[_user]) {
            return 0;
        }
        return balanceOf(_user);
    }

    function totalShareableSupply() public view returns (uint) {
        uint excludedSupply;
        for (uint i; i < _excludedFromDividends.length; i++) {
            excludedSupply += balanceOf(_excludedFromDividends[i]);
        }
        return totalSupply() - excludedSupply;
    }

    receive() external payable {}

    function claimStuckTokens(address token) external onlyOwner {
        require(token != address(this), "Owner cannot claim native tokens");
        require(token != rewardToken, "Owner cannot claim rewards tokens");
        if (token == address(0x0)) {
            payable(msg.sender).transfer(address(this).balance);
            return;
        }
        IERC20 ERC20token = IERC20(token);
        uint balance = ERC20token.balanceOf(address(this));
        TransferHelper.safeTransfer(token, msg.sender, balance);        
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(
            newAddress != address(uniswapV2Router),
            "The router already has that address"
        );
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) external onlyOwner {
        require(
            pair != uniswapV2Pair,
            "The PancakeSwap pair cannot be removed from automatedMarketMakerPairs"
        );
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;
        _isExcludedFromDividends[pair] = value;        

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    //=======FeeManagement=======//
    function excludeFromFees(
        address account,
        bool excluded
    ) external onlyOwner {
        require(
            _isExcludedFromFees[account] != excluded,
            "Account is already the value of 'excluded'"
        );
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function updateBuyFees(
        uint _liquidity,
        uint _reward,
        uint _staking
    ) external onlyOwner {
        require(
            _liquidity + _reward + _staking <=
                25,
            "Fees must be less than 25%"
        );
        buyFees.liquidity = _liquidity;
        buyFees.reward = _reward;
        buyFees.total =
            buyFees.liquidity +
            buyFees.reward;
        
        emit UpdateBuyFees(
            _liquidity,
            _reward
        );
    }

    function updateSellFees(
        uint _liquidity,
        uint _reward,
        uint _staking
    ) external onlyOwner {
        require(
            _liquidity + _reward + _staking <=
                25,
            "Fees must be less than 25%"
        );
        sellFees.liquidity = _liquidity;
        sellFees.reward = _reward;
        sellFees.total =
            sellFees.liquidity +
            sellFees.reward;
        
        emit UpdateSellFees(
            _liquidity,
            _reward
        );
    }


    function changeTreasurykWallet(address _treasurykWallet) external onlyOwner {
        require(
            _treasurykWallet != config.treasuryWallet,
            "Buyback wallet is already that address"
        );        
        config.treasuryWallet = _treasurykWallet;
        emit BuybackWalletChanged(config.treasuryWallet);
    }

    function swapAndSendFee(
        uint amount,
        address feeReceiver,
        address currency
    ) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = currency;

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(0, path, feeReceiver, block.timestamp);
    }

    function _transfer(
        address from,
        address to,
        uint amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (maxTransactionLimitEnabled) {
            if (
                (from == uniswapV2Pair || to == uniswapV2Pair) &&
                _isExcludedFromMaxTxLimit[from] == false &&
                _isExcludedFromMaxTxLimit[to] == false
            ) {
                if (from == uniswapV2Pair) {
                    require(
                        amount <= maxTransactionAmountBuy,
                        "AntiWhale: Transfer amount exceeds the maxTransactionAmount"
                    );
                } else {
                    require(
                        amount <= maxTransactionAmountSell,
                        "AntiWhale: Transfer amount exceeds the maxTransactionAmount"
                    );
                }
            }
        }

        if (maxWalletLimitEnabled) {
            if (
                _isExcludedFromMaxWalletLimit[from] == false &&
                _isExcludedFromMaxWalletLimit[to] == false &&
                to != uniswapV2Pair
            ) {
                uint balance = balanceOf(to);
                require(
                    balance + amount <= maxWalletAmount,
                    "MaxWallet: Recipient exceeds the maxWalletAmount"
                );
            }
        }

        uint contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            swapEnabled &&
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            buyFees.total + sellFees.total > 0
        ) {
            swapping = true;
            
            uint rewardShare = buyFees.reward + sellFees.reward;

            if (contractTokenBalance > 0 && rewardShare > 0) {
                uint rewards = (contractTokenBalance * rewardShare) / 100;
                swapAndSendDividends(rewards);
            }

            swapping = false;
        }

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (            
            from != uniswapV2Pair &&
            to != uniswapV2Pair
        ) {
            takeFee = false;
        }

        if (takeFee) {
            uint _totalFees;
            if (from == uniswapV2Pair) {
                _totalFees = buyFees.total;
            } else {
                _totalFees = sellFees.total;
            }
            uint fees = (amount * _totalFees) / 100;

            amount = amount - fees;            

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);
    }

    //=======Swap=======//
    function setSwapEnabled(bool _swapEnabled) external onlyOwner {
        require(
            swapEnabled != _swapEnabled,
            "Swap is already set to that state"
        );
        swapEnabled = _swapEnabled;
    }

    function setSwapTokensAtAmount(uint newAmount) external onlyOwner {
        require(
            newAmount > totalSupply() / 1000000,
            "New Amount must more than 0.0001% of total supply"
        );
        swapTokensAtAmount = newAmount;
    }

    function swapAndLiquify(uint tokens) private {
        uint half = tokens / 2;
        uint otherHalf = tokens - half;

        uint initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokens);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint newBalance = address(this).balance - initialBalance;

        uniswapV2Router.addLiquidityETH{value: newBalance}(
            address(this),
            otherHalf,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            DEAD,
            block.timestamp
        );

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    //Revisar como se llegar a tener BNBs aca.
    function swapAndSendDividends(uint amount) private {
        address[] memory path = new address[](2);
        // path[0] = uniswapV2Router.WETH();
        path[0] = address(this);
        path[1] = rewardToken;

        _approve(address(this), address(uniswapV2Router), amount);
        
        uint balanceRewardToken = IERC20(rewardToken).balanceOf(address(this));

        uniswapV2Router
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amount,
                0,
                path,
                address(this),
                block.timestamp
            );

        uint amountToDistribute = IERC20(rewardToken).balanceOf(address(this)) - balanceRewardToken;

        _distributeDividends(amountToDistribute);
        emit SendDividends(amountToDistribute);
    }

    //=======MaxWallet=======//
    mapping(address => bool) private _isExcludedFromMaxWalletLimit;
    bool public maxWalletAvailable;
    bool public maxWalletLimitEnabled;
    uint public maxWalletAmount;

    modifier _maxWalletAvailable() {
        require(maxWalletAvailable, "Max wallet limit is not available");
        _;
    }

    function setEnableMaxWalletLimit(
        bool enable
    ) external onlyOwner _maxWalletAvailable {
        require(
            enable != maxWalletLimitEnabled,
            "Max wallet limit is already set to that state"
        );
        maxWalletLimitEnabled = enable;
        emit MaxWalletLimitStateChanged(maxWalletLimitEnabled);
    }

    function setMaxWalletAmount(
        uint _maxWalletAmount
    ) external onlyOwner _maxWalletAvailable {
        require(
            _maxWalletAmount >= totalSupply() / (10 ** decimals()) / 100,
            "Max wallet percentage cannot be lower than 1%"
        );
        maxWalletAmount = _maxWalletAmount;
        emit MaxWalletLimitRateChanged(maxWalletAmount);
    }

    function setExcludeFromMaxWallet(
        address account,
        bool exclude
    ) external onlyOwner _maxWalletAvailable {
        require(
            _isExcludedFromMaxWalletLimit[account] != exclude,
            "Account is already set to that state"
        );
        _isExcludedFromMaxWalletLimit[account] = exclude;
        emit ExcludedFromMaxWalletLimit(account, exclude);
    }

    function isExcludedFromMaxWalletLimit(
        address account
    ) public view returns (bool) {
        return _isExcludedFromMaxWalletLimit[account];
    }

    //=======MaxTransaction=======//
    mapping(address => bool) private _isExcludedFromMaxTxLimit;
    bool public maxTransactionAvailable;
    bool public maxTransactionLimitEnabled;
    uint public maxTransactionAmountBuy;
    uint public maxTransactionAmountSell;

    modifier _maxTransactionAvailable() {
        require(
            maxTransactionAvailable,
            "Max transaction limit is not available"
        );
        _;
    }

    function setEnableMaxTransactionLimit(
        bool enable
    ) external onlyOwner _maxTransactionAvailable {
        require(
            enable != maxTransactionLimitEnabled,
            "Max transaction limit is already set to that state"
        );
        maxTransactionLimitEnabled = enable;
        emit MaxTransactionLimitStateChanged(maxTransactionLimitEnabled);
    }

    function setMaxTransactionAmounts(
        uint _maxTransactionAmountBuy,
        uint _maxTransactionAmountSell
    ) external onlyOwner _maxTransactionAvailable {
        require(
            _maxTransactionAmountBuy >=
                totalSupply() / (10 ** decimals()) / 1000 &&
                _maxTransactionAmountSell >=
                totalSupply() / (10 ** decimals()) / 1000,
            "Max Transaction limis cannot be lower than 0.1% of total supply"
        );
        maxTransactionAmountBuy = _maxTransactionAmountBuy * (10 ** decimals());
        maxTransactionAmountSell =
            _maxTransactionAmountSell *
            (10 ** decimals());
        emit MaxTransactionLimitRatesChanged(
            maxTransactionAmountBuy,
            maxTransactionAmountSell
        );
    }

    function setExcludeFromMaxTransactionLimit(
        address account,
        bool exclude
    ) external onlyOwner _maxTransactionAvailable {
        require(
            _isExcludedFromMaxTxLimit[account] != exclude,
            "Account is already set to that state"
        );
        _isExcludedFromMaxTxLimit[account] = exclude;
        emit ExcludedFromMaxTransactionLimit(account, exclude);
    }

    function isExcludedFromMaxTransaction(
        address account
    ) public view returns (bool) {
        return _isExcludedFromMaxTxLimit[account];
    }
}
