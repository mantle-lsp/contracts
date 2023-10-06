source .goerli.env

forge script script/emitter/deploy-emitter.s.sol:Deploy \
-vvvv \
--fork-url $FOUNDRY_RPC_URL \
--keystores $FOUNDRY_KEYSTORE --password $FOUNDRY_KEYSTORE_PASSWORD \
--sender $FOUNDRY_SENDER \
--broadcast \
--verify --etherscan-api-key $FOUNDRY_ETHERSCAN_API_KEY