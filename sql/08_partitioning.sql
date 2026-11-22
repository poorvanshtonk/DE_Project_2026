-- Phase 5 partitioning for applications.
-- In the large dataset, applications has 3,000,000 rows and is the fastest growing table.
-- Most queries filter by applied_at (such as June 2026 in R19 and R20).
--
-- In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint
-- must include all columns of the partition key. That is why the primary key is
-- (application_id, applied_at) rather than just application_id.

SET search_path TO linkedin;

-- 1. Create the partitioned parent table
CREATE TABLE applications_partitioned (
    application_id    integer NOT NULL,
    job_id            integer NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    member_id         integer NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    applied_at        timestamptz NOT NULL,
    easy_apply        boolean NOT NULL,
    status            text NOT NULL CHECK (status IN ('APPLIED', 'VIEWED', 'SHORTLISTED', 'INTERVIEW', 'OFFER', 'HIRED', 'REJECTED')),
    status_updated_at timestamptz NOT NULL,
    CONSTRAINT applications_part_pk PRIMARY KEY (application_id, applied_at),
    CONSTRAINT applications_part_job_member_unique UNIQUE (job_id, member_id, applied_at),
    CONSTRAINT applications_part_status_timing CHECK (status_updated_at >= applied_at)
) PARTITION BY RANGE (applied_at);

-- 2. Quarterly partitions covering the active project timeline (2025-01 to 2026-07)
CREATE TABLE applications_2025_q1 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE applications_2025_q2 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE applications_2025_q3 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE applications_2025_q4 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE applications_2026_q1 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE applications_2026_q2 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

-- Default partition for any future dates
CREATE TABLE applications_default PARTITION OF applications_partitioned DEFAULT;

-- 3. Indexes on the partitioned table
-- PostgreSQL automatically creates matching indexes on all partitions.
CREATE INDEX applications_part_member_applied_idx
    ON applications_partitioned (member_id, applied_at DESC)
    INCLUDE (application_id, job_id, status);

CREATE INDEX applications_part_applied_desc_idx
    ON applications_partitioned (applied_at DESC)
    INCLUDE (application_id, job_id, member_id, status);

CREATE INDEX applications_part_job_date_idx
    ON applications_partitioned (job_id, applied_at)
    WHERE status = 'APPLIED';

CREATE INDEX applications_part_hired_updated_idx
    ON applications_partitioned (status_updated_at, job_id)
    INCLUDE (applied_at)
    WHERE status = 'HIRED';

-- 4. Checking partition pruning
-- This query only looks at June 2026. PostgreSQL prunes 2025_q1 through 2026_q1
-- and default, scanning only applications_2026_q2.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM applications_partitioned
WHERE applied_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND applied_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30';

-- Helper query to inspect row distribution across individual partitions:
-- SELECT tableoid::regclass AS partition_name, count(*) AS total_rows
-- FROM applications_partitioned
-- GROUP BY 1
-- ORDER BY 1;

