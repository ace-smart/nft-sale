import * as hre from 'hardhat';
import { BetYourBeans } from '../types/ethers-contracts/BetYourBeans';
import { BetYourBeans__factory } from '../types/ethers-contracts/factories/BetYourBeans__factory';
import address from '../address';

require("dotenv").config();

const { ethers } = hre;

const sleep = (milliseconds, msg='') => {
    console.log(`Wait ${milliseconds} ms... (${msg})`);
    const date = Date.now();
    let currentDate = null;
    do {
      currentDate = Date.now();
    } while (currentDate - date < milliseconds);
}

const toEther = (val) => {
    return ethers.utils.formatEther(val);
}

const parseEther = (val, unit = 18) => {
    return ethers.utils.parseUnits(val, unit);
}

async function deploy() {
    console.log((new Date()).toLocaleString());
    
    const deployer = (await ethers.getSigners()).filter(account => account.address === "0x89352214a56bA80547A2842bbE21AEdD315722Ca")[0];
    
    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const beforeBalance = await deployer.getBalance();
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const mainnet = process.env.NETWORK == "mainnet" ? true : false;
    const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;
    const curBlock = await ethers.getDefaultProvider(url).getBlockNumber();
    const bybAddress = mainnet ? address.mainnet.byb: address.testnet.byb;
    const routerAddress = mainnet ? address.mainnet.unirouter: address.testnet.unirouter;

    const factory: BetYourBeans__factory = new BetYourBeans__factory(deployer);
    let byb: BetYourBeans = factory.attach(bybAddress).connect(deployer);
    if ("redeploy" && true) {
        byb = await factory.deploy();
    }
    console.log(`Deployed BYB... (${byb.address})`);

    if (!mainnet) {
        // await byb.setUniswapRouter(address.testnet.unirouter);
        await byb.approve(address.testnet.unirouter, parseEther('1111111111'));
    }

    const afterBalance = await deployer.getBalance();
    console.log(
        "Deployed cost:",
         (beforeBalance.sub(afterBalance)).toString()
    );
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })