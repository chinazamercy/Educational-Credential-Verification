;; CROSS-INSTITUTIONAL-RECOGNITION TOKEN CONTRACT
;; Cross-institutional credential recognition and transfer
;; Part of: Blockchain-based educational credential verification and transfer system.

;; Implement SIP-010 Fungible Token Standard
(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_TRANSFER_FAILED (err u103))
(define-constant ERR_NOT_TOKEN_OWNER (err u104))

;; Token Constants
(define-constant TOKEN_NAME "Cross Institutional Recognition")
(define-constant TOKEN_SYMBOL "CROS")
(define-constant TOKEN_DECIMALS u6)
(define-constant TOKEN_MAX_SUPPLY u1000000000000000) ;; 1 billion tokens with 6 decimals

;; Data Variables
(define-data-var total-supply uint u0)
(define-data-var contract-owner principal CONTRACT_OWNER)
(define-data-var mint-enabled bool true)
(define-data-var burn-enabled bool true)

;; Data Maps
(define-map token-balances principal uint)
(define-map token-allowances {owner: principal, spender: principal} uint)

;; Minting permissions
(define-map authorized-minters principal bool)

;; Token lock system
(define-map locked-tokens {owner: principal, locker: principal} uint)
(define-map lock-details {owner: principal, locker: principal} {
    amount: uint,
    unlock-block: uint,
    reason: (string-ascii 50)
})

;; Private Functions

;; Get balance of a principal
(define-private (get-balance-or-default (account principal))
    (default-to u0 (map-get? token-balances account))
)

;; Get allowance between owner and spender
(define-private (get-allowance-or-default (owner principal) (spender principal))
    (default-to u0 (map-get? token-allowances {owner: owner, spender: spender}))
)

;; Public Functions

;; Transfer tokens
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (let (
        (sender-balance (get-balance-or-default sender))
        (recipient-balance (get-balance-or-default recipient))
    )
        (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
        
        ;; Update balances
        (try! (map-set token-balances sender (- sender-balance amount)))
        (map-set token-balances recipient (+ recipient-balance amount))
        
        ;; Print transfer event
        (match memo
            memo-value (print {
                action: "transfer",
                sender: sender,
                recipient: recipient,
                amount: amount,
                memo: memo-value
            })
            (print {
                action: "transfer", 
                sender: sender,
                recipient: recipient,
                amount: amount
            })
        )
        
        (ok true)
    )
)

;; Get token name
(define-read-only (get-name)
    (ok TOKEN_NAME)
)

;; Get token symbol
(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
    (ok TOKEN_DECIMALS)
)

;; Get balance of account
(define-read-only (get-balance (account principal))
    (ok (get-balance-or-default account))
)

;; Get total supply
(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

;; Get token URI (metadata)
(define-read-only (get-token-uri)
    (ok (some "https://token-metadata.cross-institutional-recognition.com/metadata.json"))
)

;; Transfer from (for approved spenders)
(define-public (transfer-from (amount uint) (owner principal) (recipient principal) (memo (optional (buff 34))))
    (let (
        (owner-balance (get-balance-or-default owner))
        (recipient-balance (get-balance-or-default recipient))
        (current-allowance (get-allowance-or-default owner tx-sender))
    )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= owner-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (>= current-allowance amount) ERR_UNAUTHORIZED)
        
        ;; Update balances
        (try! (map-set token-balances owner (- owner-balance amount)))
        (map-set token-balances recipient (+ recipient-balance amount))
        
        ;; Update allowance
        (map-set token-allowances {owner: owner, spender: tx-sender} (- current-allowance amount))
        
        ;; Print transfer event
        (print {
            action: "transfer-from",
            owner: owner,
            recipient: recipient,
            spender: tx-sender,
            amount: amount
        })
        
        (ok true)
    )
)

;; Approve spender
(define-public (approve (spender principal) (amount uint))
    (begin
        (asserts! (not (is-eq spender tx-sender)) ERR_UNAUTHORIZED)
        (map-set token-allowances {owner: tx-sender, spender: spender} amount)
        
        (print {
            action: "approve",
            owner: tx-sender,
            spender: spender,
            amount: amount
        })
        
        (ok true)
    )
)

;; Get allowance
(define-read-only (get-allowance (owner principal) (spender principal))
    (ok (get-allowance-or-default owner spender))
)

;; Mint tokens (only authorized minters)
(define-public (mint (amount uint) (recipient principal))
    (let ((new-total-supply (+ (var-get total-supply) amount)))
        (asserts! (var-get mint-enabled) ERR_UNAUTHORIZED)
        (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                     (default-to false (map-get? authorized-minters tx-sender))) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= new-total-supply TOKEN_MAX_SUPPLY) ERR_INVALID_AMOUNT)
        
        ;; Update recipient balance
        (map-set token-balances recipient (+ (get-balance-or-default recipient) amount))
        
        ;; Update total supply
        (var-set total-supply new-total-supply)
        
        (print {
            action: "mint",
            recipient: recipient,
            amount: amount,
            new-total-supply: new-total-supply
        })
        
        (ok true)
    )
)

;; Burn tokens
(define-public (burn (amount uint))
    (let (
        (balance (get-balance-or-default tx-sender))
        (new-total-supply (- (var-get total-supply) amount))
    )
        (asserts! (var-get burn-enabled) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= balance amount) ERR_INSUFFICIENT_BALANCE)
        
        ;; Update sender balance
        (map-set token-balances tx-sender (- balance amount))
        
        ;; Update total supply
        (var-set total-supply new-total-supply)
        
        (print {
            action: "burn",
            burner: tx-sender,
            amount: amount,
            new-total-supply: new-total-supply
        })
        
        (ok true)
    )
)

;; Lock tokens for a specific purpose
(define-public (lock-tokens (owner principal) (amount uint) (unlock-block uint) (reason (string-ascii 50)))
    (let (
        (owner-balance (get-balance-or-default owner))
        (current-locked (default-to u0 (map-get? locked-tokens {owner: owner, locker: tx-sender})))
    )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= owner-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> unlock-block block-height) ERR_INVALID_AMOUNT)
        
        ;; Set lock details
        (map-set locked-tokens {owner: owner, locker: tx-sender} (+ current-locked amount))
        (map-set lock-details {owner: owner, locker: tx-sender} {
            amount: (+ current-locked amount),
            unlock-block: unlock-block,
            reason: reason
        })
        
        (print {
            action: "lock-tokens",
            owner: owner,
            locker: tx-sender,
            amount: amount,
            unlock-block: unlock-block,
            reason: reason
        })
        
        (ok true)
    )
)

;; Unlock tokens
(define-public (unlock-tokens (owner principal))
    (let (
        (lock-info (unwrap! (map-get? lock-details {owner: owner, locker: tx-sender}) ERR_NOT_TOKEN_OWNER))
        (unlock-block (get unlock-block lock-info))
        (amount (get amount lock-info))
    )
        (asserts! (>= block-height unlock-block) ERR_UNAUTHORIZED)
        
        ;; Remove locks
        (map-delete locked-tokens {owner: owner, locker: tx-sender})
        (map-delete lock-details {owner: owner, locker: tx-sender})
        
        (print {
            action: "unlock-tokens",
            owner: owner,
            locker: tx-sender,
            amount: amount
        })
        
        (ok true)
    )
)

;; Admin Functions

;; Add authorized minter
(define-public (add-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (map-set authorized-minters minter true)
        (ok true)
    )
)

;; Remove authorized minter
(define-public (remove-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (map-delete authorized-minters minter)
        (ok true)
    )
)

;; Toggle minting
(define-public (toggle-mint (enabled bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (var-set mint-enabled enabled)
        (ok enabled)
    )
)

;; Toggle burning
(define-public (toggle-burn (enabled bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (var-set burn-enabled enabled)
        (ok enabled)
    )
)

;; Transfer ownership
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)

;; Read-only Functions

;; Get locked token amount
(define-read-only (get-locked-tokens (owner principal) (locker principal))
    (default-to u0 (map-get? locked-tokens {owner: owner, locker: locker}))
)

;; Get lock details
(define-read-only (get-lock-details (owner principal) (locker principal))
    (map-get? lock-details {owner: owner, locker: locker})
)

;; Check if principal is authorized minter
(define-read-only (is-minter (principal principal))
    (default-to false (map-get? authorized-minters principal))
)

;; Get contract settings
(define-read-only (get-contract-settings)
    {
        owner: (var-get contract-owner),
        mint-enabled: (var-get mint-enabled),
        burn-enabled: (var-get burn-enabled),
        max-supply: TOKEN_MAX_SUPPLY
    }
)

