;; Modular Lending Protocol
;; Trait-based architecture with separated concerns

;; Protocol Constants
(define-constant PROTOCOL_ADMIN tx-sender)
(define-constant PRECISION_FACTOR u1000000)
(define-constant MAX_UINT u340282366920938463463374607431768211455)

;; Error Definitions
(define-constant E_UNAUTHORIZED (err u401))
(define-constant E_INVALID_INPUT (err u402))
(define-constant E_INSUFFICIENT_FUNDS (err u403))
(define-constant E_UNDERCOLLATERALIZED (err u404))
(define-constant E_MARKET_FROZEN (err u405))
(define-constant E_POSITION_SAFE (err u406))
(define-constant E_NO_DEBT (err u407))
(define-constant E_LIQUIDATION_FAILED (err u408))

;; Core Protocol State
(define-data-var protocol-reserves uint u0)
(define-data-var total-debt uint u0)
(define-data-var supply-accumulator uint PRECISION_FACTOR)
(define-data-var debt-accumulator uint PRECISION_FACTOR)
(define-data-var state-timestamp uint u0)

;; Interest Rate Model Parameters
(define-data-var interest-base uint u20000)        ;; 2% base
(define-data-var interest-multiplier uint u100000)  ;; 10% slope
(define-data-var interest-jump uint u600000)       ;; 60% jump rate
(define-data-var utilization-kink uint u800000)    ;; 80% kink point

;; Risk Management Parameters
(define-data-var collateral-factor uint u750000)   ;; 75% collateral factor
(define-data-var liquidation-incentive uint u100000) ;; 10% incentive
(define-data-var protocol-fee uint u100000)        ;; 10% protocol fee

;; User Account Storage
(define-map lender-accounts principal {
  supply-shares: uint,
  last-supply-index: uint
})

(define-map borrower-accounts principal {
  debt-shares: uint,
  last-debt-index: uint
})

(define-map collateral-accounts principal uint)

;; === READ-ONLY INTERFACE ===

(define-read-only (get-market-utilization)
  (let ((total-supply (var-get protocol-reserves))
        (total-borrowed (var-get total-debt)))
    (if (is-eq total-supply u0)
        u0
        (let ((utilization (/ (* total-borrowed PRECISION_FACTOR) total-supply)))
          (if (<= utilization PRECISION_FACTOR)
              utilization
              PRECISION_FACTOR)))))

(define-read-only (calculate-borrow-rate)
  (let ((utilization (get-market-utilization))
        (kink (var-get utilization-kink)))
    (if (<= utilization kink)
        (+ (var-get interest-base)
           (/ (* utilization (var-get interest-multiplier)) PRECISION_FACTOR))
        (+ (+ (var-get interest-base) (var-get interest-multiplier))
           (/ (* (- utilization kink) (var-get interest-jump))
              (- PRECISION_FACTOR kink))))))

(define-read-only (calculate-supply-rate)
  (let ((borrow-rate (calculate-borrow-rate))
        (utilization (get-market-utilization))
        (fee (var-get protocol-fee)))
    (/ (* (* borrow-rate utilization) (- PRECISION_FACTOR fee))
       (* PRECISION_FACTOR PRECISION_FACTOR))))

(define-read-only (get-account-supply (account principal))
  (match (map-get? lender-accounts account)
    account-data (let ((shares (get supply-shares account-data))
                      (user-index (get last-supply-index account-data))
                      (current-index (var-get supply-accumulator)))
                  (if (> user-index u0)
                      (/ (* shares current-index) user-index)
                      shares))
    u0))

(define-read-only (get-account-debt (account principal))
  (match (map-get? borrower-accounts account)
    account-data (let ((shares (get debt-shares account-data))
                      (user-index (get last-debt-index account-data))
                      (current-index (var-get debt-accumulator)))
                  (if (> user-index u0)
                      (/ (* shares current-index) user-index)
                      shares))
    u0))

(define-read-only (get-account-collateral (account principal))
  (default-to u0 (map-get? collateral-accounts account)))

(define-read-only (check-account-health (account principal))
  (let ((collateral (get-account-collateral account))
        (debt (get-account-debt account))
        (factor (var-get collateral-factor)))
    (if (is-eq debt u0)
        true
        (>= (/ (* collateral factor) PRECISION_FACTOR) debt))))

;; === PRIVATE FUNCTIONS ===

(define-private (accrue-interest)
  (let ((current-time (default-to u0 (get-block-info? time (- block-height u1))))
        (last-time (var-get state-timestamp)))
    (if (> current-time last-time)
        (let ((time-delta (- current-time last-time))
              (borrow-rate (calculate-borrow-rate))
              (supply-rate (calculate-supply-rate))
              (rate-per-second-borrow (/ borrow-rate u31536000)) ;; seconds in year
              (rate-per-second-supply (/ supply-rate u31536000))
              (interest-borrow (* rate-per-second-borrow time-delta))
              (interest-supply (* rate-per-second-supply time-delta)))
          (var-set debt-accumulator (+ (var-get debt-accumulator) interest-borrow))
          (var-set supply-accumulator (+ (var-get supply-accumulator) interest-supply))
          (var-set state-timestamp current-time)
          (ok true))
        (ok true))))

;; === PUBLIC INTERFACE ===

(define-public (provide-liquidity (amount uint))
  (begin
    (asserts! (> amount u0) E_INVALID_INPUT)
    (let ((accrual-result (accrue-interest))) true)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (let ((current-index (var-get supply-accumulator))
          (shares (/ (* amount PRECISION_FACTOR) current-index))
          (existing (default-to { supply-shares: u0, last-supply-index: current-index }
                                (map-get? lender-accounts tx-sender))))
      
      (map-set lender-accounts tx-sender {
        supply-shares: (+ (get supply-shares existing) shares),
        last-supply-index: current-index
      })
      
      (var-set protocol-reserves (+ (var-get protocol-reserves) amount))
      (ok amount))))

(define-public (withdraw-liquidity (amount uint))
  (begin
    (asserts! (> amount u0) E_INVALID_INPUT)
    (let ((accrual-result (accrue-interest))) true)
    
    (let ((user-balance (get-account-supply tx-sender))
          (current-index (var-get supply-accumulator))
          (shares-to-burn (/ (* amount PRECISION_FACTOR) current-index))
          (existing (unwrap! (map-get? lender-accounts tx-sender) E_INSUFFICIENT_FUNDS)))
      
      (asserts! (>= user-balance amount) E_INSUFFICIENT_FUNDS)
      
      (map-set lender-accounts tx-sender {
        supply-shares: (- (get supply-shares existing) shares-to-burn),
        last-supply-index: current-index
      })
      
      (var-set protocol-reserves (- (var-get protocol-reserves) amount))
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      (ok amount))))

(define-public (deposit-collateral-tokens (amount uint))
  (begin
    (asserts! (> amount u0) E_INVALID_INPUT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (let ((current-collateral (get-account-collateral tx-sender)))
      (map-set collateral-accounts tx-sender (+ current-collateral amount)))
    (ok amount)))

(define-public (withdraw-collateral-tokens (amount uint))
  (begin
    (asserts! (> amount u0) E_INVALID_INPUT)
    (let ((accrual-result (accrue-interest))) true)
    
    (let ((current-collateral (get-account-collateral tx-sender))
          (current-debt (get-account-debt tx-sender))
          (remaining-collateral (- current-collateral amount))
          (factor (var-get collateral-factor)))
      
      (asserts! (>= current-collateral amount) E_INSUFFICIENT_FUNDS)
      
      (if (> current-debt u0)
          (asserts! (>= (/ (* remaining-collateral factor) PRECISION_FACTOR) current-debt) 
                   E_UNDERCOLLATERALIZED)
          true)
      
      (map-set collateral-accounts tx-sender remaining-collateral)
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      (ok amount))))

(define-public (take-loan (amount uint))
  (begin
    (asserts! (> amount u0) E_INVALID_INPUT)
    (let ((accrual-result (accrue-interest))) true)
    
    (let ((collateral (get-account-collateral tx-sender))
          (current-debt (get-account-debt tx-sender))
          (factor (var-get collateral-factor))
          (max-borrow (/ (* collateral factor) PRECISION_FACTOR))
          (new-debt (+ current-debt amount))
          (current-index (var-get debt-accumulator))
          (shares (/ (* amount PRECISION_FACTOR) current-index))
          (existing (default-to { debt-shares: u0, last-debt-index: current-index }
                                (map-get? borrower-accounts tx-sender))))
      
      (asserts! (>= max-borrow new-debt) E_UNDERCOLLATERALIZED)
      (asserts! (>= (var-get protocol-reserves) amount) E_INSUFFICIENT_FUNDS)
      
      (map-set borrower-accounts tx-sender {
        debt-shares: (+ (get debt-shares existing) shares),
        last-debt-index: current-index
      })
      
      (var-set total-debt (+ (var-get total-debt) amount))
      (var-set protocol-reserves (- (var-get protocol-reserves) amount))
      
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      (ok amount))))

(define-public (repay-loan (amount uint))
  (begin
    (asserts! (> amount u0) E_INVALID_INPUT)
    (let ((accrual-result (accrue-interest))) true)
    
    (let ((current-debt (get-account-debt tx-sender))
          (repay-amount (if (> amount current-debt) current-debt amount))
          (current-index (var-get debt-accumulator))
          (shares-to-burn (/ (* repay-amount PRECISION_FACTOR) current-index))
          (existing (unwrap! (map-get? borrower-accounts tx-sender) E_NO_DEBT)))
      
      (asserts! (> current-debt u0) E_NO_DEBT)
      (try! (stx-transfer? repay-amount tx-sender (as-contract tx-sender)))
      
      (map-set borrower-accounts tx-sender {
        debt-shares: (- (get debt-shares existing) shares-to-burn),
        last-debt-index: current-index
      })
      
      (var-set total-debt (- (var-get total-debt) repay-amount))
      (var-set protocol-reserves (+ (var-get protocol-reserves) repay-amount))
      (ok repay-amount))))

(define-public (liquidate-position (borrower principal) (repay-amount uint))
  (begin
    (asserts! (> repay-amount u0) E_INVALID_INPUT)
    (asserts! (not (check-account-health borrower)) E_POSITION_SAFE)
    (let ((accrual-result (accrue-interest))) true)
    
    (let ((debt (get-account-debt borrower))
          (collateral (get-account-collateral borrower))
          (incentive (var-get liquidation-incentive))
          (actual-repay (if (> repay-amount debt) debt repay-amount))
          (seize-amount (+ actual-repay (/ (* actual-repay incentive) PRECISION_FACTOR))))
      
      (asserts! (<= seize-amount collateral) E_INSUFFICIENT_FUNDS)
      (try! (stx-transfer? actual-repay tx-sender (as-contract tx-sender)))
      
      ;; Update borrower debt
      (let ((current-index (var-get debt-accumulator))
            (shares-to-burn (/ (* actual-repay PRECISION_FACTOR) current-index))
            (existing-debt (unwrap! (map-get? borrower-accounts borrower) E_NO_DEBT)))
        (map-set borrower-accounts borrower {
          debt-shares: (- (get debt-shares existing-debt) shares-to-burn),
          last-debt-index: current-index
        }))
      
      ;; Update borrower collateral
      (map-set collateral-accounts borrower (- collateral seize-amount))
      
      ;; Transfer seized collateral to liquidator
      (try! (as-contract (stx-transfer? seize-amount tx-sender tx-sender)))
      
      ;; Update protocol state
      (var-set total-debt (- (var-get total-debt) actual-repay))
      (var-set protocol-reserves (+ (var-get protocol-reserves) actual-repay))
      (ok seize-amount))))

;; === ADMIN FUNCTIONS ===

(define-public (configure-interest-model (base uint) (multiplier uint) (jump uint) (kink uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) E_UNAUTHORIZED)
    (var-set interest-base base)
    (var-set interest-multiplier multiplier)
    (var-set interest-jump jump)
    (var-set utilization-kink kink)
    (ok true)))

(define-public (configure-risk-parameters (factor uint) (incentive uint) (fee uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) E_UNAUTHORIZED)
    (var-set collateral-factor factor)
    (var-set liquidation-incentive incentive)
    (var-set protocol-fee fee)
    (ok true)))

(define-public (bootstrap-protocol)
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) E_UNAUTHORIZED)
    (match (get-block-info? time (- block-height u1))
      timestamp (var-set state-timestamp timestamp)
      false)
    (ok true)))