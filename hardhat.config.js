const dotenv = require("dotenv");
dotenv.config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    paths: {
        sources: "./contracts",
        tests: "./test",
        cache: "./cache",
        artifacts: "./artifacts",
    },
    defaultNetwork: process.env.NETWORK || "sepolia",
    networks: {
        hardhat: {
            chainId: 1337,
        },
        sepolia: {
            url: process.env.SEPOLIA_URL,
            accounts: [`0x${process.env.SEPOLIA_KEY}`],
        },
        localhost: {
            url: process.env.LOCAL_CHAIN,
            chainId: 1337,
        },
    },
    solidity: {
        version: "0.8.17",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
};
