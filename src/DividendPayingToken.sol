// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./interfaces/DividendPayingTokenInterface.sol";
import "./interfaces/DividendPayingTokenOptionalInterface.sol";
import "./lib/SafeMathUint.sol";
import "./lib/SafeMathInt.sol";

contract DividendPayingToken is ERC20, Ownable, DividendPayingTokenInterface, DividendPayingTokenOptionalInterface {
 using SafeMath for uint256;
 using SafeMathUint for uint256;
 using SafeMathInt for int256;

 uint256 constant internal magnitude = 2**128;
 uint256 internal magnifiedDividendPerShare;
 uint256 public totalDividendsDistributed;
 
 address public immutable rewardToken;
 
 mapping(address => int256) internal magnifiedDividendCorrections;
 mapping(address => uint256) internal withdrawnDividends;

 constructor(string memory _name, string memory _symbol, address _rewardToken) ERC20(_name, _symbol) { 
 rewardToken = _rewardToken;
 }

 function distributeDividends(uint256 amount) public onlyOwner{
 require(totalSupply() > 0);

 if (amount > 0) {
 magnifiedDividendPerShare = magnifiedDividendPerShare.add(
 (amount).mul(magnitude) / totalSupply()
 );
 emit DividendsDistributed(msg.sender, amount);

 totalDividendsDistributed = totalDividendsDistributed.add(amount);
 }
 }

 function withdrawDividend() public virtual override {
 _withdrawDividendOfUser(payable(msg.sender));
 }

 function _withdrawDividendOfUser(address payable user) internal returns (uint256) {
 uint256 _withdrawableDividend = withdrawableDividendOf(user);
 if (_withdrawableDividend > 0) {
 withdrawnDividends[user] = withdrawnDividends[user].add(_withdrawableDividend);
 emit DividendWithdrawn(user, _withdrawableDividend);
 bool success = IERC20(rewardToken).transfer(user, _withdrawableDividend);

 if(!success) {
 withdrawnDividends[user] = withdrawnDividends[user].sub(_withdrawableDividend);
 return 0;
 }

 return _withdrawableDividend;
 }
 return 0;
 }

 function dividendOf(address _owner) public view override returns(uint256) {
 return withdrawableDividendOf(_owner);
 }

 function withdrawableDividendOf(address _owner) public view override returns(uint256) {
 return accumulativeDividendOf(_owner).sub(withdrawnDividends[_owner]);
 }

 function withdrawnDividendOf(address _owner) public view override returns(uint256) {
 return withdrawnDividends[_owner];
 }

 function accumulativeDividendOf(address _owner) public view override returns(uint256) {
 return magnifiedDividendPerShare.mul(balanceOf(_owner)).toInt256Safe()
 .add(magnifiedDividendCorrections[_owner]).toUint256Safe() / magnitude;
 }

 function _transfer(address from, address to, uint256 value) internal virtual override {
 require(false);

 int256 _magCorrection = magnifiedDividendPerShare.mul(value).toInt256Safe();
 magnifiedDividendCorrections[from] = magnifiedDividendCorrections[from].add(_magCorrection);
 magnifiedDividendCorrections[to] = magnifiedDividendCorrections[to].sub(_magCorrection);
 }

 function _mint(address account, uint256 value) internal override {
 super._mint(account, value);

 magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
 .sub( (magnifiedDividendPerShare.mul(value)).toInt256Safe() );
 }

 function _burn(address account, uint256 value) internal override {
 super._burn(account, value);

 magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
 .add( (magnifiedDividendPerShare.mul(value)).toInt256Safe() );
 }

 function _setBalance(address account, uint256 newBalance) internal {
 uint256 currentBalance = balanceOf(account);

 if(newBalance > currentBalance) {
 uint256 mintAmount = newBalance.sub(currentBalance);
 _mint(account, mintAmount);
 } else if(newBalance < currentBalance) {
 uint256 burnAmount = currentBalance.sub(newBalance);
 _burn(account, burnAmount);
 }
 }
}

