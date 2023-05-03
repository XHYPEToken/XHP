// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./DividendTracker.sol";


contract XHype is ERC20, Ownable {
    using Address for address payable;

    uint256 public liquidityFeeOnBuy;
    uint256 public liquidityFeeOnSell;

    uint256 public rewardFeeOnBuy;
    uint256 public rewardFeeOnSell;

    uint256 public marketingFeeOnBuy;
    uint256 public marketingFeeOnSell;

    uint256 public buybackFeeOnBuy;
    uint256 public buybackFeeOnSell;

    bool public salaryFeeAvailable;
    uint256 public salaryFeeOnBuy;
    uint256 public salaryFeeOnSell;

    bool public stakingFeeAvailable;
    uint256 public stakingFeeOnBuy;
    uint256 public stakingFeeOnSell;

    uint256 private _totalFeesOnBuy;
    uint256 private _totalFeesOnSell;

    address public marketingWallet;
    address public buybackWallet;
    address public salaryWallet;
    address public stakingWallet;

    address public marketingCurrency;
    address public buybackCurrency;
    address public salaryCurrency;

    bool public walletToWalletTransferWithoutFee;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    address private DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public swapTokensAtAmount;
    bool public swapEnabled;
    bool public swapWithLimit;
    bool private swapping;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public automatedMarketMakerPairs;

    DividendTracker public dividendTracker;
    address public immutable rewardToken;
    uint256 public gasForProcessing = 300000;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludedFromMaxTransactionLimit(
        address indexed account,
        bool isExcluded
    );
    event ExcludedFromMaxWalletLimit(address indexed account, bool isExcluded);
    event UpdateBuyFees(
        uint256 liquidityFeeOnBuy,
        uint256 marketingFeeOnBuy,
        uint256 rewardFeeOnBuy,
        uint256 buybackFeeOnBuy,
        uint256 salaryFeeOnBuy,
        uint256 stakingFeeOnBuy
    );
    event UpdateSellFees(
        uint256 liquidityFeeOnSell,
        uint256 marketingFeeOnSell,
        uint256 rewardFeeOnSell,
        uint256 buybackFeeOnSell,
        uint256 salaryFeeOnSell,
        uint256 stakingFeeOnSell
    );
    event MarketingWalletChanged(address marketingWallet);
    event BuybackWalletChanged(address buybackWallet);
    event SalaryWalletChanged(address salaryWallet);
    event StakingWalletChanged(address stakingWallet);
    event MaxWalletLimitRateChanged(uint256 maxWalletLimitRate);
    event MaxWalletLimitStateChanged(bool maxWalletLimit);
    event MaxTransactionLimitRatesChanged(
        uint256 maxTransferRateBuy,
        uint256 maxTransferRateSell
    );
    event MaxTransactionLimitStateChanged(bool maxTransactionLimit);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiqudity
    );
    event SendMarketing(uint256 bnbSend);
    event SendBuyback(uint256 bnbSend);
    event SendSalary(uint256 bnbSend);
    event SendStaking(uint256 tokenSend);
    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );
    event UpdateDividendTracker(
        address indexed newAddress,
        address indexed oldAddress
    );
    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );
    event SendDividends(uint256 amount);
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    struct FeeManager {
        bool salaryFeeAvailable_;
        bool stakingFeeAvailable_;
        uint256 liquditiyFeeOnBuy_;
        uint256 liquidityFeeOnSell_;
        uint256 rewardFeeOnBuy_;
        uint256 rewardFeeOnSell_;
        uint256 marketingFeeOnBuy_;
        uint256 marketingFeeOnSell_;
        uint256 buybackFeeOnBuy_;
        uint256 buybackFeeOnSell_;
        uint256 salaryFeeOnBuy_;
        uint256 salaryFeeOnSell_;
        uint256 stakingFeeOnBuy_;
        uint256 stakingFeeOnSell_;
        address marketingWallet_;
        address buybackWallet_;
        address salaryWallet_;
        address stakingWallet_;
        address marketingCurrency_;
        address buybackCurrency_;
        address salaryCurrency_;
    }

    struct ConstructorArgument {
        string name_;
        string symbol_;
        uint256 totalSupply_;
        address router_;
        address rewardToken_;
        uint256 mininmumTokenBalanceForDividends_;
        bool walletToWalletTransferWithoutFee_;
        bool maxTransactionLimitAvailable_;
        uint256 maxTransactionAmountBuy_;
        uint256 maxTransactionAmountSell_;
        bool maxWalletLimitAvailable_;
        uint256 maxWalletAmount_;
        FeeManager feeManager_;
        uint256 serviceFee_;
        address serviceFeeReceiver_;
    }

    constructor(
        ConstructorArgument memory _arg
    ) payable ERC20(_arg.name_, _arg.symbol_) {
        require(
            _arg.feeManager_.stakingFeeAvailable_ ||
                _arg.feeManager_.stakingFeeOnBuy_ +
                    _arg.feeManager_.stakingFeeOnSell_ ==
                0,
            "Staking Fee is not available"
        );
        require(
            _arg.feeManager_.salaryFeeAvailable_ ||
                (_arg.feeManager_.salaryFeeOnBuy_ +
                    _arg.feeManager_.salaryFeeOnSell_ ==
                    0 &&
                    _arg.feeManager_.salaryCurrency_ == address(0)),
            "Salary Fee isn't available"
        );
        require(
            _arg.feeManager_.liquditiyFeeOnBuy_ +
                _arg.feeManager_.marketingFeeOnBuy_ +
                _arg.feeManager_.rewardFeeOnBuy_ +
                _arg.feeManager_.buybackFeeOnBuy_ +
                _arg.feeManager_.salaryFeeOnBuy_ +
                _arg.feeManager_.stakingFeeOnBuy_ <=
                25 &&
                _arg.feeManager_.liquidityFeeOnSell_ +
                    _arg.feeManager_.marketingFeeOnSell_ +
                    _arg.feeManager_.rewardFeeOnSell_ +
                    _arg.feeManager_.buybackFeeOnSell_ +
                    _arg.feeManager_.salaryFeeOnSell_ +
                    _arg.feeManager_.stakingFeeOnSell_ <=
                25,
            "Fees must be less than 25%"
        );
        require(
            _arg.maxWalletAmount_ >= _arg.totalSupply_ / 100,
            "Max wallet limit rate must be greater than 1% of total supply"
        );
        require(
            _arg.maxTransactionAmountBuy_ >= _arg.totalSupply_ / 1000 &&
                _arg.maxTransactionAmountSell_ >= _arg.totalSupply_ / 1000,
            "Max transaction rates must be greater than 0.1% of total supply"
        );
        require(
            _arg.feeManager_.marketingCurrency_ !=
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c &&
                _arg.feeManager_.buybackCurrency_ !=
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c &&
                _arg.feeManager_.salaryCurrency_ !=
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
            "Marketing, buyback and salary currencies cannot be WBNB"
        );
        require(
            _arg.rewardToken_ != address(0) &&
                _arg.rewardToken_ != 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
            "Reward token cannot be BNB"
        );

        salaryFeeAvailable = _arg.feeManager_.salaryFeeAvailable_;
        stakingFeeAvailable = _arg.feeManager_.stakingFeeAvailable_;

        liquidityFeeOnBuy = _arg.feeManager_.liquditiyFeeOnBuy_;
        liquidityFeeOnSell = _arg.feeManager_.liquidityFeeOnSell_;
        rewardFeeOnBuy = _arg.feeManager_.rewardFeeOnBuy_;
        rewardFeeOnSell = _arg.feeManager_.rewardFeeOnSell_;
        marketingFeeOnBuy = _arg.feeManager_.marketingFeeOnBuy_;
        marketingFeeOnSell = _arg.feeManager_.marketingFeeOnSell_;
        buybackFeeOnBuy = _arg.feeManager_.buybackFeeOnBuy_;
        buybackFeeOnSell = _arg.feeManager_.buybackFeeOnSell_;
        salaryFeeOnBuy = _arg.feeManager_.salaryFeeOnBuy_;
        salaryFeeOnSell = _arg.feeManager_.salaryFeeOnSell_;
        stakingFeeOnBuy = _arg.feeManager_.stakingFeeOnBuy_;
        stakingFeeOnSell = _arg.feeManager_.stakingFeeOnSell_;

        _totalFeesOnBuy =
            liquidityFeeOnBuy +
            marketingFeeOnBuy +
            rewardFeeOnBuy +
            buybackFeeOnBuy +
            salaryFeeOnBuy +
            stakingFeeOnBuy;
        _totalFeesOnSell =
            liquidityFeeOnSell +
            marketingFeeOnSell +
            rewardFeeOnSell +
            buybackFeeOnSell +
            salaryFeeOnSell +
            stakingFeeOnSell;

        marketingWallet = _arg.feeManager_.marketingWallet_;
        buybackWallet = _arg.feeManager_.buybackWallet_;
        salaryWallet = _arg.feeManager_.salaryWallet_;
        stakingWallet = _arg.feeManager_.stakingWallet_;

        marketingCurrency = _arg.feeManager_.marketingCurrency_;
        buybackCurrency = _arg.feeManager_.buybackCurrency_;
        salaryCurrency = _arg.feeManager_.salaryCurrency_;

        walletToWalletTransferWithoutFee = _arg
            .walletToWalletTransferWithoutFee_;

        maxTransactionAvailable = _arg.maxTransactionLimitAvailable_;
        maxTransactionLimitEnabled = _arg.maxTransactionLimitAvailable_;
        maxTransactionAmountBuy =
            _arg.maxTransactionAmountBuy_ *
            (10 ** decimals());
        maxTransactionAmountSell =
            _arg.maxTransactionAmountSell_ *
            (10 ** decimals());

        maxWalletAvailable = _arg.maxWalletLimitAvailable_;
        maxWalletLimitEnabled = _arg.maxWalletLimitAvailable_;
        maxWalletAmount = _arg.maxWalletAmount_ * (10 ** decimals());

        dividendTracker = new DividendTracker(
            _arg.mininmumTokenBalanceForDividends_,
            _arg.rewardToken_
        );
        rewardToken = _arg.rewardToken_;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_arg.router_);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _approve(address(this), address(uniswapV2Router), type(uint256).max);

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(DEAD);
        dividendTracker.excludeFromDividends(stakingWallet);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        _isExcludedFromMaxTxLimit[owner()] = true;
        _isExcludedFromMaxTxLimit[address(0)] = true;
        _isExcludedFromMaxTxLimit[address(this)] = true;
        _isExcludedFromMaxTxLimit[DEAD] = true;
        _isExcludedFromMaxTxLimit[stakingWallet] = true;

        _isExcludedFromMaxWalletLimit[owner()] = true;
        _isExcludedFromMaxWalletLimit[address(0)] = true;
        _isExcludedFromMaxWalletLimit[address(this)] = true;
        _isExcludedFromMaxWalletLimit[DEAD] = true;
        _isExcludedFromMaxWalletLimit[stakingWallet] = true;

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD] = true;
        _isExcludedFromFees[stakingWallet] = true;

        swapEnabled = true;
        swapTokensAtAmount = (_arg.totalSupply_ * (10 ** 18)) / 5000;
        _mint(owner(), _arg.totalSupply_ * (10 ** 18));

        payable(_arg.serviceFeeReceiver_).transfer(_arg.serviceFee_);
    }

    receive() external payable {}

    function claimStuckTokens(address token) external onlyOwner {
        require(token != address(this), "Owner cannot claim native tokens");
        if (token == address(0x0)) {
            payable(msg.sender).transfer(address(this).balance);
            return;
        }
        IERC20 ERC20token = IERC20(token);
        uint256 balance = ERC20token.balanceOf(address(this));
        ERC20token.transfer(msg.sender, balance);
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

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

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
        uint256 _liquidityFeeOnBuy,
        uint256 _marketingFeeOnBuy,
        uint256 _rewardFeeOnBuy,
        uint256 _buybackFeeOnBuy,
        uint256 _salaryFeeOnBuy,
        uint256 _stakingFeeOnBuy
    ) external onlyOwner {
        require(
            _liquidityFeeOnBuy +
                _marketingFeeOnBuy +
                _rewardFeeOnBuy +
                _buybackFeeOnBuy +
                _salaryFeeOnBuy +
                _stakingFeeOnBuy <=
                25,
            "Fees must be less than 25%"
        );
        liquidityFeeOnBuy = _liquidityFeeOnBuy;
        rewardFeeOnBuy = _rewardFeeOnBuy;
        marketingFeeOnBuy = _marketingFeeOnBuy;
        buybackFeeOnBuy = _buybackFeeOnBuy;
        salaryFeeOnBuy = _salaryFeeOnBuy;
        stakingFeeOnBuy = _stakingFeeOnBuy;

        _totalFeesOnBuy =
            liquidityFeeOnBuy +
            marketingFeeOnBuy +
            rewardFeeOnBuy +
            buybackFeeOnBuy +
            salaryFeeOnBuy +
            stakingFeeOnBuy;
        emit UpdateBuyFees(
            _liquidityFeeOnBuy,
            _marketingFeeOnBuy,
            _rewardFeeOnBuy,
            _buybackFeeOnBuy,
            _salaryFeeOnBuy,
            _stakingFeeOnBuy
        );
    }

    function updateSellFees(
        uint256 _liquidityFeeOnSell,
        uint256 _marketingFeeOnSell,
        uint256 _rewardFeeOnSell,
        uint256 _buybackFeeOnSell,
        uint256 _salaryFeeOnSell,
        uint256 _stakingFeeOnSell
    ) external onlyOwner {
        require(
            _liquidityFeeOnSell +
                _marketingFeeOnSell +
                _rewardFeeOnSell +
                _buybackFeeOnSell +
                _salaryFeeOnSell +
                _stakingFeeOnSell <=
                25,
            "Fees must be less than 25%"
        );
        liquidityFeeOnSell = _liquidityFeeOnSell;
        rewardFeeOnSell = _rewardFeeOnSell;
        marketingFeeOnSell = _marketingFeeOnSell;
        buybackFeeOnSell = _buybackFeeOnSell;
        salaryFeeOnSell = _salaryFeeOnSell;
        stakingFeeOnSell = _stakingFeeOnSell;
        _totalFeesOnSell =
            liquidityFeeOnSell +
            marketingFeeOnSell +
            rewardFeeOnSell +
            buybackFeeOnSell +
            salaryFeeOnSell +
            stakingFeeOnSell;
        emit UpdateSellFees(
            _liquidityFeeOnSell,
            _marketingFeeOnSell,
            _rewardFeeOnSell,
            _buybackFeeOnSell,
            _salaryFeeOnSell,
            _stakingFeeOnSell
        );
    }

    function enableWalletToWalletTransferWithoutFee(
        bool enable
    ) external onlyOwner {
        require(
            walletToWalletTransferWithoutFee != enable,
            "Wallet to wallet transfer without fee is already set to that value"
        );
        walletToWalletTransferWithoutFee = enable;
    }

    function changeMarketingWallet(
        address _marketingWallet
    ) external onlyOwner {
        require(
            _marketingWallet != marketingWallet,
            "Marketing wallet is already that address"
        );
        require(
            !isContract(_marketingWallet) || (marketingCurrency != address(0)),
            "Marketing wallet cannot be a contract when currency is BNB"
        );
        marketingWallet = _marketingWallet;
        emit MarketingWalletChanged(marketingWallet);
    }

    function changeBuybackWallet(address _buybackWallet) external onlyOwner {
        require(
            _buybackWallet != buybackWallet,
            "Buyback wallet is already that address"
        );
        require(
            !isContract(_buybackWallet) || (buybackCurrency != address(0)),
            "Buyback wallet cannot be a contract when currency is BNB"
        );
        buybackWallet = _buybackWallet;
        emit BuybackWalletChanged(buybackWallet);
    }

    function changeSalaryWallet(address _salaryWallet) external onlyOwner {
        require(salaryFeeAvailable, "Salary fee isn't available");
        require(
            _salaryWallet != salaryWallet,
            "Salary wallet is already that address"
        );
        require(
            !isContract(_salaryWallet) || (salaryCurrency != address(0)),
            "Salary wallet cannot be a contract when currency is BNB"
        );
        salaryWallet = _salaryWallet;
        emit SalaryWalletChanged(salaryWallet);
    }

    function changeStakingWallet(address _stakingWallet) external onlyOwner {
        require(stakingFeeAvailable, "Staking fee isn't available");
        require(
            _stakingWallet != stakingWallet,
            "Staking wallet is already that address"
        );
        stakingWallet = _stakingWallet;
        emit StakingWalletChanged(stakingWallet);
    }

    function swapAndSendFee(
        uint256 amount,
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
        uint256 amount
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

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            swapEnabled &&
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            _totalFeesOnBuy + _totalFeesOnSell > 0
        ) {
            swapping = true;

            if (swapWithLimit) {
                contractTokenBalance = swapTokensAtAmount;
            }

            uint256 totalFee = _totalFeesOnBuy + _totalFeesOnSell;
            uint256 liquidityShare = liquidityFeeOnBuy + liquidityFeeOnSell;
            uint256 marketingShare = marketingFeeOnBuy + marketingFeeOnSell;
            uint256 rewardShare = rewardFeeOnBuy + rewardFeeOnSell;
            uint256 buybackShare = buybackFeeOnBuy + buybackFeeOnSell;
            uint256 salaryShare = salaryFeeOnBuy + salaryFeeOnSell;
            uint256 stakingShare = stakingFeeOnBuy + stakingFeeOnSell;

            uint256 liquidityTokens;
            uint256 stakingTokens;

            if (liquidityShare > 0) {
                liquidityTokens =
                    (contractTokenBalance * liquidityShare) /
                    totalFee;
                swapAndLiquify(liquidityTokens);
            }

            if (stakingShare > 0) {
                stakingTokens =
                    (contractTokenBalance * stakingShare) /
                    totalFee;
                super._transfer(address(this), stakingWallet, stakingTokens);
                emit SendStaking(stakingTokens);
            }

            contractTokenBalance -= liquidityTokens + stakingTokens;
            uint256 bnbShare = marketingShare +
                rewardShare +
                buybackShare +
                salaryShare;

            if (contractTokenBalance > 0 && bnbShare > 0) {
                uint256 initialBalance = address(this).balance;

                address[] memory path = new address[](2);
                path[0] = address(this);
                path[1] = uniswapV2Router.WETH();

                uniswapV2Router
                    .swapExactTokensForETHSupportingFeeOnTransferTokens(
                        contractTokenBalance,
                        0,
                        path,
                        address(this),
                        block.timestamp
                    );

                uint256 newBalance = address(this).balance - initialBalance;

                if (marketingShare > 0) {
                    uint256 marketingBNB = (newBalance * marketingShare) /
                        bnbShare;
                    if (marketingCurrency == address(0)) {
                        payable(marketingWallet).sendValue(marketingBNB);
                    } else {
                        swapAndSendFee(
                            marketingBNB,
                            marketingWallet,
                            marketingCurrency
                        );
                    }

                    emit SendMarketing(marketingBNB);
                }

                if (buybackShare > 0) {
                    uint256 buybackBNB = (newBalance * buybackShare) / bnbShare;
                    if (buybackCurrency == address(0)) {
                        payable(buybackWallet).sendValue(buybackBNB);
                    } else {
                        swapAndSendFee(
                            buybackBNB,
                            buybackWallet,
                            buybackCurrency
                        );
                    }
                    emit SendBuyback(buybackBNB);
                }

                if (salaryShare > 0) {
                    uint256 salaryBNB = (newBalance * salaryShare) / bnbShare;
                    if (salaryCurrency == address(0)) {
                        payable(salaryWallet).sendValue(salaryBNB);
                    } else {
                        swapAndSendFee(salaryBNB, salaryWallet, salaryCurrency);
                    }
                    emit SendSalary(salaryBNB);
                }

                if (rewardShare > 0) {
                    uint256 rewardBNB = (newBalance * rewardShare) / bnbShare;
                    swapAndSendDividends(rewardBNB);
                }
            }

            swapping = false;
        }

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (
            walletToWalletTransferWithoutFee &&
            from != uniswapV2Pair &&
            to != uniswapV2Pair
        ) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 _totalFees;
            if (from == uniswapV2Pair) {
                _totalFees = _totalFeesOnBuy;
            } else {
                _totalFees = _totalFeesOnSell;
            }
            uint256 fees = (amount * _totalFees) / 100;

            amount = amount - fees;

            super._transfer(from, address(this), fees);
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

        super._transfer(from, to, amount);

        try
            dividendTracker.setBalance(payable(from), balanceOf(from))
        {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if (!swapping) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (
                uint256 iterations,
                uint256 claims,
                uint256 lastProcessedIndex
            ) {
                emit ProcessedDividendTracker(
                    iterations,
                    claims,
                    lastProcessedIndex,
                    true,
                    gas,
                    tx.origin
                );
            } catch {}
        }
    }

    //=======Swap=======//
    function setSwapEnabled(bool _swapEnabled) external onlyOwner {
        require(
            swapEnabled != _swapEnabled,
            "Swap is already set to that state"
        );
        swapEnabled = _swapEnabled;
    }

    function setSwapTokensAtAmount(uint256 newAmount) external onlyOwner {
        require(
            newAmount > totalSupply() / 1_000_000,
            "New Amount must more than 0.0001% of total supply"
        );
        swapTokensAtAmount = newAmount;
    }

    function setSwapWithLimit(bool _swapWithLimit) external onlyOwner {
        require(
            swapWithLimit != _swapWithLimit,
            "Swap with limit is already set to that state"
        );
        swapWithLimit = _swapWithLimit;
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint256 newBalance = address(this).balance - initialBalance;

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

    function swapAndSendDividends(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = rewardToken;

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(0, path, address(this), block.timestamp);

        uint256 balanceRewardToken = IERC20(rewardToken).balanceOf(
            address(this)
        );
        bool success = IERC20(rewardToken).transfer(
            address(dividendTracker),
            balanceRewardToken
        );

        if (success) {
            dividendTracker.distributeDividends(balanceRewardToken);
            emit SendDividends(balanceRewardToken);
        }
    }

    //=======MaxWallet=======//
    mapping(address => bool) private _isExcludedFromMaxWalletLimit;
    bool public maxWalletAvailable;
    bool public maxWalletLimitEnabled;
    uint256 public maxWalletAmount;

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
        uint256 _maxWalletAmount
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
    uint256 public maxTransactionAmountBuy;
    uint256 public maxTransactionAmountSell;

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
        uint256 _maxTransactionAmountBuy,
        uint256 _maxTransactionAmountSell
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

    //=======Dividend Tracker=======//
    function updateDividendTracker(address newAddress) public onlyOwner {
        require(
            newAddress != address(dividendTracker),
            "The dividend tracker already has that address"
        );

        DividendTracker newDividendTracker = DividendTracker(
            payable(newAddress)
        );

        require(
            newDividendTracker.owner() == address(this),
            "The new dividend tracker must be owned by the token contract"
        );

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(DEAD);
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));
        newDividendTracker.excludeFromDividends(address(uniswapV2Pair));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            "gasForProcessing must be between 200,000 and 500,000"
        );
        require(
            newValue != gasForProcessing,
            "Cannot update gasForProcessing to same value"
        );
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateMinimumBalanceForDividends(
        uint256 newMinimumBalance
    ) external onlyOwner {
        dividendTracker.updateMinimumTokenBalanceForDividends(
            newMinimumBalance
        );
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function withdrawableDividendOf(
        address account
    ) public view returns (uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(
        address account
    ) public view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function totalRewardsEarned(address account) public view returns (uint256) {
        return dividendTracker.accumulativeDividendOf(account);
    }

    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }

    function getAccountDividendsInfo(
        address account
    )
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(
        uint256 index
    )
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (
            uint256 iterations,
            uint256 claims,
            uint256 lastProcessedIndex
        ) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(
            iterations,
            claims,
            lastProcessedIndex,
            false,
            gas,
            tx.origin
        );
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function claimAddress(address claimee) external onlyOwner {
        dividendTracker.processAccount(payable(claimee), false);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function setLastProcessedIndex(uint256 index) external onlyOwner {
        dividendTracker.setLastProcessedIndex(index);
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }
}
