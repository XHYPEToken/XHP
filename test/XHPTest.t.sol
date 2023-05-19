// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "lib/forge-std/src/Test.sol";
import "../src/XHypeV2.sol";
import "../src/mocks/Token.sol";

contract XHPTest is Test {
    
    Token public usdt;
    XhypeV2 public token;

    uint startDate = 100;

    function setUp() public {
        usdt = new Token();
        token = new XhypeV2(address(usdt),vm.addr(22));
        token.setStartDate(startDate);
        vm.warp(startDate);
    }

    function setVestings() public{
        token.setVestedWallet(vm.addr(1),90 ether,3,false);
        token.setVestedWallet(vm.addr(2),365 ether,12,false);
        token.setVestedWallet(vm.addr(3),730 ether,24,false);
        token.setVestedWallet(vm.addr(4),730 ether,24,true);

        token.transfer(vm.addr(1),90 ether);
        token.transfer(vm.addr(2),365 ether);
        token.transfer(vm.addr(3),720 ether);
        token.transfer(vm.addr(4),720 ether);
    }

    function testVestings() public {
        setVestings();
        //Vesting 1: 3 meses linear release
        vm.prank(vm.addr(1));
        vm.expectRevert("Can't use more than unvested amount");
        token.transfer(address(1),1 ether);

        vm.warp(startDate + 86401);
        
        vm.prank(vm.addr(1));
        token.transfer(address(1),1 ether);
        assertEq(token.balanceOf(address(1)), 1 ether);

        vm.warp(startDate + 2 days + 1);
        vm.prank(vm.addr(1));
        vm.expectRevert("Can't use more than unvested amount");
        token.transfer(address(1),2 ether);
        assertEq(token.balanceOf(address(1)), 1 ether);
        
        vm.warp(startDate + 91 days);
        assertEq(token.getUnvestedAmount(90 ether, 90 days, false),90 ether);
        assertEq(token.getVestedWalletWithdrawn(vm.addr(1)),1 ether);

        vm.prank(vm.addr(1));
        token.transfer(address(1),89 ether);
        assertEq(token.balanceOf(address(1)), 90 ether);

        vm.prank(vm.addr(4));
        vm.expectRevert("Lock period not over");
        token.transfer(address(1),1 ether);

        vm.warp(startDate + 182 days);

        assertEq(token.getVestedWalletWithdrawn(vm.addr(4)),0);

        vm.prank(vm.addr(4));
        token.transfer(address(1),1 ether);
        assertEq(token.getVestedWalletWithdrawn(vm.addr(4)),1 ether);
        
        vm.prank(vm.addr(2));
        token.transfer(address(1),181 ether);
        assertEq(token.getVestedWalletWithdrawn(vm.addr(2)),181 ether);
        
        vm.prank(vm.addr(3));
        token.transfer(address(1),181 ether);
        assertEq(token.getVestedWalletWithdrawn(vm.addr(3)),181 ether);
    }
}
