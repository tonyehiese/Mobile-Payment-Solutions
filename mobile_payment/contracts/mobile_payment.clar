;; Mobile Payment Solution for Touring Clarinet Artists
;; Built with Clarinet - a Clarity language implementation for Stacks blockchain
;; This smart contract handles payments, tracks merchandise sales, and manages fan interactions

(define-data-var contract-owner principal tx-sender)
(define-map artist-profiles principal {
  name: (string-utf8 50),
  merchandise-available: bool,
  accepts-offline-payments: bool,
  min-stx-payment: uint
})

(define-map merchandise uint {
  item-name: (string-utf8 50),
  price: uint,
  inventory: uint,
  artist: principal
})

(define-map sales uint {
  buyer: principal,
  item-id: uint,
  payment-amount: uint,
  timestamp: uint,
  is-offline: bool
})

(define-data-var sale-counter uint u0)
(define-data-var merch-counter uint u0)

;; Initialize the contract with the artist as owner
(define-public (initialize-artist (artist-name (string-utf8 50)) (min-payment uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only contract owner can initialize
    (map-set artist-profiles tx-sender {
      name: artist-name,
      merchandise-available: false,
      accepts-offline-payments: true,
      min-stx-payment: min-payment
    })
    (ok true)
  )
)

;; Add new merchandise for sale
(define-public (add-merchandise (name (string-utf8 50)) (price uint) (quantity uint))
  (let ((current-id (var-get merch-counter)))
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
    (map-set merchandise current-id {
      item-name: name,
      price: price,
      inventory: quantity,
      artist: tx-sender
    })
    (var-set merch-counter (+ current-id u1))
    (ok current-id)
  )
)

;; Purchase merchandise with online payment
(define-public (purchase-merchandise (item-id uint))
  (let ((item (unwrap! (map-get? merchandise item-id) (err u404)))
        (current-sale-id (var-get sale-counter)))
    ;; Check inventory
    (asserts! (> (get inventory item) u0) (err u500))
    ;; Check payment amount
    (asserts! (>= (stx-get-balance tx-sender) (get price item)) (err u401))
    
    ;; Process payment
    (try! (stx-transfer? (get price item) tx-sender (get artist item)))
    ;; Update inventory
    (map-set merchandise item-id {
      item-name: (get item-name item),
      price: (get price item),
      inventory: (- (get inventory item) u1),
      artist: (get artist item)
    })
    
    ;; Record sale
    (map-set sales current-sale-id {
      buyer: tx-sender,
      item-id: item-id,
      payment-amount: (get price item),
      timestamp: u0,
      is-offline: false
    }) 
    ;; Increment sale counter
    (var-set sale-counter (+ current-sale-id u1))
    (ok current-sale-id)
  )
)

;; Record offline sales (for cash transactions at venues)
(define-public (record-offline-sale (item-id uint) (buyer principal) (amount uint))
  (let ((item (unwrap! (map-get? merchandise item-id) (err u404)))
        (artist-profile (unwrap! (map-get? artist-profiles tx-sender) (err u404)))
        (current-sale-id (var-get sale-counter)))
    ;; Verify caller is the artist
    (asserts! (is-eq tx-sender (get artist item)) (err u403))
    ;; Check if artist accepts offline payments
    (asserts! (get accepts-offline-payments artist-profile) (err u403))
    ;; Check inventory
    (asserts! (> (get inventory item) u0) (err u500)) 
    ;; Update inventory
    (map-set merchandise item-id {
      item-name: (get item-name item),
      price: (get price item),
      inventory: (- (get inventory item) u1),
      artist: (get artist item)
    })
    
    ;; Record sale
    (map-set sales current-sale-id {
      buyer: buyer,
      item-id: item-id,
      payment-amount: amount,
      timestamp: u0,
      is-offline: true
    })
    
    ;; Increment sale counter
    (var-set sale-counter (+ current-sale-id u1))
    (ok current-sale-id)
  )
)

;; Enable/disable offline payments (useful when touring in areas with limited connectivity)
(define-public (toggle-offline-payments (enable bool))
  (let ((artist-profile (unwrap! (map-get? artist-profiles tx-sender) (err u404))))
    (map-set artist-profiles tx-sender {
      name: (get name artist-profile),
      merchandise-available: (get merchandise-available artist-profile),
      accepts-offline-payments: enable,
      min-stx-payment: (get min-stx-payment artist-profile)
    })
    (ok enable)
  )
)

;; Get sale information by sale ID
(define-read-only (get-sale-by-id (sale-id uint))
  (map-get? sales sale-id)
)

;; Check if a sale is within a given block period
(define-read-only (is-sale-in-period (sale-id uint) (start-block uint) (end-block uint))
  (match (map-get? sales sale-id)
    sale (and (>= (get timestamp sale) start-block) 
              (<= (get timestamp sale) end-block))
    false)
)

;; Get a single sale within period
(define-read-only (get-sale-if-in-period (sale-id uint) (start-block uint) (end-block uint))
  (match (map-get? sales sale-id)
    sale (if (and (>= (get timestamp sale) start-block) 
                 (<= (get timestamp sale) end-block))
            (some {id: sale-id, details: sale})
            none)
    none)
)

;; Public function to get a sale by ID if it's in period
(define-public (query-sale-in-period (sale-id uint) (start-block uint) (end-block uint))
  (match (get-sale-if-in-period sale-id start-block end-block)
    sale (ok sale)
    (err u404))
)

;; Get sales report for specific sale ID range
(define-public (get-sales-in-range (start-id uint) (end-id uint) (start-block uint) (end-block uint))
  (ok (get-sales-in-range-iter start-id end-id start-block end-block (list)))
)

;; Iterative function to collect sales in range (non-recursive version)
(define-private (get-sales-in-range-iter (start-id uint) (end-id uint) (start-block uint) (end-block uint) 
                                         (acc (list 500 {id: uint, details: {buyer: principal, item-id: uint, payment-amount: uint, timestamp: uint, is-offline: bool}})))
  (let ((result acc)
        (max-id (if (> end-id (var-get sale-counter)) (var-get sale-counter) end-id)))
    ;; Use a single sale ID for demonstration (would need a loop in real implementation)
    (if (> start-id max-id)
      result
      (get-sales-in-range-single start-id max-id start-block end-block result))
  )
)
;; Process a single sale ID
(define-private (get-sales-in-range-single (current-id uint) (max-id uint) (start-block uint) (end-block uint)
                                         (acc (list 500 {id: uint, details: {buyer: principal, item-id: uint, payment-amount: uint, timestamp: uint, is-offline: bool}})))
  (let ((next-result 
          (match (get-sale-if-in-period current-id start-block end-block)
            sale (unwrap-panic (as-max-len? (concat acc (list sale)) u500))
            acc)))
    (if (>= current-id max-id)
      next-result
      (get-sales-in-range-next (+ current-id u1) max-id start-block end-block next-result))
  )
)

;; Process the next sale ID
(define-private (get-sales-in-range-next (current-id uint) (max-id uint) (start-block uint) (end-block uint)
                                       (acc (list 500 {id: uint, details: {buyer: principal, item-id: uint, payment-amount: uint, timestamp: uint, is-offline: bool}})))
  (match (get-sale-if-in-period current-id start-block end-block)
    sale (if (>= current-id max-id)
            (unwrap-panic (as-max-len? (concat acc (list sale)) u500))
            (get-sales-in-range-next2 (+ current-id u1) max-id start-block end-block 
                                     (unwrap-panic (as-max-len? (concat acc (list sale)) u500))))
    (if (>= current-id max-id)
      acc
      (get-sales-in-range-next2 (+ current-id u1) max-id start-block end-block acc)))
)

;; Process further sale IDs
(define-private (get-sales-in-range-next2 (current-id uint) (max-id uint) (start-block uint) (end-block uint)
                                        (acc (list 500 {id: uint, details: {buyer: principal, item-id: uint, payment-amount: uint, timestamp: uint, is-offline: bool}})))
  (if (>= current-id max-id)
    acc
    (let ((next-acc (match (get-sale-if-in-period current-id start-block end-block)
                      sale (unwrap-panic (as-max-len? (concat acc (list sale)) u500))
                      acc)))
      (if (>= (+ current-id u1) max-id)
        (match (get-sale-if-in-period (+ current-id u1) start-block end-block)
          final-sale (unwrap-panic (as-max-len? (concat next-acc (list final-sale)) u500))
          next-acc)
        next-acc)
    )
  )
)

;; Get total sales count
(define-read-only (get-sales-count)
  (var-get sale-counter)
)

;; Accept tips/donations from fans
(define-public (send-tip)
  (let ((artist-profile (unwrap! (map-get? artist-profiles (var-get contract-owner)) (err u404)))
        (tip-amount (stx-get-balance tx-sender)))
    ;; Ensure minimum tip amount
    (asserts! (>= tip-amount (get min-stx-payment artist-profile)) (err u401))
    
    ;; Process tip payment
    (try! (stx-transfer? tip-amount tx-sender (var-get contract-owner)))
    (ok tip-amount)
  )
)

;; Emergency withdrawal function for contract owner
(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
    (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
    (ok amount)
  )
)

;; Set merchandise availability (useful when stock runs out during tour)
(define-public (set-merchandise-availability (available bool))
  (let ((artist-profile (unwrap! (map-get? artist-profiles tx-sender) (err u404))))
    (map-set artist-profiles tx-sender {
      name: (get name artist-profile),
      merchandise-available: available,
      accepts-offline-payments: (get accepts-offline-payments artist-profile),
      min-stx-payment: (get min-stx-payment artist-profile)
    })
    (ok available)
  )
)