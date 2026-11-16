# Phase 3: Baseline Query Timings

## How we measured

We ran the 30 queries from `queries/workload_30.sql` against the schema we created in Phase 2. At this stage, our database only has the default indexes created by PostgreSQL for primary keys and unique constraints—no extra indexes or query rewrites have been added yet.

We loaded the seed dataset into PostgreSQL 18.6 running on our benchmark laptop (MacBook Pro M4, 16 GB RAM). We used the provided `./benchmarks/run_benchmark.sh linkedin_db baseline` script to collect the timings.

The script runs each query 3 times with `EXPLAIN (ANALYZE, BUFFERS)` and computes the arithmetic average of the execution times. For the write queries (`W01` to `W05`), the script wraps each run inside a `BEGIN ... ROLLBACK` block so the underlying seed data stays unchanged between runs. All raw execution plans for each run are saved in `benchmarks/results/baseline/`.

---

## Timing table

The table below shows the execution times for all 30 queries across our three runs and the resulting average.

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Profile header: member 1023 with their current position and company | READ | 6.216 | 5.132 | 4.472 | 5.273 |
| R02: Experience section: member 1023's positions, latest first | READ | 3.466 | 3.250 | 3.083 | 3.266 |
| R03: "My Network": everyone connected to member 1023 | READ | 2.530 | 2.466 | 2.281 | 2.426 |
| R04: Profile page: mutual connections of member 1023 and member 356 | READ | 9.945 | 8.776 | 8.412 | 9.044 |
| R05: "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections | READ | 24.459 | 23.585 | 24.083 | 24.042 |
| R06: Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026 | READ | 5.639 | 6.110 | 5.310 | 5.686 |
| R07: "Jobs for you": open jobs that need at least 2 of member 1023's skills | READ | 5.078 | 4.886 | 4.653 | 4.872 |
| R08: Recruiter: applicants of job 14075 by pipeline stage | READ | 0.467 | 0.076 | 0.076 | 0.206 |
| R09: "My Jobs": member 1023's applications with their status | READ | 1.777 | 1.757 | 1.789 | 1.774 |
| R10: Invitations tab: pending invitations received by member 1023 | READ | 2.334 | 2.289 | 2.309 | 2.311 |
| R11: "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately) | READ | 4.583 | 4.466 | 4.520 | 4.523 |
| R12: Company page: current employees of Flipkart and their average tenure in years | READ | 4.672 | 4.531 | 4.574 | 4.592 |
| R13: Engagement: members who have never viewed anyone's profile (for a re-engagement nudge) | READ | 20.410 | 20.242 | 19.339 | 19.997 |
| R14: Talent insights: average days from application to hire, per company (2026 hires) | READ | 8.720 | 8.115 | 8.010 | 8.282 |
| R15: Skill demand: skills most requested by jobs posted in 2026 | READ | 8.599 | 8.445 | 8.247 | 8.430 |
| R16: Salary insights: average advertised salary range per job title and city (2026 postings with salaries) | READ | 1.516 | 1.522 | 1.552 | 1.530 |
| R17: Talent flow: companies people joined right after leaving TCS | READ | 34.307 | 34.787 | 33.820 | 34.305 |
| R18: Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first | READ | 8.178 | 7.661 | 7.678 | 7.839 |
| R19: Employer report: open jobs and June 2026 applications of every IT Services company | READ | 217.169 | 217.387 | 219.036 | 217.864 |
| R20: Platform analytics: applications per day and running total, June 2026 | READ | 6.472 | 6.221 | 6.274 | 6.322 |
| R21: Skills pages: the most-endorsed member for each skill | READ | 84.923 | 81.238 | 78.012 | 81.391 |
| R22: Trust & safety console: all applications, newest first, page 4,001 (25 per page) | READ | 30.032 | 28.527 | 28.938 | 29.166 |
| R23: Sign-in: find the member by email, ignoring case | READ | 8.930 | 8.694 | 8.468 | 8.697 |
| R24: Growth: invitation acceptance rate of Premium vs free senders (2026) | READ | 8.931 | 8.845 | 8.421 | 8.732 |
| R25: Career insights: members with a career break of more than 6 months between two positions | READ | 32.195 | 31.491 | 32.134 | 31.940 |
| W01: "Easy Apply": member 1023 applies to job 14075 | WRITE | 0.901 | 0.457 | 0.464 | 0.607 |
| W02: Member 1023 accepts their oldest pending invitation | WRITE | 2.394 | 2.441 | 2.384 | 2.406 |
| W03: …and the new connection is stored once, smaller member id first | WRITE | 2.643 | 2.720 | 4.827 | 3.397 |
| W04: Nightly job: close every job whose closing date has passed | WRITE | 2.140 | 2.189 | 2.378 | 2.236 |
| W05: Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days | WRITE | 2.966 | 2.907 | 2.761 | 2.878 |
| **Total (sum of all 30)** | | **552.592** | **541.213** | **538.305** | **544.037** |

---

## Scan types and why each query is slow or fast

| Query | Scan type(s) from execution plan | Why it is slow or fast |
|---|---|---|
| **R01** | `Index Scan on members_pkey` \| `Seq Scan on positions` \| `Index Scan on companies_pkey` | Fetching member 1023 is instant via primary key, but finding their current job forces a full scan of all 99,940 positions because `member_id` has no foreign key index. |
| **R02** | `Seq Scan on positions` \| `Index Scan on companies_pkey` | Scans all 99,940 position rows to pick out the 4 rows for member 1023 before sorting by start date and looking up company names by primary key. |
| **R03** | `Bitmap Heap Scan on connections` \| `Bitmap Index Scan on connections_pkey` | The primary key index on `(member_a, member_b)` helps for `member_a = 1023`, but finding where `member_b = 1023` requires a bitmap scan and rechecking table pages. |
| **R04** | `Seq Scan on connections` (Parallel) | Because of the `OR` condition across both member columns, PostgreSQL runs two parallel table scans across all 219,966 connection rows and hash joins them. |
| **R05** | `Bitmap Heap Scan on connections` \| `Bitmap Index Scan on connections_pkey` | Joining friends' connections with an `OR` condition causes nested loop bitmap scans and rechecks, hitting over 9,200 buffer pages to compute 2nd-degree mutuals. |
| **R06** | `Seq Scan on jobs` \| `Index Scan on companies_pkey` | Searches job titles using `ILIKE '%data analyst%'` with date and city filters; with no trigram or composite index, it scans all 15,000 jobs. |
| **R07** | `Seq Scan on job_skills` \| `Seq Scan on jobs` \| `Index Only Scan on member_skills_pkey` | Reads member 1023's skills quickly from an index-only scan, but has to scan all 65,719 rows of `job_skills` and 15,000 jobs to find matches. |
| **R08** | `Index Scan on applications_one_per_job_member` | The fastest read query (0.206 ms) because `job_id` is the leading column in our unique index `(job_id, member_id)`, so it reads only 11 buffer pages. |
| **R09** | `Index Scan on applications_one_per_job_member` \| `Index Scan on jobs_pkey` \| `Index Scan on companies_pkey` | Uses the applications index, but because `member_id` is the second column of the composite key, PostgreSQL scans index pages rather than doing a direct point lookup. |
| **R10** | `Seq Scan on invitations` \| `Index Scan on members_pkey` | `recipient_id` is not indexed, so PostgreSQL scans all 60,000 invitation rows to find the 2 pending invitations for member 1023. |
| **R11** | `Seq Scan on profile_views` | `viewed_id` lacks an index, forcing a full sequential scan of all 199,996 rows in `profile_views` to find visits to member 217. |
| **R12** | `Seq Scan on positions` \| `Seq Scan on companies` | Filters `companies` for Flipkart and hash joins with a full scan of 99,940 positions to filter current employees where `end_date IS NULL`. |
| **R13** | `Seq Scan on members` \| `Seq Scan on profile_views` | Scans both tables, but returns **0 rows** because `profile_views` contains NULL viewer IDs (private mode). In SQL, `NOT IN (subquery with NULL)` evaluates to UNKNOWN for all rows. |
| **R14** | `Seq Scan on applications` \| `Seq Scan on jobs` \| `Seq Scan on companies` | Scans all 149,984 applications and joins them with `jobs` and `companies` to compute the average hiring duration for 2026 hires. |
| **R15** | `Seq Scan on jobs` \| `Index Only Scan on job_skills_pkey` \| `Seq Scan on skills` | Scans 15,000 jobs for 2026 postings and counts skill occurrences using an Index Only Scan on `job_skills_pkey`. |
| **R16** | `Seq Scan on jobs` \| `Seq Scan on cities` | Relatively fast (1.530 ms) despite scanning `jobs` because the table fits easily in memory and only 265 buffer blocks are read. |
| **R17** | `Seq Scan on positions` \| `Seq Scan on companies` \| `Index Scan on companies_pkey` | The `LEAD()` window function over 99,940 positions requires sorting by `member_id, start_date`, which spills 2.16 MB into temporary disk files. |
| **R18** | `Seq Scan on member_skills` \| `Seq Scan on skills` \| `Index Scan on members_pkey` | Scans all 212,417 rows of `member_skills` to find members with SQL skill, then joins with `members` to filter by city and open-to-work status. |
| **R19** | `Seq Scan on companies` \| `Seq Scan on jobs` \| `Index Scan on applications_one_per_job_member` | **The slowest query (217.864 ms)**: for each of the 200 IT Services companies, PostgreSQL runs two correlated subqueries, scanning `jobs` sequentially 400 times (over 3 million row checks). |
| **R20** | `Seq Scan on applications` | Scans all 149,984 applications to filter for June 2026, group by day, and calculate the cumulative running total. |
| **R21** | `Seq Scan on member_skills` \| `Seq Scan on skills` | Slow (81.391 ms) because `ROW_NUMBER()` sorts all 212,417 member skills by `skill_id` and endorsements, spilling 6.54 MB to disk in an external merge sort. |
| **R22** | `Seq Scan on applications` | Takes ~29 ms because `OFFSET 100000 LIMIT 25` forces PostgreSQL to sort all 149,984 applications by date and discard 100,000 rows before returning 25. |
| **R23** | `Seq Scan on members` | Takes ~8.7 ms because the query filters on `lower(email)`. The unique B-tree index on `email` cannot be used on an expression, so it scans all 40,000 members. |
| **R24** | `Seq Scan on invitations` \| `Seq Scan on members` | Scans all 60,000 invitations and 40,000 members, hash joining them to calculate the 2026 acceptance rate for Premium vs free senders. |
| **R25** | `Seq Scan on positions` | Takes ~32 ms because the `LAG()` window function sorts all 99,940 positions by `member_id, start_date`, spilling 2.16 MB to disk to find career gaps > 182 days. |
| **W01** | `(no scan)` (Direct insert) | A fast insert (0.607 ms) checking conflict resolution via the unique index on `(job_id, member_id)` and verifying foreign keys. |
| **W02** | `Seq Scan on invitations` \| `Index Scan on invitations_pkey` | The subquery sequentially scans 60,000 invitations to find member 1023's oldest pending invitation before updating the row by primary key. |
| **W03** | `Seq Scan on invitations` \| `Index Scan on invitations_pkey` | Runs the same sequential scan on `invitations` to find the sender and recipient IDs before inserting into `connections`. |
| **W04** | `Seq Scan on jobs` | Scans all 15,000 jobs to find open jobs whose closing date has passed and marks 552 expired jobs as closed. |
| **W05** | `Seq Scan on jobs` \| `Seq Scan on companies` \| `Index Scan on applications_one_per_job_member` | Scans `jobs` and `companies` to find TCS jobs, then uses the index on `applications` to find and reject 119 unreviewed applications older than 60 days. |

---

## What we learned from the baseline

1. **R19 takes 40% of the entire benchmark time.** The total time for all 30 queries is 544 ms, and R19 alone takes 217.9 ms. Writing correlated subqueries inside the `SELECT` list means PostgreSQL re-scans the `jobs` table 400 times (twice for every IT Services company). Rewriting this query with regular joins or grouped CTEs in Phase 4 should fix this bottleneck.
2. **Window functions are spilling to disk.** Queries like R17, R21, and R25 need to sort large tables (up to 212,000 rows) by member or skill ID. Because there are no pre-sorted indexes on these columns, the sorting exceeds PostgreSQL's default `work_mem` and spills 2 MB to 6.5 MB into temporary disk files.
3. **Foreign key columns need secondary indexes.** While primary keys and unique constraints are indexed automatically, foreign keys are not. Everyday member lookups (R01, R02, R10, R11, W02, W03) end up scanning 60,000 to 200,000 rows to find just 1 to 5 matching rows.
4. **The subtle bug in R13 explains Problem P5.** Problem P5 in the brief asked why the re-engagement list of members who never view profiles is always empty. Our plan confirms it: 50,173 rows in `profile_views` have `viewer_id IS NULL` (private-mode views). In SQL, `NOT IN (SELECT viewer_id ...)` evaluates to `UNKNOWN` whenever the subquery contains a NULL value. This caused PostgreSQL to discard all 40,000 members. Rewriting this with `NOT EXISTS` or filtering out NULLs will give the correct result in Phase 4.
5. **R23 needs an expression index.** The unique index on `members(email)` cannot be used by `lower(email) = ...`, forcing a full scan of 40,000 rows. A functional B-tree index on `lower(email)` will turn this into an instant index lookup.
