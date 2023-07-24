// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "./AbstractDividends.sol";

contract XHype is ERC20, AbstractDividends, Ownable {
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeFromDividends(address indexed account, bool isExcluded);
    event UpdateBuyFee(uint buyFee);
    event UpdateSellFee(uint sellFee);
    
    event UpdateUniswapV2Router(address indexed newAddress);
    event SendDividends(uint amount);

    //FEES VARIABLES
    uint public buyFee = 5;
    uint public sellFee = 8;
    uint private constant MAX_FEE = 15; //15%
    

    address public immutable rewardToken;
    uint private _totalSupply = 1000000000 ether;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    //SWAPPING VARIABLES
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    uint public swapTokensAtAmount;
    bool public swapEnabled;    
    bool private swapping;

    //DIVIDENDS VARIABLES
    uint public minBalanceForDividends = 1000 ether;
    uint private startVestingDate;
    mapping(address => bool) private _isExcludedFromDividends;
    address[] private _excludedFromDividends;
    mapping(address => bool) private _isExcludedFromFees;

    //VESTING VARIABLES
    //User/wallet => vested amount
    mapping(address => uint) private threeMonthVestedWallets;
    mapping(address => uint) private twelveMonthVestedWallets;
    mapping(address => uint) private twentyFourMonthVestedWallets;
    mapping(address => uint) private lockedTime;
    mapping(address => bool) private isVested;
    //User/wallet => withdrawn amount
    mapping(address => uint) public vestedWalletsWithdrawn;

    
    bool private nukeTheWhales = false;
    mapping (address => bool) private excludedFromNukeTheWhales;
    mapping (address => uint256) public previousSale;
    uint private transferPercentageAllowed = 5;

    constructor()
        payable
        ERC20("XHype", "XHP")
        AbstractDividends(getSharesOf, totalShareableSupply)
    {
        rewardToken = address(0x55d398326f99059fF775485246999027B3197955); //USDT on BSC network
        
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(address(0x10ED43C718714eb63d5aA57B78B54704E256024E)); //Pancakeswap Router on BSC
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _isExcludedFromDividends[owner()] = true;
        _excludedFromDividends.push(owner());
        _isExcludedFromDividends[address(this)] = true;
        _excludedFromDividends.push(address(this));
        _isExcludedFromDividends[DEAD] = true;
        _excludedFromDividends.push(DEAD);
        _isExcludedFromDividends[address(_uniswapV2Pair)] = true;
        _excludedFromDividends.push(address(_uniswapV2Pair));
        _isExcludedFromDividends[address(_uniswapV2Router)] = true;
        _excludedFromDividends.push(address(_uniswapV2Router));
        _isExcludedFromDividends[address(0x4aEb644A9a035e5E0b354EA4b463D1c0E8E79CF9)] = true; //Advisors
        _excludedFromDividends.push(address(0x4aEb644A9a035e5E0b354EA4b463D1c0E8E79CF9));
        _isExcludedFromDividends[address(0x3aB47F80a046d2A4D92A5c229fe93fA6708aEB13)] = true; //Treasury
        _excludedFromDividends.push(address(0x3aB47F80a046d2A4D92A5c229fe93fA6708aEB13));
        _isExcludedFromDividends[address(0x1767c992C70AB29fBE9194f4D8160C373B6d7ED8)] = true; //Marketing
        _excludedFromDividends.push(address(0x1767c992C70AB29fBE9194f4D8160C373B6d7ED8));
        _isExcludedFromDividends[address(0xe24bfB419f5C0EDa8660d53452212cf0c87E4151)] = true; //Team
        _excludedFromDividends.push(address(0xe24bfB419f5C0EDa8660d53452212cf0c87E4151));
        _isExcludedFromDividends[address(0xF949709F80dec4d9E2420c0e6a98081F13fFf368)] = true; //DEXES
        _excludedFromDividends.push(address(0xF949709F80dec4d9E2420c0e6a98081F13fFf368));
        _isExcludedFromDividends[address(0x9DBe36b089451aAEfF495824BB507eD0902f5644)] = true; //Future Developments
        _excludedFromDividends.push(address(0x9DBe36b089451aAEfF495824BB507eD0902f5644));
        _isExcludedFromDividends[address(0xaD064A0827214234E228B9213Af52E5e6457e4C0)] = true; //Charity Wallet
        _excludedFromDividends.push(address(0xaD064A0827214234E228B9213Af52E5e6457e4C0));
        _isExcludedFromDividends[address(0x4f931e269402Cfa2cB998EF3402c7897DA7bd1db)] = true; //Burning Pool
        _excludedFromDividends.push(address(0x4f931e269402Cfa2cB998EF3402c7897DA7bd1db));
        
        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD] = true;

        swapEnabled = true;
        swapTokensAtAmount = 10000 ether;
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

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router),"The router already has that address");
        emit UpdateUniswapV2Router(newAddress);
        uniswapV2Router = IUniswapV2Router02(newAddress);
        if (IUniswapV2Factory(uniswapV2Router.factory()).getPair(address(this), uniswapV2Router.WETH()) == address(0)){
            address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
                .createPair(address(this), uniswapV2Router.WETH());
            uniswapV2Pair = _uniswapV2Pair;
        }else{
            uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(address(this), uniswapV2Router.WETH());
        }
    }

    function setMinBalanceForDividends(uint amount) external onlyOwner {
        require(amount > 0 && amount <= 1000000 ether,"Must be between 0 and 1000000");
        minBalanceForDividends = amount;
    }

    function setStartVestingDate(uint _startVestingDate) external onlyOwner {
        require(startVestingDate == 0,"Start date can be setted only once");
        require(_startVestingDate > block.timestamp,"Start date must be in the future");
        startVestingDate = _startVestingDate;
    }

    function setTransferPercentageAllowed(uint _percentage) external onlyOwner {
        require (_percentage > 0,"Percentage can't be 0");
        require (_percentage <= 1000,"Percentage can't be more than 1000");
        transferPercentageAllowed = _percentage;
    }

    function setExcludeFromNukeTheWhales(address user, bool excluded) external onlyOwner{
        excludedFromNukeTheWhales[user] = excluded;
    }

    function startNukingTheWhales() external onlyOwner {
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
        
        if (nukeTheWhales && !excludedFromNukeTheWhales[from]) {
            if(from != owner() && to != owner()) {
                require(amount <= (totalSupply()) * (transferPercentageAllowed) / (10**3), "Transfer amount exceeds max permitted");
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

        if (swapEnabled && canSwap && !swapping) {
            swapping = true;
            
            swapAndSendDividends(contractTokenBalance);

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
            uint _fees;
            if (from == uniswapV2Pair) {
                _fees = buyFee;
            } else {
                _fees = sellFee;
                previousSale[from] = block.timestamp;
            }
            uint fees = (amount * _fees) / 100;

            amount = amount - fees;

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);
    }

    //=======Swap=======//
    function toggleSwapEnabled() external onlyOwner {        
        swapEnabled = !swapEnabled;
    }

    function setSwapTokensAtAmount(uint newAmount) external onlyOwner {
        require(newAmount > totalSupply() / 1000000, "New Amount must be more than 0.0001% of total supply");
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

        uint initialBalance = IERC20(rewardToken).balanceOf(address(this));

        _approve(address(this), address(uniswapV2Router), amount);

        // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value:amount}(
            0, // accept any amount of Tokens
            path,
            address(this),
            block.timestamp
        );

        uint amountToDistribute = IERC20(rewardToken).balanceOf(address(this)) - initialBalance;

        _distributeDividends(amountToDistribute);
        emit SendDividends(amountToDistribute);
    }

    //VESTING
    function setVestedWallet(address account, uint amount, uint vestingTime, uint lockingTime) external onlyOwner {
        require(vestingTime == 3 || vestingTime == 12 || vestingTime == 24, "Vesting time not allowed");
        require(balanceOf(account) == 0,"Can't vest account with balance");
        require(!isVested[account],"Wallet is already vested");

        if (vestingTime == 3){
            threeMonthVestedWallets[account] = amount;
        }else if(vestingTime == 12){
            twelveMonthVestedWallets[account] = amount;
        }else{
            twentyFourMonthVestedWallets[account] = amount;
        }
        lockedTime[account] = lockingTime;
        isVested[account] = true;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override view {
        if (isVested[from]){
            require(amount <= getAvailableAmount(from),"Can't use more than available amount");
        }
    }

    function getLockedTime(address account) external view returns(uint){
        return lockedTime[account];
    }

    function getUnvestedAmount(address account,uint totalVestedAmount, uint vestingTime) internal view returns(uint){
        if (block.timestamp < (startVestingDate + lockedTime[account])){
            return 0;
        }
        if (startVestingDate + vestingTime + (lockedTime[account]) <= block.timestamp){            
            return balanceOf(account);
        }
        
        uint availableAmountPerDay = totalVestedAmount / vestingTime;
        uint timePassed = block.timestamp - (startVestingDate + lockedTime[account]);

        return (timePassed * availableAmountPerDay) - vestedWalletsWithdrawn[account];
    }

    function getAvailableAmount(address from) public view returns(uint){
        if (!isVested[from]){
            return balanceOf(from);
        }
        if (twentyFourMonthVestedWallets[from] > 0){            
            return getUnvestedAmount(from, twentyFourMonthVestedWallets[from], 730 days);//24 month linear release            
        }else if (twelveMonthVestedWallets[from] > 0){
            return getUnvestedAmount(from, twelveMonthVestedWallets[from], 365 days);//12 month linear release            
        }else if (threeMonthVestedWallets[from] > 0){
            return getUnvestedAmount(from, threeMonthVestedWallets[from], 90 days);//3 month linear release            
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override{
        if (isVested[from]){
            vestedWalletsWithdrawn[from] += amount;
        }
    }

    //DIVIDENDS
    function excludeFromDividends(address account) external onlyOwner() {
        require(!_isExcludedFromDividends[account], "Account is already excluded");
        
        _isExcludedFromDividends[account] = true;
        _excludedFromDividends.push(account);
        emit ExcludeFromDividends(account, true);
    }

    function includeInDividends(address account) external onlyOwner() {
        require(_isExcludedFromDividends[account], "Account is already included");
        for (uint256 i = 0; i < _excludedFromDividends.length; i++){
            if (_excludedFromDividends[i] == account) {
                _excludedFromDividends[i] = _excludedFromDividends[_excludedFromDividends.length - 1];
                _isExcludedFromDividends[account] = false;
                _excludedFromDividends.pop();
                break;
            }
        }
        emit ExcludeFromDividends(account, false);
    }

    function withdrawDividends() external{
        uint256 amount = _prepareCollect(msg.sender);
        require(amount > 0, "Nothing to withdraw");
        TransferHelper.safeTransfer(rewardToken, msg.sender, amount);
        emit DividendsWithdrawn(msg.sender, amount);
    }

    function getVestedWalletWithdrawn(address account) external view returns(uint){
        return vestedWalletsWithdrawn[account];
    }

    //ADMIN WITHDRAWALS
    function withdrawBalance(address receiver) external onlyOwner{
        require(address(this).balance > 0,"Nothing to withdraw");
        TransferHelper.safeTransferETH(receiver, address(this).balance);
    }

    function claimStuckTokens(address token) external onlyOwner {
        require(token != address(this), "Owner cannot claim native tokens");
        require(token != rewardToken, "Owner cannot claim rewards tokens");

        IERC20 ERC20token = IERC20(token);
        uint balance = ERC20token.balanceOf(address(this));
        TransferHelper.safeTransfer(token, msg.sender, balance);        
    }

    receive() external payable {}
}