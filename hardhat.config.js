/**
    * @type import('hardhat/config').HardhatUserConfig
*/
require("@nomiclabs/hardhat-ethers");
require("dotenv").config()

const SOL_VERSION = process.env.SOL_VERSION || "0.8.3"
const FORK_NODE_URL = process.env.FORK_NODE_URL
const MAINNET_DEPLOY_PRIVATE_KEY = process.env.MAINNET_DEPLOY_PRIVATE_KEY
const RINKEBY_DEPLOY_PRIVATE_KEY = process.env.RINKEBY_DEPLOY_PRIVATE_KEY
const LOCALNET_DEPLOY_PRIVATE_KEY = process.env.LOCALNET_DEPLOY_PRIVATE_KEY
const MAINNET_NODE_URL = process.env.MAINNET_NODE_URL
const RINKEBY_NODE_URL = process.env.RINKEBY_NODE_URL

let HARDHAT_CONFIG = {}
let MAINNET_CONFIG = {}
let RINKEBY_CONFIG = {}
let NETWORKS_CONFIG = {}

// configure hardhat
if (LOCALNET_DEPLOY_PRIVATE_KEY) HARDHAT_CONFIG.accounts = [ LOCALNET_DEPLOY_PRIVATE_KEY ]
if (FORK_NODE_URL) {
    HARDHAT_CONFIG.forking = {
        url: FORK_NODE_URL
    }
}
NETWORKS_CONFIG.hardhat = HARDHAT_CONFIG

// configure main net
if (MAINNET_DEPLOY_PRIVATE_KEY && MAINNET_NODE_URL) {
    MAINNET_CONFIG.accounts = [ MAINNET_DEPLOY_PRIVATE_KEY ]
    MAINNET_CONFIG.url = MAINNET_NODE_URL
    NETWORKS_CONFIG.mainnet = MAINNET_CONFIG
}

// configure rinkeby
if (RINKEBY_DEPLOY_PRIVATE_KEY && RINKEBY_NODE_URL) {
    RINKEBY_CONFIG.accounts = [ RINKEBY_DEPLOY_PRIVATE_KEY ]
    RINKEBY_CONFIG.url = RINKEBY_NODE_URL
    NETWORKS_CONFIG.rinkeby = RINKEBY_CONFIG
}

console.log(NETWORKS_CONFIG)
module.exports = {
    solidity: {
        version: SOL_VERSION,
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    networks: NETWORKS_CONFIG
}
