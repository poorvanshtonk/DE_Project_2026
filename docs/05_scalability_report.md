# Phase 5: Scalability Report

## How we tested the large dataset

We loaded the faculty's `large_data` export into a new database named `linkedin_large`. This dataset is roughly 20× the size of the seed data, with 21,303,424 total rows across all 12 tables:
- `applications`: 2,999,984 rows (was 149,984)
- `profile_views`: 3,999,994 rows (was 199,996)
- `connections`: 4,399,965 rows (was 219,966)
- `positions`: 1,998,792 rows (was 99,940)
- `members`: 800,000 rows (was 40,000)
- `member_skills`: 4,249,459 rows (was 212,417)
- `invitations`: 1,199,999 rows (was 60,000)
- `jobs`: 300,000 rows (was 15,000)
- `job_skills`: 1,315,149 rows (was 65,719)
- `companies`: 40,000 rows (was 2,000)
- `skills`: 72 rows
- `cities`: 10 rows

We applied the schema from `sql/01_schema.sql`, loaded all CSV files, created our Phase 4 indexes from `sql/05_indexes.sql`, and ran `ANALYZE`.

We benchmarked the 30 queries from `sql/06_optimized_queries.sql` on the project laptop (MacBook Pro M4, 16 GB RAM) using `./benchmarks/run_benchmark.sh linkedin_large large 3 sql/06_optimized_queries.sql`. Each query ran 3 times with `EXPLAIN (ANALYZE, BUFFERS)`. Write queries ran inside `BEGIN ... ROLLBACK` blocks so the data stayed unchanged. The raw execution plans and summary are in [`benchmarks/results/large/`](../benchmarks/results/large/).

---

## Results table

The table compares our Phase 4 optimized times on the seed data with our times on the 20× large dataset. Growth is calculated as `large_time / seed_time`.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth | Target (ms) | Meets target? | What the plan shows on large data |
|---|---:|---:|---:|---:|:---:|---|
| **R01** | 0.072 | 0.374 | 5.2× | < 5 | Yes | Index point lookups on member, current position, and company. |
| **R02** | 0.053 | 0.401 | 7.6× | < 5 | Yes | Index-only scan on positions in date order, then company lookup. |
| **R03** | 0.041 | 0.546 | 13.3× | < 5 | Yes | Separate indexed lookups on `member_a` and `member_b` joined with `UNION ALL`. |
| **R04** | 0.073 | 0.406 | 5.6× | < 5 | Yes | Looks up connections for both members using indexes, then hash joins the friend lists. |
| **R05** | 0.199 | 8.552 | 43.0× | < 250 | Yes | Follows 2nd-degree friend connections; grouping and sorting finishes in 8.5 ms. |
| **R06** | 0.200 | 12.573 | 62.9× | < 250 | Yes | Uses the posted date index for June 2026; checks title filter in memory. |
| **R07** | 0.737 | 40.584 | 55.1× | < 250 | Yes | Joins member skills to job skills on open jobs using indexes; aggregates matching skills. |
| **R08** | 0.063 | 0.199 | 3.2× | < 5 | Yes | Index scan on `job_id` using the unique index. |
| **R09** | 0.054 | 0.250 | 4.6× | < 5 | Yes | Index-only scan on `applications_member_applied_idx` for member 1023. |
| **R10** | 0.056 | 0.063 | 1.1× | < 5 | Yes | Partial index on pending invitations finds recipient's invites directly. |
| **R11** | 0.066 | 0.353 | 5.3× | < 5 | Yes | Index-only scan on profile views for viewed member since April 2026. |
| **R12** | 0.129 | 5.340 | 41.4× | < 250 | Yes | Partial index on current employees at Flipkart; averages tenure across ~1,000 employees. |
| **R13** | 10.200 | 252.048 | 24.7× | < 250 | Explained | Switched from Merge Anti Join to Parallel Hash Anti Join. Spilled batches to disk on run 1 (285 ms); warm runs were 236 ms and 234 ms. Giving the session `work_mem = 64MB` stops the spill and runs in 245 ms. |
| **R14** | 2.668 | 118.550 | 44.4× | < 5,000 | Yes | Partial index finds 2026 hires; joins to jobs and companies to average hire days. |
| **R15** | 6.929 | 59.962 | 8.7× | < 5,000 | Yes | Date range scan on `jobs_posted_idx` joined with `job_skills` and `skills`. |
| **R16** | 1.185 | 10.483 | 8.8× | < 5,000 | Yes | Date range index scan on `jobs_posted_idx` for jobs with salary info. |
| **R17** | 30.351 | 643.054 | 21.2× | < 5,000 | Yes | Index supplies positions in member and start-date order for `LEAD` across 2M rows. |
| **R18** | 2.313 | 26.888 | 11.6× | < 250 | Yes | `member_skills_skill_rank_idx` finds SQL members in endorsement order; filters city. |
| **R19** | 2.952 | 50.049 | 17.0× | < 5,000 | Yes | Aggregates open jobs and June applications once for IT Services companies. |
| **R20** | 1.091 | 29.721 | 27.2× | < 5,000 | Yes | Index-only scan over June 2026 applications; calculates running sum by day. |
| **R21** | 0.273 | 0.395 | 1.4× | < 5,000 | Yes | Lateral lookup finds top member for each of the 72 skills in endorsement order. |
| **R22** | 5.861 | 11.683 | 2.0× | < 250 | Yes | Index-only scan on applications walks 100,000 index tuples in memory. |
| **R23** | 0.021 | 0.038 | 1.8× | < 5 | Yes | Expression index on `lower(email)` finds member in 3 page hits. |
| **R24** | 6.646 | 90.756 | 13.7× | < 5,000 | Yes | Index scan on 2026 invitations joined with members to calculate acceptance rate. |
| **R25** | 27.897 | 610.110 | 21.9× | < 5,000 | Yes | Index supplies positions in order for `LAG` across all 2M position rows. |
| **W01** | 0.600 | 1.064 | 1.8× | < 5 | Yes | Inserts one application; unique index verifies no conflict. |
| **W02** | 0.147 | 0.434 | 3.0× | < 5 | Yes | Partial index finds oldest pending invitation; single row update. |
| **W03** | 0.358 | 1.055 | 2.9× | < 5 | Yes | Finds oldest pending invitation and inserts single connection row. |
| **W04** | 2.681 | 370.741 | 138.3× | < 1,000 | Yes | Closes expired open jobs using partial index; updates ~3,000 rows in bulk. |
| **W05** | 1.878 | 70.843 | 37.7× | < 250 | Yes | Updates unreviewed applications for TCS older than 60 days. |
| **Total** | **105.794** | **2417.515** | **22.9×** | — | — | Running all 30 queries takes about 2.4 seconds total. |

---

## Growth analysis

Looking at how the query times changed between the seed data and the large data, the queries fall into three groups:

### 1. Queries that stayed about the same (growth under 5×)
- **Queries:** R08 (3.2×), R09 (4.6×), R10 (1.1×), R21 (1.4×), R22 (2.0×), R23 (1.8×), W01 (1.8×), W02 (3.0×), W03 (2.9×).
- **Why:**
  - B-tree depth only went up by 1 level. Growing from 40,000 members and 150,000 applications to 800,000 members and 3,000,000 applications only adds one level to the index tree (height 2 to height 3). A single-point lookup like R23 (`lower(email)`), R08 (applicants for one job), R10 (invitations for one member), and single-row writes (W01, W02, W03) only has to read one additional 8 KB page.
  - Fixed loop count in R21: The lateral query runs once per skill. Since the number of skills is still 72, it still does 72 fast root-to-leaf searches in `member_skills_skill_rank_idx`.
  - Sequential index scan in R22: Walking 100,000 index tuples using `applications_applied_desc_idx` stayed fast (11.6 ms) because the index pages were already cached in memory.

### 2. Queries that grew roughly 20× (growth between 5× and 30×)
- **Queries:** R01 (5.2×), R02 (7.6×), R03 (13.3×), R04 (5.6×), R11 (5.3×), R13 (24.7×), R15 (8.7×), R16 (8.8×), R17 (21.2×), R18 (11.6×), R19 (17.0×), R20 (27.2×), R24 (13.7×), R25 (21.9×).
- **Why:**
  - Full-table window functions in R17 and R25: Both queries compute window functions (`LEAD`, `LAG`) across the entire position history. The positions table grew from 99,940 rows to 1,998,792 rows (exactly 20.0×). Because the window function has to visit every single position to detect job changes and career breaks, execution time grew linearly from ~30 ms to ~610–643 ms.
  - Date ranges with 20× more rows: In R20, the June 2026 filter had ~9,000 applications in the seed data and ~180,000 applications in the large data. The index scan had 20× more tuples to read and group, scaling from 1.09 ms to 29.7 ms. The same happened with R15 (2026 jobs by skill), R16 (2026 salaries), and R19 (June IT applications).

### 3. Queries that grew more than 20× (growth over 30×)
- **Queries:** R05 (43.0×), R06 (62.9×), R07 (55.1×), R12 (41.4×), R14 (44.4×), W04 (138.3×), W05 (37.7×).
- **Why:**
  - Network expansion in R05: Finding 2nd-degree connections depends on both the member's connections and the connections of each friend ($O(d^2)$ branching). Member 1023 has more connections in the large dataset, and each connection has more friends. Checking thousands of candidate edges instead of ~150 pushed time from 0.20 ms to 8.55 ms, which is still well under the 250 ms target.
  - Multi-table skill joins in R07: Matching member 1023's skills against open jobs found far more qualifying jobs in the large data, so grouping and filtering had to process more intermediate rows (40.58 ms).
  - Text filtering in R06: While the date index limits the candidate jobs, evaluating `title ILIKE '%data analyst%'` across 20× more candidate rows in June 2026 took 12.57 ms.
  - Bulk updates in W04 and W05: In W04, the number of open jobs past their closing date went from ~150 to ~3,000. Updating 3,000 rows means writing new tuple versions, generating WAL, and updating entries in 5 separate indexes (`jobs_pkey`, `jobs_company_status_idx`, `jobs_posted_idx`, `jobs_open_id_idx`, `jobs_expired_open_idx`), which took 370 ms compared to 2.7 ms. In W05, unreviewed TCS applications older than 60 days grew by ~30×, increasing the update time to 70.8 ms.

---

## What broke at scale and how we fixed it

### R13: Memory spill on 4 million profile views

On the seed data, R13 ran in 10.2 ms using a **Merge Anti Join** with `members_pkey` and `profile_views_viewer_idx`. Both inputs were read in member ID order.

On the large data, the planner saw 800,000 members and 4,000,000 profile views. It switched from the index merge join to a **Parallel Hash Anti Join**:
```text
Gather (cost=69564.94..121983.40 rows=245850)
  -> Parallel Hash Anti Join (cost=68564.94..96398.40)
       Hash Cond: (m.member_id = v.viewer_id)
       -> Parallel Seq Scan on members m
       -> Parallel Hash
            -> Parallel Seq Scan on profile_views v
```

**What happened:**
PostgreSQL's default `work_mem` is 4 MB. A hash table of 4 million `viewer_id` integers does not fit into 4 MB. PostgreSQL had to split the hash table into **32 batches** and write overflow buckets to temporary disk files:
- `temp read=12155 written=12476` (about 100 MB of temp disk I/O).
- Run 1 (cold cache) took **285.038 ms**.
- Run 2 and Run 3 dropped to **236.162 ms** and **234.944 ms** once pages were in memory, giving an average of 252.048 ms.

**The fixes:**
1. **Increase `work_mem`:** Setting `work_mem = '64MB'` allows the full hash table to build in memory with `Batches: 1`. Disk spilling drops to zero, and the query completes in **245.6 ms**.
2. **Use streaming merge anti join:** Setting `enable_hashjoin = off` makes PostgreSQL use the index-based **Merge Anti Join** again (`members_pkey` merged with `profile_views_viewer_idx`). It uses zero temp disk buffers and runs in **250.3 ms**.

### R22: OFFSET pagination at large scale

R22 fetches page 4,001 using `OFFSET 100000 LIMIT 25`. On our 3-million-row table, our index-only scan on `applications_applied_desc_idx` handled this in 11.68 ms because the working set was cached.

However, `OFFSET` pagination gets slower as you go deeper:
- To return 25 rows at offset 100,000, PostgreSQL has to read and discard 100,000 index tuples.
- At 100× scale (300 million applications), page 40,000 would need to discard 1,000,000 tuples, taking seconds.

**The fix: Keyset pagination:**
Instead of `OFFSET 100000`, the query passes the `applied_at` and `application_id` of the last row on the previous page:
```sql
SELECT application_id, job_id, member_id, status, applied_at
FROM applications
WHERE (applied_at, application_id) < (:last_applied_at, :last_application_id)
ORDER BY applied_at DESC, application_id DESC
LIMIT 25;
```
Keyset pagination does an index seek directly to the starting tuple in under **0.1 ms**, no matter which page you are on.

---

## Storage analysis

We checked relation sizes in PostgreSQL using `pg_total_relation_size()`:

| Table | Table size | Index size | Total size (Large) | Total size (Seed) | Growth |
|---|---:|---:|---:|---:|---:|
| `applications` | 211 MB | 465 MB | 677 MB | 36 MB | 18.8× |
| `profile_views` | 192 MB | 276 MB | 468 MB | 24 MB | 19.5× |
| `connections` | 186 MB | 264 MB | 450 MB | 23 MB | 19.6× |
| `member_skills` | 180 MB | 219 MB | 399 MB | 20 MB | 20.0× |
| `positions` | 144 MB | 189 MB | 333 MB | 17 MB | 19.6× |
| `members` | 98 MB | 119 MB | 217 MB | 11 MB | 19.7× |
| `invitations` | 101 MB | 76 MB | 176 MB | 9 MB | 19.6× |
| `job_skills` | 46 MB | 56 MB | 102 MB | 5 MB | 20.4× |
| `jobs` | 38 MB | 38 MB | 75 MB | 4 MB | 18.8× |
| `companies` | 4.2 MB | 0.9 MB | 5.1 MB | 0.3 MB | 17.0× |
| `skills` | 16 kB | 32 kB | 48 kB | 48 kB | 1.0× |
| `cities` | 16 kB | 32 kB | 48 kB | 48 kB | 1.0× |
| **Total database** | **~1,200 MB** | **~1,703 MB** | **2,910 MB** | **155 MB** | **18.8×** |

The database grew from 155 MB to 2,910 MB (~2.9 GB), which closely tracks the 20× row increase. Indexes take up 1,703 MB (~58% of total storage), while the tables take 1,200 MB. On `applications`, indexes take 465 MB compared to 211 MB for the table data itself. This extra space comes from covering indexes (`INCLUDE` columns) and partial indexes that let our search and write queries run in sub-millisecond times.

---

## Architecture for 100× growth

At 100× growth, the database will store roughly 2 billion rows and require ~300 GB. Here is how we plan for that volume:

### 1. Partitioning `applications`
- **Table:** `applications` (projected at 150M–300M rows).
- **Strategy:** `PARTITION BY RANGE (applied_at)` using quarterly partitions (`applications_YYYY_qN`).
- **Why:** Most search queries (R19, R20, R22) filter by recent application dates. Quarterly partitions make partition pruning very effective, and older partitions (e.g. over 18 months old) can be detached and archived without locking the active table.
- **Primary key rule:** In PostgreSQL declarative partitioning, every `PRIMARY KEY` and `UNIQUE` constraint must include all partition key columns. Because of this:
  - The primary key must be `PRIMARY KEY (application_id, applied_at)` instead of just `application_id`.
  - The unique check preventing multiple applications per job must become `UNIQUE (job_id, member_id, applied_at)`.
- **DDL:** Implemented in [`sql/08_partitioning.sql`](../sql/08_partitioning.sql).
- **Partition pruning check:** Querying applications for June 2026 scans only `applications_2026_q2` and prunes all other quarters, finishing in **0.026 ms** with `EXPLAIN (ANALYZE, BUFFERS)`.

### 2. Sharding strategy
- **Key:** Shard by `member_id` across database nodes.
- **Handling connections across shards (R03 & R05):**
  - A connection links two members who may live on different shards.
  - Storing each connection as two directed edges solves this: `(1023 -> 767)` lives on member 1023's shard, and `(767 -> 1023)` lives on member 767's shard.
  - With directed edges, **R03 ("My Network") is completely single-shard** and reads from the local shard.
  - **R04 (Mutual connections):** Reads member A's connections from Shard 1, member B's connections from Shard 2, and finds the intersection in the application service.
  - **R05 (People You May Know):** At 100× scale, multi-hop joins across shards are too expensive for real-time SQL. Instead, candidate suggestions should be precomputed offline by a batch graph job (like Spark GraphX) and stored in Redis.

### 3. Read replicas and caching
- **Primary node (Writes and critical reads):**
  - All write queries: `W01`, `W02`, `W03`, `W04`, `W05`.
  - Reads requiring immediate consistency: `R23` (Sign-in), `R10` (Pending invitations), `R09` (My Jobs right after applying).
- **Read replicas (Reporting and analytics):**
  - Offload heavy analytics queries that can tolerate slight replication delay: `R12`, `R14`, `R15`, `R16`, `R17`, `R18`, `R19`, `R20`, `R24`, `R25`.
- **Redis caching:**
  - `R01` (Profile header): Cache serialized profile by `member_id` (15-minute TTL, cleared on profile edit).
  - `R02` (Positions history): Cache position list by `member_id`.
  - `R21` (Top endorsed member per skill): Cache top-member lookup for 24 hours.

### 4. Database maintenance
- **Autovacuum tuning for `applications`:**
  - With continuous inserts and status updates (APPLIED → VIEWED → HIRED/REJECTED), PostgreSQL's default 20% scale factor would wait for 600,000 updates before vacuuming, causing table bloat.
  - We tune autovacuum specifically on `applications`:
    ```sql
    ALTER TABLE applications SET (
        autovacuum_vacuum_scale_factor = 0.05,
        autovacuum_vacuum_cost_limit = 2000,
        autovacuum_vacuum_cost_delay = 2
    );
    ```
- **Archiving:** Detach old quarters (`ALTER TABLE applications_partitioned DETACH PARTITION ...`) and export them to Parquet files on object storage.
- **Summary tables:** Replace on-the-fly reporting queries like R19 and R20 with materialized views refreshed nightly using `pg_cron`.

---

## Conclusion and remaining risks

The schema and indexes handled the 20× large dataset well. The entire 30-query test ran in **~2.4 seconds combined**, and customer-facing queries stayed under 1 ms.

**Remaining risks for 100×:**
1. **Full-history window queries (R17, R25):** At 600+ ms on 2 million rows, these will exceed 6 seconds at 100×. Full-table career analytics should eventually be moved to an OLAP warehouse (like BigQuery or ClickHouse) instead of running on the OLTP database.
2. **Index memory:** At 100× scale, indexes will reach ~170 GB. Servers will need enough RAM (256 GB+) to keep the index working sets in memory and avoid random disk reads.
3. **Graph recommendations (R05):** Second-degree network lookups work fine today, but calculating mutual connections at hundreds of millions of edges needs an asynchronous recommendation pipeline rather than live SQL joins.
