# FloodGuard: Blockchain Early Warning & Relief

**Blockchain-Based Flood Early Warning and Transparent Disaster Relief System for Nepal**

![FloodGuard architecture](docs/architecture.png)

FloodGuard is a proof-of-concept project exploring how blockchain technology and risk assessment can support flood early-warning systems and transparent disaster relief in Nepal.

The prototype combines a Solidity smart contract for recording relief transactions with a Python-based risk engine for assessing flood risk and generating sample alerts. It explores how emergency warnings can remain fast while relief funding and aid distribution become more traceable.

**Project status:** Experimental prototype, not audited, and not intended for operational emergency warnings or real financial transactions.

## Problem Statement

Flood-prone communities can face sudden disasters, delayed warnings, and difficulties tracking relief funding. Donors and aid recipients may lack a shared, verifiable record of how funds are allocated and distributed.

FloodGuard explores two complementary approaches:

- **Early warning:** Assess environmental risk and generate timely alerts.
- **Transparent relief:** Record donations, verification steps, and aid distribution on a shared blockchain ledger.

## Proposed Solution

FloodGuard separates time-sensitive risk assessment from blockchain-based recordkeeping.

1. Environmental data can be assessed by a Python risk engine.
2. Risk scores determine sample alert levels.
3. Alerts can be generated in English and Nepali.
4. Alert hashes can be recorded on-chain for verification.
5. Household registration and evacuation confirmations can be recorded.
6. Donations can be collected in disaster-specific pools.
7. Aid claims can be submitted and released after configured verification steps.

These capabilities represent the intended design of the prototype, not validated real-world outcomes.

## Key Features

- Rule-based flood-risk scoring
- Sample early-warning alerts
- English and Nepali alert messages
- Blockchain-based alert-hash recording
- Disaster-specific donation pools
- Household registration and evacuation tracking
- Verified aid claims and payment release
- Safeguards against duplicate registrations and claims
- Per-household aid limits

## How It Works

```text
Environmental Data
        ↓
Python Risk Engine
        ↓
Risk Assessment and Alerts
        ↓
Alert Hash Recording
        ↓
Blockchain Relief Ledger
        ↓
Donation Tracking and Verified Aid Distribution
```

Risk assessment and alert generation operate off-chain to avoid blockchain delays. Blockchain functions provide an auditable record of configured relief activities.

## Technology Stack

- **Solidity:** Smart contracts for donations and aid distribution
- **Python:** Rule-based risk assessment and alert generation
- **Blockchain:** Recording alerts and relief transactions
- **SMS integration:** Planned alert-delivery capability
- **Web3 integration:** Planned connection between the risk engine and smart contract

## Repository Structure

```text
floodguard/
├── README.md
├── docs/
│   └── architecture.png
├── contracts/
│   └── FloodRelief.sol
└── risk_engine/
    └── risk_engine.py
```

## Getting Started

### 1. Run the risk engine

Requires Python 3.8 or newer.

```bash
python risk_engine/risk_engine.py
```

The demonstration runs sample stations and prints example alerts in English and Nepali, along with hashes that could be recorded on-chain.

### 2. Test the smart contract

1. Open [Remix IDE](https://remix.ethereum.org/).
2. Load `contracts/FloodRelief.sol`.
3. Compile using a compatible Solidity compiler version.
4. Deploy to a test environment for experimentation.
5. Explore disaster creation, donations, household registration, evacuation confirmation, aid claims, and receipt confirmation.

Never use this unaudited prototype for real funds or operational disaster response.

## Roadmap

1. Connect the risk engine to the smart contract.
2. Integrate an SMS gateway for alerts.
3. Develop a dashboard for relief tracking.
4. Evaluate risk scoring against historical flood data.
5. Explore secure household receipt confirmation.
6. Conduct independent security and privacy reviews.
7. Evaluate a small pilot with relevant local stakeholders.

## Limitations and Safety

- The risk model is a basic rule-based prototype, not a validated forecasting system.
- Live sensor feeds, satellite integrations, and SMS delivery are not established as production-ready integrations.
- Blockchain records cannot independently verify whether real-world reports are truthful.
- Hashes and public transactions may still present privacy risks.
- The smart contract has not undergone an independent security audit.

**FloodGuard is an experimental project. It must not be used for real emergency alerts, evacuation decisions, operational relief distribution, or real-money transactions.**

## Project Credits

FloodGuard is an independent proof-of-concept project developed by Pratik Pokhrel.

## License

MIT License. See the `LICENSE` file for the applicable terms.
