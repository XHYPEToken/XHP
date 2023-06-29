const path = require("path");
require('dotenv').config({path: './.env'});
const HDWalletProvider = require("@truffle/hdwallet-provider");
const AccountIndex = 0;

module.exports = {  
  contracts_directory: "./src",
  contracts_build_directory: path.join(__dirname, "compiledContracts"),
  networks: {
    development: {
    port: 8545,
    network_id: "1684494096376",
    host: "127.0.0.1"
    },
    mumbai: {
      provider: function() {
          return new HDWalletProvider(process.env.MNEMONICTEST, "https://polygon-mumbai.blockpi.network/v1/rpc/public", AccountIndex)
      },
      network_id: "80001"
    },
    local: {
      provider: function() {
          return new HDWalletProvider(process.env.MNEMONIC, "http://127.0.0.1:8545", AccountIndex)
      },
      network_id: "5777",
      gas: 5500000,       
      gasPrice: "25000000000",      
    },
    bscTestnet: {
      provider: function() {
          return new HDWalletProvider(process.env.MNEMONICTEST, "https://data-seed-prebsc-1-s1.binance.org:8545", AccountIndex)
      },
      network_id: "97"      
    },
    polygon: {
      provider: () => new HDWalletProvider({
        mnemonic: {
          phrase: process.env.MNEMONIC
        },
        providerOrUrl:
        "https://rpc-mainnet.matic.quiknode.pro"
      }),
      network_id: 137,
      // confirmations: 2,
      // timeoutBlocks: 200,
      skipDryRun: true,
      chainId: 137,
      gasPrice: 500000000000
    },
    rinkeby: {
      provider: function() {
          return new HDWalletProvider(process.env.MNEMONIC, "https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161", AccountIndex )
          // return new HDWalletProvider(process.env.PRIVATEKEY, "https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161")
      },
      network_id: "4",
      gas: 5500000,       
      gasPrice: "25000000000",
    },
    mainnet: {
      provider: function() {
          return new HDWalletProvider(process.env.MNEMONIC, "https://mainnet.infura.io/v3/a8ef08c3916542bebb40be254d8072b2",AccountIndex)
          // return new HDWalletProvider(process.env.PRIVATE_KEY, "https://mainnet.infura.io/v3/105d810a150c4ae6bfc417ebdbb14e84");
      },
      network_id: "1",      
    }     
  },
  compilers: {
    solc: {
    version: "0.8.17"
    }
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 180
    }
  },
  plugins: ['truffle-plugin-verify','truffle-contract-size']
};
