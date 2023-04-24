# Marketplace

Solidity contracts used in [Pawnfi](https://www.pawnfi.com/) marketplace.

## Overview

The Marketplace contract offers an NFT listing and offer service on the Ethereum blockchain. It facilitates the purchase of a signed NFT by a buyer from a seller, with the seller being contractually obligated to sell the NFT to the buyer at the price agreed upon and signed by both parties.

## Audits

- PeckShield ( - ) : [report](./audits/audits.pdf) (Also available in Chinese in the same folder)

## Contracts

### Installation

- To run marketplace, pull the repository from GitHub and install its dependencies. You will need [npm](https://docs.npmjs.com/cli/install) installed.

```bash
git clone https://github.com/PawnFi/Marketplace.git
cd Marketplace
npm install 
```
- Create an enviroment file named `.env` and fill the next enviroment variables

```
# Import private key
PRIVATEKEY= your private key  

# Add Infura provider keys
MAINNET_NETWORK=https://mainnet.infura.io/v3/YOUR_API_KEY
GOERLI_NETWORK=https://goerli.infura.io/v3/YOUR_API_KEY

```

### Compile

```
npx hardhat compile
```



### Local deployment

In order to deploy this code to a local testnet, you should install the npm package `@pawnfi/marketplace` and import the approveTrade bytecode located at
`@pawnfi/marketplace/artifacts/contracts/PawnfiApproveTrade.sol/PawnfiApproveTrade.json`.
For example:

```typescript
import {
  abi as APPROVETRADE_ABI,
  bytecode as APPROVETRADE_BYTECODE,
} from '@pawnfi/marketplace/artifacts/contracts/PawnfiApproveTrade.sol/PawnfiApproveTrade.json'

// deploy the bytecode
```

This will ensure that you are testing against the same bytecode that is deployed to mainnet and public testnets, and all Pawnfi code will correctly interoperate with your local deployment.

### Using solidity interfaces

The Pawnfi marketplace interfaces are available for import into solidity smart contracts via the npm artifact `@pawnfi/marketplace`, e.g.:

```solidity
import '@pawnfi/marketplace/contracts/interfaces/IPawnfiApproveTrade.sol';

contract MyContract {
  IPawnfiApproveTrade approveTrade;

  function doSomethingWithApproveTrade() {
    // approveTrade.matchAskWithTakerBid(...);
  }
}

```

## Discussion

For any concerns with the protocol, open an issue or visit us on [Discord](https://discord.com/invite/pawnfi) to discuss.

For security concerns, please email [dev@pawnfi.com](mailto:dev@pawnfi.com).

_© Copyright 2023, Pawnfi Ltd._
