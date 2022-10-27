import * as hre from 'hardhat';
import { BYBStaking } from '../types/ethers-contracts/BYBStaking';
import { BYBStaking__factory } from '../types/ethers-contracts/factories/BYBStaking__factory';
import { NFTStaking } from '../types/ethers-contracts/NFTStaking';
import { NFTStaking__factory } from '../types/ethers-contracts/factories/NFTStaking__factory';
import { Rewarder } from '../types/ethers-contracts/Rewarder';
import { Rewarder__factory } from '../types/ethers-contracts/factories/Rewarder__factory';
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
    const bybAddress = mainnet ? address.mainnet.byb : address.testnet.byb;
    const nftAddress = mainnet ? address.mainnet.bybNFT.nft: address.testnet.bybNFT.nft;
    const rewarderAddress = mainnet ? address.mainnet.bybStaking.rewarder: address.testnet.bybStaking.rewarder;
    const tokenStakingAddress = mainnet ? address.mainnet.bybStaking.token: address.testnet.bybStaking.token;
    const nftStakingAddress = mainnet ? address.mainnet.bybStaking.nft: address.testnet.bybStaking.nft;

    const rewarderFactory: Rewarder__factory = new Rewarder__factory(deployer);
    let rewarder: Rewarder = rewarderFactory.attach(rewarderAddress).connect(deployer);
    if ("redeploy" && false) {
        rewarder = await rewarderFactory.deploy();
    }
    console.log(`Deployed Rewarder... (${rewarder.address})`);

    const bybStakingFactory: BYBStaking__factory = new BYBStaking__factory(deployer);
    let bybStaking: BYBStaking = bybStakingFactory.attach(tokenStakingAddress).connect(deployer);
    if ("redeploy" && true) {
        bybStaking = await bybStakingFactory.deploy(bybAddress, rewarder.address);
    }
    console.log(`Deployed BYBStaking... (${bybStaking.address})`);

    const nftStakingFactory: NFTStaking__factory = new NFTStaking__factory(deployer);
    let nftStaking: NFTStaking = nftStakingFactory.attach(nftStakingAddress).connect(deployer);
    if ("redeploy" && true) {
        nftStaking = await nftStakingFactory.deploy(nftAddress, rewarder.address);
    }
    console.log(`Deployed NFTStaking... (${nftStaking.address})`);

    if ("Setting pools" && true) {
        await rewarder.setPool(bybStaking.address, true);
        await rewarder.setPool(nftStaking.address, true);
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