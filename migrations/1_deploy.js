let RewardToken = artifacts.require("./mocks/Token.sol");
let XHP = artifacts.require("./XHypeV2.sol");
let pancakeRouter = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"; //BSC Testnet
  
module.exports = async (deployer, accounts) => {

  /*ONLY FOR TEST PORPOUSE*/
  await deployer.deploy(RewardToken);
  let rewardToken = await RewardToken.deployed();
  // let rewardToken = await RewardToken.at('0xc6439Bfc8573741116AE357172Bb92C6D11a1837'); //TEST USDT on BSCTESTNET
  /*ONLY FOR TEST PORPOUSE*/

  await deployer.deploy(XHP,rewardToken.address,pancakeRouter);
};

// tBNB 0xae13d989dac2f0debff460ac112a837c89baa7cd
// FeaturedToken 0xdCd8b5Dcbf2454446F3b7AA48d68941B8f75aB41
// tBNB <-> FeaturedToken pair: 0x0F5B99A872098f364547c0C33E35d6F9bc590A2B