# Flux

A modular DeFi lending protocol built on the Stacks blockchain, enabling users to supply liquidity, borrow against collateral, and participate in a decentralized money market.

## Overview

Flux is a lending protocol that allows users to:
- **Supply liquidity** and earn interest on their STX tokens
- **Borrow STX** against collateral with dynamic interest rates
- **Liquidate undercollateralized positions** to maintain protocol solvency

The protocol uses a trait-based architecture with separated concerns, implementing sophisticated interest rate models and risk management mechanisms.

## Key Features

### 📈 Dynamic Interest Rates
- Utilization-based interest rate model with configurable parameters
- Kinked rate curve for optimal capital efficiency
- Separate supply and borrow rates with protocol fees

### 🔒 Collateralized Lending
- Over-collateralized borrowing with configurable collateral factors
- Real-time health factor monitoring
- Automated liquidation mechanism for risk management

### 💧 Liquidity Provision
- Share-based accounting for fair interest distribution
- Continuous interest accrual using time-weighted calculations
- Seamless deposit and withdrawal of liquidity

### ⚡ Liquidation Engine
- Health-based position monitoring
- Liquidator incentives for maintaining protocol solvency
- Partial and full liquidation support

## Protocol Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| Base Interest Rate | 2% | Minimum borrowing rate |
| Interest Multiplier | 10% | Rate slope before kink |
| Jump Rate | 60% | Rate slope after kink |
| Utilization Kink | 80% | Optimal utilization point |
| Collateral Factor | 75% | Maximum LTV ratio |
| Liquidation Incentive | 10% | Liquidator reward |
| Protocol Fee | 10% | Protocol reserve percentage |

## Core Functions

### For Lenders
```clarity
;; Supply STX to earn interest
(provide-liquidity amount)

;; Withdraw supplied STX plus accrued interest
(withdraw-liquidity amount)
```

### For Borrowers
```clarity
;; Deposit STX as collateral
(deposit-collateral-tokens amount)

;; Borrow STX against collateral
(take-loan amount)

;; Repay borrowed STX
(repay-loan amount)

;; Withdraw collateral (if health factor allows)
(withdraw-collateral-tokens amount)
```

### For Liquidators
```clarity
;; Liquidate undercollateralized positions
(liquidate-position borrower repay-amount)
```

## Interest Rate Model

Flux uses a kinked interest rate model:

```
Rate = Base + (Utilization × Multiplier)  [if Utilization ≤ Kink]
Rate = Base + Multiplier + ((Utilization - Kink) × Jump) / (1 - Kink)  [if Utilization > Kink]
```

This creates:
- Low rates at low utilization to encourage borrowing
- Moderate rates at optimal utilization
- High rates at extreme utilization to encourage repayment

## Risk Management

### Health Factor
```clarity
Health Factor = (Collateral × Collateral Factor) / Debt
```

Positions with Health Factor < 1.0 are eligible for liquidation.

### Liquidation Process
1. Anyone can liquidate undercollateralized positions
2. Liquidator repays borrower's debt
3. Liquidator receives collateral + liquidation incentive
4. Remaining collateral stays with borrower

## Security Features

- **Access Control**: Admin functions restricted to protocol owner
- **Overflow Protection**: Safe arithmetic operations throughout
- **Input Validation**: Comprehensive parameter checking
- **State Consistency**: Atomic operations for critical state changes

## Getting Started

### Prerequisites
- Stacks wallet (Hiro, Xverse, etc.)
- STX tokens for transactions and collateral

### Deployment
1. Deploy the contract to Stacks blockchain
2. Call `bootstrap-protocol` to initialize timestamps
3. Configure parameters using admin functions (optional)

### Usage Example

```clarity
;; 1. Supply 1000 STX to earn interest
(contract-call? .flux provide-liquidity u1000000000)

;; 2. Deposit 2000 STX as collateral
(contract-call? .flux deposit-collateral-tokens u2000000000)

;; 3. Borrow 1000 STX (75% LTV)
(contract-call? .flux take-loan u1000000000)

;; 4. Repay loan
(contract-call? .flux repay-loan u1000000000)
```

## Read-Only Functions

Monitor protocol and account state:

```clarity
;; Check market utilization
(get-market-utilization)

;; Get current interest rates
(calculate-borrow-rate)
(calculate-supply-rate)

;; Check account balances
(get-account-supply account)
(get-account-debt account)
(get-account-collateral account)

;; Verify account health
(check-account-health account)
```

## Architecture

The protocol follows a modular design:

- **State Management**: Centralized storage with clear separation
- **Interest Calculations**: Time-based accrual with precise arithmetic
- **Account Management**: Efficient share-based accounting
- **Risk Assessment**: Real-time health monitoring
- **Admin Controls**: Flexible parameter management

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 401 | E_UNAUTHORIZED | Caller lacks required permissions |
| 402 | E_INVALID_INPUT | Invalid function parameters |
| 403 | E_INSUFFICIENT_FUNDS | Insufficient balance for operation |
| 404 | E_UNDERCOLLATERALIZED | Position health factor too low |
| 405 | E_MARKET_FROZEN | Protocol operations paused |
| 406 | E_POSITION_SAFE | Position not eligible for liquidation |
| 407 | E_NO_DEBT | Account has no outstanding debt |
| 408 | E_LIQUIDATION_FAILED | Liquidation execution failed |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement changes with tests
4. Submit a pull request

## Disclaimer

This is experimental DeFi software. Users should understand the risks including but not limited to smart contract vulnerabilities, liquidation risk, and market volatility. Never invest more than you can afford to lose.