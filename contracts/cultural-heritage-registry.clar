;; Cultural Heritage Registry Smart Contract
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ARTIFACT_NOT_FOUND (err u101))
(define-constant ERR_ARTIFACT_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_METADATA (err u103))
(define-constant ERR_VERIFICATION_FAILED (err u104))
(define-constant ERR_ACCESS_DENIED (err u105))
(define-constant ERR_INVALID_STATUS (err u106))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Artifact status constants
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_DISPUTED u2)
(define-constant STATUS_PROTECTED u3)

;; Data structures
(define-map artifacts
  { artifact-id: uint }
  {
    name: (string-ascii 256),
    description: (string-utf8 1024),
    origin: (string-ascii 128),
    cultural-significance: (string-utf8 512),
    owner: principal,
    verifier: (optional principal),
    status: uint,
    creation-date: uint,
    verification-date: (optional uint),
    metadata-hash: (buff 32),
    image-hash: (optional (buff 32))
  }
)

(define-map artifact-ownership-history
  { artifact-id: uint, transfer-id: uint }
  {
    from: principal,
    to: principal,
    transfer-date: uint,
    notes: (optional (string-utf8 256))
  }
)

(define-map authorized-verifiers principal bool)
(define-map artifact-access-permissions { artifact-id: uint, user: principal } bool)

;; Data variables
(define-data-var next-artifact-id uint u1)
(define-data-var next-transfer-id uint u1)
(define-data-var total-artifacts uint u0)
(define-data-var total-verified-artifacts uint u0)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (is-authorized-verifier (verifier principal))
  (default-to false (map-get? authorized-verifiers verifier))
)

(define-private (is-artifact-owner (artifact-id uint))
  (match (map-get? artifacts { artifact-id: artifact-id })
    artifact (is-eq tx-sender (get owner artifact))
    false
  )
)

(define-private (has-artifact-access (artifact-id uint))
  (or 
    (is-artifact-owner artifact-id)
    (default-to false (map-get? artifact-access-permissions { artifact-id: artifact-id, user: tx-sender }))
    (is-contract-owner)
  )
)

;; Validator functions
(define-private (is-valid-status (status uint))
  (or (is-eq status STATUS_PENDING)
      (is-eq status STATUS_VERIFIED)
      (is-eq status STATUS_DISPUTED)
      (is-eq status STATUS_PROTECTED))
)

(define-private (is-valid-metadata (name (string-ascii 256)) 
                                  (description (string-utf8 1024)) 
                                  (origin (string-ascii 128))
                                  (cultural-significance (string-utf8 512)))
  (and (> (len name) u0)
       (> (len description) u0)
       (> (len origin) u0)
       (> (len cultural-significance) u0))
)

;; Public functions

;; Register a new cultural heritage artifact
(define-public (register-artifact 
  (name (string-ascii 256))
  (description (string-utf8 1024))
  (origin (string-ascii 128))
  (cultural-significance (string-utf8 512))
  (metadata-hash (buff 32))
  (image-hash (optional (buff 32))))
  
  (let ((artifact-id (var-get next-artifact-id)))
    ;; Validate input
    (asserts! (is-valid-metadata name description origin cultural-significance) ERR_INVALID_METADATA)
    (asserts! (is-none (map-get? artifacts { artifact-id: artifact-id })) ERR_ARTIFACT_ALREADY_EXISTS)
    
    ;; Create artifact record
    (map-set artifacts 
      { artifact-id: artifact-id }
      {
        name: name,
        description: description,
        origin: origin,
        cultural-significance: cultural-significance,
        owner: tx-sender,
        verifier: none,
        status: STATUS_PENDING,
        creation-date: stacks-block-height,
        verification-date: none,
        metadata-hash: metadata-hash,
        image-hash: image-hash
      }
    )
    
    ;; Update counters
    (var-set next-artifact-id (+ artifact-id u1))
    (var-set total-artifacts (+ (var-get total-artifacts) u1))
    
    ;; Log initial ownership
    (map-set artifact-ownership-history
      { artifact-id: artifact-id, transfer-id: u0 }
      {
        from: tx-sender,
        to: tx-sender,
        transfer-date: stacks-block-height,
        notes: (some u"Initial registration")
      }
    )
    
    (ok artifact-id)
  )
)

;; Verify an artifact (only authorized verifiers)
(define-public (verify-artifact (artifact-id uint))
  (let ((artifact (unwrap! (map-get? artifacts { artifact-id: artifact-id }) ERR_ARTIFACT_NOT_FOUND)))
    ;; Check authorization
    (asserts! (is-authorized-verifier tx-sender) ERR_NOT_AUTHORIZED)
    
    ;; Update artifact with verification
    (map-set artifacts 
      { artifact-id: artifact-id }
      (merge artifact {
        verifier: (some tx-sender),
        status: STATUS_VERIFIED,
        verification-date: (some stacks-block-height)
      })
    )
    
    ;; Update verified artifacts counter
    (if (is-eq (get status artifact) STATUS_PENDING)
        (var-set total-verified-artifacts (+ (var-get total-verified-artifacts) u1))
        true
    )
    
    (ok true)
  )
)

;; Protect an artifact (mark as protected heritage)
(define-public (protect-artifact (artifact-id uint))
  (let ((artifact (unwrap! (map-get? artifacts { artifact-id: artifact-id }) ERR_ARTIFACT_NOT_FOUND)))
    ;; Only verified artifacts can be protected
    (asserts! (is-eq (get status artifact) STATUS_VERIFIED) ERR_INVALID_STATUS)
    (asserts! (is-authorized-verifier tx-sender) ERR_NOT_AUTHORIZED)
    
    ;; Update status to protected
    (map-set artifacts 
      { artifact-id: artifact-id }
      (merge artifact { status: STATUS_PROTECTED })
    )
    
    (ok true)
  )
)

;; Transfer artifact ownership
(define-public (transfer-artifact (artifact-id uint) (new-owner principal) (notes (optional (string-utf8 256))))
  (let ((artifact (unwrap! (map-get? artifacts { artifact-id: artifact-id }) ERR_ARTIFACT_NOT_FOUND))
        (transfer-id (var-get next-transfer-id)))
    
    ;; Check if caller is the current owner
    (asserts! (is-artifact-owner artifact-id) ERR_NOT_AUTHORIZED)
    
    ;; Update ownership
    (map-set artifacts 
      { artifact-id: artifact-id }
      (merge artifact { owner: new-owner })
    )
    
    ;; Log transfer
    (map-set artifact-ownership-history
      { artifact-id: artifact-id, transfer-id: transfer-id }
      {
        from: tx-sender,
        to: new-owner,
        transfer-date: stacks-block-height,
        notes: notes
      }
    )
    
    (var-set next-transfer-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

;; Grant access permission to view artifact details
(define-public (grant-access (artifact-id uint) (user principal))
  (begin
    (asserts! (is-artifact-owner artifact-id) ERR_NOT_AUTHORIZED)
    (map-set artifact-access-permissions { artifact-id: artifact-id, user: user } true)
    (ok true)
  )
)

;; Revoke access permission
(define-public (revoke-access (artifact-id uint) (user principal))
  (begin
    (asserts! (is-artifact-owner artifact-id) ERR_NOT_AUTHORIZED)
    (map-delete artifact-access-permissions { artifact-id: artifact-id, user: user })
    (ok true)
  )
)

;; Admin functions

;; Add authorized verifier (only contract owner)
(define-public (add-verifier (verifier principal))
  (begin
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    (map-set authorized-verifiers verifier true)
    (ok true)
  )
)

;; Remove authorized verifier (only contract owner)
(define-public (remove-verifier (verifier principal))
  (begin
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    (map-delete authorized-verifiers verifier)
    (ok true)
  )
)

;; Read-only functions

;; Get artifact details (with access control)
(define-read-only (get-artifact (artifact-id uint))
  (let ((artifact (unwrap! (map-get? artifacts { artifact-id: artifact-id }) ERR_ARTIFACT_NOT_FOUND)))
    (if (has-artifact-access artifact-id)
        (ok artifact)
        ERR_ACCESS_DENIED
    )
  )
)

;; Get artifact basic info (public)
(define-read-only (get-artifact-public-info (artifact-id uint))
  (match (map-get? artifacts { artifact-id: artifact-id })
    artifact (ok {
      artifact-id: artifact-id,
      name: (get name artifact),
      origin: (get origin artifact),
      status: (get status artifact),
      creation-date: (get creation-date artifact),
      verification-date: (get verification-date artifact)
    })
    ERR_ARTIFACT_NOT_FOUND
  )
)

;; Get ownership history
(define-read-only (get-ownership-history (artifact-id uint) (transfer-id uint))
  (map-get? artifact-ownership-history { artifact-id: artifact-id, transfer-id: transfer-id })
)

;; Check if user is authorized verifier
(define-read-only (is-verifier (user principal))
  (is-authorized-verifier user)
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-artifacts: (var-get total-artifacts),
    total-verified-artifacts: (var-get total-verified-artifacts),
    next-artifact-id: (var-get next-artifact-id)
  }
)

;; Check artifact access permission
(define-read-only (check-access (artifact-id uint) (user principal))
  (or 
    (is-eq user (unwrap! (get owner (map-get? artifacts { artifact-id: artifact-id })) false))
    (default-to false (map-get? artifact-access-permissions { artifact-id: artifact-id, user: user }))
  )
)
