# SalaryFlow - Automated Employee Payroll Streaming

Version 1.0.0 - Enterprise Edition

## Overview

SalaryFlow is a decentralized payroll streaming smart contract built on the Stacks blockchain. It enables employers to create automated, block-by-block salary payments for employees, providing real-time access to earned wages without manual payroll processing.

## Key Features

- **Automated Salary Streaming**: Employees earn salary on a per-block basis and can withdraw at any time
- **Escrow Protection**: All funds are held in smart contract escrow until earned
- **Flexible Payroll Management**: Employers can suspend, resume, or terminate payroll contracts
- **Processing Fee System**: Built-in 0.5% processing fee for platform sustainability
- **Multi-Employee Support**: Track up to 1,000 active payroll contracts
- **Transparent Accounting**: All transactions and balances are verifiable on-chain

## Technical Specifications

### Constants

- **Minimum Employment Period**: 144 blocks (approximately 24 hours)
- **Maximum Payrolls**: 1,000 concurrent contracts
- **Processing Fee**: 0.5% (50 basis points)
- **Company Admin**: Set at contract deployment

### Employment Status Types

1. **Active (1)**: Employee is actively accruing salary
2. **Suspended (2)**: Temporarily paused, no salary accrual
3. **Terminated (3)**: Contract ended by employer
4. **Ended (4)**: Contract completed, all funds paid out

## Core Functions

### For Employers

#### create-payroll-contract
Creates a new payroll contract for an employee.

**Parameters:**
- `employee` (principal): Employee's wallet address
- `total-salary` (uint): Total salary amount in microSTX
- `contract-duration` (uint): Contract length in blocks

**Returns:** Payroll ID

**Requirements:**
- Employee cannot be the employer
- Total salary must be greater than 0
- Duration must be at least 144 blocks
- Employer must have sufficient balance (salary + 0.5% fee)

**Example:**
```clarity
(contract-call? .salaryflow create-payroll-contract 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u10000000000 u4320)
```

#### suspend-payroll
Temporarily suspends salary accrual for an employee.

**Parameters:**
- `payroll-id` (uint): ID of the payroll to suspend

**Returns:** Boolean success

**Requirements:**
- Caller must be the employer
- Payroll must be active

#### resume-payroll
Resumes a suspended payroll contract.

**Parameters:**
- `payroll-id` (uint): ID of the payroll to resume

**Returns:** Boolean success

**Requirements:**
- Caller must be the employer
- Payroll must be suspended

**Notes:** Suspended time is tracked and excluded from salary calculations

#### terminate-payroll
Terminates a payroll contract and distributes remaining funds.

**Parameters:**
- `payroll-id` (uint): ID of the payroll to terminate

**Returns:** Boolean success

**Behavior:**
- Calculates earned salary up to termination block
- Transfers earned amount to employee
- Returns unearned funds to employer
- Marks contract as terminated

### For Employees

#### withdraw-salary
Allows employees to withdraw their earned salary at any time.

**Parameters:**
- `payroll-id` (uint): ID of the payroll contract

**Returns:** Amount withdrawn in microSTX

**Requirements:**
- Caller must be the employee
- Payroll must be active
- Available salary must be greater than 0

**Calculation:**
- Earned salary = (blocks worked × hourly rate) - already paid amount
- Automatically marks contract as "ended" when fully paid

## Read-Only Functions

### get-payroll-info
Retrieves complete information about a payroll contract.

**Parameters:**
- `payroll-id` (uint): ID of the payroll

**Returns:**
```clarity
{
  payroll: {employer, employee, salary-amount, hourly-rate, hire-date, 
            contract-duration, paid-out, employment-status, suspension-date, 
            total-suspended-time},
  escrow: {escrowed-amount, available-balance},
  available-for-withdrawal: uint
}
```

### get-employee-payrolls
Gets all active payrolls for an employee or employer.

**Parameters:**
- `employee` (principal): Wallet address

**Returns:**
```clarity
{
  active-payrolls: (list uint),
  payroll-count: uint
}
```

### get-system-stats
Returns overall platform statistics.

**Returns:**
```clarity
{
  total-payrolls: uint,
  total-volume: uint,
  processing-fees: uint,
  is-paused: bool
}
```

## Admin Functions

### toggle-system-pause
Pauses or resumes the entire system (emergency use only).

**Requirements:** Caller must be company admin

### withdraw-processing-fees
Allows admin to withdraw accumulated processing fees.

**Requirements:** 
- Caller must be company admin
- Fees must be greater than 0

## Error Codes

- **100**: Not authorized
- **101**: Invalid payroll parameters
- **102**: Insufficient funds
- **103**: Payroll not found
- **104**: Payroll already terminated
- **105**: Invalid employment period
- **107**: Payroll inactive
- **108**: No salary available for withdrawal
- **109**: Maximum payrolls reached

## Salary Calculation Logic

### Active Payroll
```
hours_worked = current_block - hire_date - total_suspended_time
max_hours = min(hours_worked, contract_duration)
available_salary = (hourly_rate × max_hours) - paid_out
```

### Suspended Payroll
```
hours_worked = suspension_date - hire_date - total_suspended_time
available_salary = (hourly_rate × hours_worked) - paid_out
```

## Security Features

1. **Escrow Protection**: All funds locked in contract until earned
2. **Authorization Checks**: Function-level access control
3. **State Validation**: Employment status checks prevent invalid operations
4. **Overflow Protection**: Safe math operations throughout
5. **Suspension Tracking**: Accurate time accounting during suspensions

## Deployment

1. Deploy the contract to Stacks blockchain
2. Company admin is set as the deployer address
3. System starts in active (unpaused) state
4. No initial configuration required

## Integration Example

```clarity
;; Employer creates 30-day payroll contract
;; Salary: 1,000 STX (1000000000 microSTX)
;; Duration: 4,320 blocks (approximately 30 days)

(contract-call? .salaryflow create-payroll-contract 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 
  u1000000000 
  u4320)

;; Employee withdraws earned salary after 1 week
(contract-call? .salaryflow withdraw-salary u1)

;; Employer checks payroll status
(contract-call? .salaryflow get-payroll-info u1)
```

## Best Practices

1. **Contract Duration**: Set realistic contract durations based on employment terms
2. **Regular Withdrawals**: Employees should withdraw regularly to minimize escrow exposure
3. **Suspension Usage**: Use suspension for leave/vacation rather than termination
4. **Balance Monitoring**: Employers should monitor escrow balances for each payroll
5. **Gradual Scaling**: Test with small amounts before scaling to production payrolls

## Limitations

1. Maximum 1,000 concurrent payroll contracts
2. Minimum contract duration of 144 blocks (24 hours)
3. Processing fee applies to all new contracts
4. No partial contract modifications (must terminate and recreate)
5. Block-based time calculation (not real-time clock)

## Gas Optimization

The contract uses efficient data structures and minimal storage operations:
- Map-based storage for O(1) lookups
- Consolidated state updates
- Minimal storage reads per operation

## Testing Recommendations

1. Test with small amounts on testnet first
2. Verify salary calculations over different time periods
3. Test suspension and resumption edge cases
4. Validate termination fund distribution
5. Confirm admin functions are properly restricted