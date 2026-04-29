# Crowdfunding (Foundry)

A learning-focused crowdfunding smart contract built with Solidity and tested using Foundry. This project focuses on secure fund handling, state transitions, and advanced testing techniques like fuzzing and invariants.

---

## Features

* Create campaigns with funding goal and deadline
* Users can fund campaigns with ETH
* Refund mechanism if campaign fails
* Creator can withdraw funds if goal is reached
* Tracks per-user contributions
* Gas-optimized storage using smaller data types

---

## Core Logic

* Campaign creator sets:
  * `goal`
  * `deadline`
* Users fund before deadline
* Outcomes:
  * **Success** → creator withdraws funds
  * **Failure** → users claim refunds

---

## Testing

This project includes:

* **Unit Tests** – Core functionality validation
* **Fuzz Tests** – Randomized input testing
* **Invariant Tests (Handler-based)** – System-level correctness across all states

---

## Invariants Tested

* Total contributions always match `amountRaised`
* Sum of all user contributions equals contract accounting
* No user contribution exceeds total raised
* Contract balance matches `amountRaised` (if not withdrawn)
* After withdrawal, contract balance is zero

---

## Tech Stack

* Solidity ^0.8.20
* Foundry

---

## Project Structure
```
src/ # Smart contracts
script/ # Deployment scripts
test/
├── unit/ # Unit tests
├── fuzz/ # Fuzz tests
└── invariant/ # Invariant tests (handler-based)
```


---

## Notes

* Designed as a **learning project**, not production-ready
* Focuses on correctness, edge cases, and attack-resistant logic
* Covers full lifecycle: **fund → refund → withdraw**
* Demonstrates invariant testing with a custom handler

---