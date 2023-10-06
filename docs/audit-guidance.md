# Audit guidance

Please see the documentation website for details of our bug bounty and responsible disclosure programs.

Hello auditors! We'd like to say thank you for working with Mantle on reviewing our contracts. We take our commitment to security very seriously, so please reach out if you are unsure of any aspects about the design of the system and we will be happy to clarify. We wanted to share some thoughts and guidance on the how the contracts are designed, which will hopefully shed some light on some of the nuances and will let you complete an audit without having to make assumptions which we then challenge later.

### Work in scope

Not all files in the repo are in scope for audits. You should assume that any non-script files which list perceived sensitive data are intentional. For example, we may list private keys in readmes and config for our dev networks. These keys are not used anywhere else and should not be considered a problem.

### Design principals

The Mantle LSP system is intended to be extremely durable and to live for many years. Therefore, contracts are designed with simplicity and readability in mind above all else. There are many cases where things could be done "more efficiently", for example, we choose not to use bitwise operations to store multiple boolean flags. This is absolutely intentional and is by design, so we would prefer not to receive issues about them (see notes on where we do care about efficiency in the gas section below).

### Trust assumptions

Please understand that the system is not designed to be entirely decentralized. The trust assumption is that Mantle has the ability to change the behavior of the protocol at all times. While the contracts are designed to ensure the safety of user funds, we acknowledge (like in other popular protocols) that anybody with the ability to upgrade the contracts can make changes which could adversely effect the system.
Please be aware that all "privileged" operations will be done by the Mantle security council, and therefore the same trust assumptions apply. We will not accept any issues which claim "centralization risks" because of this.

### Oracle

The oracle, whilst still ultimately having the same trust assumptions as above, is intended to be run with multiple instances. We are aware that the code initializes with a single oracle in the quorum set - this is to simplify testing. For all issues you should assume that the mainnet configuration of at least 3 independent oracles will be used. As such, we are interested in ways which an attacker that takes control of all oracles can affect the system, but we deem this to be a low likelihood and therefore low severity (unless it leads to complete loss of funds). We would also like to note that the oracle has mechanisms for recoverability by the security council if needed.

### Gas

Generally, we only care about gas on "user hot paths". These are the functions which make up the main user interactions with the system; staking, unstaking and claiming. Even in these cases, we prefer safety and readability above micro gas optimizations. We intentionally do not use tricks, unchecked or assembly for optimizations - please do not raise issues about this.

In other paths, such as service-driven or admin functions, we put even less emphasis on gas. In a protocol which will handle $1B+, the risk of introducing issues via gas-optimized complexity far outweighs the benefit of the saving a few dollars on transactions which happen infrequently. This, of course, also extends to deployment time - we are not optimizing for cost of deployment. Please do not raise any gas issues unless there are proven significant savings on user hot paths which also maintain readability.

### Assumed competence

Generally, you should assume competence on behalf of the operator. Mantle assumes the risk of using correct initialization parameters and setter parameters. In reality, these will be checked thoroughly and the transactions will be executed by a multi-sig consisting of many people. Please do not raise issues for input validation on functions, unless it is not possible to recover from the change, or the change has an unexpected adverse effect on the system.
