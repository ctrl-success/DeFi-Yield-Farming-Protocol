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
(define-constant token-decimals u8)
(define-constant max-supply u1000000000000000) ;; 100M tokens with 8 decimals

;; Data variables
(define-data-var token-name (string-ascii 32) "YieldVault Token")
(define-data-var token-symbol (string-ascii 10) "YVT")
(define-data-var token-uri (optional (string-utf8 256)) (some u"https://yieldvault.defi/metadata.json"))
(define-data-var total-minted uint u0)

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

;; Administrative Functions

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ (var-get total-minted) amount) max-supply) err-invalid-amount)
    
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

;; Read-only helper functions
(define-read-only (get-max-supply)
  (ok max-supply))

(define-read-only (get-remaining-supply)
  (ok (- max-supply (var-get total-minted))))
