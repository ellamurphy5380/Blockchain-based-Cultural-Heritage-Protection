(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-insufficient-funds (err u105))

(define-constant heritage-site-active u1)
(define-constant heritage-site-threatened u2)
(define-constant heritage-site-protected u3)
(define-constant heritage-site-damaged u4)

(define-constant threat-level-low u1)
(define-constant threat-level-medium u2)
(define-constant threat-level-high u3)
(define-constant threat-level-critical u4)

(define-data-var next-site-id uint u1)
(define-data-var next-report-id uint u1)
(define-data-var next-conservation-id uint u1)
(define-data-var total-funding uint u0)
(define-data-var conservation-fee uint u1000000)

(define-map heritage-sites
    uint
    {
        name: (string-ascii 100),
        location: (string-ascii 200),
        description: (string-ascii 500),
        owner: principal,
        guardian: principal,
        status: uint,
        cultural-value: uint,
        registered-at: uint,
        last-updated: uint,
        funding-goal: uint,
        funding-raised: uint,
    }
)

(define-map site-guardians
    uint
    principal
)

(define-map threat-reports
    uint
    {
        site-id: uint,
        reporter: principal,
        threat-type: (string-ascii 100),
        threat-level: uint,
        description: (string-ascii 500),
        reported-at: uint,
        verified: bool,
        resolved: bool,
    }
)

(define-map conservation-projects
    uint
    {
        site-id: uint,
        project-name: (string-ascii 100),
        manager: principal,
        description: (string-ascii 500),
        budget: uint,
        spent: uint,
        started-at: uint,
        deadline: uint,
        completed: bool,
    }
)

(define-map site-funding
    uint
    (list 50 {
        donor: principal,
        amount: uint,
        donated-at: uint,
    })
)

(define-map user-contributions
    principal
    {
        total-donated: uint,
        sites-supported: uint,
        reports-submitted: uint,
    }
)

(define-public (register-heritage-site
        (name (string-ascii 100))
        (location (string-ascii 200))
        (description (string-ascii 500))
        (cultural-value uint)
        (funding-goal uint)
    )
    (let (
            (site-id (var-get next-site-id))
            (current-height stacks-block-height)
        )
        (asserts! (> (len name) u0) (err u106))
        (asserts! (> (len location) u0) (err u107))
        (asserts! (> cultural-value u0) (err u108))
        (asserts! (> funding-goal u0) (err u109))

        (map-set heritage-sites site-id {
            name: name,
            location: location,
            description: description,
            owner: tx-sender,
            guardian: tx-sender,
            status: heritage-site-active,
            cultural-value: cultural-value,
            registered-at: current-height,
            last-updated: current-height,
            funding-goal: funding-goal,
            funding-raised: u0,
        })

        (map-set site-guardians site-id tx-sender)
        (var-set next-site-id (+ site-id u1))

        (print {
            event: "heritage-site-registered",
            site-id: site-id,
            name: name,
            owner: tx-sender,
        })
        (ok site-id)
    )
)

(define-public (assign-guardian
        (site-id uint)
        (new-guardian principal)
    )
    (let ((site (unwrap! (map-get? heritage-sites site-id) err-not-found)))
        (asserts! (is-eq tx-sender (get owner site)) err-unauthorized)

        (map-set heritage-sites site-id
            (merge site {
                guardian: new-guardian,
                last-updated: stacks-block-height,
            })
        )
        (map-set site-guardians site-id new-guardian)

        (print {
            event: "guardian-assigned",
            site-id: site-id,
            guardian: new-guardian,
        })
        (ok true)
    )
)

(define-public (report-threat
        (site-id uint)
        (threat-type (string-ascii 100))
        (threat-level uint)
        (description (string-ascii 500))
    )
    (let (
            (report-id (var-get next-report-id))
            (site (unwrap! (map-get? heritage-sites site-id) err-not-found))
        )
        (asserts! (<= threat-level threat-level-critical) err-invalid-status)
        (asserts! (>= threat-level threat-level-low) err-invalid-status)
        (asserts! (> (len threat-type) u0) (err u110))

        (map-set threat-reports report-id {
            site-id: site-id,
            reporter: tx-sender,
            threat-type: threat-type,
            threat-level: threat-level,
            description: description,
            reported-at: stacks-block-height,
            verified: false,
            resolved: false,
        })

        (if (>= threat-level threat-level-high)
            (map-set heritage-sites site-id
                (merge site {
                    status: heritage-site-threatened,
                    last-updated: stacks-block-height,
                })
            )
            true
        )

        (update-user-stats tx-sender u0 u0 u1)
        (var-set next-report-id (+ report-id u1))

        (print {
            event: "threat-reported",
            report-id: report-id,
            site-id: site-id,
            threat-level: threat-level,
        })
        (ok report-id)
    )
)

(define-public (verify-threat (report-id uint))
    (let (
            (report (unwrap! (map-get? threat-reports report-id) err-not-found))
            (site-id (get site-id report))
            (site (unwrap! (map-get? heritage-sites site-id) err-not-found))
        )
        (asserts! (is-guardian-or-owner site-id tx-sender) err-unauthorized)
        (asserts! (not (get verified report)) (err u111))

        (map-set threat-reports report-id (merge report { verified: true }))

        (if (>= (get threat-level report) threat-level-medium)
            (map-set heritage-sites site-id
                (merge site {
                    status: heritage-site-threatened,
                    last-updated: stacks-block-height,
                })
            )
            true
        )

        (print {
            event: "threat-verified",
            report-id: report-id,
            site-id: site-id,
        })
        (ok true)
    )
)

(define-public (resolve-threat (report-id uint))
    (let (
            (report (unwrap! (map-get? threat-reports report-id) err-not-found))
            (site-id (get site-id report))
            (site (unwrap! (map-get? heritage-sites site-id) err-not-found))
        )
        (asserts! (is-guardian-or-owner site-id tx-sender) err-unauthorized)
        (asserts! (get verified report) (err u112))
        (asserts! (not (get resolved report)) (err u113))

        (map-set threat-reports report-id (merge report { resolved: true }))

        (map-set heritage-sites site-id
            (merge site {
                status: heritage-site-active,
                last-updated: stacks-block-height,
            })
        )

        (print {
            event: "threat-resolved",
            report-id: report-id,
            site-id: site-id,
        })
        (ok true)
    )
)

(define-public (fund-heritage-site
        (site-id uint)
        (amount uint)
    )
    (let (
            (site (unwrap! (map-get? heritage-sites site-id) err-not-found))
            (current-funding (default-to (list) (map-get? site-funding site-id)))
            (new-funding-entry {
                donor: tx-sender,
                amount: amount,
                donated-at: stacks-block-height,
            })
        )
        (asserts! (> amount u0) (err u114))
        (try! (stx-transfer? amount tx-sender contract-owner))

        (map-set heritage-sites site-id
            (merge site {
                funding-raised: (+ (get funding-raised site) amount),
                last-updated: stacks-block-height,
            })
        )

        (map-set site-funding site-id
            (unwrap! (as-max-len? (append current-funding new-funding-entry) u50)
                (err u115)
            ))

        (update-user-stats tx-sender amount u1 u0)
        (var-set total-funding (+ (var-get total-funding) amount))

        (print {
            event: "site-funded",
            site-id: site-id,
            donor: tx-sender,
            amount: amount,
        })
        (ok true)
    )
)

(define-public (create-conservation-project
        (site-id uint)
        (project-name (string-ascii 100))
        (description (string-ascii 500))
        (budget uint)
        (deadline uint)
    )
    (let (
            (project-id (var-get next-conservation-id))
            (site (unwrap! (map-get? heritage-sites site-id) err-not-found))
        )
        (asserts! (is-guardian-or-owner site-id tx-sender) err-unauthorized)
        (asserts! (> (len project-name) u0) (err u116))
        (asserts! (> budget u0) (err u117))
        (asserts! (> deadline stacks-block-height) (err u118))

        (try! (stx-transfer? (var-get conservation-fee) tx-sender contract-owner))

        (map-set conservation-projects project-id {
            site-id: site-id,
            project-name: project-name,
            manager: tx-sender,
            description: description,
            budget: budget,
            spent: u0,
            started-at: stacks-block-height,
            deadline: deadline,
            completed: false,
        })

        (map-set heritage-sites site-id
            (merge site {
                status: heritage-site-protected,
                last-updated: stacks-block-height,
            })
        )

        (var-set next-conservation-id (+ project-id u1))

        (print {
            event: "conservation-project-created",
            project-id: project-id,
            site-id: site-id,
        })
        (ok project-id)
    )
)

(define-public (complete-conservation-project (project-id uint))
    (let ((project (unwrap! (map-get? conservation-projects project-id) err-not-found)))
        (asserts! (is-eq tx-sender (get manager project)) err-unauthorized)
        (asserts! (not (get completed project)) (err u119))

        (map-set conservation-projects project-id
            (merge project { completed: true })
        )

        (print {
            event: "conservation-project-completed",
            project-id: project-id,
        })
        (ok true)
    )
)

(define-read-only (get-heritage-site (site-id uint))
    (map-get? heritage-sites site-id)
)

(define-read-only (get-threat-report (report-id uint))
    (map-get? threat-reports report-id)
)

(define-read-only (get-conservation-project (project-id uint))
    (map-get? conservation-projects project-id)
)

(define-read-only (get-site-funding (site-id uint))
    (map-get? site-funding site-id)
)

(define-read-only (get-user-stats (user principal))
    (default-to {
        total-donated: u0,
        sites-supported: u0,
        reports-submitted: u0,
    }
        (map-get? user-contributions user)
    )
)

(define-read-only (get-total-funding)
    (var-get total-funding)
)

(define-read-only (get-conservation-fee)
    (var-get conservation-fee)
)

(define-read-only (is-guardian-or-owner
        (site-id uint)
        (user principal)
    )
    (match (map-get? heritage-sites site-id)
        site (or (is-eq user (get owner site)) (is-eq user (get guardian site)))
        false
    )
)

(define-private (update-user-stats
        (user principal)
        (donated uint)
        (sites-supported uint)
        (reports-submitted uint)
    )
    (let ((current-stats (get-user-stats user)))
        (map-set user-contributions user {
            total-donated: (+ (get total-donated current-stats) donated),
            sites-supported: (+ (get sites-supported current-stats) sites-supported),
            reports-submitted: (+ (get reports-submitted current-stats) reports-submitted),
        })
    )
)
