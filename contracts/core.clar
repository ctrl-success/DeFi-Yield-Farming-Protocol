;; YieldVault Core - Multi-pool yield farming protocol
;; Allows users to stake LP tokens and other assets to earn YVT rewards

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-pool-not-found (err u201))
(define-constant err-insufficient-balance (err u202))
(define-constant err-pool-inactive (err u203))
(define-constant err-invalid-amount (err u204))
(define-constant err-cooldown-active (err u205))
(define-constant err-no-stake (err u206))
(define-constant err-transfer-failed (err u207))
(define-constant blocks-per-day u144)
(define-constant reward-precision u1000000) ;; 6 decimal precision

;; Data Variables
(define-data-var next-pool-id uint u1)
(define-data-var protocol-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var treasury principal contract-owner)
(define-data-var emergency-shutdown bool false)

;; Data Maps
(define-map pools
  { pool-id: uint }
  {
    token-contract: principal,
    name: (string-ascii 50),
    active: bool,
    reward-rate: uint, ;; YVT per block per staked token
    total-staked: uint,
    last-reward-block: uint,
    accumulated-reward-per-share: uint,
    lock-period: uint ;; blocks
  })

(define-map user-stakes
  { pool-id: uint, user: principal }
  {
    amount: uint,
    reward-debt: uint,
    last-stake-block: uint,
    unlock-block: uint
  })

(define-map pool-participants
  { pool-id: uint }
  { count: uint })

;; Pool Management Functions

(define-public (create-pool 
  (token-contract principal) 
  (name (string-ascii 50)) 
  (reward-rate uint) 
  (lock-period uint))
  (let ((pool-id (var-get next-pool-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> reward-rate u0) err-invalid-amount)
    
    (map-set pools
      { pool-id: pool-id }
      {
        token-contract: token-contract,
        name: name,
        active: true,
        reward-rate: reward-rate,
        total-staked: u0,
        last-reward-block: block-height,
        accumulated-reward-per-share: u0,
        lock-period: lock-period
      })
    
    (map-set pool-participants { pool-id: pool-id } { count: u0 })
    (var-set next-pool-id (+ pool-id u1))
    (ok pool-id)))

(define-public (toggle-pool-status (pool-id uint))
  (let ((pool-info (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set pools
      { pool-id: pool-id }
      (merge pool-info { active: (not (get active pool-info)) }))
    (ok (not (get active pool-info)))))

;; Helper Functions (defined before public functions that use them)

(define-private (update-pool-rewards (pool-id uint))
  (let ((pool-info (unwrap-panic (map-get? pools { pool-id: pool-id }))))
    (if (and (> (get total-staked pool-info) u0) (> block-height (get last-reward-block pool-info)))
      (let (
        (blocks-elapsed (- block-height (get last-reward-block pool-info)))
        (total-reward (* blocks-elapsed (get reward-rate pool-info)))
        (reward-per-share (/ (* total-reward reward-precision) (get total-staked pool-info)))
      )
        (map-set pools
          { pool-id: pool-id }
          (merge pool-info {
            accumulated-reward-per-share: (+ (get accumulated-reward-per-share pool-info) reward-per-share),
            last-reward-block: block-height
          })))
      (map-set pools
        { pool-id: pool-id }
        (merge pool-info { last-reward-block: block-height })))))

(define-private (calculate-pending-rewards (amount uint) (reward-debt uint) (acc-reward-per-share uint))
  (if (> amount u0)
    (let ((total-reward (/ (* amount acc-reward-per-share) reward-precision)))
      (if (> total-reward reward-debt)
        (- total-reward reward-debt)
        u0))
    u0))

(define-private (is-emergency-active)
  (var-get emergency-shutdown))
;; Read-only Functions

(define-read-only (get-pool-info (pool-id uint))
  (map-get? pools { pool-id: pool-id }))

(define-read-only (get-user-stake (pool-id uint) (user principal))
  (map-get? user-stakes { pool-id: pool-id, user: user }))

(define-read-only (get-pending-rewards (pool-id uint) (user principal))
  (match (map-get? pools { pool-id: pool-id })
    pool-info
      (match (map-get? user-stakes { pool-id: pool-id, user: user })
        user-info
          (let (
            (blocks-elapsed (- block-height (get last-reward-block pool-info)))
            (total-reward (if (> (get total-staked pool-info) u0)
              (* blocks-elapsed (get reward-rate pool-info))
              u0))
            (reward-per-share (if (> (get total-staked pool-info) u0)
              (/ (* total-reward reward-precision) (get total-staked pool-info))
              u0))
            (new-acc-reward-per-share (+ (get accumulated-reward-per-share pool-info) reward-per-share))
          )
            (ok (calculate-pending-rewards 
              (get amount user-info) 
              (get reward-debt user-info) 
              new-acc-reward-per-share)))
        (ok u0))
    (err err-pool-not-found)))

(define-read-only (get-pool-count)
  (ok (- (var-get next-pool-id) u1)))

(define-read-only (get-pool-participants (pool-id uint))
  (match (map-get? pool-participants { pool-id: pool-id })
    participants (ok (get count participants))
    (err err-pool-not-found)))

(define-read-only (get-emergency-status)
  (ok (var-get emergency-shutdown)))

(define-read-only (get-treasury)
  (ok (var-get treasury)))

(define-read-only (get-protocol-fee-rate)
  (ok (var-get protocol-fee-rate)))

;; Emergency Functions

(define-public (set-emergency-shutdown (shutdown bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-shutdown shutdown)
    (ok shutdown)))

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set treasury new-treasury)
    (ok true)))

(define-public (set-protocol-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-amount) ;; Max 10%
    (var-set protocol-fee-rate new-rate)
    (ok true)))

(define-public (update-pool-reward-rate (pool-id uint) (new-rate uint))
  (let ((pool-info (unwrap! (map-get? pools { pool-id: pool-id }) err-pool-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-rate u0) err-invalid-amount)
    
    ;; Update rewards before changing rate
    (update-pool-rewards pool-id)
    
    (map-set pools
      { pool-id: pool-id }
      (merge pool-info { reward-rate: new-rate }))
    (ok true)))