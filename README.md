# SXT Staking Contracts

SXT staking contracts, for staking SXT tokens, nominating validators and unstaking.

## 📑 Table of Contents

- [🛠️ Deployment](#deployment)
- [📧 Contact](#contact)
- [📚 Additional Resources](#additional-resources)

## <a name="deployment"></a>🛠️ Deployment

This can be deployed by running the following

* Set environment variables, preferrably using an env file `.env` file
  ```bash
  # .env file

  # This variable must be the url of the RPC node
  ETH_RPC_URL=

  # The private key of the account to deploy the contract from
  PRIVATE_KEY=

  # The API key for etherscan to verify the contracts
  ETHERSCAN_API_KEY=
  ```

  ```bash
  source .env
  ```

* Run the deployment script
  ```bash
  ./jobs/deploy.sh
  ```

* Dry run the transaction using any of the following (or variations).
    1. Use a Ledger hardware wallet
        ```bash
        forge script script/deploy.s.sol --rpc-url=$ETH_RPC_URL --ledger
        ```
    2. Use a Trezor hardware wallet
        ```bash
        forge script script/deploy.s.sol --rpc-url=$ETH_RPC_URL --trezor
        ```
    3. Use the foundry keystore, which can be set up using `cast wallet`. Be sure to set the `ETH_KEYSTORE_ACCOUNT` env variable.
        ```bash
        forge script script/deploy.s.sol --rpc-url=$ETH_RPC_URL
        ```
    4. Use a private key
        ```bash
        forge script script/deploy.s.sol --rpc-url=$ETH_RPC_URL --private-key=$PRIVATE_KEY
        ```
* Add `--broadcast` to actually run the deployment.


## <a name="contact"></a>📧 Contact

For questions on this repository, please open an issue.

## <a name="additional-resources"></a>📚 Additional Resources

- [📜 License](LICENSE)
- [👨‍💻 Code Owners](CODEOWNERS)