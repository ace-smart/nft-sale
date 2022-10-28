import * as hre from 'hardhat';
import { BetYourBeansNFTSale } from '../types/ethers-contracts/BetYourBeansNFTSale';
import { BetYourBeansNFTSale__factory } from '../types/ethers-contracts/factories/BetYourBeansNFTSale__factory';
import address from '../address';

require("dotenv").config();

const { ethers } = hre;

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
    const nftAddress = mainnet ? address.mainnet.bybNFT.nft: address.testnet.bybNFT.nft;
    const saleAddress = mainnet ? address.mainnet.bybNFT.sale: address.testnet.bybNFT.sale;

    const factory: BetYourBeansNFTSale__factory = new BetYourBeansNFTSale__factory(deployer);
    let sale: BetYourBeansNFTSale = factory.attach(saleAddress).connect(deployer);
    if ("redeploy" && true) {
        sale = await factory.deploy(nftAddress);
    }
    console.log(`Deployed BetYourBeansNFTSale... (${sale.address})`);

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