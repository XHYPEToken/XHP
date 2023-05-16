// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "./AbstractDividends.sol";

contract XhypeV2 is ERC20, AbstractDividends, Ownable {
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event UpdateBuyFee(uint buyFee);
    event UpdateSellFee(uint sellFee);
    
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event UpdateUniswapV2Router(address indexed newAddress,address indexed oldAddress);
    event SendDividends(uint amount);

    using Address for address;
    using Address for address payable;

    uint public buyFee = 5;
    uint public sellFee = 8;
        
    uint public minBalanceForDividends = 1000 ether;
    uint private _totalSupply = 1000000000 ether;

    uint private startDate;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    address private DEAD = 0x000000000000000000000000000000000000dEaD;

    uint public swapTokensAtAmount;
    bool public swapEnabled;    
    bool private swapping;

    mapping(address => bool) private _isExcludedFromDividends;
    address[] private _excludedFromDividends;
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private automatedMarketMakerPairs;

    //User/wallet => vested amount
    mapping(address => uint) private threeMonthVestedWallets;
    mapping(address => uint) private twelveMonthVestedWallets;
    mapping(address => uint) private twentyFourMonthVestedWallets;
    mapping(address => bool) private sixMonthLockedWallets;
    //User/wallet => withdrawn amount
    mapping(address => uint) private vestedWalletsWithdrawn;

    address public immutable rewardToken;

    uint private constant MAX_FEE = 15; //15%
    
    bool private nukeTheWhales = false;
    mapping (address => uint256) public previousSale;

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
        
        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        _isExcludedFromDividends[owner()];
        _isExcludedFromDividends[address(this)];
        _isExcludedFromDividends[DEAD];
        _isExcludedFromDividends[address(_uniswapV2Router)];
        _isExcludedFromDividends[address(0x4aEb644A9a035e5E0b354EA4b463D1c0E8E79CF9)]; //Advisors
        _isExcludedFromDividends[address(0x3aB47F80a046d2A4D92A5c229fe93fA6708aEB13)]; //Treasury
        _isExcludedFromDividends[address(0x1767c992C70AB29fBE9194f4D8160C373B6d7ED8)]; //Marketing
        _isExcludedFromDividends[address(0xe24bfB419f5C0EDa8660d53452212cf0c87E4151)]; //Team
        _isExcludedFromDividends[address(0xF949709F80dec4d9E2420c0e6a98081F13fFf368)]; //DEXES
        _isExcludedFromDividends[address(0x9DBe36b089451aAEfF495824BB507eD0902f5644)]; //Future Developments
        _isExcludedFromDividends[address(0xaD064A0827214234E228B9213Af52E5e6457e4C0)]; //Charity Wallet
        _isExcludedFromDividends[address(0x4f931e269402Cfa2cB998EF3402c7897DA7bd1db)]; //Burning Pool

        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD] = true;

        swapEnabled = true;
        swapTokensAtAmount = (totalSupply()) / 5000;
        _mint(owner(), totalSupply());
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function getSharesOf(address _user) public view returns (uint) {
        if (_isExcludedFromDividends[_user]) {
            return 0;
        }
        
        return balanceOf(_user) >= minBalanceForDividends ? balanceOf(_user) : 0;
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

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router),"The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function setAutomatedMarketMakerPair(address pair,bool value) external onlyOwner {
        require(pair != uniswapV2Pair,"The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value,"Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;
        _isExcludedFromDividends[pair] = value;        

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function setMinBalanceForDividends(uint amount) external onlyOwner {
        require(amount > 0,"Amount must be bigger than 0");
        minBalanceForDividends = amount;
    }

    function setStartDate(uint _startDate) external onlyOwner {
        require(startDate > 0,"Start date can be setted only once");
        require(_startDate > block.timestamp,"Start date must be in the future");
        startDate = _startDate;
    }

    function startNukingTheWhales() public onlyOwner() {
        nukeTheWhales = true;
    }

    //=======FeeManagement=======//
    function excludeFromFees(address account, bool excluded) external onlyOwner {
        require(_isExcludedFromFees[account] != excluded,"Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function updateBuyFee(uint _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE,"Fee must be less than 15%");
        buyFee = _newFee;
        
        emit UpdateBuyFee(buyFee);
    }

    function updateSellFees(uint _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE, "Fees must be less than 15%");
        sellFee = _newFee;
        
        emit UpdateSellFee(_newFee);
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
        
        if (nukeTheWhales) {            
            if(from != owner() && to != owner()) {
                require(amount <= (totalSupply()) * (1) / (10**3), "Transfer amount exceeds the 0.1% of the supply.");
            }

            if(to == address(uniswapV2Pair) || to == address(uniswapV2Router)) { 
                uint256 fromBalance = balanceOf(from);
                uint256 threshold = (totalSupply()) * (5) / (10**3);
 
                if (fromBalance > threshold) {
                    uint _now = block.timestamp;
                    require(amount < fromBalance / (5), "For your protection, max sell is 20% if you hold 0.5% or more of supply.");
                    require( _now - (previousSale[from]) > 1 days, "You must wait a full day before you may sell again.");
                }
            }
        }

        uint contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (swapEnabled && canSwap && !swapping &&
            !automatedMarketMakerPairs[from] && buyFee + sellFee > 0
        ) {
            swapping = true;
            
            uint rewardShare = buyFee + sellFee;

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

        if (from != uniswapV2Pair && to != uniswapV2Pair) {
            takeFee = false;
        }

        if (takeFee) {
            uint _totalFees;
            if (from == uniswapV2Pair) {
                _totalFees = buyFee;
            } else {
                _totalFees = sellFee;
                previousSale[from] = block.timestamp;
            }
            uint fees = (amount * _totalFees) / 100;

            amount = amount - fees;

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);
    }

    //=======Swap=======//
    function setSwapEnabled(bool _swapEnabled) external onlyOwner {
        require(swapEnabled != _swapEnabled,"Swap is already set to that state");
        swapEnabled = _swapEnabled;
    }

    function setSwapTokensAtAmount(uint newAmount) external onlyOwner {
        require(
            newAmount > totalSupply() / 1000000,
            "New Amount must be more than 0.0001% of total supply"
        );
        swapTokensAtAmount = newAmount;
    }

    function swapAndSendDividends(uint amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        uint initialBalance = address(this).balance;

        _approve(address(this), address(uniswapV2Router), amount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        uint newBalance = address(this).balance - initialBalance;

        swapEthForTokensAndDistribute(newBalance);
    }

    function swapEthForTokensAndDistribute(uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(rewardToken);

        uint balanceRewardToken = IERC20(rewardToken).balanceOf(address(this));

        _approve(address(this), address(uniswapV2Router), amount);

        // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value:amount}(
            0, // accept any amount of Tokens
            path,
            address(this),
            block.timestamp
        );

        uint amountToDistribute = IERC20(rewardToken).balanceOf(address(this)) - balanceRewardToken;

        _distributeDividends(amountToDistribute);
        emit SendDividends(amountToDistribute);
    }

    function setVestedWallet(address account, uint amount, uint vestingTime, bool sixMonthLock) external onlyOwner {
        require(vestingTime == 3 || vestingTime == 12 || vestingTime == 24, "Vesting time not allowed");
        require(balanceOf(account) == 0,"Can't vest account with balance");

        if (vestingTime == 3){
            threeMonthVestedWallets[account] = amount;
        }else if(vestingTime == 12){
            twelveMonthVestedWallets[account] = amount;
        }else{
            twentyFourMonthVestedWallets[account] = amount;
            if (sixMonthLock){
                sixMonthLockedWallets[account] = true;
            }
        }        
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override view {
        //If wallet balance is vested
        if (twentyFourMonthVestedWallets[from] > 0){
            if (sixMonthLockedWallets[from]){
                require(block.timestamp >= startDate + 183 days,"Vesting period not over"); //6 month lock
            }
            uint availableAmount = getAvailableAmount(twentyFourMonthVestedWallets[from], 730, true);//24 month linear release - 6 month lock            
            require(amount <= availableAmount - vestedWalletsWithdrawn[from],"Can't use more than unvested amount");
        }else if (twelveMonthVestedWallets[from] > 0){
            uint availableAmount = getAvailableAmount(twelveMonthVestedWallets[from], 365, false);//12 month linear release
            require(amount <= availableAmount - vestedWalletsWithdrawn[from],"Can't use more than unvested amount");
        }else if (threeMonthVestedWallets[from] > 0){
            uint availableAmount = getAvailableAmount(threeMonthVestedWallets[from], 90, false);//3 month linear release
            require(amount <= availableAmount - vestedWalletsWithdrawn[from],"Can't use more than unvested amount");
        }
    }

    function getAvailableAmount(uint totalVestedAmount, uint vestingTime, bool sixMonthLocked) internal view returns(uint){
        uint availableAmountPerDay = totalVestedAmount / vestingTime;
        uint daysPassed = block.timestamp - (startDate + (sixMonthLocked ? 180 days : 0));

        return daysPassed * availableAmountPerDay;
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override{
        if (twentyFourMonthVestedWallets[from] > 0 ||
            twelveMonthVestedWallets[from] > 0 ||
            threeMonthVestedWallets[from] > 0 ){
            vestedWalletsWithdrawn[from] += amount;
        }
    }

    function withdrawBalance(address receiver) external onlyOwner{
        require(address(this).balance > 0,"Nothing to withdraw");

        TransferHelper.safeTransferETH(receiver, address(this).balance);
    }
}