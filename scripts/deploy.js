// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat")
const { ethers } = hre

async function main() {
    let provider = ethers.getDefaultProvider()
    let [ deployer ] = await hre.ethers.getSigners()

    await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: ["0xAaaDbbAc0C00F44D658A5D5526dA7E4b9A4DFef2"],
    });
    deployer = await ethers.getSigner("0xAaaDbbAc0C00F44D658A5D5526dA7E4b9A4DFef2")

    console.log("Deploying contracts with the account:", deployer.address)
    console.log("Account balance:", (await deployer.getBalance()).toString())


    const FEE_SHARING_ADDR = '0xBcD7254A1D759EFA08eC7c3291B2E85c5dCC12ce';
    const LOOKS_ADDR = '0xf4d2888d29D722226FafA5d9B24F9164c092421E';
    const WETH9 = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
    const SWAP_ROUTER = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
    const UNI_FACTORY = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
    const PRECISION_FACTOR = 10**18;

    const DEPLOYMENT = '0x40918ba7f132e0acba2ce4de4c4baf9bd2d7d849';

    let arbContract
    if (DEPLOYMENT) {
        arbContract = await hre.ethers.getContractAt("UniSwapArb", DEPLOYMENT)
    } else {
        // get contract factor and deploy
        let arbFact = await hre.ethers.getContractFactory("UniSwapArb")
        console.log("About to deploy")
        arbContract = await arbFact.deploy(
            SWAP_ROUTER,
            UNI_FACTORY,
            WETH9,
            LOOKS_ADDR,
            FEE_SHARING_ADDR
        )
        await arbContract.deployed()
        console.log("deployed contract address:", arbContract.address);
    }

    let amnt = ethers.constants.WeiPerEther.mul(100000)
    await arbContract.startArb(amnt);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
