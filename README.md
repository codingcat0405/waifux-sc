# Smartcontract project for CryptoPop

# Requirement

 -  NodeJS
 -  Yarn
 -  Ganache
 
## Create .env file from env.example
Edit ganache private key,MNEMONIC  and Bscscan API 


## Compile
`yarn compile`
## Test
`yarn test`
## Deploy
`yarn deploy dev`
## Verify 
```
yarn hardhat verify --network bsctest 0xCONTRACTADDRESS
```

## Deployed Contract 
- see in `config.json`
```json
{
  "dev": {},
  "bsctest": {
    "Artwork": "0x8c7Ed89f0B5d3FFA171e5c6410806Ba28103196D",
    "WBNB": "0x115A205FF2F143687470362bABb116dD6a737226",
    "Marketplace": "0x0a8E294463e8c1a82708a1BAa262477D384A62e9",
    "AuctionHouse": "0x5941177E0496DAE2ac5b47580f5221a5F1D66264"
  },
  "main": {}
}
```

