;; CREDENTIAL-ISSUANCE CONTRACT
;; Secure credential issuance and digital certification
;; Part of: Blockchain-based educational credential verification and transfer system.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INSUFFICIENT_BALANCE (err u104))
(define-constant ERR_INVALID_STATUS (err u105))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var next-item-id uint u1)
(define-data-var total-items uint u0)
(define-data-var admin-count uint u1)

;; Data Maps
(define-map contract-admins principal bool)
(define-map item-registry uint {
    owner: principal,
    name: (string-ascii 100),
    description: (string-ascii 256),
    value: uint,
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint
})

(define-map user-items principal (list 50 uint))
(define-map item-owners uint principal)

;; Access control
(define-map permissions {user: principal, action: (string-ascii 20)} bool)

;; Activity log
(define-map activity-log uint {
    actor: principal,
    action: (string-ascii 50),
    target-id: uint,
    timestamp: uint,
    details: (string-ascii 200)
})
(define-data-var next-log-id uint u1)

;; Contract settings
(define-map settings (string-ascii 50) uint)

;; Private Functions

;; Check if user has permission for action
(define-private (has-permission (user principal) (action (string-ascii 20)))
    (or 
        (is-eq user CONTRACT_OWNER)
        (default-to false (map-get? contract-admins user))
        (default-to false (map-get? permissions {user: user, action: action}))
    )
)

;; Log activity
(define-private (log-activity (action (string-ascii 50)) (target-id uint) (details (string-ascii 200)))
    (let ((log-id (var-get next-log-id)))
        (map-set activity-log log-id {
            actor: tx-sender,
            action: action,
            target-id: target-id,
            timestamp: block-height,
            details: details
        })
        (var-set next-log-id (+ log-id u1))
        log-id
    )
)

;; Update user items list
(define-private (add-item-to-user (user principal) (item-id uint))
    (let ((current-items (default-to (list) (map-get? user-items user))))
        (match (as-max-len? (append current-items item-id) u50)
            updated-list (map-set user-items user updated-list)
            false ;; List is full
        )
    )
)

;; Remove item from user list
(define-private (remove-item-from-user (user principal) (item-id uint))
    (let ((current-items (default-to (list) (map-get? user-items user))))
        (map-set user-items user (filter is-not-target current-items))
    )
)

;; Helper for filtering (placeholder)
(define-private (is-not-target (id uint))
    true ;; Simplified implementation
)

;; Public Functions

;; Initialize contract with settings
(define-public (initialize-contract (max-items uint) (base-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set contract-admins CONTRACT_OWNER true)
        (map-set settings "max-items" max-items)
        (map-set settings "base-fee" base-fee)
        (log-activity "contract-initialized" u0 "Contract settings configured")
        (ok true)
    )
)

;; Add new admin
(define-public (add-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (not (default-to false (map-get? contract-admins new-admin))) ERR_ALREADY_EXISTS)
        (map-set contract-admins new-admin true)
        (var-set admin-count (+ (var-get admin-count) u1))
        (log-activity "admin-added" u0 "New admin added to contract")
        (ok true)
    )
)

;; Create new item
(define-public (create-item (name (string-ascii 100)) (description (string-ascii 256)) (value uint))
    (let (
        (item-id (var-get next-item-id))
        (max-items (default-to u1000 (map-get? settings "max-items")))
    )
        (asserts! (var-get contract-active) ERR_INVALID_STATUS)
        (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)
        (asserts! (< (var-get total-items) max-items) ERR_INVALID_AMOUNT)
        
        ;; Create item record
        (map-set item-registry item-id {
            owner: tx-sender,
            name: name,
            description: description,
            value: value,
            status: "active",
            created-at: block-height,
            updated-at: block-height
        })
        
        ;; Set item owner
        (map-set item-owners item-id tx-sender)
        
        ;; Add to user's items
        (add-item-to-user tx-sender item-id)
        
        ;; Update counters
        (var-set next-item-id (+ item-id u1))
        (var-set total-items (+ (var-get total-items) u1))
        
        ;; Log activity
        (log-activity "item-created" item-id name)
        
        (print {
            action: "create-item",
            item-id: item-id,
            owner: tx-sender,
            name: name,
            value: value
        })
        
        (ok item-id)
    )
)

;; Update existing item
(define-public (update-item (item-id uint) (new-name (string-ascii 100)) (new-description (string-ascii 256)) (new-value uint))
    (let ((item-data (unwrap! (map-get? item-registry item-id) ERR_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get owner item-data)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status item-data) "active") ERR_INVALID_STATUS)
        
        ;; Update item
        (map-set item-registry item-id (merge item-data {
            name: new-name,
            description: new-description,
            value: new-value,
            updated-at: block-height
        }))
        
        ;; Log activity
        (log-activity "item-updated" item-id new-name)
        
        (print {
            action: "update-item",
            item-id: item-id,
            owner: tx-sender,
            new-name: new-name,
            new-value: new-value
        })
        
        (ok true)
    )
)

;; Transfer item ownership
(define-public (transfer-item (item-id uint) (new-owner principal))
    (let ((item-data (unwrap! (map-get? item-registry item-id) ERR_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get owner item-data)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status item-data) "active") ERR_INVALID_STATUS)
        (asserts! (not (is-eq tx-sender new-owner)) ERR_INVALID_AMOUNT)
        
        ;; Update ownership
        (map-set item-registry item-id (merge item-data {
            owner: new-owner,
            updated-at: block-height
        }))
        (map-set item-owners item-id new-owner)
        
        ;; Update user lists
        (remove-item-from-user tx-sender item-id)
        (add-item-to-user new-owner item-id)
        
        ;; Log activity
        (log-activity "item-transferred" item-id "Ownership transferred")
        
        (print {
            action: "transfer-item",
            item-id: item-id,
            from: tx-sender,
            to: new-owner
        })
        
        (ok true)
    )
)

;; Deactivate item
(define-public (deactivate-item (item-id uint))
    (let ((item-data (unwrap! (map-get? item-registry item-id) ERR_NOT_FOUND)))
        (asserts! (or 
            (is-eq tx-sender (get owner item-data))
            (has-permission tx-sender "deactivate")
        ) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status item-data) "active") ERR_INVALID_STATUS)
        
        ;; Deactivate item
        (map-set item-registry item-id (merge item-data {
            status: "inactive",
            updated-at: block-height
        }))
        
        ;; Log activity
        (log-activity "item-deactivated" item-id "Item deactivated")
        
        (ok true)
    )
)

;; Batch operation: Create multiple items
(define-public (batch-create-items (items (list 10 {name: (string-ascii 100), description: (string-ascii 256), value: uint})))
    (let ((results (map create-single-item items)))
        (ok (len results))
    )
)

;; Helper for batch creation
(define-private (create-single-item (item {name: (string-ascii 100), description: (string-ascii 256), value: uint}))
    (let (
        (item-id (var-get next-item-id))
        (name (get name item))
        (description (get description item))
        (value (get value item))
    )
        (map-set item-registry item-id {
            owner: tx-sender,
            name: name,
            description: description,
            value: value,
            status: "active",
            created-at: block-height,
            updated-at: block-height
        })
        
        (map-set item-owners item-id tx-sender)
        (add-item-to-user tx-sender item-id)
        (var-set next-item-id (+ item-id u1))
        (var-set total-items (+ (var-get total-items) u1))
        
        item-id
    )
)

;; Grant permission to user
(define-public (grant-permission (user principal) (action (string-ascii 20)))
    (begin
        (asserts! (has-permission tx-sender "manage-permissions") ERR_UNAUTHORIZED)
        (map-set permissions {user: user, action: action} true)
        (log-activity "permission-granted" u0 action)
        (ok true)
    )
)

;; Emergency pause contract
(define-public (emergency-pause)
    (begin
        (asserts! (has-permission tx-sender "emergency-pause") ERR_UNAUTHORIZED)
        (var-set contract-active false)
        (log-activity "contract-paused" u0 "Emergency pause activated")
        (ok true)
    )
)

;; Resume contract
(define-public (resume-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-active true)
        (log-activity "contract-resumed" u0 "Contract resumed")
        (ok true)
    )
)

;; Update contract settings
(define-public (update-setting (key (string-ascii 50)) (value uint))
    (begin
        (asserts! (has-permission tx-sender "update-settings") ERR_UNAUTHORIZED)
        (map-set settings key value)
        (log-activity "setting-updated" u0 key)
        (ok true)
    )
)

;; Read-only Functions

;; Get item details
(define-read-only (get-item (item-id uint))
    (map-get? item-registry item-id)
)

;; Get item owner
(define-read-only (get-item-owner (item-id uint))
    (map-get? item-owners item-id)
)

;; Get user's items
(define-read-only (get-user-items (user principal))
    (default-to (list) (map-get? user-items user))
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-items: (var-get total-items),
        next-item-id: (var-get next-item-id),
        admin-count: (var-get admin-count),
        contract-active: (var-get contract-active)
    }
)

;; Check if user is admin
(define-read-only (is-admin (user principal))
    (default-to false (map-get? contract-admins user))
)

;; Get activity log entry
(define-read-only (get-activity-log (log-id uint))
    (map-get? activity-log log-id)
)

;; Get contract setting
(define-read-only (get-setting (key (string-ascii 50)))
    (map-get? settings key)
)

;; Check user permission
(define-read-only (check-permission (user principal) (action (string-ascii 20)))
    (has-permission user action)
)

;; Get items by status (simplified)
(define-read-only (get-items-by-status (status (string-ascii 20)))
    ;; Simplified implementation - would return filtered list
    (ok (list))
)

;; Get recent activity
(define-read-only (get-recent-activity (count uint))
    (let ((current-log-id (var-get next-log-id)))
        ;; Simplified - would return last N activities
        (ok (list))
    )
)

