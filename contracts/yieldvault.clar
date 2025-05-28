;; YieldVault Token (YVT) - Governance and utility token for the YieldVault protocol
;; Implements SIP-010 fungible token standard with enhanced governance features

(define-fungible-token yieldvault-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-recipient (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-transfer-failed (err u105))
(define-constant err-insufficient-allowance (err u106))
(define-constant err-minting-disabled (err u107))
(define-constant err-max-supply-exceeded (err u108))
(define-constant token-decimals u8)
(define-constant max-supply u10000000000000000) ;; 100M tokens with 8 decimals

;; Data variables
(define-data-var token-name (string-ascii 32) "YieldVault Token")
(define-data-var token-symbol (string-ascii 10) "YVT")
(define-data-var token-uri (optional (string-utf8 256)) (some u"https://yieldvault.defi/metadata.json"))
(define-data-var total-minted uint u0)
(define-data-var minting-enabled bool true)

;; Authorized minters map - allows specific contracts to mint tokens
(define-map authorized-minters principal bool)

;; Allowances for transfer-from functionality
(define-map allowances { owner: principal, spender: principal } uint)

;; SIP-010 Standard Functions

(define-read-only (get-name)
  (ok (var-get token-name)))

(define-read-only (get-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok token-decimals))

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance yieldvault-token who)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply yieldvault-token)))

(define-read-only (get-token-uri)
  (ok (var-get token-uri)))

;; (define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
;;   (begin
;;     (asserts! (or (is-eq tx-sender from) (is-eq contract-caller from)) err-not-token-owner)
;;     (asserts! (> amount u0) err-invalid-amount)
;;     (asserts! (not (is-eq from to)) err-invalid-recipient)
    
;;     (match (ft-transfer? yieldvault-token amount from to)
;;       success (begin
;;         (print memo)
;;         (ok true))
;;       error (err err-transfer-failed))))

;; Administrative Functions

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (var-get minting-enabled) err-minting-disabled)
    (asserts! (or 
      (is-eq tx-sender contract-owner) 
      (default-to false (map-get? authorized-minters tx-sender))) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ (var-get total-minted) amount) max-supply) err-max-supply-exceeded)
    
    (match (ft-mint? yieldvault-token amount recipient)
      success (begin
        (var-set total-minted (+ (var-get total-minted) amount))
        (ok true))
      error (err error))))

(define-public (burn (amount uint) (burner principal))
  (begin
    (asserts! (or (is-eq tx-sender burner) (is-eq tx-sender contract-owner)) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (ft-get-balance yieldvault-token burner) amount) err-insufficient-balance)
    
    (match (ft-burn? yieldvault-token amount burner)
      success (begin
        (var-set total-minted (- (var-get total-minted) amount))
        (ok true))
      error (err error))))

(define-public (set-token-uri (new-uri (optional (string-utf8 256))))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set token-uri new-uri)
    (ok true)))

(define-public (authorize-minter (minter principal) (authorized bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-minters minter authorized)
    (ok true)))

(define-public (toggle-minting (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set minting-enabled enabled)
    (ok enabled)))

;; Allowance Functions (for enhanced token functionality)

(define-public (approve (spender principal) (amount uint))
  (begin
    (asserts! (not (is-eq tx-sender spender)) err-invalid-recipient)
    (map-set allowances { owner: tx-sender, spender: spender } amount)
    (ok true)))

;; (define-public (transfer-from (amount uint) (owner principal) (recipient principal) (memo (optional (buff 34))))
;;   (let ((allowance (unwrap! (map-get? allowances { owner: owner, spender: tx-sender }) err-insufficient-allowance)))
;;     (asserts! (>= allowance amount) err-insufficient-allowance)
;;     (asserts! (> amount u0) err-invalid-amount)
;;     (asserts! (not (is-eq owner recipient)) err-invalid-recipient)
    
;;     (match (ft-transfer? yieldvault-token amount owner recipient)
;;       success (begin
;;         (map-set allowances { owner: owner, spender: tx-sender } (- allowance amount))
;;         (print memo)
;;         (ok true))
;;       error (err err-transfer-failed))))

(define-public (increase-allowance (spender principal) (amount uint))
  (let ((current-allowance (default-to u0 (map-get? allowances { owner: tx-sender, spender: spender }))))
    (asserts! (not (is-eq tx-sender spender)) err-invalid-recipient)
    (asserts! (> amount u0) err-invalid-amount)
    (map-set allowances { owner: tx-sender, spender: spender } (+ current-allowance amount))
    (ok true)))

(define-public (decrease-allowance (spender principal) (amount uint))
  (let ((current-allowance (default-to u0 (map-get? allowances { owner: tx-sender, spender: spender }))))
    (asserts! (not (is-eq tx-sender spender)) err-invalid-recipient)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= current-allowance amount) err-insufficient-allowance)
    (map-set allowances { owner: tx-sender, spender: spender } (- current-allowance amount))
    (ok true)))

;; Read-only helper functions

(define-read-only (get-allowance (owner principal) (spender principal))
  (ok (default-to u0 (map-get? allowances { owner: owner, spender: spender }))))

(define-read-only (get-max-supply)
  (ok max-supply))

(define-read-only (get-remaining-supply)
  (ok (- max-supply (var-get total-minted))))

(define-read-only (get-total-minted)
  (ok (var-get total-minted)))

(define-read-only (is-minting-enabled)
  (ok (var-get minting-enabled)))

(define-read-only (is-authorized-minter (minter principal))
  (ok (default-to false (map-get? authorized-minters minter))))

;; Utility functions for token holders

(define-read-only (get-balance-of (account principal))
  (ft-get-balance yieldvault-token account))

(define-read-only (get-total-supply-uint)
  (ft-get-supply yieldvault-token))

;; Emergency functions

(define-public (emergency-burn (amount uint) (target principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (ft-get-balance yieldvault-token target) amount) err-insufficient-balance)
    
    (match (ft-burn? yieldvault-token amount target)
      success (begin
        (var-set total-minted (- (var-get total-minted) amount))
        (ok true))
      error (err error))))

(define-public (emergency-mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ (var-get total-minted) amount) max-supply) err-max-supply-exceeded)
    
    (match (ft-mint? yieldvault-token amount recipient)
      success (begin
        (var-set total-minted (+ (var-get total-minted) amount))
        (ok true))
      error (err error))))