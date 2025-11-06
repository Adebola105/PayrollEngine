;; SalaryFlow - Automated Employee Payroll Streaming
;; Version: 1.0.0 - Enterprise Edition

;; ==============================================
;; CONSTANTS & ERROR CODES
;; ==============================================

(define-constant company-admin tx-sender)
(define-constant max-payrolls u1000)
(define-constant min-employment-period u144) ;; ~24 hours in blocks
(define-constant processing-fee u50) ;; 0.5% (50/10000)

;; Error codes
(define-constant err-not-authorized (err u100))
(define-constant err-invalid-payroll (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-payroll-not-found (err u103))
(define-constant err-payroll-terminated (err u104))
(define-constant err-invalid-employment-period (err u105))
(define-constant err-payroll-inactive (err u107))
(define-constant err-salary-not-available (err u108))
(define-constant err-max-payrolls-reached (err u109))

;; ==============================================
;; DATA STRUCTURES
;; ==============================================

;; Employment status
(define-constant employment-active u1)
(define-constant employment-suspended u2)
(define-constant employment-terminated u3)
(define-constant employment-ended u4)

;; Core payroll data
(define-map payrolls
  { payroll-id: uint }
  {
    employer: principal,
    employee: principal,
    salary-amount: uint,
    hourly-rate: uint,
    hire-date: uint,
    contract-duration: uint,
    paid-out: uint,
    employment-status: uint,
    suspension-date: uint,
    total-suspended-time: uint
  })

;; Payroll escrow
(define-map payroll-escrow
  { payroll-id: uint }
  { escrowed-amount: uint, available-balance: uint })

;; Company employee tracking
(define-map company-employees
  { employee: principal }
  { active-payrolls: (list 50 uint), payroll-count: uint })

;; ==============================================
;; STATE VARIABLES
;; ==============================================

(define-data-var next-payroll-id uint u1)
(define-data-var total-payrolls uint u0)
(define-data-var system-paused bool false)
(define-data-var total-payroll-volume uint u0)
(define-data-var processing-fees-collected uint u0)

;; ==============================================
;; PRIVATE HELPER FUNCTIONS
;; ==============================================

;; Calculate available salary for withdrawal
(define-private (calculate-available-salary (payroll-id uint))
  (match (map-get? payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (current-block block-height)
      (hire-date (get hire-date payroll-data))
      (hourly-rate (get hourly-rate payroll-data))
      (paid-out (get paid-out payroll-data))
      (employment-status (get employment-status payroll-data))
      (contract-duration (get contract-duration payroll-data))
      (suspended-time (get total-suspended-time payroll-data))
    )
    (if (is-eq employment-status employment-suspended)
      ;; If suspended, calculate up to suspension date
      (let ((hours-worked (- (get suspension-date payroll-data) hire-date suspended-time)))
        (if (> hours-worked u0)
          (- (* hourly-rate hours-worked) paid-out)
          u0))
      ;; If active, calculate current available
      (if (>= current-block hire-date)
        (let (
          (hours-worked (- current-block hire-date suspended-time))
          (max-hours (if (> hours-worked contract-duration) contract-duration hours-worked))
        )
        (if (> max-hours u0)
          (- (* hourly-rate max-hours) paid-out)
          u0))
        u0)))
    u0))

;; Validate payroll parameters
(define-private (validate-payroll-params (employee principal) (salary uint) (duration uint))
  (and
    (not (is-eq employee tx-sender))
    (> salary u0)
    (>= duration min-employment-period)
    (< (var-get total-payrolls) max-payrolls)))

;; Add employee payroll
(define-private (add-employee-payroll (employee principal) (payroll-id uint))
  (map-set company-employees
    { employee: employee }
    { active-payrolls: (list payroll-id), payroll-count: u1 }))

;; Remove employee payroll
(define-private (remove-employee-payroll (employee principal) (payroll-id uint))
  true)

;; Calculate processing fee
(define-private (calculate-processing-fee (salary uint))
  (/ (* salary processing-fee) u10000))

;; ==============================================
;; PUBLIC FUNCTIONS - CORE PAYROLL
;; ==============================================

;; Create payroll contract
(define-public (create-payroll-contract 
  (employee principal)
  (total-salary uint)
  (contract-duration uint))
  
  (let (
    (payroll-id (var-get next-payroll-id))
    (current-block block-height)
    (hourly-rate (/ total-salary contract-duration))
    (processing-fee-amount (calculate-processing-fee total-salary))
    (total-with-fee (+ total-salary processing-fee-amount))
  )
  
  ;; Validation
  (asserts! (not (var-get system-paused)) err-not-authorized)
  (asserts! (validate-payroll-params employee total-salary contract-duration) err-invalid-payroll)
  (asserts! (>= (stx-get-balance tx-sender) total-with-fee) err-insufficient-funds)
  
  ;; Transfer funds to escrow
  (try! (stx-transfer? total-with-fee tx-sender (as-contract tx-sender)))
  
  ;; Create payroll
  (map-set payrolls
    { payroll-id: payroll-id }
    {
      employer: tx-sender,
      employee: employee,
      salary-amount: total-salary,
      hourly-rate: hourly-rate,
      hire-date: current-block,
      contract-duration: contract-duration,
      paid-out: u0,
      employment-status: employment-active,
      suspension-date: u0,
      total-suspended-time: u0
    })
  
  ;; Track escrow
  (map-set payroll-escrow
    { payroll-id: payroll-id }
    { escrowed-amount: total-salary, available-balance: total-salary })
  
  ;; Update state
  (var-set next-payroll-id (+ payroll-id u1))
  (var-set total-payrolls (+ (var-get total-payrolls) u1))
  (var-set total-payroll-volume (+ (var-get total-payroll-volume) total-salary))
  (var-set processing-fees-collected (+ (var-get processing-fees-collected) processing-fee-amount))
  
  ;; Update employee tracking
  (add-employee-payroll tx-sender payroll-id)
  (add-employee-payroll employee payroll-id)
  
  (ok payroll-id)))

;; Withdraw salary
(define-public (withdraw-salary (payroll-id uint))
  (let (
    (payroll-data (unwrap! (map-get? payrolls { payroll-id: payroll-id }) err-payroll-not-found))
    (available-salary (calculate-available-salary payroll-id))
  )
  
  ;; Validation
  (asserts! (is-eq tx-sender (get employee payroll-data)) err-not-authorized)
  (asserts! (is-eq (get employment-status payroll-data) employment-active) err-payroll-inactive)
  (asserts! (> available-salary u0) err-salary-not-available)
  
  ;; Update payroll
  (map-set payrolls
    { payroll-id: payroll-id }
    (merge payroll-data {
      paid-out: (+ (get paid-out payroll-data) available-salary)
    }))
  
  ;; Update escrow
  (match (map-get? payroll-escrow { payroll-id: payroll-id })
    escrow-data
    (map-set payroll-escrow
      { payroll-id: payroll-id }
      (merge escrow-data {
        available-balance: (- (get available-balance escrow-data) available-salary)
      }))
    false)
  
  ;; Transfer funds
  (try! (as-contract (stx-transfer? available-salary tx-sender (get employee payroll-data))))
  
  ;; Check completion
  (let ((new-paid-out (+ (get paid-out payroll-data) available-salary)))
    (if (>= new-paid-out (get salary-amount payroll-data))
      (begin
        (map-set payrolls
          { payroll-id: payroll-id }
          (merge payroll-data { employment-status: employment-ended }))
        (remove-employee-payroll (get employer payroll-data) payroll-id)
        (remove-employee-payroll (get employee payroll-data) payroll-id))
      false))
  
  (ok available-salary)))

;; ==============================================
;; PAYROLL MANAGEMENT
;; ==============================================

;; Suspend payroll
(define-public (suspend-payroll (payroll-id uint))
  (let (
    (payroll-data (unwrap! (map-get? payrolls { payroll-id: payroll-id }) err-payroll-not-found))
  )
  (asserts! (is-eq tx-sender (get employer payroll-data)) err-not-authorized)
  (asserts! (is-eq (get employment-status payroll-data) employment-active) err-payroll-inactive)
  
  (map-set payrolls
    { payroll-id: payroll-id }
    (merge payroll-data {
      employment-status: employment-suspended,
      suspension-date: block-height
    }))
  
  (ok true)))

;; Resume payroll
(define-public (resume-payroll (payroll-id uint))
  (let (
    (payroll-data (unwrap! (map-get? payrolls { payroll-id: payroll-id }) err-payroll-not-found))
    (suspension-duration (- block-height (get suspension-date payroll-data)))
  )
  (asserts! (is-eq tx-sender (get employer payroll-data)) err-not-authorized)
  (asserts! (is-eq (get employment-status payroll-data) employment-suspended) err-payroll-inactive)
  
  (map-set payrolls
    { payroll-id: payroll-id }
    (merge payroll-data {
      employment-status: employment-active,
      total-suspended-time: (+ (get total-suspended-time payroll-data) suspension-duration),
      suspension-date: u0
    }))
  
  (ok true)))

;; Terminate payroll
(define-public (terminate-payroll (payroll-id uint))
  (let (
    (payroll-data (unwrap! (map-get? payrolls { payroll-id: payroll-id }) err-payroll-not-found))
    (escrow-data (unwrap! (map-get? payroll-escrow { payroll-id: payroll-id }) err-payroll-not-found))
  )
  
  (asserts! (is-eq tx-sender (get employer payroll-data)) err-not-authorized)
  (asserts! (not (is-eq (get employment-status payroll-data) employment-terminated)) err-payroll-terminated)
  
  (let (
    (available-to-employee (calculate-available-salary payroll-id))
    (remaining-to-employer (- (get available-balance escrow-data) available-to-employee))
  )
  
  ;; Update status
  (map-set payrolls
    { payroll-id: payroll-id }
    (merge payroll-data { employment-status: employment-terminated }))
  
  ;; Distribute funds
  (if (> available-to-employee u0)
    (try! (as-contract (stx-transfer? available-to-employee tx-sender (get employee payroll-data))))
    true)
  
  (if (> remaining-to-employer u0)
    (try! (as-contract (stx-transfer? remaining-to-employer tx-sender (get employer payroll-data))))
    true)
  
  ;; Clean up tracking
  (remove-employee-payroll (get employer payroll-data) payroll-id)
  (remove-employee-payroll (get employee payroll-data) payroll-id)
  
  (ok true))))

;; ==============================================
;; READ-ONLY FUNCTIONS
;; ==============================================

;; Get payroll info
(define-read-only (get-payroll-info (payroll-id uint))
  (match (map-get? payrolls { payroll-id: payroll-id })
    payroll-data
    (let (
      (escrow (map-get? payroll-escrow { payroll-id: payroll-id }))
      (available-now (calculate-available-salary payroll-id))
    )
    (ok {
      payroll: payroll-data,
      escrow: escrow,
      available-for-withdrawal: available-now
    }))
    err-payroll-not-found))

;; Get employee payrolls
(define-read-only (get-employee-payrolls (employee principal))
  (map-get? company-employees { employee: employee }))

;; Get system stats
(define-read-only (get-system-stats)
  (ok {
    total-payrolls: (var-get total-payrolls),
    total-volume: (var-get total-payroll-volume),
    processing-fees: (var-get processing-fees-collected),
    is-paused: (var-get system-paused)
  }))

;; ==============================================
;; ADMIN FUNCTIONS
;; ==============================================

;; Toggle system pause
(define-public (toggle-system-pause)
  (begin
    (asserts! (is-eq tx-sender company-admin) err-not-authorized)
    (var-set system-paused (not (var-get system-paused)))
    (ok (var-get system-paused))))

;; Withdraw processing fees
(define-public (withdraw-processing-fees)
  (let ((fees (var-get processing-fees-collected)))
    (asserts! (is-eq tx-sender company-admin) err-not-authorized)
    (asserts! (> fees u0) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? fees tx-sender company-admin)))
    (var-set processing-fees-collected u0)
    
    (ok fees)))